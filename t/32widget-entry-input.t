#!/usr/bin/perl

use strict;

use Test::More tests => 35;
use Test::Identity;
use Test::Refcount;
use IO::Async::Test;

use t::MockTerm;
use t::TestWindow;

use Tickit::Widget::Entry;

my ( $term, $win ) = mk_term_and_window;

my $entry = Tickit::Widget::Entry->new(
   text => "Initial",
);

is( $entry->text,     "Initial", '$entry->text initially' );
is( $entry->position, 0,         '$entry->position initially' );

$entry->set_window( $win );
# Hack for testing
$win->restore;

wait_for { $term->is_changed };

is_deeply( [ $term->methodlog ],
           [ SETPEN,
             CLEAR,
             GOTO(0,0),
             SETPEN,
             PRINT("Initial"),
             SETBG(undef),
             ERASECH(73),
             GOTO(0,0) ],
           '$term written to initially' );

is_deeply( [ $term->get_display ],
           [ PAD("Initial"),
             BLANKS(24) ],
           '$term display initially' );

is_deeply( [ $term->get_position ],
           [ 0, 0 ],
           '$term initially' );

$term->presskey( key => "Right" );

is( $entry->position, 1, '$entry->position after Right' );

is_deeply( [ $term->methodlog ],
           [ GOTO(0,1) ],
           '$term written to after Right' );

is_deeply( [ $term->get_position ],
           [ 0, 1 ],
           '$term position after Right' );

$term->presskey( key => "End" );

is( $entry->position, 7, '$entry->position after End' );

is_deeply( [ $term->methodlog ],
           [ GOTO(0,7) ],
           '$term written to after End' );

is_deeply( [ $term->get_position ],
           [ 0, 7 ],
           '$term position after End' );

$term->presskey( key => "Left" );

is( $entry->position, 6, '$entry->position after Left' );

is_deeply( [ $term->methodlog ],
           [ GOTO(0,6) ],
           '$term written to after Left' );

is_deeply( [ $term->get_position ],
           [ 0, 6 ],
           '$term position after Left' );

$term->presskey( key => "Home" );

is( $entry->position, 0, '$entry->position after Home' );

is_deeply( [ $term->methodlog ],
           [ GOTO(0,0) ],
           '$term written to after Home' );

is_deeply( [ $term->get_position ],
           [ 0, 0 ],
           '$term position after Home' );

$term->presskey( text => "X" );

is( $entry->text,     "XInitial", '$entry->text after X' );
is( $entry->position, 1,          '$entry->position after X' );

is_deeply( [ $term->methodlog ],
           [ SETBG(undef),
             INSERTCH(1),
             SETPEN,
             PRINT("X") ],
           '$term written to after X' );

is_deeply( [ $term->get_display ],
           [ PAD("XInitial"),
             BLANKS(24) ],
           '$term display after X' );

is_deeply( [ $term->get_position ],
           [ 0, 1 ],
           '$term position after X' );

$term->presskey( key => "Backspace" );

is( $entry->text,     "Initial", '$entry->text after Backspace' );
is( $entry->position, 0,         '$entry->position after Backspace' );

is_deeply( [ $term->methodlog ],
           [ GOTO(0,0),
             SETBG(undef),
             DELETECH(1) ],
           '$term written to after Backspace' );

is_deeply( [ $term->get_display ],
           [ PAD("Initial"),
             BLANKS(24) ],
           '$term display after Backspace' );

is_deeply( [ $term->get_position ],
           [ 0, 0 ],
           '$term position after Backspace' );

$term->presskey( key => "Delete" );

is( $entry->text,     "nitial", '$entry->text after Delete' );
is( $entry->position, 0,        '$entry->position after Delete' );

is_deeply( [ $term->methodlog ],
           [ SETBG(undef),
             DELETECH(1) ],
           '$term written to after Delete' );

is_deeply( [ $term->get_display ],
           [ PAD("nitial"),
             BLANKS(24) ],
           '$term display after Delete' );

is_deeply( [ $term->get_position ],
           [ 0, 0 ],
           '$term position after Delete' );

my $line;
$entry->set_on_enter(
   sub {
      identical( $_[0], $entry, 'on_enter $_[0] is $entry' );
      $line = $_[1];
   }
);

$term->presskey( key => "Enter" );

is( $line, "nitial", 'on_enter $_[1] is line' );
is_deeply( [ $term->methodlog ], [], '$term unmodified after Enter' );
