#!/usr/bin/perl

use strict;

use Test::More tests => 24;

use Tickit::Test;

use Tickit::Pen;

my $rootwin = mk_window;

my $win = $rootwin->make_sub( 3, 10, 4, 30 );

$win->goto( 2, 3 );
$win->print( "Hello" );

is_termlog( [ GOTO(5,13),
              SETPEN,
              PRINT("Hello"), ],
            'Termlog' );

is_display( [ ( "" ) x 5,
              "             Hello" ],
            'Display' );
 
$win->pen->chattr( b => 1 );

is_deeply( { $win->getpenattrs },
           { b => 1 },
           '$win has b => 1' );

is( $win->getpenattr( 'b' ), 1, '$win has pen b 1' );

is_deeply( { $win->get_effective_penattrs },
           { b => 1 },
           '$win->get_effective_penattrs has all attrs' );

is( $win->get_effective_penattr( 'b' ), 1, '$win has effective pen b 1' );

$win->goto( 2, 3 );
$win->print( "Hello" );

is_termlog( [ GOTO(5,13),
              SETPEN(b => 1),
              PRINT("Hello"), ],
            'Termlog with correct pen' );

$win->print( "large", Tickit::Pen->new( fg => 'red' ) );

is_termlog( [ SETPEN(b => 1, fg => 1),
              PRINT("large"), ],
            'Termlog with passed pen' );

$win->print( "world", u => 1 );

is_termlog( [ SETPEN(b => 1, u => 1),
              PRINT("world"), ],
            'Termlog with pen attributes hash' );

$win->pen->chattr( bg => 4 );

$win->erasech( 4, 0 );

is_termlog( [ SETBG(4),
              ERASECH(4) ],
            'Termlog after erasech' );

$win->erasech( 4, 0, Tickit::Pen->new( bg => 2 ) );

is_termlog( [ SETBG(2),
              ERASECH(4) ],
            'Termlog after erasech with passed pen' );

$win->erasech( 4, 0, bg => 6 );

is_termlog( [ SETBG(6),
              ERASECH(4) ],
            'Termlog after erasech with pen attributes hash' );

$win->clearline( 0 );

is_termlog( [ GOTO(3,10), SETBG(4), ERASECH(30) ],
            '$win->clearline clears one line' );

$win->clear;

is_termlog( [ GOTO(3,10), SETBG(4), ERASECH(30),
              GOTO(4,10), SETBG(4), ERASECH(30),
              GOTO(5,10), SETBG(4), ERASECH(30),
              GOTO(6,10), SETBG(4), ERASECH(30) ],
            '$win->clear clears window lines' );

my $subwin = $win->make_sub( 2, 2, 1, 10 );

$subwin->pen->chattr( fg => 3 );

is_deeply( { $subwin->getpenattrs },
           { fg => 3 },
           '$subwin has fg => 3' );

is( $subwin->getpenattr( 'b' ),  undef, '$win has pen b undef' );
is( $subwin->getpenattr( 'fg' ), 3,     '$win has pen fg 1' );

is_deeply( { $subwin->get_effective_penattrs },
           { b => 1, bg => 4, fg => 3 },
           '$subwin->get_effective_penattrs has all attrs' );

is( $subwin->get_effective_penattr( 'b' ),  1, '$win has effective pen b 1' );
is( $subwin->get_effective_penattr( 'fg' ), 3, '$win has effective pen fg 1' );

$subwin->goto( 0, 0 );
$subwin->print( "Foo" );

is_termlog( [ GOTO(5,12),
              SETPEN(fg => 3, bg => 4, b => 1),
              PRINT("Foo"), ],
            'Termlog with correct pen' );

is_display( [ ( "") x 5,
              "            Foo" ],
            'Display' );

$rootwin->scroll( 1, 0 );

is_termlog( [ SETBG(undef),
              SCROLLRECT(0,0,25,80, 1,0) ],
            'Termlog scrolled' );

ok( !$win->scroll( 1, 0 ), '$win does not support scrolling' );
