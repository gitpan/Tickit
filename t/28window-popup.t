#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use Test::Identity;
use Test::Refcount;

use Tickit::Test;

my $root = mk_window;

my $win = $root->make_sub( 10, 20, 1, 50 );
flush_tickit;

my $popupwin = $win->make_popup( 2, 2, 10, 10 );
flush_tickit;

is_oneref( $popupwin, '$popupwin has refcount 1 initially' );

identical( $popupwin->parent, $root, '$popupwin->parent is $root' );

is( $popupwin->abs_top,  12, '$popupwin->abs_top' );
is( $popupwin->abs_left, 22, '$popupwin->abs_left' );

my @key_events;
$popupwin->set_on_key( with_ev => sub {
   my ( $win, $ev ) = @_;
   push @key_events, [ $ev->type => $ev->str ];
   return 1;
} );

presskey( text => "G" );

my @mouse_events;
$popupwin->set_on_mouse( with_ev => sub {
   my ( $win, $ev ) = @_;
   push @mouse_events, [ $ev->type => $ev->button, $ev->line, $ev->col ];
   return 1;
} );

pressmouse( press => 1, 5, 12 );

is_deeply( \@mouse_events, [ [ press => 1, -7, -10 ] ] );

done_testing;
