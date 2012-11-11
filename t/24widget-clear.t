#!/usr/bin/perl

use strict;

use Test::More tests => 4;

use Tickit::Test;

use Tickit::Widget;

my $win = mk_window;

{
   my $widget = WidgetWithClear->new;
   $widget->set_window( $win );

   flush_tickit;

   is_display( [ [TEXT("Hello")] ],
                 'Display initially for widget with clear' );

   $win->goto( 1, 0 );
   $win->print( "Junk" );

   $win->expose;

   flush_tickit;

   is_display( [ [TEXT("Hello")] ],
                 'Display cleared of junk by widget with clear' );
}

{
   my $widget = WidgetNoClear->new;
   $widget->set_window( $win );

   flush_tickit;

   is_display( [ [TEXT("Hello")] ],
                 'Display initially for widget without clear' );

   $win->goto( 1, 0 );
   $win->print( "Junk" );

   $win->expose;

   flush_tickit;

   is_display( [ [TEXT("Hello")],
                 [TEXT("Junk")] ],
                 'Display not cleared of junk by widget without clear' );
}

package WidgetBase;
use base qw( Tickit::Widget );

sub render
{
   my $self = shift;
   $self->window->goto( 0, 0 );
   $self->window->print( "Hello" );
}

sub lines { 1 }
sub cols  { 5 }

package WidgetWithClear;
use base qw( WidgetBase );
use constant CLEAR_BEFORE_RENDER => 1;

package WidgetNoClear;
use base qw( WidgetBase );
use constant CLEAR_BEFORE_RENDER => 0;
