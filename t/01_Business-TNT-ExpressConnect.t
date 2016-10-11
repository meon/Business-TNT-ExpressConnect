#!/usr/bin/perl

use strict;
use warnings;

use Test::Most;

use_ok('Business::TNT::ExpressConnect') or exit;

my $config;
subtest 'files' => sub {
    ok(-r Business::TNT::ExpressConnect->_price_request_in_xsd,  'PriceRequestIN.xsd present');
    ok(-r Business::TNT::ExpressConnect->_price_request_out_xsd, 'PriceResponseOUT.xsd present');
    is(ref(eval {$config = Business::TNT::ExpressConnect->_config}),
        'HASH', 'try to load configuration file');
};

# finished with off-line testing unless username and password set in configuration file
unless ($config->{_}->{username}) {
SKIP: {
        skip 'skipping on-line testing etc/tnt-expressconnect.ini not filled with credentials', 1;
    }
    done_testing();
    exit(0);
}

# finish unless TNT servers are reachable
unless (Business::TNT::ExpressConnect->http_ping) {
SKIP: {
        skip 'skipping on-line testing, '
            . $Business::TNT::ExpressConnect::tnt_get_price_url
            . ' not reachable', 1;
    }
    done_testing();
    exit(0);
}

subtest 'on-line' => sub {
    ok(1, 'TODO on-line testing');
};

done_testing();
