#!/usr/bin/perl

use strict;

use Test::More tests => 9;

use Tickit::Test;

my ( $term, $rootwin ) = mk_term_and_window;

my $win;

# Off the top
$win = $rootwin->make_sub( -2, 0, 5, 80 );

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

$win->goto( 0, 0 );
$win->erasech( 10, 0 );

is_termlog( [],
            'Termlog for window erasech off top' );

# Off the bottom
$win = $rootwin->make_sub( 22, 0, 5, 80 );

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

$win->goto( 4, 0 );
$win->erasech( 10, 0 );

is_termlog( [],
            'Termlog for window erasech off bottom' );

# Off the left
$win = $rootwin->make_sub( 10, -5, 1, 10 );

$win->goto( 0, 0 );
$win->print( $_ ) for qw( ABC DEFG HIJ );

is_termlog( [ GOTO(10,0),
              SETPEN,
              PRINT("FG" ),
              SETPEN,
              PRINT("HIJ") ],
            'Termlog for window clipping off left' );

$win->goto( 0, 0 );
$win->erasech( 10, 0 );

is_termlog( [ GOTO(10,0),
              SETBG(undef),
              ERASECH(5) ],
            'Termlog for window erasech off left' );

# Off the right
$win = $rootwin->make_sub( 10, 75, 1, 10 );

$win->goto( 0, 0 );
$win->print( $_ ) for qw( ABC DEFG HIJ );

is_termlog( [ GOTO(10,75),
              SETPEN,
              PRINT("ABC"),
              SETPEN,
              PRINT("DE") ],
            'Termlog for window clipping off right' );

$win->goto( 0, 0 );
$win->erasech( 10, 0 );

is_termlog( [ GOTO(10,75),
              SETBG(undef),
              ERASECH(5) ],
            'Termlog for window erasech off right' );

# Second-level nesting
$win = $rootwin->make_sub( 10, 20, 5, 10 );
my $subwin = $win->make_sub( -5, -5, 15, 20 );

$subwin->goto( $_, 0 ) and $subwin->print( "Content for line $_ here" ) for 0 .. 14;

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
