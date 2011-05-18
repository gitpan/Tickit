#!/usr/bin/perl

use strict;

use Test::More tests => 16;
use Test::Identity;

use Tickit::Test;

use Tickit::Widget::Static;
use Tickit::Widget::Box;

my $win = mk_window;

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

is_termlog( [ SETPEN,
              CLEAR,
              GOTO(0,0),
              SETPEN,
              PRINT("Widget"),
              SETBG(undef),
              ERASECH(74), ],
            'Termlog initially' );

is_display( [ "Widget" ],
            'Display initially' );

$widget->set_border( 2 );

flush_tickit;

is_termlog( [ SETPEN,
              CLEAR,
              GOTO(2,2),
              SETPEN,
              PRINT("Widget"),
              SETBG(undef),
              ERASECH(70), ],
            'Termlog after ->set_border' );

is_display( [ "", "", "  Widget" ],
            'Display after ->set_border' );

$widget->set_window( undef );
$static->set_window( undef );

$widget = Tickit::Widget::Box->new;

$widget->set_window( $win );

flush_tickit;

is_termlog( [ SETPEN,
              CLEAR, ],
            'Termlog before late adding of child' );

is_display( [ ],
            'Display blank before late adding of child' );

$widget->add( $static );

flush_tickit;

is_termlog( [ GOTO(0,0),
              SETPEN,
              PRINT("Widget"),
              SETBG(undef),
              ERASECH(74), ],
            'Termlog after late adding of child' );

is_display( [ "Widget" ],
            'Display after late adding of child' );

$widget->set_window( undef );

ok( !defined $static->window, '$static has no window after ->set_window undef' );
