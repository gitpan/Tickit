#!/usr/bin/perl

use strict;
use warnings;

use Test::More;

use Tickit::Test;

use Tickit::Widget;

my $win = mk_window;

{
   my $warnings = "";

   my $widget = do {
      local $SIG{__WARN__} = sub { $warnings .= join "", @_ };
      LegacyRenderWidget->new;
   };

   like( $warnings,
         qr/^Constructing a legacy ->render LegacyRenderWidget at /,
         'Constructing a ->render Widget yields a warning');

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

done_testing;

package LegacyRenderWidget;
use base qw( Tickit::Widget );

sub render
{
   my $self = shift;
   $self->window->goto( 0, 0 );
   $self->window->print( "Hello" );
}

sub lines { 1 }
sub cols  { 5 }
