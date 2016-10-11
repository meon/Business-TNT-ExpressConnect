package Business::TNT::ExpressConnect;

our $VERSION = '0.01';

use Path::Class qw(dir file);
use Config::INI::Reader;
use LWP::UserAgent;

use Business::TNT::ExpressConnect::SPc;

our $user_agent;
our $config;
our $tnt_get_price_url = 'https://express.tnt.com/expressconnect/pricing/getprice';

sub get_price {
    return 'TODO';
}

sub http_ping {
    my $response = _user_agent()->get($tnt_get_price_url);

    return 1 if $response->code == 401;
    return 0;
}

sub _user_agent {
    return $user_agent
        if $user_agent;

    my $user_agent = LWP::UserAgent->new;
    $user_agent->timeout(10);
    $user_agent->env_proxy;

    return $user_agent;
}

sub _config {
    return $config if defined($config);

    my $config_filename =
        file(Business::TNT::ExpressConnect::SPc->sysconfdir, 'tnt-expressconnect.ini');
    if (-r $config_filename) {
        $config = Config::INI::Reader->read_file($config_filename);
    }
    else {
        $config = {};
    }

    return $config;
}

sub _xsd_basedir {
    dir(Business::TNT::ExpressConnect::SPc->datadir, 'tnt-expressconnect', 'xsd', 'pricing', 'v3');
}

sub _price_request_in_xsd {
    return _xsd_basedir->file('PriceRequestIN.xsd');
}

sub _price_request_out_xsd {
    return _xsd_basedir->file('PriceResponseOUT.xsd');
}

1;

__END__

=head1 NAME

Business::TNT::ExpressConnect - TNT ExpressConnect interface

=head1 SYNOPSIS

    my $tnt = Business::TNT::ExpressConnect->new();
    my $tnt_prices = $tnt->get_price(
        sender => {},
        delivery => {},
        collection_datetime => {},
    )

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
