#!/usr/bin/perl

use strict;

use Test::More tests => 34;
use Test::Identity;
use Test::Refcount;
use IO::Async::Test;

use IO::Async::Loop;

use t::MockTerm;

use Tickit;

my $loop = IO::Async::Loop->new();
testing_loop( $loop );

my $term = t::MockTerm->new;

my $tickit = Tickit->new(
   term => $term
);

$loop->add( $tickit );

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

is_deeply( { $win->getpen },
           { DEFAULTPEN },
           '$win has default attrs' );

is( $win->getpen( 'fg' ), undef, '$win has pen fg undef' );

is_deeply( { $win->get_effective_pen },
           { DEFAULTPEN },
           '$win->get_effective_pen has default attrs' );

is( $win->get_effective_pen( 'fg' ), undef, '$win has effective_pen fg undef' );

$win->goto( 2, 3 );
$win->print( "Hello" );

is_deeply( [ $term->methodlog ], 
          [ GOTO(2,3),
            SETPEN,
            PRINT("Hello"),
          ],
          '$term written to' );

is_deeply( [ $term->get_display ],
           [ BLANKS(2),
             PAD("   Hello"),
             BLANKS(22) ],
           '$term display' );

$win->chpen( fg => 3 );

is_deeply( { $win->getpen },
           { DEFAULTPEN, fg => 3 },
           '$win->getpen has fg => 3' );

is( $win->getpen( 'fg' ), 3, '$win has pen fg 3' );

is_deeply( { $win->get_effective_pen },
           { DEFAULTPEN, fg => 3 },
           '$win->get_effective_pen has fg => 3' );

is( $win->get_effective_pen( 'fg' ), 3, '$win has effective_pen fg 3' );

$win->goto( 2, 3 );
$win->print( "Hello" );

is_deeply( [ $term->methodlog ],
           [ GOTO(2,3),
             SETPEN(fg => 3),
             PRINT("Hello") ],
           '$term written with correct pen' );

$win->scroll( 1, 0 );

is_deeply( [ $term->methodlog ],
           [ [ scroll => 0, 24, 1 ] ],
           '$term scrolled' );

$win->erasech( 15 );

is_deeply( [ $term->methodlog ],
           [ SETBG(undef),
             ERASECH(15) ],
           '$term chars erased' );

ok( $win->insertch( 10 ), '$win can insertch' );

is_deeply( [ $term->methodlog ],
           [ SETBG(undef),
             [ insertch => 10 ] ],
           '$term chars inserted' );

ok( $win->deletech( 8 ), '$win can deletech' );

is_deeply( [ $term->methodlog ],
           [ SETBG(undef),
             [ deletech => 8 ] ],
           '$term chars deleted' );

$win->clear;

is_deeply( [ $term->methodlog ],
           [ SETPEN(fg => 3),
             CLEAR ],
           '$term scrolled' );

is( $geom_changed, 0, '$reshaped is 0 before term resize' );

$term->resize( 30, 100 );

is( $win->lines, 30, '$win->lines is 30 after term resize' );
is( $win->cols, 100, '$win->cols is 100 after term resize' );

is( $geom_changed, 1, '$reshaped is 1 after term resize' );

is_refcount( $win, 2, '$win has refcount 2 before dropping Tickit' );

$loop->remove( $tickit );
undef $tickit;

is_oneref( $win, '$win has refcount 1 at EOF' );
