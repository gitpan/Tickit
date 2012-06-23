#!/usr/bin/perl

use strict;

use Test::More tests => 23;
use Test::Identity;
use Test::Refcount;

use Tickit::Test;

my $rootwin = mk_window;

my $floatwin = $rootwin->make_float( 10, 10, 5, 30 );

is_oneref( $floatwin, '$floatwin has refcount 1 initially' );
is_refcount( $rootwin, 3, '$rootwin has refcount 3 after ->make_float' );

is_deeply( [ $rootwin->_get_span_visibility( 10, 0 ) ],
           [ 1, 10 ], '$rootwin 10,0 visible for 10 columns' );
is_deeply( [ $rootwin->_get_span_visibility( 10, 10 ) ],
           [ 0, 30 ], '$rootwin 10,10 invisible for 30 columns' );
is_deeply( [ $rootwin->_get_span_visibility( 10, 40 ) ],
           [ 1, 40 ], '$rootwin 10,40 visible for 40 columns' );
is_deeply( [ $rootwin->_get_span_visibility( 15, 0 ) ],
           [ 1, 80 ], '$rootwin 15,0 visible for 80 columns' );

is_deeply( [ $floatwin->_get_span_visibility( 0, 0 ) ],
           [ 1, 30 ], '$floatwin 0,0 is visible for 30 columns' );
is_deeply( [ $floatwin->_get_span_visibility( 0, 20 ) ],
           [ 1, 10 ], '$floatwin 0,20 is visible for 10 columns' );

$rootwin->goto( 10, 0 );
$rootwin->print( "X" x 80 );

is_termlog( [ GOTO(10,0),
              SETPEN,
              PRINT("X"x10),
              GOTO(10,40),
              SETPEN,
              PRINT("X"x40) ],
            'Termlog for print under floating window' );

is_display( [ BLANKLINES(10),
              [TEXT("X"x10), BLANK(30), TEXT("X"x40)] ],
            'Display for print under floating window' );

my $win = $rootwin->make_sub( 10, 20, 1, 50 );

$win->goto( 0, 0 );
$win->print( "Y" x 50 );

is_termlog( [ GOTO(10,20),
              GOTO(10,40),
              SETPEN,
              PRINT("Y"x30) ],
            'Termlog for print sibling under floating window' );

is_display( [ BLANKLINES(10),
              [TEXT("X"x10), BLANK(30), TEXT("Y"x30), TEXT("X"x10)] ],
            'Display for print sibling under floating window' );

$floatwin->goto( 0, 0 );
$floatwin->print( "|-- Yipee --|" );

is_termlog( [ GOTO(10,10),
              SETPEN,
              PRINT("|-- Yipee --|") ],
            'Termlog for print to floating window' );

is_display( [ BLANKLINES(10),
              [TEXT("X"x10), TEXT("|-- Yipee --|"), BLANK(17), TEXT("Y"x30), TEXT("X"x10)] ],
            'Display for print to floating window' );

ok( !$rootwin->scrollrect( 0, 0, 20, 80, 0, +3 ), '$rootwin disallows scrollrect under a float' );

my $subwin = $floatwin->make_sub( 0, 4, 1, 6 );
$subwin->goto( 0, 0 );
$subwin->print( "Byenow" );

is_termlog( [ GOTO(10,14),
              SETPEN,
              PRINT("Byenow") ],
            'Termlog for print to child of floating window' );

is_display( [ BLANKLINES(10),
              [TEXT("X"x10), TEXT("|-- Byenow--|"), BLANK(17), TEXT("Y"x30), TEXT("X"x10)] ],
            'Display for print to child of floating window' );

$floatwin->hide;

is_deeply( [ $rootwin->_get_span_visibility( 10, 0 ) ],
           [ 1, 80 ], '$rootwin 10,0 visible for 80 columns after $floatwin->hide' );

{
   my $popupwin = $win->make_popup( 2, 2, 10, 10 );

   is_oneref( $popupwin, '$popupwin has refcount 1 initially' );

   identical( $popupwin->parent, $rootwin, '$popupwin->parent is $rootwin' );

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
}
