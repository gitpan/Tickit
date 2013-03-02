#!/usr/bin/perl

use strict;

use Test::More tests => 23;
use Test::Refcount;

use Tickit::Test;

my $root = mk_window;

my $pos;

my $rootfloat = $root->make_float( 10, 10, 5, 30 );

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

$root->goto( 10, 0 );
$pos = $root->print( "X" x 80 );

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

is( $pos->columns, 80, '$pos->columns is 80 for print under floating window' );

{
   my $win = $root->make_sub( 10, 20, 1, 50 );

   $win->goto( 0, 0 );
   $pos = $win->print( "Y" x 50 );

   is_termlog( [ GOTO(10,20),
                 GOTO(10,40),
                 SETPEN,
                 PRINT("Y"x30) ],
               'Termlog for print sibling under floating window' );

   is_display( [ BLANKLINES(10),
                 [TEXT("X"x10), BLANK(30), TEXT("Y"x30), TEXT("X"x10)] ],
               'Display for print sibling under floating window' );

   is( $pos->columns, 50, '$pos->columns is 50 for print sibling under floating window' );

   $win->close;
}

$rootfloat->goto( 0, 0 );
$rootfloat->print( "|-- Yipee --|" );

is_termlog( [ GOTO(10,10),
              SETPEN,
              PRINT("|-- Yipee --|") ],
            'Termlog for print to floating window' );

is_display( [ BLANKLINES(10),
              [TEXT("X"x10), TEXT("|-- Yipee --|"), BLANK(17), TEXT("Y"x30), TEXT("X"x10)] ],
            'Display for print to floating window' );

ok( !$root->scrollrect( 0, 0, 20, 80, 0, +3 ), '$root disallows scrollrect under a float' );

my $subwin = $rootfloat->make_sub( 0, 4, 1, 6 );
$subwin->goto( 0, 0 );
$pos = $subwin->print( "Byenow" );

is_termlog( [ GOTO(10,14),
              SETPEN,
              PRINT("Byenow") ],
            'Termlog for print to child of floating window' );

is_display( [ BLANKLINES(10),
              [TEXT("X"x10), TEXT("|-- Byenow--|"), BLANK(17), TEXT("Y"x30), TEXT("X"x10)] ],
            'Display for print to child of floating window' );

is( $pos->columns, 6, '$pos->columns is 6 for print to child of floating window' );

$rootfloat->hide;

is_deeply( [ $root->_get_span_visibility( 10, 0 ) ],
           [ 1, 80 ], '$root 10,0 visible for 80 columns after $rootfloat->hide' );

$rootfloat->show;

# Scrolling with float obscurations
{
   my @exposed_rects;
   $root->set_on_expose( sub { push @exposed_rects, $_[1] } );
   $root->set_expose_after_scroll( 1 );

   $root->scroll( 3, 0 );
   flush_tickit;

   is_termlog( [ SETPEN,
                 SCROLLRECT(0,0,10,80, 3,0),
                 SETPEN,
                 SETPEN,
                 SETPEN,
                 SCROLLRECT(15,0,10,80, 3,0) ],
               'Termlog after scroll with floats' );

   is_deeply( \@exposed_rects,
              [ Tickit::Rect->new( top =>  7, left =>  0, lines => 3, cols => 80 ),
                Tickit::Rect->new( top => 10, left =>  0, lines => 5, cols => 10 ),
                Tickit::Rect->new( top => 10, left => 40, lines => 5, cols => 40 ),
                Tickit::Rect->new( top => 22, left =>  0, lines => 3, cols => 80 ), ],
              'Exposed regions after scroll with floats' );
}
