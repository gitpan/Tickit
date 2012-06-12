#!/usr/bin/perl

use strict;

use Test::More tests => 19;

use Tickit::Test;

my ( $term, $rootwin ) = mk_term_and_window;

my $win = $rootwin->make_sub( 3, 10, 4, 20 );

my $root_exposed;
$rootwin->set_on_expose( sub { $root_exposed++ } );

my $win_exposed;
my $exposed_rect;
$win->set_on_expose( sub { shift; ( $exposed_rect ) = @_; $win_exposed++ } );

$rootwin->expose;

ok( !$exposed_rect, 'on_expose not yet invoked' );

flush_tickit;

is( $exposed_rect->top,    0, '$exposed_rect->top after $rootwin->expose' );
is( $exposed_rect->left,   0, '$exposed_rect->left after $rootwin->expose' );
is( $exposed_rect->lines,  4, '$exposed_rect->lines after $rootwin->expose' );
is( $exposed_rect->cols,  20, '$exposed_rect->cols after $rootwin->expose' );
is( $root_exposed, 1, '$root expose count 1 after $rootwin->expose' );
is( $win_exposed,  1, '$win expose count 1 after $rootwin->expose' );

$win->expose;

flush_tickit;

is( $exposed_rect->top,    0, '$exposed_rect->top after $win->expose' );
is( $exposed_rect->left,   0, '$exposed_rect->left after $win->expose' );
is( $exposed_rect->lines,  4, '$exposed_rect->lines after $win->expose' );
is( $exposed_rect->cols,  20, '$exposed_rect->cols after $win->expose' );
is( $root_exposed, 1, '$root expose count 1 after $win->expose' );
is( $win_exposed, 2, '$win expose count 2 after $win->expose' );

$rootwin->expose;
$win->expose;

flush_tickit;

is( $root_exposed, 2, '$root expose count 2 after root-then-win' );
is( $win_exposed, 3, '$win expose count 3 after root-then-win' );

$win->expose;
$rootwin->expose;

flush_tickit;

is( $root_exposed, 3, '$root expose count 3 after win-then-root' );
is( $win_exposed, 4, '$win expose count 4 after win-then-root' );

$win->hide;
$win->show;

flush_tickit;

is( $root_exposed, 3, '$root expose count 3 after hide+show' );
is( $win_exposed, 5, '$win expose count 5 after hide+show' );
