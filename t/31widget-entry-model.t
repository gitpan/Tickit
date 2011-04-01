#!/usr/bin/perl

use strict;

use Test::More tests => 57;
use Test::Refcount;
use IO::Async::Test;

use t::MockTerm;
use t::TestWindow;

use Tickit::Widget::Entry;

my ( $term, $win ) = mk_term_and_window;

my $entry = Tickit::Widget::Entry->new;

ok( defined $entry, 'defined $entry' );

is( $entry->text,     "", '$entry->text initially' );
is( $entry->position, 0,  '$entry->position initially' );

$entry->set_window( $win );

wait_for { $term->is_changed };

is_deeply( [ $term->methodlog ],
           [ SETPEN,
             CLEAR,
             GOTO(0,0),
             SETBG(undef),
             ERASECH(80) ],
           '$term written to initially' );

is_deeply( [ $term->get_display ],
           [ BLANKS(25) ],
           '$term display initially' );

is_deeply( [ $term->get_position ],
           [ 0, 0 ],
           '$term position initally' );

$entry->text_insert( "Hello", 0 );

is( $entry->text,     "Hello", '$entry->text after ->text_insert' );
is( $entry->position, 5,       '$entry->position after ->text_insert' );

is_deeply( [ $term->methodlog ],
           [ SETPEN,
             PRINT("Hello") ],
           '$term written to after ->text_insert' );

is_deeply( [ $term->get_display ],
           [ PAD("Hello"),
             BLANKS(24) ],
           '$term display after ->text_insert' );

is_deeply( [ $term->get_position ],
           [ 0, 5 ],
           '$term position after ->text_insert' );

$entry->text_insert( " ", 0 );

is( $entry->text,     " Hello", '$entry->text after ->text_insert at 0' );
is( $entry->position, 6,        '$entry->position after ->text_insert at 0' );

is_deeply( [ $term->methodlog ],
           [ GOTO(0,0),
             SETBG(undef),
             INSERTCH(1),
             SETPEN,
             PRINT(" "),
             GOTO(0,6) ],
           '$term written to after ->text_insert at 0' );

is_deeply( [ $term->get_display ],
           [ PAD(" Hello"),
             BLANKS(24) ],
           '$term display after ->text_insert at 0' );

is_deeply( [ $term->get_position ],
           [ 0, 6 ],
           '$term position after ->text_insert at 0' );

$entry->text_delete( 5, 1 );

is( $entry->text,     " Hell", '$entry->text after ->text_delete' );
is( $entry->position, 5,       '$entry->position after ->text_delete' );

is_deeply( [ $term->methodlog ],
           [ GOTO(0,5),
             SETBG(undef),
             DELETECH(1) ],
           '$term written to after ->text_delete' );

is_deeply( [ $term->get_display ],
           [ PAD(" Hell"),
             BLANKS(24) ],
           '$term display after ->text_delete' );

is_deeply( [ $term->get_position ],
           [ 0, 5 ],
           '$term position after ->text_delete' );

$entry->text_splice( 0, 2, "Y" );

is( $entry->text,     "Yell", '$entry->text after ->text_splice shrink' );
is( $entry->position, 4,      '$entry->position after ->text_splice shrink' );

is_deeply( [ $term->methodlog ],
           [ GOTO(0,0),
             SETBG(undef),
             DELETECH(1),
             SETPEN,
             PRINT("Y"),
             GOTO(0,4) ],
           '$term written to after ->text_splice shrink' );

is_deeply( [ $term->get_display ],
           [ PAD("Yell"),
             BLANKS(24) ],
           '$term display after ->text_splice shrink' );

is_deeply( [ $term->get_position ],
           [ 0, 4 ],
           '$term position after ->text_splice shrink' );

$entry->text_splice( 3, 1, "p" );

is( $entry->text,     "Yelp", '$entry->text after ->text_splice preserve' );
is( $entry->position, 4,      '$entry->position after ->text_splice preserve' );

is_deeply( [ $term->methodlog ],
           [ GOTO(0,3),
             SETPEN,
             PRINT("p") ],
           '$term written to after ->text_splice preserve' );

is_deeply( [ $term->get_display ],
           [ PAD("Yelp"),
             BLANKS(24) ],
           '$term display after ->text_splice preserve' );

is_deeply( [ $term->get_position ],
           [ 0, 4 ],
           '$term position after ->text_splice preserve' );

$entry->text_splice( 3, 1, "low" );

is( $entry->text,     "Yellow", '$entry->text after ->text_splice grow' );
is( $entry->position, 6,        '$entry->position after ->text_splice grow' );

is_deeply( [ $term->methodlog ],
           [ GOTO(0,3),
             SETBG(undef),
             INSERTCH(2),
             SETPEN,
             PRINT("low") ],
           '$term written to after ->text_splice grow' );

is_deeply( [ $term->get_display ],
           [ PAD("Yellow"),
             BLANKS(24) ],
           '$term display after ->text_splice grow' );

is_deeply( [ $term->get_position ],
           [ 0, 6 ],
           '$term position after ->text_splice grow' );

$entry->set_position( 3 );

is( $entry->position, 3, '$entry->position after ->set_position' );

is_deeply( [ $term->methodlog ],
           [ GOTO(0,3) ],
           '$term written to after ->set_position' );

is_deeply( [ $term->get_display ],
           [ PAD("Yellow"),
             BLANKS(24) ],
           '$term display after ->set_position' );

is_deeply( [ $term->get_position ],
           [ 0, 3 ],
           '$term position after ->set_position' );

$entry->set_text( "Different text" );

is( $entry->text, "Different text", '$entry->text after ->set_text' );

wait_for { $term->is_changed };

is_deeply( [ $term->methodlog ],
           [ SETPEN,
             CLEAR,
             GOTO(0,0),
             SETPEN,
             PRINT("Different text"),
             SETBG(undef),
             ERASECH(66),
             GOTO(0,3) ],
           '$term written to after ->set_text' );

is_deeply( [ $term->get_display ],
           [ PAD("Different text"),
             BLANKS(24) ],
           '$term display after ->set_text' );

is_deeply( [ $term->get_position ],
           [ 0, 3 ],
           '$term position after ->set_text' );

$entry->set_window( undef );

$entry = Tickit::Widget::Entry->new(
   text     => "Some initial text",
   position => 5,
);

is( $entry->text,     "Some initial text", '$entry->text for initialised' );
is( $entry->position, 5,                   '$entry->position for initialised' );

$entry->set_window( $win );
# Hack for test purposes
$win->restore;

wait_for { $term->is_changed };

is_deeply( [ $term->methodlog ],
           [ SETPEN,
             CLEAR,
             GOTO(0,0),
             SETPEN,
             PRINT("Some initial text"),
             SETBG(undef),
             ERASECH(63),
             GOTO(0,5) ],
           '$term written to for initialised' );

is_deeply( [ $term->get_display ],
           [ PAD("Some initial text"),
             BLANKS(24) ],
           '$term display for initialised' );

is_deeply( [ $term->get_position ],
           [ 0, 5 ],
           '$term position for initalised' );

is( $entry->find_bow_forward( 9 ), 13, 'find_bow_forward( 9 )' );
is( $entry->find_eow_forward( 9 ), 12, 'find_eow_forward( 9 )' );
is( $entry->find_bow_backward( 9 ), 5, 'find_bow_backward( 9 )' );
is( $entry->find_eow_backward( 9 ), 4, 'find_eow_backward( 9 )' );

is( $entry->find_bow_forward( 15 ), undef, 'find_bow_forward( 15 )' );
is( $entry->find_eow_forward( 15 ), 17,    'find_eow_forward( 15 )' );

is( $entry->find_bow_backward( 2 ), 0,     'find_bow_backward( 2 )' );
is( $entry->find_eow_backward( 2 ), undef, 'find_eow_backward( 2 )' );
