#!/usr/bin/perl

use strict;

use Test::More tests => 13;

use Tickit::Pen;

my $pen = Tickit::Pen->new;

isa_ok( $pen, "Tickit::Pen", '$pen isa Tickit::Pen' );

is_deeply( { $pen->getattrs }, {}, '$pen initial attrs' );
is( $pen->getattr( 'fg' ), undef, '$pen fg initially undef' );

$pen->chattr( fg => 3 );

is_deeply( { $pen->getattrs }, { fg => 3 }, '$pen attrs after chattr' );
is( $pen->getattr( 'fg' ), 3, '$pen fg after chattr' );

$pen->chattr( fg => "blue" );

is_deeply( { $pen->getattrs }, { fg => 4 }, '$pen attrs fg named' );
is( $pen->getattr( 'fg' ), 4, '$pen fg named' );

$pen->delattr( 'fg' );

is_deeply( { $pen->getattrs }, {}, '$pen attrs after delattr' );
is( $pen->getattr( 'fg' ), undef, '$pen fg after delattr' );

my %attrs = ( b => 1, na => 5 );

$pen->chattrs( \%attrs );

is_deeply( { $pen->getattrs }, { b => 1 }, '$pen attrs after chattrs' );
is_deeply( \%attrs, { na => 5 }, '%attrs after chattrs' );

$pen = Tickit::Pen->new( fg => 1, bg => 2 );

is_deeply( { $pen->getattrs }, { fg => 1, bg => 2 }, '$pen initial attrs' );

is( $pen->getattr( 'fg' ), 1, '$pen fg initially 1' );
