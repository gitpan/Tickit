#!/usr/bin/perl

use strict;

use Test::More tests => 24;
use IO::Async::Test;

use t::MockTerm;
use t::TestTickit;

my ( $term, $rootwin ) = mk_term_and_window;

my $win = $rootwin->make_sub( 3, 10, 4, 20 );

$win->goto( 2, 3 );
$win->print( "Hello" );

is_deeply( [ $term->methodlog ], 
           [ GOTO(5,13),
             SETPEN,
             PRINT("Hello"),
           ],
           '$term written to' );

is_deeply( [ $term->get_display ],
           [ BLANKS(5),
             PAD("             Hello"),
             BLANKS(19) ],
           '$term display' );
 
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

is_deeply( [ $term->methodlog ],
           [ GOTO(5,13),
             SETPEN(b => 1),
             PRINT("Hello"),
           ],
           '$term written to with correct pen' );

$win->penprint( "world", u => 1 );

is_deeply( [ $term->methodlog ],
           [ SETPEN(b => 1, u => 1),
             PRINT("world"),
           ],
           '$term written with modified pen' );

$win->pen->chattr( bg => 4 );
$win->clear;

is_deeply( [ $term->methodlog ],
           [ GOTO(3,10), SETBG(4), ERASECH(20),
             GOTO(4,10), SETBG(4), ERASECH(20),
             GOTO(5,10), SETBG(4), ERASECH(20),
             GOTO(6,10), SETBG(4), ERASECH(20) ],
           '$rootwin->flush redraws lines' );

is_deeply( [ $term->get_display ],
           [ BLANKS(25) ],
           '$term display after bg change' );

$win->clear;

is_deeply( [ $term->methodlog ],
           [ GOTO(3,10), SETBG(4), ERASECH(20),
             GOTO(4,10), SETBG(4), ERASECH(20),
             GOTO(5,10), SETBG(4), ERASECH(20),
             GOTO(6,10), SETBG(4), ERASECH(20) ],
           '$win->clear clears window lines' );

ok( !$win->insertch( 5 ), '$win cannot insertch' );
ok( !$win->deletech( 5 ), '$win cannot deletech' );

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

is_deeply( [ $term->methodlog ],
           [ GOTO(5,12),
             SETPEN(fg => 3, bg => 4, b => 1),
             PRINT("Foo"),
           ],
           '$term written to with correct pen' );

is_deeply( [ $term->get_display ],
           [ BLANKS(5),
             PAD("            Foo"),
             BLANKS(19) ],
           '$term display' );

$rootwin->scroll( 1, 0 );

is_deeply( [ $term->methodlog ],
           [ [ scroll => 0, 24, 1 ] ],
           '$term scrolled' );

ok( !$win->scroll( 1, 0 ), '$win does not support scrolling' );

ok( !$term->is_changed, 'no $term methods recorded' );
