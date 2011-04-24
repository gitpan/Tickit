#!/usr/bin/perl

use strict;

use Test::More tests => 15;

use t::MockTerm;
use t::TestTickit;

use Tickit::Widget::Entry;

my ( $term, $win ) = mk_term_and_window;

my $entry = Tickit::Widget::Entry->new(
   text => "A"x70,
   position => 70,
);

$entry->set_window( $win );

flush_tickit;

is_deeply( [ $term->methodlog ],
           [ SETPEN,
             CLEAR,
             GOTO(0,0),
             SETPEN,
             PRINT("A"x70),
             SETBG(undef),
             ERASECH(10),
             GOTO(0,70) ],
           '$term written to initially' );

is_deeply( [ $term->get_display ],
           [ PAD("A"x70),
             BLANKS(24) ],
           '$term display initially' );

is_deeply( [ $term->get_position ],
           [ 0, 70 ],
           '$term position initially' );

$entry->text_insert( "B"x20, $entry->position );

flush_tickit;

is_deeply( [ $term->methodlog ],
           [ SETPEN,
             CLEAR,
             GOTO(0,0),
             SETPEN,
             PRINT(("A"x30).("B"x20)),
             SETBG(undef),
             ERASECH(30),
             GOTO(0,50) ],
           '$term written to after append to scroll' );

is_deeply( [ $term->get_display ],
           [ PAD(("A"x30).("B"x20)),
             BLANKS(24) ],
           '$term display after append to scroll' );

is_deeply( [ $term->get_position ],
           [ 0, 50 ],
           '$term position after append to scroll' );

$entry->set_position( 0 );

flush_tickit;

is_deeply( [ $term->methodlog ],
           [ GOTO(0,0),
             SETPEN,
             CLEAR,
             GOTO(0,0),
             SETPEN,
             PRINT(("A"x70).("B"x10)),
             GOTO(0,0) ],
           '$term written to after ->set_position 0' );

is_deeply( [ $term->get_display ],
           [ PAD(("A"x70).("B"x10)),
             BLANKS(24) ],
           '$term display after ->set_position 0' );

is_deeply( [ $term->get_position ],
           [ 0, 0 ],
           '$term position after ->set_position 0' );

$entry->set_position( 90 );

flush_tickit;

is_deeply( [ $term->methodlog ],
           [ GOTO(0,50),
             SETPEN,
             CLEAR,
             GOTO(0,0),
             SETPEN,
             PRINT(("A"x30).("B"x20)),
             SETBG(undef),
             ERASECH(30),
             GOTO(0,50) ],
           '$term written to after ->set_position 90' );

is_deeply( [ $term->get_display ],
           [ PAD(("A"x30).("B"x20)),
             BLANKS(24) ],
           '$term display after ->set_position 90' );

is_deeply( [ $term->get_position ],
           [ 0, 50 ],
           '$term position after ->set_position 90' );

$entry->set_position( 0 );

flush_tickit;
$term->methodlog; # drain methods

$entry->text_delete( 0, 1 );

flush_tickit;

is_deeply( [ $term->methodlog ],
           [ SETBG(undef),
             DELETECH(1),
             GOTO(0,79),
             SETPEN,
             PRINT("B"),
             GOTO(0,0) ],
           '$term written to after ->text_delete 0, 1' );

is_deeply( [ $term->get_display ],
           [ PAD(("A"x69).("B"x11)),
             BLANKS(24) ],
           '$term display after ->text_delete 0, 1' );

is_deeply( [ $term->get_position ],
           [ 0, 0 ],
           '$term position after ->text_delete 0, 1' );
