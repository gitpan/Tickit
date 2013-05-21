#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use Test::Identity;
use Test::Refcount;

use Tickit::Test;

use Tickit::Widget;

my $win = mk_window;

my $render_called = 0;
my %render_args;
my $gained_window;
my $lost_window;
my $widget = TestWidget->new;

is_oneref( $widget, '$widget has refcount 1 initially' );

identical( $widget->window, undef, '$widget->window initally' );
is( $render_called, 0, 'render not yet called' );

$widget->set_window( $win );

flush_tickit;

identical( $widget->window, $win, '$widget->window after set_window' );
is( $render_called, 1, 'render is called after set_window' );

identical( $widget->window->pen, $widget->pen, '$widget->window shares pen' );

is_deeply( \%render_args,
   {
      rect  => Tickit::Rect->new( top => 0, left => 0, lines => 25, cols => 80 ),
      top   => 0,
      left  => 0,
      lines => 25,
      cols  => 80,
   }, 'render arguments after set_window' );

identical( $gained_window, $win, '$widget->window_gained called' );

is_display( [ [TEXT("Hello")] ],
            'Display initially' );

$widget->pen->chattr( fg => 2 );

flush_tickit;

is_display( [ [TEXT("Hello",fg=>2), BLANK(75,fg=>2)] ],
            'Display with correct pen after pen->chattr' );

$widget->set_pen( Tickit::Pen->new( fg => 4 ) );

identical( $widget->window->pen, $widget->pen, '$widget->window shares pen after ->set_pen' );

flush_tickit;

is_display( [ [TEXT("Hello",fg=>4), BLANK(75,fg=>2)] ],
            'Display with correct pen after ->chpen' );

$widget->set_window( undef );

identical( $lost_window, $win, '$widget->window_lost called' );

is_oneref( $widget, '$widget has refcount 1 at EOF' );

done_testing;

package TestWidget;

use base qw( Tickit::Widget );

use constant CLEAR_BEFORE_RENDER => 0;
sub render
{
   my $self = shift;
   %render_args = @_;

   $render_called++;

   $self->window->goto( 0, 0 );
   $self->window->print( "Hello" );
}

sub lines { 1 }
sub cols  { 5 }

sub window_gained
{
   my $self = shift;
   ( $gained_window ) = @_;
   $self->SUPER::window_gained( @_ );
}

sub window_lost
{
   my $self = shift;
   ( $lost_window ) = @_;
   $self->SUPER::window_lost( @_ );
}
