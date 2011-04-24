#!/usr/bin/perl

use strict;

use Test::More tests => 11;
use Test::Identity;

use t::MockTerm;
use t::TestTickit;

use Tickit::Widget::Static;
use Tickit::Widget::Frame;

my ( $term, $win ) = mk_term_and_window;

my $static = Tickit::Widget::Static->new( text => "Widget" );

my $widget = Tickit::Widget::Frame->new;

ok( defined $widget, 'defined $widget' );

is( $widget->style, "ascii", '$widget->style' );

$widget->add( $static );
$widget->set_window( $win );

flush_tickit;

is_deeply( [ $term->methodlog ],
           [ SETPEN,
             CLEAR,
             GOTO(0,0),
             SETPEN,
             PRINT("+" . ("-"x78) . "+"),
             ( map { GOTO($_,0),  SETPEN, PRINT("|"),
                     GOTO($_,79), SETPEN, PRINT("|") } 1 .. 23 ),
             GOTO(24,0),
             SETPEN,
             PRINT("+" . ("-"x78) . "+"),
             GOTO(1,1),
             SETPEN,
             PRINT("Widget"),
             SETBG(undef),
             ERASECH(72),
             ],
           '$term written to initially' );

is_deeply( [ $term->get_display ],
           [ "+".("-"x78)."+",
             "|Widget".(" "x72)."|",
             ("|".(" "x78)."|") x 22,
             "+".("-"x78)."+", ],
           '$term display initially' );

$widget->set_style( "single" );

flush_tickit;

is_deeply( [ $term->methodlog ],
           [ SETPEN,
             CLEAR,
             GOTO(0,0),
             SETPEN,
             PRINT("\x{250C}" . ("\x{2500}"x78) . "\x{2510}"),
             ( map { GOTO($_,0),  SETPEN, PRINT("\x{2502}"),
                     GOTO($_,79), SETPEN, PRINT("\x{2502}") } 1 .. 23 ),
             GOTO(24,0),
             SETPEN,
             PRINT("\x{2514}" . ("\x{2500}"x78) . "\x{2518}"),
             GOTO(1,1),
             SETPEN,
             PRINT("Widget"),
             SETBG(undef),
             ERASECH(72),
             ],
           '$term written to after ->set_style' );

is_deeply( [ $term->get_display ],
           [ "\x{250C}".("\x{2500}"x78)."\x{2510}",
             "\x{2502}Widget".(" "x72)."\x{2502}",
             ("\x{2502}".(" "x78)."\x{2502}") x 22,
             "\x{2514}".("\x{2500}"x78)."\x{2518}", ],
           '$term display after ->set_style' );

# That style is hard to test against so put it back to ASCII
$widget->set_style( "ascii" );

$widget->set_title( "Title" );

flush_tickit;

is_deeply( [ $term->methodlog ],
           [ SETPEN,
             CLEAR,
             GOTO(0,0),
             SETPEN,
             PRINT("+ "),
             SETPEN,
             PRINT("Title"),
             SETPEN,
             PRINT(" ". ("-"x71) . "+"),
             ( map { GOTO($_,0),  SETPEN, PRINT("|"),
                     GOTO($_,79), SETPEN, PRINT("|") } 1 .. 23 ),
             GOTO(24,0),
             SETPEN,
             PRINT("+" . ("-"x78) . "+"),
             GOTO(1,1),
             SETPEN,
             PRINT("Widget"),
             SETBG(undef),
             ERASECH(72),
             ],
           '$term written to with title' );

is_deeply( [ $term->get_display ],
           [ "+ Title ".("-"x71)."+",
             "|Widget".(" "x72)."|",
             ("|".(" "x78)."|") x 22,
             "+".("-"x78)."+", ],
           '$term display with title' );

$widget->set_title_align( "right" );

flush_tickit;

is_deeply( [ $term->methodlog ],
           [ SETPEN,
             CLEAR,
             GOTO(0,0),
             SETPEN,
             PRINT("+". ("-"x71) . " "),
             SETPEN,
             PRINT("Title"),
             SETPEN,
             PRINT(" +"),
             ( map { GOTO($_,0),  SETPEN, PRINT("|"),
                     GOTO($_,79), SETPEN, PRINT("|") } 1 .. 23 ),
             GOTO(24,0),
             SETPEN,
             PRINT("+" . ("-"x78) . "+"),
             GOTO(1,1),
             SETPEN,
             PRINT("Widget"),
             SETBG(undef),
             ERASECH(72),
             ],
           '$term written to with right-aligned title' );

is_deeply( [ $term->get_display ],
           [ "+".("-"x71)." Title +",
             "|Widget".(" "x72)."|",
             ("|".(" "x78)."|") x 22,
             "+".("-"x78)."+", ],
           '$term display with right-aligned title' );

$widget->frame_pen->chattr( fg => "red" );

flush_tickit;

is_deeply( [ $term->methodlog ],
           [ SETPEN,
             CLEAR,
             GOTO(0,0),
             SETPEN(fg => 1),
             PRINT("+". ("-"x71) . " "),
             SETPEN(fg => 1),
             PRINT("Title"),
             SETPEN(fg => 1),
             PRINT(" +"),
             ( map { GOTO($_,0),  SETPEN(fg => 1), PRINT("|"),
                     GOTO($_,79), SETPEN(fg => 1), PRINT("|") } 1 .. 23 ),
             GOTO(24,0),
             SETPEN(fg => 1),
             PRINT("+" . ("-"x78) . "+"),
             GOTO(1,1),
             SETPEN,
             PRINT("Widget"),
             SETBG(undef),
             ERASECH(72),
             ],
           '$term written to with correct pen' );
