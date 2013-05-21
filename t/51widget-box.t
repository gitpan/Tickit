#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use Test::Identity;

use Tickit::Test;

use Tickit::Widget::Box;

my $win = mk_window;

my( $child_lines, $child_cols );
my $child_render_rect;

my $widget = Tickit::Widget::Box->new(
   child => TestWidget->new,
);

ok( defined $widget, 'defined $widget' );

is( scalar $widget->children, 1, 'scalar $widget->children' );
identical( ( $widget->children )[0], $widget->child, '$widget->children[0]' );

$child_lines = 3; $child_cols = 10;

is( $widget->lines,  3, '$widget->lines with no bounds' );
is( $widget->cols,  10, '$widget->cols with no bounds' );

$widget->set_window( $win );
flush_tickit;

is( $child_render_rect, Tickit::Rect->new( top => 11, left => 35, lines => 3, cols => 10 ),
   'child render rect with no bounds' );

$widget->set_child_lines_min( 5 );
$widget->set_child_cols_min( 20 );

is( $widget->lines,  5, '$widget->lines with min bounds' );
is( $widget->cols,  20, '$widget->cols with min bounds' );

flush_tickit;

is( $child_render_rect, Tickit::Rect->new( top => 10, left => 30, lines => 5, cols => 20 ),
   'child render rect with min bounds' );

$child_lines = 8; $child_cols = 40;

$widget->set_child_lines_max( 6 );
$widget->set_child_cols_max( 30 );

is( $widget->lines,  6, '$widget->lines with max bounds' );
is( $widget->cols,  30, '$widget->cols with max bounds' );

flush_tickit;

is( $child_render_rect, Tickit::Rect->new( top => 9, left => 25, lines => 6, cols => 30 ),
   'child render rect with max bounds' );

$widget->set_child_lines( "80%" );

flush_tickit;

is( $child_render_rect, Tickit::Rect->new( top => 2, left => 25, lines => 20, cols => 30 ),
   'child render rect with lines at ratio' );

$widget->set_valign( 0.0 );
$widget->set_align( 0.0 );

flush_tickit;

is( $child_render_rect, Tickit::Rect->new( top => 0, left => 0, lines => 20, cols => 30 ),
   'child render rect with top-left alignment' );

done_testing;

package TestWidget;

use base qw( Tickit::Widget );

use constant CLEAR_BEFORE_RENDER => 0;
sub render
{
   my $self = shift;
   $child_render_rect = $self->window->rect;
}

sub lines { $child_lines }
sub cols  { $child_cols }
