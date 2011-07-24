#!/usr/bin/perl

use strict;

use Test::More tests => 23;

use Tickit::Test;

use Tickit::Widget::Static;
use Tickit::Widget::VBox;

my ( $term, $win ) = mk_term_and_window;

my @statics = map { Tickit::Widget::Static->new( text => "Widget $_" ) } 0 .. 2;

my $widget = Tickit::Widget::VBox->new;

ok( defined $widget, 'defined $widget' );

is( scalar $widget->children, 0, '$widget has 0 children' );

$widget->add( $_ ) for @statics;

is( scalar $widget->children, 3, '$widget has 3 children after adding' );

is( $widget->lines, 3, '$widget->lines is 3' );
is( $widget->cols, 8, '$widget->cols is 8' );

$widget->set_window( $win );

ok( defined $statics[0]->window, '$static has window after ->set_window $win' );

flush_tickit;

is_termlog( [ SETPEN,
              CLEAR,
              GOTO(0,0),
              SETPEN,
              PRINT("Widget 0"),
              SETBG(undef),
              ERASECH(72),
              GOTO(1,0),
              SETPEN,
              PRINT("Widget 1"),
              SETBG(undef),
              ERASECH(72),
              GOTO(2,0),
              SETPEN,
              PRINT("Widget 2"),
              SETBG(undef),
              ERASECH(72) ],
            'Termlog initially' );

is_display( [ "Widget 0",
              "Widget 1",
              "Widget 2" ],
            'Display' );

$widget->set_child_opts( 1, expand => 1 );

flush_tickit;

is_termlog( [ SETPEN,
              CLEAR,
              GOTO(0,0),
              SETPEN,
              PRINT("Widget 0"),
              SETBG(undef),
              ERASECH(72),
              GOTO(1,0),
              SETPEN,
              PRINT("Widget 1"),
              SETBG(undef),
              ERASECH(72),
              ( map { GOTO($_,0), SETBG(undef), ERASECH(80) } 2 .. 23 ),
              GOTO(24,0),
              SETPEN,
              PRINT("Widget 2"),
              SETBG(undef),
              ERASECH(72), ],
            'widgets moved after expand change' );

is_display( [ "Widget 0",
              "Widget 1",
              ("") x 22,
              "Widget 2" ],
            'Display after expand change' );

$statics[0]->set_text( "A longer piece of text for the static" );

flush_tickit;

is_termlog( [ SETPEN,
              CLEAR,
              GOTO(0,0),
              SETPEN,
              PRINT("A longer piece of text for the static"),
              SETBG(undef),
              ERASECH(43),
              GOTO(1,0),
              SETPEN,
              PRINT("Widget 1"),
              SETBG(undef),
              ERASECH(72),
              ( map { GOTO($_,0), SETBG(undef), ERASECH(80) } 2 .. 23 ),
              GOTO(24,0),
              SETPEN,
              PRINT("Widget 2"),
              SETBG(undef),
              ERASECH(72), ],
            'widgets moved after static text change' );

is_display( [ "A longer piece of text for the static",
              "Widget 1",
              ( "" ) x 22,
              "Widget 2" ],
            'Display after static text change' );

$statics[1]->pen->chattr( fg => 5 );

flush_tickit;

is_termlog( [ GOTO(1,0),
              SETPEN(fg => 5),
              PRINT("Widget 1"),
              SETBG(undef),
              ERASECH(72),
              ( map { GOTO($_,0), SETBG(undef), ERASECH(80) } 2 .. 23 ) ],
            'redraw after static attr change' );

$widget->pen->chattr( b => 1 );

flush_tickit;

is_termlog( [ SETPEN(b => 1),
              CLEAR,
              GOTO(0,0),
              SETPEN(b => 1),
              PRINT("A longer piece of text for the static"),
              SETBG(undef),
              ERASECH(43),
              GOTO(1,0),
              SETPEN(b => 1, fg => 5),
              PRINT("Widget 1"),
              SETBG(undef),
              ERASECH(72),
              ( map { GOTO($_,0), SETBG(undef), ERASECH(80) } 2 .. 23 ),
              GOTO(24,0),
              SETPEN(b => 1),
              PRINT("Widget 2"),
              SETBG(undef),
              ERASECH(72), ],
            'redraw after widget attr change' );

resize_term( 30, 100 );

flush_tickit;

is_termlog( [ SETPEN(b => 1),
              CLEAR,
              GOTO(0,0),
              SETPEN(b => 1),
              PRINT("A longer piece of text for the static"),
              SETBG(undef),
              ERASECH(63),
              GOTO(1,0),
              SETPEN(b => 1, fg => 5),
              PRINT("Widget 1"),
              SETBG(undef),
              ERASECH(92),
              ( map { GOTO($_,0), SETBG(undef), ERASECH(100) } 2 .. 28 ),
              GOTO(29,0),
              SETPEN(b => 1),
              PRINT("Widget 2"),
              SETBG(undef),
              ERASECH(92), ],
            'Termlog after resize' );

is_display( [ "A longer piece of text for the static",
              "Widget 1",
              ( "" ) x 27,
              "Widget 2" ],
            'Display after resize' );

$widget->add( Tickit::Widget::Static->new( text => "New Widget" ) );

is( scalar $widget->children, 4, '$widget now has 4 children after new widget' );

flush_tickit;

is_termlog( [ SETPEN(b => 1),
              CLEAR,
              GOTO(0,0),
              SETPEN(b => 1),
              PRINT("A longer piece of text for the static"),
              SETBG(undef),
              ERASECH(63),
              GOTO(1,0),
              SETPEN(b => 1, fg => 5),
              PRINT("Widget 1"),
              SETBG(undef),
              ERASECH(92),
              ( map { GOTO($_,0), SETBG(undef), ERASECH(100) } 2 .. 27 ),
              GOTO(28,0),
              SETPEN(b => 1),
              PRINT("Widget 2"),
              SETBG(undef),
              ERASECH(92),
              GOTO(29,0),
              SETPEN(b => 1),
              PRINT("New Widget"),
              SETBG(undef),
              ERASECH(90), ],
            'Termlog after new widget' );

is_display( [ "A longer piece of text for the static",
              "Widget 1",
              ( "" ) x 26,
              "Widget 2",
              "New Widget" ],
            'Display after new widget' );

$widget->pen->chattr( bg => 4 );

flush_tickit;

is_termlog( [ SETPEN(b => 1, bg => 4),
              CLEAR,
              GOTO(0,0),
              SETPEN(b => 1, bg => 4),
              PRINT("A longer piece of text for the static"),
              SETBG(4),
              ERASECH(63),
              GOTO(1,0),
              SETPEN(b => 1, fg => 5, bg => 4),
              PRINT("Widget 1"),
              SETBG(4),
              ERASECH(92),
              ( map { GOTO($_,0), SETBG(4), ERASECH(100) } 2 .. 27 ),
              GOTO(28,0),
              SETPEN(b => 1, bg => 4),
              PRINT("Widget 2"),
              SETBG(4),
              ERASECH(92),
              GOTO(29,0),
              SETPEN(b => 1, bg => 4),
              PRINT("New Widget"),
              SETBG(4),
              ERASECH(90), ],
           'Termlog after new widget' );

$widget->set_child_opts( 2, force_size => 3 );

flush_tickit;

is_display( [ "A longer piece of text for the static",
              "Widget 1",
              ( "" ) x 24,
              "Widget 2",
              ( "" ) x 2,
              "New Widget" ],
            'Display after force_size' );

is_termlog( [ SETPEN(b => 1, bg => 4),
              CLEAR,
              GOTO(0,0),
              SETPEN(b => 1, bg => 4),
              PRINT("A longer piece of text for the static"),
              SETBG(4),
              ERASECH(63),
              GOTO(1,0),
              SETPEN(b => 1, fg => 5, bg => 4),
              PRINT("Widget 1"),
              SETBG(4),
              ERASECH(92),
              ( map { GOTO($_,0), SETBG(4), ERASECH(100) } 2 .. 25 ),
              GOTO(26,0),
              SETPEN(b => 1, bg => 4),
              PRINT("Widget 2"),
              SETBG(4),
              ERASECH(92),
              ( map { GOTO($_,0), SETBG(4), ERASECH(100) } 27 .. 28 ),
              GOTO(29,0),
              SETPEN(b => 1, bg => 4),
              PRINT("New Widget"),
              SETBG(4),
              ERASECH(90), ],
           'Termlog after new widget' );

$widget->set_window( undef );

ok( !defined $statics[0]->window, '$static has no window after ->set_window undef' );
