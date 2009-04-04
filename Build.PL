use strict;
use warnings;
use Module::Build::Smolder;

my $builder = Module::Build::Smolder->new(
    module_name       => 'Net::Mollom',
    license           => 'perl',
    dist_author       => 'Michael Peters <mpeters@plusthree.com>',
    dist_version_from => 'lib/Net/Mollom.pm',
    build_requires    => {
        'Test::More'        => 0,
        'Any::Moose'        => 0,
        'XML::RPC'          => 0.9,
        'Params::Validate'  => 0,
        'Digest::HMAC_SHA1' => 0,
        'MIME::Base64'      => 0,
        'DateTime'          => 0,
    },
    add_to_cleanup => ['Net-Mollom-*'],
);

$builder->create_build_script();
