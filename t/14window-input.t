#!/usr/bin/perl

use strict;

use Test::More tests => 11;

use Tickit::Test;

my ( $term, $rootwin ) = mk_term_and_window;

my $win = $rootwin->make_sub( 3, 10, 4, 20 );

$win->focus( 0, 0 );

my @key_events;
$win->set_on_key( sub {
   push @key_events, [ $_[1] => $_[2] ];
   return 1;
} );

$term->presskey( text => "A" );

is_deeply( \@key_events, [ [ text => "A" ] ], 'on_key A' );

my @mouse_events;
$win->set_on_mouse( sub {
   push @mouse_events, [ @_[1..4] ];
   return 1;
} );

undef @mouse_events;
$term->pressmouse( press => 1, 5, 15 );

is_deeply( \@mouse_events, [ [ press => 1, 2, 5 ] ], 'on_mouse abs@15,5' );

undef @mouse_events;
$term->pressmouse( press => 1, 1, 2 );

is_deeply( \@mouse_events, [], 'no event for mouse abs@2,1' );

my $subwin = $win->make_sub( 2, 2, 1, 10 );

$subwin->focus( 0, 0 );

my @subkey_events;
my @submouse_events;
my $subret = 1;
$subwin->set_on_key( sub {
   push @subkey_events, [ $_[1] => $_[2] ];
   return $subret;
} );
$subwin->set_on_mouse( sub {
   push @submouse_events, [ @_[1..4] ];
   return $subret;
} );

undef @key_events;

$term->presskey( text => "B" );

is_deeply( \@subkey_events, [ [ text => "B" ] ], 'on_key B on subwin' );
is_deeply( \@key_events,    [ ],                 'on_key B on win' );

undef @mouse_events;

$term->pressmouse( press => 1, 5, 15 );

is_deeply( \@submouse_events, [ [ press => 1, 0, 3 ] ], 'on_mouse abs@15,5 on subwin' );
is_deeply( \@mouse_events,    [ ],                      'on_mouse abs@15,5 on win' );

$subret = 0;

undef @key_events;
undef @subkey_events;

$term->presskey( text => "C" );

is_deeply( \@subkey_events, [ [ text => "C" ] ], 'on_key C on subwin' );
is_deeply( \@key_events,    [ [ text => "C" ] ], 'on_key C on win' );

undef @mouse_events;
undef @submouse_events;

$term->pressmouse( press => 1, 5, 15 );

is_deeply( \@submouse_events, [ [ press => 1, 0, 3 ] ], 'on_mouse abs@15,5 on subwin' );
is_deeply( \@mouse_events,    [ [ press => 1, 2, 5 ] ], 'on_mouse abs@15,5 on win' );
