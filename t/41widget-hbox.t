#!/usr/bin/perl

use strict;

use Test::More tests => 21;

use Tickit::Test;

use Tickit::Widget::Static;
use Tickit::Widget::HBox;

my ( $term, $win ) = mk_term_and_window;

my @statics = map { Tickit::Widget::Static->new( text => "Widget $_" ) } 0 .. 2;

my $widget = Tickit::Widget::HBox->new(
   spacing => 2,
);

ok( defined $widget, 'defined $widget' );

is( scalar $widget->children, 0, '$widget has 0 children' );

$widget->add( $_ ) for @statics;

is( scalar $widget->children, 3, '$widget has 3 children after adding' );

is( $widget->lines, 1, '$widget->lines is 1' );
is( $widget->cols, 3*8, '$widget->cols is 3*8' );

$widget->set_window( $win );

ok( defined $statics[0]->window, '$static has window after ->set_window $win' );

flush_tickit;

is_termlog( [ SETPEN,
              CLEAR,
              GOTO(0,0),
              SETPEN,
              PRINT("Widget 0"),
              GOTO(0,10),
              SETPEN,
              PRINT("Widget 1"),
              GOTO(0,20),
              SETPEN,
              PRINT("Widget 2"), ],
            'Termlog initially' );

is_display( [ "Widget 0  Widget 1  Widget 2" ],
            'Display' );

$widget->set_child_opts( 1, expand => 1 );

flush_tickit;

is_termlog( [ SETPEN,
              CLEAR,
              GOTO(0,0),
              SETPEN,
              PRINT("Widget 0"),
              GOTO(0,10),
              SETPEN,
              PRINT("Widget 1"),
              SETBG(undef),
              ERASECH(52),
              GOTO(0,72),
              SETPEN,
              PRINT("Widget 2"), ],
            'widgets moved after expand change' );

is_display( [ "Widget 0  Widget 1                                                      Widget 2" ],
            'Display after expand change' );

$statics[0]->set_text( "A longer piece of text for the static" );

flush_tickit;

is_termlog( [ SETPEN,
              CLEAR,
              GOTO(0,0),
              SETPEN,
              PRINT("A longer piece of text for the static"),
              GOTO(0,39),
              SETPEN,
              PRINT("Widget 1"),
              SETBG(undef),
              ERASECH(23),
              GOTO(0,72),
              SETPEN,
              PRINT("Widget 2"), ],
            'widgets moved after static text change' );

is_display( [ "A longer piece of text for the static  Widget 1                         Widget 2" ],
            'Display after static text change' );

$statics[1]->pen->chattr( fg => 5 );

flush_tickit;

is_termlog( [ GOTO(0,39),
              SETPEN(fg => 5),
              PRINT("Widget 1"),
              SETBG(undef),
              ERASECH(23), ],
            'redraw after static attr change' );

$widget->pen->chattr( b => 1 );

flush_tickit;

is_termlog( [ SETPEN(b => 1),
              CLEAR,
              GOTO(0,0),
              SETPEN(b => 1),
              PRINT("A longer piece of text for the static"),
              GOTO(0,39),
              SETPEN(b => 1, fg => 5),
              PRINT("Widget 1"),
              SETBG(undef),
              ERASECH(23),
              GOTO(0,72),
              SETPEN(b => 1),
              PRINT("Widget 2"), ],
            'redraw after widget attr change' );

$term->resize( 30, 100 );

flush_tickit;

is_termlog( [ SETPEN(b => 1),
              CLEAR,
              GOTO(0,0),
              SETPEN(b => 1),
              PRINT("A longer piece of text for the static"),
              GOTO(0,39),
              SETPEN(b => 1, fg => 5),
              PRINT("Widget 1"),
              SETBG(undef),
              ERASECH(43),
              GOTO(0,92),
              SETPEN(b => 1),
              PRINT("Widget 2"), ],
           'Termlog after resize' );

is_display( [ "A longer piece of text for the static  Widget 1                                             Widget 2" ],
            'Display after static text change' );

$widget->add( Tickit::Widget::Static->new( text => "New Widget" ) );

is( scalar $widget->children, 4, '$widget now has 4 children after new widget' );

flush_tickit;

is_termlog( [ SETPEN(b => 1),
              CLEAR(),
              GOTO(0,0),
              SETPEN(b => 1),
              PRINT("A longer piece of text for the static"),
              GOTO(0,39),
              SETPEN(b => 1, fg => 5),
              PRINT("Widget 1"),
              SETBG(undef),
              ERASECH(31),
              GOTO(0,80),
              SETPEN(b => 1),
              PRINT("Widget 2"),
              GOTO(0,90),
              SETPEN(b => 1),
              PRINT("New Widget"), ],
            'Termlog after new widget' );

is_display( [ "A longer piece of text for the static  Widget 1                                 Widget 2  New Widget" ],
            'Display after new widget' );

$widget->pen->chattr( bg => 4 );

flush_tickit;

is_termlog( [ SETPEN(b => 1, bg => 4),
              CLEAR(),
              GOTO(0,0),
              SETPEN(b => 1, bg => 4),
              PRINT("A longer piece of text for the static"),
              GOTO(0,39),
              SETPEN(b => 1, fg => 5, bg => 4),
              PRINT("Widget 1"),
              SETBG(4),
              ERASECH(31),
              GOTO(0,80),
              SETPEN(b => 1, bg => 4),
              PRINT("Widget 2"),
              GOTO(0,90),
              SETPEN(b => 1, bg => 4),
              PRINT("New Widget"), ],
            'Termlog after chpen bg' );

$widget->set_window( undef );

ok( !defined $statics[0]->window, '$static has no window after ->set_window undef' );
