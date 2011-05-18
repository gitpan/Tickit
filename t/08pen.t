#!/usr/bin/perl

use strict;

use Test::More tests => 23;
use Test::Refcount;

use Tickit::Pen;

my $pen = Tickit::Pen->new;

my $changed = 0;

isa_ok( $pen, "Tickit::Pen", '$pen isa Tickit::Pen' );

my $observer = bless {}, "PenObserver";
$pen->add_on_changed( $observer );

is_oneref( $observer, 'Pen observer does not increase refcount' );

is_deeply( { $pen->getattrs }, {}, '$pen initial attrs' );
is( $pen->getattr( 'fg' ), undef, '$pen fg initially undef' );

is( $changed, 0, '$changed before chattr' );

$pen->chattr( fg => 3 );

is_deeply( { $pen->getattrs }, { fg => 3 }, '$pen attrs after chattr' );
is( $pen->getattr( 'fg' ), 3, '$pen fg after chattr' );

is( $changed, 1, '$changed after chattr' );

$pen->chattr( fg => "blue" );

is_deeply( { $pen->getattrs }, { fg => 4 }, '$pen attrs fg named' );
is( $pen->getattr( 'fg' ), 4, '$pen fg named' );

is( $changed, 2, '$changed after chattr named' );

$pen->chattr( fg => "hi-blue" );

is_deeply( { $pen->getattrs }, { fg => 12 }, '$pen attrs fg named high-intensity' );
is( $pen->getattr( 'fg' ), 12, '$pen fg named high-intensity' );

is( $changed, 3, '$changed after chattr named high-intensity' );

$pen->delattr( 'fg' );

is_deeply( { $pen->getattrs }, {}, '$pen attrs after delattr' );
is( $pen->getattr( 'fg' ), undef, '$pen fg after delattr' );

is( $changed, 4, '$changed after delattr' );

my %attrs = ( b => 1, na => 5 );

$pen->chattrs( \%attrs );

is( $changed, 5, '$changed after chattrs' );

is_deeply( { $pen->getattrs }, { b => 1 }, '$pen attrs after chattrs' );
is_deeply( \%attrs, { na => 5 }, '%attrs after chattrs' );

$pen->remove_on_changed( $observer );

$pen->chattr( fg => "red" );

is( $changed, 5, '$changed unchanged after remove+chattr' );

$pen = Tickit::Pen->new( fg => 1, bg => 2 );

is_deeply( { $pen->getattrs }, { fg => 1, bg => 2 }, '$pen initial attrs' );

is( $pen->getattr( 'fg' ), 1, '$pen fg initially 1' );

package PenObserver;
sub on_pen_changed { $changed++ }