#!/usr/bin/perl

use strict;

use Test::More tests => 17;

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

is_display( [ [TEXT("Widget 0"),
               BLANK(2),
               TEXT("Widget 1"),
               BLANK(2),
               TEXT("Widget 2")] ],
            'Display initially' );

$widget->set_child_opts( 1, expand => 1 );

flush_tickit;

is_display( [ [TEXT("Widget 0"),
               BLANK(2),
               TEXT("Widget 1"),
               BLANK(54),
               TEXT("Widget 2")] ],
            'Display after expand change' );

$statics[0]->set_text( "A longer piece of text for the static" );

flush_tickit;

is_display( [ [TEXT("A longer piece of text for the static"),
               BLANK(2),
               TEXT("Widget 1"),
               BLANK(25),
               TEXT("Widget 2")] ],
            'Display after static text change' );

$statics[1]->pen->chattr( fg => 5 );

flush_tickit;

is_display( [ [TEXT("A longer piece of text for the static"),
               BLANK(2),
               TEXT("Widget 1",fg=>5),
               BLANK(25),
               TEXT("Widget 2")] ],
            'Display after static attr change' );

$widget->pen->chattr( b => 1 );

flush_tickit;

# TODO: This part is non-ideal due to the boldness of BLANK() pens. Look into it
is_display( [ [TEXT("A longer piece of text for the static",b=>1),
               BLANK(2,b=>1),
               TEXT("Widget 1",fg=>5,b=>1),
               BLANK(23),
               BLANK(2,b=>1),
               TEXT("Widget 2",b=>1)] ],
            'Display after widget attr change' );

resize_term( 30, 100 );

flush_tickit;

is_display( [ [TEXT("A longer piece of text for the static",b=>1),
               BLANK(2,b=>1),
               TEXT("Widget 1",fg=>5,b=>1),
               BLANK(43),
               BLANK(2,b=>1),
               TEXT("Widget 2",b=>1)] ],
            'Display after resize' );

$widget->add( Tickit::Widget::Static->new( text => "New Widget" ) );

is( scalar $widget->children, 4, '$widget now has 4 children after new widget' );

flush_tickit;

is_display( [ [TEXT("A longer piece of text for the static",b=>1),
               BLANK(2,b=>1),
               TEXT("Widget 1",fg=>5,b=>1),
               BLANK(31),
               BLANK(2,b=>1),
               TEXT("Widget 2",b=>1),
               BLANK(2,b=>1),
               TEXT("New Widget",b=>1)] ],
            'Display after new widget' );

$widget->pen->chattr( bg => 4 );

flush_tickit;

is_display( [ [TEXT("A longer piece of text for the static",bg=>4,b=>1),
               BLANK(2,bg=>4,b=>1),
               TEXT("Widget 1",fg=>5,bg=>4,b=>1),
               BLANK(31,bg=>4),
               BLANK(2,bg=>4,b=>1),
               TEXT("Widget 2",bg=>4,b=>1),
               BLANK(2,bg=>4,b=>1),
               TEXT("New Widget",bg=>4,b=>1)] ],
            'Display after chpen bg' );

$widget->set_child_opts( 2, force_size => 15 );

flush_tickit;

is_display( [ [TEXT("A longer piece of text for the static",bg=>4,b=>1),
               BLANK(2,bg=>4,b=>1),
               TEXT("Widget 1",fg=>5,bg=>4,b=>1),
               BLANK(24,bg=>4),
               BLANK(2,bg=>4,b=>1),
               TEXT("Widget 2",bg=>4,b=>1),
               BLANK(7,bg=>4),
               BLANK(2,bg=>4,b=>1),
               TEXT("New Widget",bg=>4,b=>1)] ],
            'Display after force_size' );

$widget->set_window( undef );

ok( !defined $statics[0]->window, '$static has no window after ->set_window undef' );