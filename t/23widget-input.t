#!/usr/bin/perl

use strict;

use Test::More tests => 4;
use Test::Refcount;

use t::MockTerm;
use t::TestTickit;

use Tickit::Widget;

my ( $term, $win ) = mk_term_and_window;

my @keys;
my $widget = TestWidget->new;

is_oneref( $widget, '$widget has refcount 1 initially' );

$widget->set_window( $win );

flush_tickit;

ok( $term->{cursorvis}, 'Cursor visible on window' );

$term->presskey( text => "A" );

is_deeply( \@keys, [ [ text => "A" ] ], 'on_key A' );

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
   push @keys, [ $_[0] => $_[1] ];
}
