#!/usr/bin/perl

use strict;

use Test::More tests => 12;
use Test::Identity;

use Tickit::Term;

my $term = Tickit::Term->new();
$term->set_size( 25, 80 );

{
   is( $term->lines, 25, '$term->lines 25 initially' );
   is( $term->cols,  80, '$term->cols 80 initially' );

   my ( $lines, $cols );
   my $id = $term->bind_event( resize => sub {
      my ( undef, $ev, $args ) = @_;
      identical( $_[0], $term, '$_[0] is term for resize event' );
      is( $ev, "resize", '$ev is resize for resize event' );
      $lines = $args->{lines};
      $cols  = $args->{cols};
   } );

   ok( defined $id, '$id defined for $term->bind_event' );

   $term->set_size( 30, 100 );

   is( $term->lines,  30, '$term->lines 30 after set_size' );
   is( $term->cols,  100, '$term->cols 100 after set_size' );

   is( $lines,  30, '$lines to bind_event sub after set_size' );
   is( $cols,  100, '$cols to bind_event sub after set_size' );

   $term->unbind_event_id( $id );
}

# Legacy event handling
{
   my ( $lines, $cols );
   $term->set_on_resize( sub {
      identical( shift, $term, '$_[0] is $term for on_resize' );
      ( $lines, $cols ) = @_;
   } );

   $term->set_size( 40, 120 );

   is( $lines,  40, '$lines to on_resize after set_size' );
   is( $cols,  120, '$cols to on_resize after set_size' );
}
