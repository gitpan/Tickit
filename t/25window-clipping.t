#!/usr/bin/perl

use strict;
use warnings;

use Test::More;

use Tickit::Test;

my $rootwin = mk_window;

my $pos;

# Off the top
$rootwin->goto( -1, 0 );
$pos = $rootwin->print( "Clipping off top" );

is_termlog( [],
            'Termlog empty for window goto off top' );

is_display( [],
            'Display empty for window goto off top' );

is( $pos->columns, 16, '$pos->columns is 16 for print off top' );

# Off the bottom
$rootwin->goto( 28, 0 );
$pos = $rootwin->print( "Clipping off bottom" );

is_termlog( [],
            'Termlog empty for window goto off bottom' );

is_display( [],
            'Display empty for window goto off bottom' );

is( $pos->columns, 19, '$pos->columns is 19 for print off bottom' );

# Clip to the left
$rootwin->goto( 0, -7 );
$pos =$rootwin->print( "Clipping off left" );

is_termlog( [ GOTO(0,0),
              SETPEN,
              PRINT("g off left") ],
            'Termlog for window goto off left' );

is_display( [ [TEXT("g off left")], ],
            'Display for window goto off left' );

is( $pos->columns, 17, '$pos->columns is 17 for print off left' );

$rootwin->clear;
drain_termlog;

# Boundary conditions
$rootwin->goto( 0, -1 );
$rootwin->print( "A" );
$rootwin->print( "B" );

is_termlog( [ GOTO(0,0),
              SETPEN,
              PRINT("B") ],
            'Termlog for window left boundary condition' );

is_display( [ [TEXT("B")], ],
            'Display for window left boundary condition' );

$rootwin->clear;
drain_termlog;

# Clip to the right
$rootwin->goto( 0, 73 );
$pos = $rootwin->print( "Clipping off right" );

is_termlog( [ GOTO(0,73),
              SETPEN,
              PRINT("Clippin") ],
            'Termlog for window goto clip right' );

is_display( [ [BLANK(73), TEXT("Clippin")], ],
            'Display for window goto clip right' );

is( $pos->columns, 18, '$pos->columns is 16 for print off right' );

$rootwin->clear;
drain_termlog;

# Off the right
$rootwin->goto( 0, 85 );
$rootwin->print( "Entirely missing" );

is_termlog( [],
            'Termlog empty for window goto off right' );

is_display( [],
            'Display empty for window goto off right' );

$rootwin->clear;
drain_termlog;

my $win;

# Off the top
$win = $rootwin->make_sub( -2, 0, 5, 80 );

is_deeply( [ $win->_get_span_visibility( 0, 0 ) ],
           [ 0, undef ], '$win off top 0,0 invisible indefinitely' );
is_deeply( [ $win->_get_span_visibility( 3, 0 ) ],
           [ 1, 80 ], '$win off top 5,0 visible for 80 columns' );

foreach my $line ( 0 .. 4 ) {
   $win->goto( $line, 0 );
   $win->print( "Window line $line" );
}

is_termlog( [ GOTO(0,0),
              SETPEN,
              PRINT("Window line 2"),
              GOTO(1,0),
              SETPEN,
              PRINT("Window line 3"),
              GOTO(2,0),
              SETPEN,
              PRINT("Window line 4") ],
            'Termlog for window clipping off top' );

is_display( [ [TEXT("Window line 2")],
              [TEXT("Window line 3")],
              [TEXT("Window line 4")] ],
            'Display for window clipping off top' );

$win->goto( 0, 0 );
$win->erasech( 10, 0 );

is_termlog( [],
            'Termlog for window erasech off top' );

$rootwin->clear;
drain_termlog;

# Off the bottom
$win = $rootwin->make_sub( 22, 0, 5, 80 );

is_deeply( [ $win->_get_span_visibility( 0, 0 ) ],
           [ 1, 80 ], '$win off bottom 0,0 visible for 80 columns' );
is_deeply( [ $win->_get_span_visibility( 3, 0 ) ],
           [ 0, undef ], '$win off bottom 5,0 invisible indefinitely' );

foreach my $line ( 0 .. 4 ) {
   $win->goto( $line, 0 );
   $win->print( "Window line $line" );
}

is_termlog( [ GOTO(22,0),
              SETPEN,
              PRINT("Window line 0"),
              GOTO(23,0),
              SETPEN,
              PRINT("Window line 1"),
              GOTO(24,0),
              SETPEN,
              PRINT("Window line 2") ],
            'Termlog for window clipping off bottom' );

is_display( [ BLANKLINES(22),
              [TEXT("Window line 0")],
              [TEXT("Window line 1")],
              [TEXT("Window line 2")] ],
            'Display for window clipping off bottom' );

$win->goto( 4, 0 );
$win->erasech( 10, 0 );

is_termlog( [],
            'Termlog for window erasech off bottom' );

$rootwin->clear;
drain_termlog;

# Off the left
$win = $rootwin->make_sub( 10, -5, 1, 10 );

is_deeply( [ $win->_get_span_visibility( 0, 0 ) ],
           [ 0, 5 ], '$win off left 0,0 invisible for 5 columns' );
is_deeply( [ $win->_get_span_visibility( 0, 5 ) ],
           [ 1, 5 ], '$win off left 0,5 visible for 5 columns' );
is_deeply( [ $win->_get_span_visibility( 0, -3 ) ],
           [ 0, 8 ], '$win off left 0,-3 invisible for 8 columns' );

$win->goto( 0, 0 );
$win->print( $_ ) for qw( ABC DEFG HIJ );

is_termlog( [ GOTO(10,0),
              SETPEN,
              PRINT("FG" ),
              SETPEN,
              PRINT("HIJ") ],
            'Termlog for window clipping off left' );

is_display( [ BLANKLINES(10),
              [TEXT("FGHIJ")] ],
            'Display for window clipping off left' );

$win->goto( 0, 0 );
$win->erasech( 10, 0 );

is_termlog( [ GOTO(10,0),
              SETBG(undef),
              ERASECH(5) ],
            'Termlog for window erasech off left' );

$rootwin->clear;
drain_termlog;

# Off the right
$win = $rootwin->make_sub( 10, 75, 1, 10 );

is_deeply( [ $win->_get_span_visibility( 0, 0 ) ],
           [ 1, 5 ], '$win off right 0,0 visible for 5 columns' );
is_deeply( [ $win->_get_span_visibility( 0, 5 ) ],
           [ 0, undef ], '$win off right 0,5 invisible indefinitely' );
is_deeply( [ $win->_get_span_visibility( 0, -3 ) ],
           [ 0, 3 ], '$win off right 0,-3 invisible for 3 columns' );

$win->goto( 0, 0 );
$win->print( $_ ) for qw( ABC DEFG HIJ );

is_termlog( [ GOTO(10,75),
              SETPEN,
              PRINT("ABC"),
              SETPEN,
              PRINT("DE") ],
            'Termlog for window clipping off right' );

is_display( [ BLANKLINES(10),
              [BLANK(75), TEXT("ABCDE")] ],
            'Display for window clipping off right' );

$win->goto( 0, 0 );
$win->erasech( 10, 0 );

is_termlog( [ GOTO(10,75),
              SETBG(undef),
              ERASECH(5) ],
            'Termlog for window erasech off right' );

$rootwin->clear;
drain_termlog;

# Second-level nesting
$win = $rootwin->make_sub( 10, 20, 5, 10 );
my $subwin = $win->make_sub( -5, -5, 15, 20 );

is_deeply( [ $subwin->_get_span_visibility( 0, 0 ) ],
           [ 0, undef ], '$subwin 0,0 invisible indefinitely' );
is_deeply( [ $subwin->_get_span_visibility( 5, 0 ) ],
           [ 0, 5 ], '$subwin 5,0 invisible for 5 columns' );
is_deeply( [ $subwin->_get_span_visibility( 5, 5 ) ],
           [ 1, 10 ], '$subwin 5,5 visible for 10 columns' );
is_deeply( [ $subwin->_get_span_visibility( 5, 15 ) ],
           [ 0, undef ], '$subwin 5,15 invisible indefinitely' );

$subwin->goto( $_, 0 ), $subwin->print( "Content for line $_ here" ) for 0 .. 14;

is_termlog( [ GOTO(10,20),
              SETPEN,
              PRINT("nt for lin"),
              GOTO(11,20),
              SETPEN,
              PRINT("nt for lin"),
              GOTO(12,20),
              SETPEN,
              PRINT("nt for lin"),
              GOTO(13,20),
              SETPEN,
              PRINT("nt for lin"),
              GOTO(14,20),
              SETPEN,
              PRINT("nt for lin") ],
            'Termlog for clipped nested window' );

is_display( [ BLANKLINES(10),
              [BLANK(20), TEXT("nt for lin") ],
              [BLANK(20), TEXT("nt for lin") ],
              [BLANK(20), TEXT("nt for lin") ],
              [BLANK(20), TEXT("nt for lin") ],
              [BLANK(20), TEXT("nt for lin") ] ],
            'Display for clipped nested window' );

done_testing;
