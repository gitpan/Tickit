#!/usr/bin/perl

use strict;

use Test::More tests => 10;
use Test::Identity;
use Test::Refcount;

use t::MockTerm;
use t::TestTickit;

use Tickit::Widget;

my ( $term, $win ) = mk_term_and_window;

my $render_called = 0;
my $gained_window;
my $lost_window;
my $widget = TestWidget->new;

is_oneref( $widget, '$widget has refcount 1 initially' );

identical( $widget->window, undef, '$widget->window initally' );
is( $render_called, 0, 'render not yet called' );

$widget->set_window( $win );

identical( $widget->window, $win, '$widget->window after set_window' );
is( $render_called, 1, 'render is called after set_window' );

identical( $gained_window, $win, '$widget->window_gained called' );

flush_tickit;

is_deeply( [ $term->methodlog ],
           [ SETPEN,
             CLEAR,
             GOTO(0,0),
             SETPEN,
             PRINT("Hello"), ],
           '$term written to' );

$widget->pen->chattr( fg => 2 );

flush_tickit;

is_deeply( [ $term->methodlog ],
           [ SETPEN(fg => 2),
             CLEAR,
             GOTO(0,0),
             SETPEN(fg => 2),
             PRINT("Hello"), ],
           '$term rewritten with correct pen' );

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
