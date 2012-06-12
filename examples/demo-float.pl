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
$win->set_on_expose( sub {
   my ( $self, $rect ) = @_;

   foreach my $line ( $rect->top .. $rect->bottom - 1 ) {
      $self->goto( $line, 0 );
      $self->print( "Here is some content for line $line " .
         "X" x ( $self->cols - 30 ),
         fg => 1 + ( $line + $colour_offset ) % 6,
      );
   }
} );

# Logic to erase the borders
$rootwin->set_on_expose( sub {
   my ( $self, $rect ) = @_;

   foreach my $line ( $rect->top .. 4 ) {
      $self->clearline( $line );
   }
   foreach my $line ( $self->lines-5 .. $rect->bottom-1 ) {
      $self->clearline( $line );
   }
   if( $rect->left < 5 ) {
      foreach my $line ( max( $rect->top, 4 ) .. min( $self->lines-5, $rect->bottom-1 ) ) {
         $self->goto( $line, 0 );
         $self->erasech( 5 );
      }
   }
   if( $rect->right > $self->cols-5 ) {
      foreach my $line ( max( $rect->top, 4 ) .. min( $self->lines-5, $rect->bottom-1 ) ) {
         $self->goto( $line, $self->cols-5 );
         $self->erasech( 5 );
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

$rootwin->set_on_mouse( sub {
   my ( undef, $ev, $button, $line, $col ) = @_;
   return unless $ev eq "press";

   if( $button == 3 ) {
      $popup_win->hide if $popup_win;

      $popup_win = $rootwin->make_float( $line, $col, 3, 21 );
      $popup_win->pen->chattr( bg => 4 );

      $popup_win->set_on_expose( sub {
         my ( $self, $rect ) = @_;
         $self->goto( 0, 0 );
         $self->print( "+-------------------+" );
         $self->goto( 1, 0 );
         $self->print( "| Popup Window Here |" );
         $self->goto( 2, 0 );
         $self->print( "+-------------------+" );
      } );

      $popup_win->show;
   }
   else {
      $popup_win->hide if $popup_win;
      undef $popup_win;
   }
} );

$rootwin->expose;
$tickit->run;
