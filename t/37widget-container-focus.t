#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use Test::Identity;
use Test::Refcount;

use Tickit::Test;

# Since we need real Windows in the widgets, it's easier just to use some HBoxes
# We haven't strictly tested this yet, but never mind...
use Tickit::Widget::HBox;

my ( $term, $win ) = mk_term_and_window;

my @f_widgets = map { my $w = TestWidget->new; $w->{CAN_FOCUS} = 1; $w } 0 .. 1;
my @n_widgets = map { TestWidget->new } 0 .. 3;

# first/after/before/last on a single container
{
   my $container = Tickit::Widget::HBox->new;
   $container->set_window( $win );

   $container->add( $_ ) for $n_widgets[0], $f_widgets[0], $n_widgets[1], $f_widgets[1];

   $container->focus_next( first => undef );
   ok( $f_widgets[0]->window->is_focused, '$f_widgets[0] has focus after "first" linear' );

   $container->focus_next( after => $f_widgets[0] );
   ok( $f_widgets[1]->window->is_focused, '$f_widgets[1] has focus after "after" linear' );

   $container->focus_next( before => $f_widgets[1] );
   ok( $f_widgets[0]->window->is_focused, '$f_widgets[0] has focus after "before" linear' );

   $container->focus_next( last => undef );
   ok( $f_widgets[1]->window->is_focused, '$f_widgets[1] has focus after "last" linear' );

   # Wrap-around at the top level
   $container->focus_next( after => $f_widgets[1] );
   ok( $f_widgets[0]->window->is_focused, '$f_widgets[0] has focus after "after" linear wraparound' );

   $container->focus_next( before => $f_widgets[0] );
   ok( $f_widgets[1]->window->is_focused, '$f_widgets[1] has focus after "before" linear wraparound' );

   $container->set_window( undef );
}

# Tree search
{
   my $tree1 = Tickit::Widget::HBox->new;
   $tree1->add( $_ ) for $f_widgets[0], $n_widgets[0];

   my $tree2 = Tickit::Widget::HBox->new;
   $tree2->add( $_ ) for $f_widgets[1], $n_widgets[1];

   my $root = Tickit::Widget::HBox->new;
   $root->add( $_ ) for $tree1, $tree2;

   $root->set_window( $win );

   $root->focus_next( first => undef );
   ok( $f_widgets[0]->window->is_focused, '$f_widgets[0] has focus after "first" tree' );

   $tree1->focus_next( after => $f_widgets[0] );
   ok( $f_widgets[1]->window->is_focused, '$f_widgets[1] has focus after "after" tree' );

   $tree2->focus_next( before => $f_widgets[1] );
   ok( $f_widgets[0]->window->is_focused, '$f_widgets[0] has focus after "before" tree' );

   $root->focus_next( last => undef );
   ok( $f_widgets[1]->window->is_focused, '$f_widgets[1] has focus after "last" tree' );

   # Wrap-around at the top level
   $tree2->focus_next( after => $f_widgets[1] );
   ok( $f_widgets[0]->window->is_focused, '$f_widgets[0] has focus after "after" tree wraparound' );

   $tree1->focus_next( before => $f_widgets[0] );
   ok( $f_widgets[1]->window->is_focused, '$f_widgets[1] has focus after "before" tree wraparound' );

   $root->set_window( undef );
}

# Tree with unfocusable children
{
   my $tree1 = Tickit::Widget::HBox->new;
   $tree1->add( $_ ) for $f_widgets[0], $n_widgets[0];

   my $tree2 = Tickit::Widget::HBox->new;
   $tree2->add( $_ ) for $n_widgets[1], $n_widgets[2];

   my $tree3 = Tickit::Widget::HBox->new;
   $tree3->add( $_ ) for $f_widgets[1], $n_widgets[3];

   my $root = Tickit::Widget::HBox->new;
   $root->add( $_ ) for $tree1, $tree2, $tree3;

   $root->set_window( $win );

   $root->focus_next( first => undef );
   ok( $f_widgets[0]->window->is_focused, '$f_widgets[0] has focus after "first" tree sparse' );

   $tree1->focus_next( after => $f_widgets[0] );
   ok( $f_widgets[1]->window->is_focused, '$f_widgets[1] has focus after "after" tree sparse' );

   $tree2->focus_next( before => $f_widgets[1] );
   ok( $f_widgets[0]->window->is_focused, '$f_widgets[0] has focus after "before" tree sparse' );

   $root->focus_next( last => undef );
   ok( $f_widgets[1]->window->is_focused, '$f_widgets[1] has focus after "last" tree sparse' );

   $root->set_window( undef );
}

# Tab / Shift-Tab key handling
{
   my $container = Tickit::Widget::HBox->new;
   $container->set_window( $win );

   $container->add( $_ ) for $n_widgets[0], $f_widgets[0], $n_widgets[1], $f_widgets[1];

   $container->focus_next( first => undef );
   ok( $f_widgets[0]->window->is_focused, '$f_widgets[0] has focus before Tab' );

   presskey( key => "Tab" );

   ok( $f_widgets[1]->window->is_focused, '$f_widgets[1] has focus after Tab' );

   $container->set_window( undef );
}

done_testing;

package TestWidget;

use base qw( Tickit::Widget );

use constant CLEAR_BEFORE_RENDER => 0;
sub render {}

sub lines { 1 }
sub cols  { 5 }

sub CAN_FOCUS { shift->{CAN_FOCUS} }

use constant KEYPRESSES_FROM_STYLE => 1;
