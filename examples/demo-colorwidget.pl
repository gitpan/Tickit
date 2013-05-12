#!/usr/bin/perl

package ColourWidget;
use base 'Tickit::Widget';

use strict;
use warnings;

use Tickit;

my $text = "Press 0 to 7 to change the colour of this text";

sub lines { 1 }
sub cols  { length $text }

use constant CLEAR_BEFORE_RENDER => 0;
sub render
{
   my $self = shift;
   my $win = $self->window;

   $win->clear;
   $win->goto( ( $win->lines - $self->lines ) / 2, ( $win->cols - $self->cols ) / 2 );
   $win->print( $text );

   $win->focus( 0, 0 );
}

sub on_key
{
   my $self = shift;
   my ( $args ) = @_;

   if( $args->type eq "text" and $args->str =~ m/[0-7]/ ) {
      $self->pen->chattr( fg => $args->str );
      $self->redraw;
      return 1;
   }

   return 0;
}

Tickit->new( root => ColourWidget->new )->run;
