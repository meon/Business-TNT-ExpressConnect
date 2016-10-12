package Business::TNT::ExpressConnect;

use 5.010;
use strict;
use warnings;

our $VERSION = '0.01';

use Path::Class qw(dir file);
use Config::INI::Reader;
use LWP::UserAgent;
use Moose;
use XML::Compile::Schema;
use XML::Compile::Util qw/pack_type/;
use DateTime;

use Business::TNT::ExpressConnect::SPc;

has 'user_agent' => (is => 'ro', lazy_build => 1);
has 'config'     => (is => 'ro', lazy_build => 1);
has 'username'   => (is => 'ro', lazy_build => 1);
has 'password'   => (is => 'ro', lazy_build => 1);
has 'xml_schema' => (is => 'ro', lazy_build => 1);
has 'error'      => (is => 'rw', isa        => 'Bool', default => 0);
has 'errors'     => (is => 'rw', isa        => 'ArrayRef[Str]');
has 'warnings'   => (is => 'rw', isa        => 'ArrayRef[Str]');

sub _build_user_agent {
    my ($self) = @_;

    my $user_agent = LWP::UserAgent->new;
    $user_agent->timeout(10);
    $user_agent->env_proxy;

    return $user_agent;
}

sub _build_config {
    my ($self) = @_;

    my $config_filename =
        file(Business::TNT::ExpressConnect::SPc->sysconfdir, 'tnt-expressconnect.ini');

    return Config::INI::Reader->read_file($config_filename) if (-r $config_filename);

    return {};
}

sub _build_username {
    my ($self) = @_;

    return $self->config->{_}->{username};
}

sub _build_password {
    my ($self) = @_;

    return $self->config->{_}->{password};
}

sub _build_xml_schema {
    my ($self) = @_;

    my $xsd_file   = file($self->_price_request_common_xsd)->relative->stringify;
    my $xml_schema = XML::Compile::Schema->new($xsd_file);

    return $xml_schema;
}

sub _xsd_basedir {
    dir(Business::TNT::ExpressConnect::SPc->datadir, 'tnt-expressconnect', 'xsd', 'pricing', 'v3');
}

sub _price_request_in_xsd {
    return _xsd_basedir->file('PriceRequestIN.xsd');
}

sub _price_request_out_xsd {
    my ($self) = @_;

    return _xsd_basedir->file('PriceResponseOUT.xsd');
}

sub _price_request_common_xsd {
    my ($self) = @_;

    return _xsd_basedir->file('commonDefinitions.xsd');
}

sub tnt_get_price_url {
    return 'https://express.tnt.com/expressconnect/pricing/getprice';
}

sub hash_to_price_request_xml {
    my ($self, $params) = @_;

    my $xml_schema = $self->xml_schema;
    $xml_schema->importDefinitions($self->_price_request_in_xsd);

    # create and use a writer
    my $doc = XML::LibXML::Document->new('1.0', 'UTF-8');
    my $write = $xml_schema->compile(WRITER => '{}priceRequest');

    my %priceCheck = (
        rateId   => 1,                     #unique within priceRequest
        sender   => $params->{sender},
        delivery => $params->{delivery},
        collectionDateTime => ($params->{collection_datetime} // DateTime->now()),
        currency => ($params->{currency} // 'EUR'),
        product => {type => ($params->{product_type} // 'N')}
        ,    #“D” Document(paper/manuals/reports) or “N” Non-document (packages)
    );

    $priceCheck{consignmentDetails} = $params->{consignmentDetails}
        if ($params->{consignmentDetails});
    $priceCheck{pieceLine} = $params->{pieceLine} if ($params->{pieceLine});

    my %hash = (appId => 'PC', appVersion => '3.0', priceCheck => [\%priceCheck]);
    my $xml = $write->($doc, \%hash);
    $doc->setDocumentElement($xml);

    return $doc;
}

sub get_prices {
    my ($self, $args) = @_;

    my $user_agent = $self->user_agent;
    my $req = HTTP::Request->new(POST => $self->tnt_get_price_url);
    $req->authorization_basic($self->username, $self->password);
    $req->header('Content-Type' => 'text/xml; charset=utf-8');

    if (my $file = $args->{file}) {
        $req->content('' . file($file)->slurp);

    }
    elsif (my $params = $args->{params}) {
        my $xml = $self->hash_to_price_request_xml($params);
        $req->content($xml->toString(1));

    }
    else {
        $self->error(1);
        $self->errors(['missing price request data']);
        return undef;
    }

    my $response = $user_agent->request($req);

    if ($response->is_error) {
        $self->error(1);
        $self->errors(['Request failed: ' . $response->status_line]);
        return undef;
    }

    my $response_xml = $response->content;

    #parse schema
    my $xml_schema = $self->xml_schema;
    $xml_schema->importDefinitions($self->_price_request_out_xsd);

    #read xml file
    my $elem = XML::Compile::Util::pack_type '', 'document';
    my $read = $xml_schema->compile(READER => $elem);

    my $data = $read->($response_xml);

    my @errors;
    my @warnings;
    foreach my $error (@{$data->{errors}->{brokenRule}}) {
        if ($error->{messageType} eq "W") {
            push @warnings, $error->{description};
        } else {
            push @errors, $error->{description};
        }
    }

    if (@warnings) {
        $self->warnings(\@warnings);
    }
    if (@errors) {
        $self->error(1);
        $self->errors(\@errors);
        return undef;
    }

    my $ratedServices = $data->{priceResponse}->[0]->{ratedServices};
    my $currency      = $ratedServices->{currency};
    my $ratedService  = $ratedServices->{ratedService};

    my %prices;
    foreach my $option (@$ratedService) {
        $prices{$option->{product}->{id}} = {
            price_desc           => $option->{product}->{productDesc},
            currency             => $currency,
            total_price          => $option->{totalPrice},
            total_price_excl_vat => $option->{totalPriceExclVat},
            vat_amount           => $option->{vatAmount},
            charge_elements      => $option->{chargeElements},
        };
    }

    return \%prices;
}

sub http_ping {
    my ($self) = @_;
    my $response = $self->user_agent->get($self->tnt_get_price_url);

    return 1 if $response->code == 401;
    return 0;
}

1;

__END__

=head1 NAME

Business::TNT::ExpressConnect - TNT ExpressConnect interface

=head1 SYNOPSIS

    my $tnt = Business::TNT::ExpressConnect->new();
    my $tnt_prices = $tnt->get_prices({file => $xml_filename});

    my %params = (
        sender             => {country => 'AT', town => 'Vienna',    postcode => 1020},
        delivery           => {country => 'AT', town => 'Schwechat', postcode => '2320'},
        consignmentDetails => {
            totalWeight         => 1.25,
            totalVolume         => 0.1,
            totalNumberOfPieces => 1
        }
    );

    $tnt_prices = $tnt->get_prices({params => \%params});

    warn join("\n",@{$tnt->errors}) unless ($tnt_prices);


=head1 NOTE

WORK IN PROGRESS

=head1 DESCRIPTION

=head1 CONFIGURATION

=head2 etc/tnt-expressconnect.ini

    username = john
    password = secret

=head1 AUTHOR

Jozef Kutej, C<< <jkutej at cpan.org> >>;
Andrea Pavlovic, C<< <spinne at cpan.org> >>

=head1 CONTRIBUTORS

The following people have contributed to the meon::Web by committing their
code, sending patches, reporting bugs, asking questions, suggesting useful
advice, nitpicking, chatting on IRC or commenting on my blog (in no particular
order):

    you?

=head1 LICENSE AND COPYRIGHT

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.

=cut
