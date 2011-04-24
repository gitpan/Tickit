#!/usr/bin/perl

use strict;

use Test::More tests => 11;
use Test::Identity;

use t::MockTerm;
use t::TestTickit;

use Tickit::Widget::Static;
use Tickit::Widget::Box;

my ( $term, $win ) = mk_term_and_window;

my $static = Tickit::Widget::Static->new( text => "Widget" );

my $widget = Tickit::Widget::Box->new;

ok( defined $widget, 'defined $widget' );

is( scalar $widget->children, 0, '$widget has 0 children' );

$widget->add( $static );

is( scalar $widget->children, 1, '$widget has 1 child after adding' );
identical( $widget->child, $static, '$widget->child is $static' );

is( $widget->lines, 1, '$widget->lines is 1' );
is( $widget->cols,  6, '$widget->cols is 6' );

$widget->set_window( $win );

ok( defined $static->window, '$static has window after $widget->set_window' );

flush_tickit;

is_deeply( [ $term->methodlog ],
           [ SETPEN,
             CLEAR,
             GOTO(0,0),
             SETPEN,
             PRINT("Widget"),
             SETBG(undef),
             ERASECH(74),
             ],
           '$term written to initially' );

is_deeply( [ $term->get_display ],
           [ PAD("Widget"),
             BLANKS(24) ],
           '$term display initially' );

$widget->set_border( 2 );

flush_tickit;

is_deeply( [ $term->methodlog ],
           [ SETPEN,
             CLEAR,
             GOTO(2,2),
             SETPEN,
             PRINT("Widget"),
             SETBG(undef),
             ERASECH(70),
             ],
           '$term written to after ->set_border' );

is_deeply( [ $term->get_display ],
           [ BLANKS(2),
             PAD("  Widget"),
             BLANKS(22) ],
           '$term display after ->set_border' );
