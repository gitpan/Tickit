#!/usr/bin/perl

use strict;
use warnings;

use Test::More;

use Tickit::Test;

my $rootwin = mk_window;

my $win = $rootwin->make_sub( 3, 10, 4, 20 );

$win->focus( 0, 0 );
flush_tickit;

my $keyev;
my @key_events;
$win->set_on_key( sub {
   ( undef, $keyev ) = @_;
   push @key_events, [ $keyev->type => $keyev->str ];
   return 1;
} );

presskey( text => "A" );

is_deeply( \@key_events, [ [ text => "A" ] ], 'on_key A' );

ok( !$keyev->mod_is_shift, 'A key is not shift' );
ok( !$keyev->mod_is_ctrl,  'A key is not ctrl' );
ok( !$keyev->mod_is_alt,   'A key is not alt' );

undef @key_events;

presskey( key => "C-a", 4 );

is_deeply( \@key_events, [ [ key => "C-a" ] ], 'on_key C-a' );

ok( !$keyev->mod_is_shift, 'C-a key is not shift' );
ok(  $keyev->mod_is_ctrl,  'C-a key is ctrl' );
ok( !$keyev->mod_is_alt,   'C-a key is not alt' );

my @mouse_events;
$win->set_on_mouse( sub {
   my ( $self, $ev ) = @_;
   push @mouse_events, [ $ev->type => $ev->button, $ev->line, $ev->col ];
   return 1;
} );

undef @mouse_events;
pressmouse( press => 1, 5, 15 );

is_deeply( \@mouse_events, [ [ press => 1, 2, 5 ] ], 'on_mouse abs@15,5' );

undef @mouse_events;
pressmouse( press => 1, 1, 2 );

is_deeply( \@mouse_events, [], 'no event for mouse abs@2,1' );

my $subwin = $win->make_sub( 2, 2, 1, 10 );

$subwin->focus( 0, 0 );
flush_tickit;

my @subkey_events;
my @submouse_events;
my $subret = 1;
$subwin->set_on_key( sub {
   my ( $self, $ev ) = @_;
   push @subkey_events, [ $ev->type => $ev->str ];
   return $subret;
} );
$subwin->set_on_mouse( sub {
   my ( $self, $ev ) = @_;
   push @submouse_events, [ $ev->type => $ev->button, $ev->line, $ev->col ];
   return $subret;
} );

undef @key_events;

presskey( text => "B" );

is_deeply( \@subkey_events, [ [ text => "B" ] ], 'on_key B on subwin' );
is_deeply( \@key_events,    [ ],                 'on_key B on win' );

undef @mouse_events;

pressmouse( press => 1, 5, 15 );

is_deeply( \@submouse_events, [ [ press => 1, 0, 3 ] ], 'on_mouse abs@15,5 on subwin' );
is_deeply( \@mouse_events,    [ ],                      'on_mouse abs@15,5 on win' );

$subret = 0;

undef @key_events;
undef @subkey_events;

presskey( text => "C" );

is_deeply( \@subkey_events, [ [ text => "C" ] ], 'on_key C on subwin' );
is_deeply( \@key_events,    [ [ text => "C" ] ], 'on_key C on win' );

undef @mouse_events;
undef @submouse_events;

pressmouse( press => 1, 5, 15 );

is_deeply( \@submouse_events, [ [ press => 1, 0, 3 ] ], 'on_mouse abs@15,5 on subwin' );
is_deeply( \@mouse_events,    [ [ press => 1, 2, 5 ] ], 'on_mouse abs@15,5 on win' );

my $otherwin = $rootwin->make_sub( 10, 10, 4, 20 );
flush_tickit;

my @handlers;
$win->set_on_key     ( sub { push @handlers, "win";      return 0 } );
$subwin->set_on_key  ( sub { push @handlers, "subwin";   return 0 } );
$otherwin->set_on_key( sub { push @handlers, "otherwin"; return 0 } );

presskey( text => "D" );

is_deeply( \@handlers, [qw( subwin win otherwin )], 'on_key D propagates to otherwin after win' );

$subwin->hide;

undef @handlers;

presskey( text => "E" );

is_deeply( \@handlers, [qw( win otherwin )], 'hidden windows do not receive input events' );

done_testing;
