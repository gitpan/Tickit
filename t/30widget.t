#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use Test::Refcount;

my $widget = TestWidget->new;

ok( defined $widget, 'defined $widget' );

is_oneref( $widget, '$widget has refcount 1 initially' );

my $pen = $widget->pen;
isa_ok( $pen, "Tickit::Pen", '$pen' );

is_deeply( { $widget->pen->getattrs }, {}, '$widget pen initially empty' );
is( $widget->pen->getattr('b'), undef, '$widget pen does not define b' );

$pen->chattr( u => 1 );

is_deeply( { $widget->pen->getattrs }, { u => 1 }, '$widget pen now has u=1' );
is( $widget->pen->getattr('u'), 1, '$widget pen defines u as 1' );

{
   my $widget = TestWidget->new(
      i => 1,
   );

   is_deeply( { $widget->pen->getattrs }, { i => 1 }, 'Widget constructor sets initial pen' );
}

is_oneref( $widget, '$widget has refcount 1 at EOF' );

done_testing;

package TestWidget;

use base qw( Tickit::Widget );

use constant CLEAR_BEFORE_RENDER => 0;
sub render {}

sub lines { 1 }
sub cols  { 5 }
