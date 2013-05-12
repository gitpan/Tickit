#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
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

presskey( text => "A" );

is_deeply( \@key_events, [ [ text => "A" ] ], 'on_key A' );

pressmouse( press => 1, 4, 3 );

is_deeply( \@mouse_events, [ [ press => 1, 4, 3 ] ], 'on_mouse abs@3,4' );

is_oneref( $widget, '$widget has refcount 1 at EOF' );

done_testing;

package TestWidget;

use base qw( Tickit::Widget );

use constant CLEAR_BEFORE_RENDER => 0;
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
   my ( $args ) = @_;
   push @key_events, [ $args->type => $args->str ];
}

sub on_mouse
{
   my $self = shift;
   my ( $args ) = @_;
   push @mouse_events, [ $args->type => $args->button, $args->line, $args->col ];
}
