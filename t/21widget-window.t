#!/usr/bin/perl

use strict;

use Test::More tests => 10;
use Test::Identity;
use Test::Refcount;

use Tickit::Test;

use Tickit::Widget;

my $win = mk_window;

my $render_called = 0;
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

identical( $gained_window, $win, '$widget->window_gained called' );

is_termlog( [ SETPEN,
              CLEAR,
              GOTO(0,0),
              SETPEN,
              PRINT("Hello"), ],
            'Termlog initially' );

$widget->pen->chattr( fg => 2 );

flush_tickit;

is_termlog( [ SETPEN(fg => 2),
              CLEAR,
              GOTO(0,0),
              SETPEN(fg => 2),
              PRINT("Hello"), ],
            'Termlog with correct pen' );

$widget->set_window( undef );

identical( $lost_window, $win, '$widget->window_lost called' );

is_oneref( $widget, '$widget has refcount 1 at EOF' );

package TestWidget;

use base qw( Tickit::Widget );

sub render
{
   my $self = shift;

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
}

sub window_lost
{
   my $self = shift;
   ( $lost_window ) = @_;
}
