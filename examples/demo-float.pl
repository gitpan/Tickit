#!/usr/bin/perl

use strict;
use warnings;

use List::Util qw( min max );

use Tickit::Async;
use IO::Async::Loop;
use IO::Async::Timer::Periodic;

my $loop = IO::Async::Loop->new;
my $tickit = Tickit::Async->new;

my $colour_offset = 0;
my $rootwin = $tickit->rootwin;

my $win = $rootwin->make_sub( 5, 5, $rootwin->lines - 10, $rootwin->cols - 10 );
$win->set_on_expose( with_rb => sub {
   my ( $self, $rb, $rect ) = @_;

   foreach my $line ( $rect->linerange ) {
      $rb->text_at( $line, 0, "Here is some content for line $line " .
         "X" x ( $self->cols - 30 ),
         Tickit::Pen->new( fg => 1 + ( $line + $colour_offset ) % 6 ),
      );
   }
} );

# Logic to erase the borders
$rootwin->set_on_expose( with_rb => sub {
   my ( $self, $rb, $rect ) = @_;

   foreach my $line ( $rect->top .. 4 ) {
      $rb->erase_at( $line, 0, $self->cols );
   }
   foreach my $line ( $self->lines-5 .. $rect->bottom-1 ) {
      $rb->erase_at( $line, 0, $self->cols );
   }
   if( $rect->left < 5 ) {
      foreach my $line ( max( $rect->top, 4 ) .. min( $self->lines-5, $rect->bottom-1 ) ) {
         $rb->erase_at( $line, 0, 5 );
      }
   }
   if( $rect->right > $self->cols-5 ) {
      foreach my $line ( max( $rect->top, 4 ) .. min( $self->lines-5, $rect->bottom-1 ) ) {
         $rb->erase_at( $line, $self->cols - 5, 5 );
      }
   }
} );

$loop->add( IO::Async::Timer::Periodic->new(
   interval => 0.5,
   on_tick => sub {
      $colour_offset++;
      $colour_offset %= 6;
      $win->expose;
   } )->start );

my $popup_win;

$rootwin->set_on_mouse( with_ev => sub {
   my ( $self, $ev ) = @_;
   return unless $ev->type eq "press";

   if( $ev->button == 3 ) {
      $popup_win->hide if $popup_win;

      $popup_win = $rootwin->make_float( $ev->line, $ev->col, 3, 21 );
      $popup_win->pen->chattr( bg => 4 );

      $popup_win->set_on_expose( with_rb => sub {
         my ( $self, $rb, $rect ) = @_;
         $rb->text_at( 0, 0, "+-------------------+" );
         $rb->text_at( 1, 0, "| Popup Window Here |" );
         $rb->text_at( 2, 0, "+-------------------+" );
      } );

      $popup_win->show;
   }
   else {
      $popup_win->hide if $popup_win;
      undef $popup_win;
   }
});

$rootwin->expose;
$tickit->run;
