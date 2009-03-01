#!perl -T
use strict;
use warnings;
use Test::More (tests => 7);
use Net::Mollom;

# ham content
my $mollom = Net::Mollom->new(
    private_key => '42d54a81124966327d40c928fa92de0f',
    public_key => '72446602ffba00c907478c8f45b83b03',
);
isa_ok($mollom, 'Net::Mollom');

# test parameter validation
eval { $mollom->get_statistics };
ok($@);
like($@, qr/'type' missing/);
eval { $mollom->get_statistics(type => 'today_days') };
ok($@);
like($@, qr/did not pass regex check/);

my $count = $mollom->get_statistics(type => 'total_days');
ok($count);
cmp_ok($count, '>=', 0);
