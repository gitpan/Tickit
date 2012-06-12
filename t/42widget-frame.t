#!/usr/bin/perl

use strict;

use Test::More tests => 10;
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

is_display( [ [TEXT("+".("-"x78)."+")],
              [TEXT("|Widget".(" "x72)."|")],
              ( [TEXT("|"), BLANK(78), TEXT("|")] )  x 22,
              [TEXT("+".("-"x78)."+")] ],
            'Display initially' );

SKIP: {
   skip "No UTF-8 locale", 1 unless ${^UTF8LOCALE};

   $widget->set_style( "single" );

   flush_tickit;

   is_display( [ [TEXT("\x{250C}".("\x{2500}"x78)."\x{2510}")],
                 [TEXT("\x{2502}Widget".(" "x72)."\x{2502}")],
                 ( [TEXT("\x{2502}"), BLANK(78), TEXT("\x{2502}")] ) x 22,
                 [TEXT("\x{2514}".("\x{2500}"x78)."\x{2518}")] ],
               'Display after ->set_style' );
}

# That style is hard to test against so put it back to ASCII
$widget->set_style( "ascii" );

$widget->set_title( "Title" );

flush_tickit;

is_display( [ [TEXT("+ Title ".("-"x71)."+")],
              [TEXT("|Widget".(" "x72)."|")],
              ( [TEXT("|"), BLANK(78), TEXT("|")] )  x 22,
              [TEXT("+".("-"x78)."+")] ],
            'Display with title' );

$widget->set_title_align( "right" );

flush_tickit;

is_display( [ [TEXT("+".("-"x71)." Title +")],
              [TEXT("|Widget".(" "x72)."|")],
              ( [TEXT("|"), BLANK(78), TEXT("|")] )  x 22,
              [TEXT("+".("-"x78)."+")] ],
            'Display with right-aligned title' );

$widget->frame_pen->chattr( fg => "red" );

flush_tickit;

is_display( [ [TEXT("+".("-"x71)." Title +",fg=>1)],
              [TEXT("|",fg=>1), TEXT("Widget".(" "x72)), TEXT("|",fg=>1)],
              ( [TEXT("|",fg=>1), BLANK(78), TEXT("|",fg=>1)] ) x 22,
              [TEXT("+".("-"x78)."+",fg=>1)] ],
            'Display with correct pen' );

$static->set_text( "New text" );

flush_tickit;

is_display( [ [TEXT("+".("-"x71)." Title +",fg=>1)],
              [TEXT("|",fg=>1), TEXT("New text".(" "x70)), TEXT("|",fg=>1)],
              ( [TEXT("|",fg=>1), BLANK(78), TEXT("|",fg=>1)] ) x 22,
              [TEXT("+".("-"x78)."+",fg=>1)] ],
            'Display after $static->set_text' );

$widget->set_window( undef );

ok( !defined $static->window, '$static has no window after ->set_window undef' );
