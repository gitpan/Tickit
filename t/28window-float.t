#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use Test::Identity;
use Test::Refcount;

use Tickit::Test;

my $root = mk_window;

my $rootfloat = $root->make_float( 10, 10, 5, 30 );
flush_tickit;

is_oneref( $rootfloat, '$rootfloat has refcount 1 initially' );
is_refcount( $root, 3, '$root has refcount 3 after ->make_float' );

is_deeply( [ $root->_get_span_visibility( 10, 0 ) ],
           [ 1, 10 ], '$root 10,0 visible for 10 columns' );
is_deeply( [ $root->_get_span_visibility( 10, 10 ) ],
           [ 0, 30 ], '$root 10,10 invisible for 30 columns' );
is_deeply( [ $root->_get_span_visibility( 10, 40 ) ],
           [ 1, 40 ], '$root 10,40 visible for 40 columns' );
is_deeply( [ $root->_get_span_visibility( 15, 0 ) ],
           [ 1, 80 ], '$root 15,0 visible for 80 columns' );

is_deeply( [ $rootfloat->_get_span_visibility( 0, 0 ) ],
           [ 1, 30 ], '$rootfloat 0,0 is visible for 30 columns' );
is_deeply( [ $rootfloat->_get_span_visibility( 0, 20 ) ],
           [ 1, 10 ], '$rootfloat 0,20 is visible for 10 columns' );

$root->set_on_expose( sub {
   my ( $win, $rb, $rect ) = @_;

   foreach my $line ( $rect->linerange ) {
      $rb->text_at( $line, $rect->left, "X" x $rect->cols );
   }
});

$root->expose( Tickit::Rect->new(
   top => 10, lines => 1, left => 0, cols => 80,
) );
flush_tickit;

is_termlog( [ GOTO(10,0),
              SETPEN,
              PRINT("X"x10),
              GOTO(10,40),
              SETPEN,
              PRINT("X"x40) ],
            'Termlog for print under floating window' );

is_display( [ BLANKLINES(10),
              [TEXT("X"x10), BLANK(30), TEXT("X"x40)] ],
            'Display for print under floating window' );

{
   my $win = $root->make_sub( 10, 20, 1, 50 );

   $win->set_on_expose( sub {
      my ( undef, $rb, $rect ) = @_;
      $rb->text_at( 0, 0, "Y" x 50 );
   });

   $win->expose;
   flush_tickit;

   is_termlog( [ GOTO(10,40),
                 SETPEN,
                 PRINT("Y"x30) ],
               'Termlog for print sibling under floating window' );

   is_display( [ BLANKLINES(10),
                 [TEXT("X"x10), BLANK(30), TEXT("Y"x30), TEXT("X"x10)] ],
               'Display for print sibling under floating window' );

   my $popupwin = $win->make_popup( 2, 2, 10, 10 );
   flush_tickit;

   is_oneref( $popupwin, '$popupwin has refcount 1 initially' );

   identical( $popupwin->parent, $root, '$popupwin->parent is $root' );

   is( $popupwin->abs_top,  12, '$popupwin->abs_top' );
   is( $popupwin->abs_left, 22, '$popupwin->abs_left' );

   my @key_events;
   $popupwin->set_on_key( sub {
      my ( $win, $ev ) = @_;
      push @key_events, [ $ev->type => $ev->str ];
      return 1;
   } );

   presskey( text => "G" );

   my @mouse_events;
   $popupwin->set_on_mouse( sub {
      my ( $win, $ev ) = @_;
      push @mouse_events, [ $ev->type => $ev->button, $ev->line, $ev->col ];
      return 1;
   } );

   pressmouse( press => 1, 5, 12 );

   is_deeply( \@mouse_events, [ [ press => 1, -7, -10 ] ] );

   $popupwin->close;
   $win->close;
}

$rootfloat->set_on_expose( sub {
   my ( undef, $rb, $rect ) = @_;
   $rb->text_at( 0, 0, "|-- Yipee --|" );
});
$rootfloat->expose;
flush_tickit;

is_termlog( [ GOTO(10,10),
              SETPEN,
              PRINT("|-- Yipee --|") ],
            'Termlog for print to floating window' );

is_display( [ BLANKLINES(10),
              [TEXT("X"x10), TEXT("|-- Yipee --|"), BLANK(17), TEXT("Y"x30), TEXT("X"x10)] ],
            'Display for print to floating window' );

my $subwin = $rootfloat->make_sub( 0, 4, 1, 6 );

$subwin->set_on_expose( sub {
   my ( undef, $rb, $rect ) = @_;
   $rb->text_at( 0, 0, "Byenow" );
});
$subwin->expose;
flush_tickit;

is_termlog( [ GOTO(10,14),
              SETPEN,
              PRINT("Byenow") ],
            'Termlog for print to child of floating window' );

is_display( [ BLANKLINES(10),
              [TEXT("X"x10), TEXT("|-- Byenow--|"), BLANK(17), TEXT("Y"x30), TEXT("X"x10)] ],
            'Display for print to child of floating window' );

$rootfloat->hide;
flush_tickit;
drain_termlog;

is_deeply( [ $root->_get_span_visibility( 10, 0 ) ],
           [ 1, 80 ], '$root 10,0 visible for 80 columns after $rootfloat->hide' );

$rootfloat->show;
flush_tickit;
drain_termlog;

# Scrolling with float obscurations
{
   my @exposed_rects;
   $root->set_on_expose( sub { push @exposed_rects, $_[2] } );

   $root->scroll( 3, 0 );
   flush_tickit;

   is_termlog( [ SETPEN,
                 SCROLLRECT(0,0,10,80, 3,0),
                 SCROLLRECT(15,0,10,80, 3,0) ],
               'Termlog after scroll with floats' );

   is_deeply( \@exposed_rects,
              [ Tickit::Rect->new( top =>  7, left =>  0, lines => 3, cols => 80 ),
                Tickit::Rect->new( top => 10, left =>  0, lines => 5, cols => 10 ),
                Tickit::Rect->new( top => 10, left => 40, lines => 5, cols => 40 ),
                Tickit::Rect->new( top => 22, left =>  0, lines => 3, cols => 80 ), ],
              'Exposed regions after scroll with floats' );
}

done_testing;
