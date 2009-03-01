#!perl -T
use strict;
use warnings;
use Test::More (tests => 8);
use Net::Mollom;

# bad public and private keys
my $mollom = Net::Mollom->new(
    private_key => '123',
    public_key => '456',
);
isa_ok($mollom, 'Net::Mollom');
my $result;
eval { $result = $mollom->verify_key };
ok($@);
like($@, qr/could not find your public key/);

# bad private key
$mollom = Net::Mollom->new(
    private_key => '123',
    public_key => '72446602ffba00c907478c8f45b83b03',
);
isa_ok($mollom, 'Net::Mollom');
eval { $result = $mollom->verify_key };
ok($@);
like($@, qr/hash is incorrect/);

# good public and private keys
$mollom = Net::Mollom->new(
    private_key => '42d54a81124966327d40c928fa92de0f',
    public_key => '72446602ffba00c907478c8f45b83b03',
);
isa_ok($mollom, 'Net::Mollom');
$result = $mollom->verify_key();
is($result, 1, 'key is verified');
