#!/usr/bin/perl

use strict;

use Test::More tests => 5;
use Test::Refcount;

use Tickit::Test;

use Tickit::Widget;

my ( $term, $win ) = mk_term_and_window;

my @key_events;
my @mouse_events;
my $widget = TestWidget->new;

is_oneref( $widget, '$widget has refcount 1 initially' );

$widget->set_window( $win );

flush_tickit;

ok( $term->{cursorvis}, 'Cursor visible on window' );

$term->presskey( text => "A" );

is_deeply( \@key_events, [ [ text => "A" ] ], 'on_key A' );

$term->pressmouse( press => 1, 4, 3 );

is_deeply( \@mouse_events, [ [ press => 1, 4, 3 ] ], 'on_mouse abs@3,4' );

is_oneref( $widget, '$widget has refcount 1 at EOF' );

package TestWidget;

use base qw( Tickit::Widget );

sub render
{
   my $self = shift;
   $self->window->focus( 0, 0 );
}

sub lines  { 1 }
sub cols   { 1 }

sub on_key
{
   my $self = shift;
   push @key_events, [ $_[0] => $_[1] ];
}

sub on_mouse
{
   my $self = shift;
   push @mouse_events, [ @_ ];
}
