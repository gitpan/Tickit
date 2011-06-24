#!/usr/bin/perl

use strict;

use Test::More tests => 13;
use Test::Identity;

use Tickit::Test;

use Tickit::Widget::Static;
use Tickit::Widget::Frame;

my $win = mk_window;

my $static = Tickit::Widget::Static->new( text => "Widget" );

my $widget = Tickit::Widget::Frame->new;

ok( defined $widget, 'defined $widget' );

is( $widget->style, "ascii", '$widget->style' );

$widget->add( $static );
$widget->set_window( $win );

ok( defined $static->window, '$static has window after $widget->set_window' );

flush_tickit;

is_termlog( [ SETPEN,
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
              ( map { GOTO($_,1), SETBG(undef), ERASECH(78) } 2 .. 23 ) ],
            'Termlog initially' );

is_display( [ "+".("-"x78)."+",
              "|Widget".(" "x72)."|",
              ("|".(" "x78)."|") x 22,
              "+".("-"x78)."+", ],
            'Display initially' );

$widget->set_style( "single" );

flush_tickit;

is_termlog( [ SETPEN,
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
              ( map { GOTO($_,1), SETBG(undef), ERASECH(78) } 2 .. 23 ) ],
            'Termlog after ->set_style' );

is_display( [ "\x{250C}".("\x{2500}"x78)."\x{2510}",
              "\x{2502}Widget".(" "x72)."\x{2502}",
              ("\x{2502}".(" "x78)."\x{2502}") x 22,
              "\x{2514}".("\x{2500}"x78)."\x{2518}", ],
            'Display after ->set_style' );

# That style is hard to test against so put it back to ASCII
$widget->set_style( "ascii" );

$widget->set_title( "Title" );

flush_tickit;

is_termlog( [ SETPEN,
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
              ( map { GOTO($_,1), SETBG(undef), ERASECH(78) } 2 .. 23 ) ],
            'Termlog with title' );

is_display( [ "+ Title ".("-"x71)."+",
              "|Widget".(" "x72)."|",
              ("|".(" "x78)."|") x 22,
              "+".("-"x78)."+", ],
            'Display with title' );

$widget->set_title_align( "right" );

flush_tickit;

is_termlog( [ SETPEN,
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
              ( map { GOTO($_,1), SETBG(undef), ERASECH(78) } 2 .. 23 ) ],
            'Termlog with right-aligned title' );

is_display( [ "+".("-"x71)." Title +",
              "|Widget".(" "x72)."|",
              ("|".(" "x78)."|") x 22,
              "+".("-"x78)."+", ],
            'Display with right-aligned title' );

$widget->frame_pen->chattr( fg => "red" );

flush_tickit;

is_termlog( [ SETPEN,
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
              ( map { GOTO($_,1), SETBG(undef), ERASECH(78) } 2 .. 23 ) ],
            'Termlog with correct pen' );

$widget->set_window( undef );

ok( !defined $static->window, '$static has no window after ->set_window undef' );
