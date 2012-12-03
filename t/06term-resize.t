#!/usr/bin/perl

use strict;

use Test::More tests => 7;
use Test::Identity;

use Tickit::Term;

my $term = Tickit::Term->new();
$term->set_size( 25, 80 );

my ( $lines, $cols );
$term->set_on_resize( sub {
   identical( shift, $term, '$_[0] is $term for on_resize' );
   ( $lines, $cols ) = @_;
} );

is( $term->lines, 25, '$term->lines 25 initially' );
is( $term->cols,  80, '$term->cols 80 initially' );

$term->set_size( 30, 100 );

is( $term->lines,  30, '$term->lines 30 after set_size' );
is( $term->cols,  100, '$term->cols 100 after set_size' );

is( $lines,  30, '$lines to on_resize after set_size' );
is( $cols,  100, '$cols to on_resize after set_size' );
