#!/usr/bin/perl

use strict;

use Test::More tests => 8;
use Test::Refcount;

my $widget = TestWidget->new;

ok( defined $widget, 'defined $widget' );

is_oneref( $widget, '$widget has refcount 1 initially' );

is_deeply( { $widget->getpen }, {}, '$widget pen initially empty' );
is( $widget->getpenattr('b'), undef, '$widget pen does not define b' );

$widget->chpen( b => 1 );

is_deeply( { $widget->getpen }, { b => 1 }, '$widget pen now has b=1' );
is( $widget->getpenattr('b'), 1, '$widget pen defines b as 1' );

{
   my $widget = TestWidget->new(
      i => 1,
   );

   is_deeply( { $widget->getpen }, { i => 1 }, 'Widget constructor sets initial pen' );
}

is_oneref( $widget, '$widget has refcount 1 at EOF' );

package TestWidget;

use base qw( Tickit::Widget );

sub render {}

sub lines { 1 }
sub cols  { 5 }
