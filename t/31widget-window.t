#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use Test::Identity;
use Test::Refcount;

use Tickit::Test;

use Tickit::Widget;

my $win = mk_window;

my $gained_window;
my $lost_window;
my $render_rect;
my $widget = TestWidget->new;

is_oneref( $widget, '$widget has refcount 1 initially' );

identical( $widget->window, undef, '$widget->window initally' );

$widget->set_window( $win );

flush_tickit;

identical( $widget->window, $win, '$widget->window after set_window' );

identical( $widget->window->pen, $widget->pen, '$widget->window shares pen' );

identical( $gained_window, $win, '$widget->window_gained called' );

is( $render_rect,
    Tickit::Rect->new( top => 0, left => 0, lines => 25, cols => 80 ),
    '$rect to ->render_to_rb method' );

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

sub render_to_rb
{
   my $self = shift;
   ( my $rb, $render_rect ) = @_;

   $rb->text_at( 0, 0, "Hello" );
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
