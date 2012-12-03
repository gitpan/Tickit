#!/usr/bin/perl

use strict;

use Test::More tests => 5;
use Test::Identity;
use Test::Refcount;

use Tickit::Test;

my $root = mk_window;

my $win = $root->make_sub( 10, 20, 1, 50 );

my $popupwin = $win->make_popup( 2, 2, 10, 10 );

is_oneref( $popupwin, '$popupwin has refcount 1 initially' );

identical( $popupwin->parent, $root, '$popupwin->parent is $root' );

is( $popupwin->abs_top,  12, '$popupwin->abs_top' );
is( $popupwin->abs_left, 22, '$popupwin->abs_left' );

my @key_events;
$popupwin->set_on_key( sub {
   push @key_events, [ $_[1] => $_[2] ];
   return 1;
} );

presskey( text => "G" );

my @mouse_events;
$popupwin->set_on_mouse( sub {
   push @mouse_events, [ @_[1..4] ];
   return 1;
} );

pressmouse( press => 1, 5, 12 );

is_deeply( \@mouse_events, [ [ press => 1, -7, -10 ] ] );
