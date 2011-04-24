#!/usr/bin/perl

use strict;

use Test::More tests => 40;
use Test::Fatal;
use Test::Identity;
use Test::Refcount;
use IO::Async::Test;

use t::MockTerm;
use t::TestTickit;

my ( $term, $rootwin ) = mk_term_and_window;

# Already 2 references; Tickit object keeps a permanent one, and we have one
# here. This is fine.
is_refcount( $rootwin, 2, '$rootwin has refcount 2 initially' );

my $win = $rootwin->make_sub( 3, 10, 4, 20 );

is_oneref( $win, '$win has refcount 1 initially' );
is_refcount( $rootwin, 3, '$rootwin has refcount 3 after ->make_sub' );

is( "$win", 'Tickit::Window[20x4 abs@10,3]', '$win string overload' );

my $geom_changed = 0;
$win->set_on_geom_changed( sub { $geom_changed++ } );

isa_ok( $win, "Tickit::Window", '$win isa Tickit::Window' );

is( $win->top,   3, '$win->top' );
is( $win->left, 10, '$win->left' );

is( $win->abs_top,   3, '$win->abs_top' );
is( $win->abs_left, 10, '$win->abs_left' );

is( $win->lines,  4, '$win->lines' );
is( $win->cols,  20, '$win->cols' );

identical( $win->parent, $rootwin, '$win->parent' );
identical( $win->root,   $rootwin, '$win->root' );

identical( $win->term, $term, '$win->term' );

is( $geom_changed, 0, '$reshaped is 0 before resize' );

$win->resize( 4, 15 );

is( $win->lines, 4, '$win->lines is 4 after resize' );
is( $win->cols, 15, '$win->cols is 15 after resize' );

is( $geom_changed, 1, '$reshaped is 1 after resize' );

ok( exception { $win->goto( 6, 1 ) },
   '$win->goto out of line bounds' );

ok( exception { $win->goto( 0, 50 ) },
   '$win->goto out of col bounds' );

ok( exception { $win->make_sub( -1, 0, 1, 1 ) },
   '$win->make_sub out of top bounds' );

ok( exception { $win->make_sub( 0, 0, 100, 1 ) },
   '$win->make_sub out of bottom bounds' );

ok( exception { $win->make_sub( 0, -1, 1, 1 ) },
   '$win->make_sub out of left bounds' );

ok( exception { $win->make_sub( 0, 0, 1, 100 ) },
   '$win->make_sub out of right bounds' );

my $subwin = $win->make_sub( 2, 2, 1, 10 );

is( $subwin->top,  2, '$subwin->top' );
is( $subwin->left, 2, '$subwin->left' );

is( $subwin->abs_top,   5, '$subwin->abs_top' );
is( $subwin->abs_left, 12, '$subwin->abs_left' );

is( $subwin->lines,  1, '$subwin->lines' );
is( $subwin->cols,  10, '$subwin->cols' );

identical( $subwin->parent, $win, '$subwin->parent' );
identical( $subwin->root,   $rootwin, '$subwin->root' );

identical( $subwin->term, $term, '$subwin->term' );

$win->reposition( 5, 15 );

is( $win->top,   5, '$win->top after reposition' );
is( $win->left, 15, '$win->left after reposition' );

is( $win->abs_top,   5, '$win->abs_top after reposition' );
is( $win->abs_left, 15, '$win->abs_left after reposition' );

is( $geom_changed, 2, '$reshaped is 2 after reposition' );

is_refcount( $win, 2, '$win has refcount 2 at EOF' );
is_refcount( $rootwin, 3, '$rootwin has refcount 3 at EOF' );
