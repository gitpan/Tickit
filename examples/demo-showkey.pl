#!/usr/bin/perl

package ShowKeyWidget;
use base 'Tickit::Widget';

use strict;
use warnings;

use Tickit;

my $text;

sub lines {  1 }
sub cols  { 10 }

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

   $text = join ": ", $args->type, $args->str;
   $self->redraw;

   return 0;
}

Tickit->new( root => ShowKeyWidget->new )->run;
