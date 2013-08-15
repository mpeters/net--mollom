#!perl -T
use strict;
use warnings;
use Test::More;
use Net::Mollom;

package Test::Net::Mollom;
use base 'Net::Mollom';

sub _make_api_call { $main::API_CALLS++; return shift->SUPER::_make_api_call(@_) };

package main;

our $API_CALLS = 0;

use 5.014;
say "version: $Net::Mollom::VERSION";

{
    my $mollom = Test::Net::Mollom->new(
        private_key => '42d54a81124966327d40c928fa92de0f',
        public_key => '72446602ffba00c907478c8f45b83b03',
    );
    $mollom->server_list;
}
is($API_CALLS,1,"reality check: server_list makes one API call if it hasn't been called before.");
{
    my $mollom = Test::Net::Mollom->new(
        private_key => '42d54a81124966327d40c928fa92de0f',
        public_key => '72446602ffba00c907478c8f45b83b03',
    );
    $mollom->server_list;
}

is($API_CALLS,1,'server_list is persistent at the package level. A second object re-uses the same list.');

done_testing;
