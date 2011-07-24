use strict;
use warnings;

use Module::Build;

my $build = Module::Build->new(
   module_name => 'Tickit',
   requires => {
      'Exporter' => '5.57',
      'IO::Async' => 0.29,
      'IO::Async::Stream' => '0.34',
      'IO::Async::Test' => 0,
      'List::MoreUtils' => 0,
      'Term::Terminfo' => 0,
      'Term::Size' => 0,
      'Term::TermKey::Async' => 0,
   },
   build_requires => {
      'Test::Fatal' => 0,
      'Test::HexString' => 0,
      'Test::Identity' => 0,
      'Test::More' => 0,
      'Test::Refcount' => 0,
   },
   auto_configure_requires => 0, # Don't add M::B to configure_requires
   license => 'perl',
   create_makefile_pl => 'traditional',
   create_license => 1,
   create_readme  => 1,
);

$build->create_build_script;
