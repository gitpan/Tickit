#!/usr/bin/perl

use strict;
use warnings;

use Tickit;

package DndArea;
use base qw( Tickit::Widget );
use Tickit::RenderBuffer;

sub lines { 1 }
sub cols  { 1 }

use constant CLEAR_BEFORE_RENDER => 0;
sub render
{
   my $self = shift;
   my $win = $self->window or return;

   my $rb = Tickit::RenderBuffer->new( lines => $win->lines, cols => $win->cols );
   $rb->clear( $win->pen );

   my $centreline = int( $win->lines / 2 );

   $rb->text_at( $centreline, int( $win->cols / 2 ) - 5, ref $self, $win->pen );

   if( $self->can( "render_rb" ) ) {
      $rb->save;

      $rb->setpen( $win->pen );
      $self->render_rb( $rb );

      $rb->restore;
   }

   $rb->render_to_window( $win );
}

sub render_rb
{
   my $self = shift;
   my ( $rb ) = @_;

   if( defined $self->{start_line} ) {
      $rb->text_at( $self->{start_line}, $self->{start_col}, "S", Tickit::Pen->new( fg => "red" ) );
   }

   if( defined $self->{over_line} ) {
      $rb->text_at( $self->{over_line}-1, $self->{over_col}  , "|", Tickit::Pen->new ( fg => "black" ) );
      $rb->text_at( $self->{over_line}+1, $self->{over_col}  , "|", Tickit::Pen->new ( fg => "black" ) );
      $rb->text_at( $self->{over_line}  , $self->{over_col}-1, "-", Tickit::Pen->new ( fg => "black" ) );
      $rb->text_at( $self->{over_line}  , $self->{over_col}+1, "-", Tickit::Pen->new ( fg => "black" ) );
   }

   if( defined $self->{end_line} ) {
      $rb->text_at( $self->{end_line}, $self->{end_col}, "E", Tickit::Pen->new ( fg => "magenta" ) );
   }
}

sub on_mouse
{
   my $self = shift;
   my ( $args ) = @_;

   if( $args->type eq "press" ) {
      undef $_ for @{$self}{qw( start_line start_col over_line over_col end_line end_col )};
      $self->redraw;
      return 1;
   }

   if( $args->type eq "drag_start" ) {
      ( $self->{start_line}, $self->{start_col} ) = ( $args->line, $args->col );
      $self->redraw;
      return 1;
   }

   if( $args->type eq "drag" ) {
      ( $self->{over_line}, $self->{over_col} ) = ( $args->line, $args->col );
      $self->redraw;
      return 1;
   }

   if( $args->type eq "drag_drop" ) {
      undef $_ for @{$self}{qw( over_line over_col )};
      ( $self->{end_line}, $self->{end_col} ) = ( $args->line, $args->col );
      $self->redraw;
      return 1;
   }
}

Tickit->new( root => DndArea->new( bg => "blue" ) )->run;
