#!/usr/bin/perl

use strict;

use Test::More tests => 26;

use Tickit::Rect;

my $rect = Tickit::Rect->new(
   top  => 5,
   left => 10,
   lines => 7,
   cols  => 20,
);

isa_ok( $rect, "Tickit::Rect", '$rect' );

is( $rect->top,     5, '$rect->top' );
is( $rect->left,   10, '$rect->left' );
is( $rect->lines,   7, '$rect->lines' );
is( $rect->cols,   20, '$rect->cols' );
is( $rect->bottom, 12, '$rect->bottom' );
is( $rect->right,  30, '$rect->right' );

my $subrect;

$subrect = $rect->intersect( Tickit::Rect->new( top => 0, left => 0, lines => 25, cols => 80 ) );
is( $subrect->top,     5, '$subrect->top after intersect wholescreen' );
is( $subrect->left,   10, '$subrect->left after intersect wholescreen' );
is( $subrect->lines,   7, '$subrect->lines after intersect wholescreen' );
is( $subrect->cols,   20, '$subrect->cols after intersect wholescreen' );
is( $subrect->bottom, 12, '$subrect->bottom after intersect wholescreen' );
is( $subrect->right,  30, '$subrect->right after intersect wholescreen' );

$subrect = $rect->intersect( Tickit::Rect->new( top => 10, left => 20, lines => 15, cols => 60 ) );
is( $subrect->top,    10, '$subrect->top after intersect partial' );
is( $subrect->left,   20, '$subrect->left after intersect partial' );
is( $subrect->lines,   2, '$subrect->lines after intersect partial' );
is( $subrect->cols,   10, '$subrect->cols after intersect partial' );
is( $subrect->bottom, 12, '$subrect->bottom after intersect partial' );
is( $subrect->right,  30, '$subrect->right after intersect partial' );

$subrect = $rect->intersect( Tickit::Rect->new( top => 20, left => 20, lines => 5, cols => 60 ) );
ok( !defined $subrect, '$subrect undefined after intersect outside' );

$rect = Tickit::Rect->new(
   top    => 3,
   left   => 8,
   bottom => 9,
   right  => 22,
);

is( $rect->top,     3, '$rect->top' );
is( $rect->left,    8, '$rect->left' );
is( $rect->lines,   6, '$rect->lines' );
is( $rect->cols,   14, '$rect->cols' );
is( $rect->bottom,  9, '$rect->bottom' );
is( $rect->right,  22, '$rect->right' );
