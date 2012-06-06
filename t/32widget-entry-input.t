#!/usr/bin/perl

use strict;

use Test::More tests => 35;
use Test::Identity;

use Tickit::Test;

use Tickit::Widget::Entry;

my $win = mk_window;

my $entry = Tickit::Widget::Entry->new(
   text => "Initial",
);

is( $entry->text,     "Initial", '$entry->text initially' );
is( $entry->position, 0,         '$entry->position initially' );

$entry->set_window( $win );

flush_tickit;

is_termlog( [ GOTO(0,0),
              SETPEN,
              PRINT("Initial"),
              SETBG(undef),
              ERASECH(73),
              ( map { GOTO($_,0), SETBG(undef), ERASECH(80) } 1 .. 24 ),
              GOTO(0,0) ],
            'Termlog initially' );

is_display( [ "Initial" ],
            'Display initially' );

is_cursorpos( 0, 0, 'Position initially' );

presskey( key => "Right" );

is( $entry->position, 1, '$entry->position after Right' );

is_termlog( [ GOTO(0,1) ],
            'Termlog after Right' );

is_cursorpos( 0, 1, 'Position after Right' );

presskey( key => "End" );

is( $entry->position, 7, '$entry->position after End' );

is_termlog( [ GOTO(0,7) ],
            'Termlog after End' );

is_cursorpos( 0, 7, 'Position after End' );

presskey( key => "Left" );

is( $entry->position, 6, '$entry->position after Left' );

is_termlog( [ GOTO(0,6) ],
            'Termlog after Left' );

is_cursorpos( 0, 6, 'Position after Left' );

presskey( key => "Home" );

is( $entry->position, 0, '$entry->position after Home' );

is_termlog( [ GOTO(0,0) ],
            'Termlog after Home' );

is_cursorpos( 0, 0, 'Position after Home' );

presskey( text => "X" );

is( $entry->text,     "XInitial", '$entry->text after X' );
is( $entry->position, 1,          '$entry->position after X' );

is_termlog( [ SETBG(undef),
              GOTO(0,0),
              INSERTCH(1),
              GOTO(0,0),
              SETPEN,
              PRINT("X") ],
            'Termlog after X' );

is_display( [ "XInitial" ],
            'Display after X' );

is_cursorpos( 0, 1, 'Position after X' );

presskey( key => "Backspace" );

is( $entry->text,     "Initial", '$entry->text after Backspace' );
is( $entry->position, 0,         '$entry->position after Backspace' );

is_termlog( [ SETBG(undef),
              GOTO(0,0),
              DELETECH(1) ],
            'Termlog after Backspace' );

is_display( [ "Initial" ],
            'Display after Backspace' );

is_cursorpos( 0, 0, 'Position after Backspace' );

presskey( key => "Delete" );

is( $entry->text,     "nitial", '$entry->text after Delete' );
is( $entry->position, 0,        '$entry->position after Delete' );

is_termlog( [ SETBG(undef),
              GOTO(0,0),
              DELETECH(1) ],
            'Termlog after Delete' );

is_display( [ "nitial" ],
            'Display after Delete' );

is_cursorpos( 0, 0, 'Position after Delete' );

my $line;
$entry->set_on_enter(
   sub {
      identical( $_[0], $entry, 'on_enter $_[0] is $entry' );
      $line = $_[1];
   }
);

presskey( key => "Enter" );

is( $line, "nitial", 'on_enter $_[1] is line' );
is_termlog( [],
            'Termlog unmodified after Enter' );
