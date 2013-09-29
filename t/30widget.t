#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use Test::Refcount;

my $lines = 1;
my $cols  = 5;
my $widget = TestWidget->new;

ok( defined $widget, 'defined $widget' );

is_oneref( $widget, '$widget has refcount 1 initially' );

my $pen = $widget->pen;
isa_ok( $pen, "Tickit::Pen", '$pen' );

is_deeply( { $widget->pen->getattrs }, {}, '$widget pen initially empty' );
is( $widget->pen->getattr('b'), undef, '$widget pen does not define b' );

is_deeply( [ $widget->requested_size ], [ 1, 5 ],
           '$widget->requested_size initially' );

$pen->chattr( u => 1 );

is_deeply( { $widget->pen->getattrs }, { u => 1 }, '$widget pen now has u=1' );
is( $widget->pen->getattr('u'), 1, '$widget pen defines u as 1' );

{
   my $widget = TestWidget->new(
      i => 1,
   );

   is_deeply( { $widget->pen->getattrs }, { i => 1 }, 'Widget constructor sets initial pen' );
}

$lines = 2;
is_deeply( [ $widget->requested_size ], [ 1, 5 ],
           '$widget->requested_size unchanged before ->resized' );

$widget->resized;
is_deeply( [ $widget->requested_size ], [ 2, 5 ],
           '$widget->requested_size changed after ->resized' );

$widget->set_requested_size( 3, 8 );
is_deeply( [ $widget->requested_size ], [ 3, 8 ],
           '$widget->requested_size changed again after ->set_requested_size' );

is_oneref( $widget, '$widget has refcount 1 at EOF' );

done_testing;

package TestWidget;

use base qw( Tickit::Widget );

sub render_to_rb {}

sub lines { $lines }
sub cols  { $cols }
