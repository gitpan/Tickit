#!/usr/bin/perl

use strict;

use Test::More tests => 41;
use Test::Identity;
use Test::Refcount;

use Tickit::Test;

my ( $term, $rootwin ) = mk_term_and_window;

# Already 2 references; Tickit object keeps a permanent one, and we have one
# here. This is fine.
is_refcount( $rootwin, 2, '$rootwin has refcount 2 initially' );

my $win = $rootwin->make_sub( 3, 10, 4, 20 );

is_oneref( $win, '$win has refcount 1 initially' );
is_refcount( $rootwin, 3, '$rootwin has refcount 3 after ->make_sub' );

is( "$win", 'Tickit::Window[20x4 abs@10,3]', '$win string overload' );
ok( $win != $rootwin, '$win numeric comparison compares object identities' );

my $geom_changed = 0;
$win->set_on_geom_changed( sub { $geom_changed++ } );

isa_ok( $win, "Tickit::Window", '$win isa Tickit::Window' );

is( $win->top,   3, '$win->top' );
is( $win->left, 10, '$win->left' );

is( $win->abs_top,   3, '$win->abs_top' );
is( $win->abs_left, 10, '$win->abs_left' );

is( $win->lines,  4, '$win->lines' );
is( $win->cols,  20, '$win->cols' );

isa_ok( my $rect = $win->rect, "Tickit::Rect", '$win->rect' );
is( $rect->top,     3, '$win->rect->top' );
is( $rect->left,   10, '$win->rect->left' );
is( $rect->bottom,  7, '$win->rect->bottom' );
is( $rect->right,  30, '$win->rect->right' );

identical( $win->parent, $rootwin, '$win->parent' );
identical( $win->root,   $rootwin, '$win->root' );

identical( $win->term, $term, '$win->term' );

is( $geom_changed, 0, '$reshaped is 0 before resize' );

$win->resize( 4, 15 );

is( $win->lines, 4, '$win->lines is 4 after resize' );
is( $win->cols, 15, '$win->cols is 15 after resize' );

is( $geom_changed, 1, '$reshaped is 1 after resize' );

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
is_refcount( $rootwin, 3, '$rootwin has refcount 3 before $win drop' );

undef $subwin;
undef $win;

is_refcount( $rootwin, 2, '$rootwin has refcount 3 at EOF' );
