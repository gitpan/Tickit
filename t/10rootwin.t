#!/usr/bin/perl

use strict;

use Test::More tests => 36;
use Test::Identity;
use Test::Refcount;

use Tickit::Test;

use Tickit;

my $term = mk_term;

my $tickit = Tickit->new(
   term => $term
);

my $win = $tickit->rootwin;

isa_ok( $win, "Tickit::RootWindow", '$win isa Tickit::RootWindow' );
isa_ok( $win, "Tickit::Window", '$win isa Tickit::Window' );

# Already 2 references; Tickit object keeps a permanent one, and we have one
# here. This is fine.
is_refcount( $win, 2, '$win has refcount 2 initially' );

my $geom_changed = 0;
$win->set_on_geom_changed( sub { $geom_changed++ } );

is( $win->top,  0, '$win->top is 0' );
is( $win->left, 0, '$win->left is 0' );

is( $win->abs_top,  0, '$win->abs_top is 0' );
is( $win->abs_left, 0, '$win->abs_left is 0' );

is( $win->lines, 25, '$win->lines is 25' );
is( $win->cols,  80, '$win->cols is 80' );

identical( $win->term, $term, '$win->term returns $term' );

isa_ok( $win->pen, "Tickit::Pen", '$win->pen isa Tickit::Pen' );

is_deeply( { $win->getpenattrs },
           {},
           '$win has no attrs set' );

is( $win->getpenattr( 'fg' ), undef, '$win has pen fg undef' );

is_deeply( { $win->get_effective_penattrs },
           {},
           '$win->get_effective_penattrs has no attrs set' );

is( $win->get_effective_penattr( 'fg' ), undef, '$win has effective pen fg undef' );

$win->goto( 2, 3 );
$win->print( "Hello" );

is_termlog( [ GOTO(2,3),
              SETPEN,
              PRINT("Hello"), ],
            'Termlog initially' );

is_display( [ "", "", "   Hello", ],
            'Display initially' );

$win->pen->chattr( fg => 3 );

is_deeply( { $win->getpenattrs },
           { fg => 3 },
           '$win->getpenattrs has fg => 3' );

is( $win->getpenattr( 'fg' ), 3, '$win has pen fg 3' );

is_deeply( { $win->get_effective_penattrs },
           { fg => 3 },
           '$win->get_effective_penattrs has fg => 3' );

is( $win->get_effective_penattr( 'fg' ), 3, '$win has effective pen fg 3' );

my $newpen = Tickit::Pen->new;
$newpen->chattr( fg => 3 );
$newpen->chattr( u => 1 );

$win->set_pen( $newpen );

is_deeply( { $win->getpenattrs },
           { fg => 3, u => 1 },
           '$win->set_pen replaces window pen' );

$win->pen->chattr( u => undef );

$win->goto( 2, 3 );
$win->print( "Hello" );

is_termlog( [ GOTO(2,3),
              SETPEN(fg => 3),
              PRINT("Hello") ],
            'Termlog with correct pen' );

$win->scroll( 1, 0 );

is_termlog( [ SCROLL(0,24,1) ],
            'Termlog scrolled' );

$win->erasech( 15 );

is_termlog( [ SETBG(undef),
              ERASECH(15) ],
            'Termlog chars erased' );

ok( $win->insertch( 10 ), '$win can insertch' );

is_termlog( [ SETBG(undef),
              INSERTCH(10) ],
           'Termlog chars inserted' );

ok( $win->deletech( 8 ), '$win can deletech' );

is_termlog( [ SETBG(undef),
              DELETECH(8) ],
            'Termlog chars deleted' );

$win->clear;

is_termlog( [ SETPEN(fg => 3),
              CLEAR ],
            'Termlog cleared' );

is( $geom_changed, 0, '$reshaped is 0 before term resize' );

$term->resize( 30, 100 );

is( $win->lines, 30, '$win->lines is 30 after term resize' );
is( $win->cols, 100, '$win->cols is 100 after term resize' );

is( $geom_changed, 1, '$reshaped is 1 after term resize' );

is_refcount( $win, 2, '$win has refcount 2 before dropping Tickit' );

undef $tickit;

is_oneref( $win, '$win has refcount 1 at EOF' );
