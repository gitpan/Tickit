use strict;
use warnings;

use Module::Build;

my $build = Module::Build->new(
   module_name => 'Tickit',
   requires => {
      'IO::Async' => 0.29,
      'IO::Async::Stream' => '0.34',
      'IO::Async::Test' => 0,
      'List::MoreUtils' => 0,
      'Term::Terminfo' => 0,
      'Term::Size' => 0,
      'Term::TermKey::Async' => 0,
   },
   build_requires => {
      'Test::Exception' => 0,
      'Test::HexString' => 0,
      'Test::Identity' => 0,
      'Test::More' => 0,
      'Test::Refcount' => 0,
   },
   license => 'perl',
   create_makefile_pl => 'traditional',
);
  
$build->create_build_script;
