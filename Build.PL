use strict;
use warnings;

use Module::Build;
use ExtUtils::PkgConfig;

my %build_args;

sub add_cflags_libs
{
   my ( $modname ) = @_;

   my $cflags = ExtUtils::PkgConfig->cflags( $modname );
   my $libs   = ExtUtils::PkgConfig->libs( $modname );

   push @{ $build_args{extra_compiler_flags} }, split( m/ +/, $cflags );

   push @{ $build_args{extra_linker_flags} }, split( m/ +/, $libs );
}

if( eval { ExtUtils::PkgConfig->modversion( "tickit" ) } ) {
   # libtickit installed; just use it
   add_cflags_libs "tickit";
}
else {
   # libtickit not installed; use bundled source code instead
   $build_args{c_source}     = "src";
   $build_args{include_dirs} = "include";

   $build_args{extra_compiler_flags} = [qw( -std=c99 )];

   # bundled source still needs libtermkey and optionally can use
   # unibilium
   if( eval { ExtUtils::PkgConfig->modversion( "unibilium" ) } ) {
      push @{ $build_args{extra_compiler_flags} }, qw( -DHAVE_UNIBILIUM );

      add_cflags_libs "unibilium";
   }
   elsif( eval { ExtUtils::PkgConfig->modversion( "ncursesw" ) } ) {
      add_cflags_libs "ncursesw";
   }
   else {
      push @{ $build_args{extra_linker_flags} }, qw( -lncurses );
   }

   eval { ExtUtils::PkgConfig->modversion( "termkey" ); 1 } or
      die "OS unsupported - need libtermkey";

   add_cflags_libs "termkey";
}

my $build = Module::Build->new(
   module_name => 'Tickit',
   %build_args,
   requires => {
      'Exporter' => '5.57',
      'List::MoreUtils' => 0,
   },
   configure_requires => {
      'ExtUtils::PkgConfig' => 0,
      'Module::Build' => 0,
   },
   build_requires => {
      'Test::Builder::Tester' => 0,
      'Test::Fatal' => 0,
      'Test::HexString' => 0,
      'Test::Identity' => 0,
      'Test::More' => 0,
      'Test::Refcount' => 0,
   },
   auto_configure_requires => 1,
   license => 'perl',
   create_makefile_pl => 'small',
   create_license => 1,
   create_readme  => 1,
);

$build->create_build_script;
