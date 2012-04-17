#!/usr/bin/perl

use strict;

use Test::More tests => 22;
use Test::HexString;

use Tickit::Term;

my $stream = "";
sub stream_is
{
   my ( $expect, $name ) = @_;

   is_hexstr( substr( $stream, 0, length $expect, "" ), $expect, $name );
}

my $writer = bless [], "TestWriter";
sub TestWriter::write { $stream .= $_[1] }

my $term = Tickit::Term->new( writer => $writer );
$term->set_size( 25, 80 );

isa_ok( $term, "Tickit::Term", '$term isa Tickit::Term' );

$stream = "";
$term->print( "Hello" );
stream_is( "Hello", '$term->print' );

$stream = "";
$term->goto( 0, 0 );
stream_is( "\e[1;1H", '$term->goto( 0, 0 )' );

$stream = "";
$term->goto( 1 );
stream_is( "\e[2H", '$term->goto( 1 )' );

$stream = "";
$term->goto( undef, 2 );
stream_is( "\e[3G", '$term->goto( undef, 2 )' );

$stream = "";
$term->move( 4, undef );
stream_is( "\e[4B", '$term->move( 4, undef )' );

$stream = "";
$term->move( undef, 7 );
stream_is( "\e[7C", '$term->move( 4, undef )' );

$stream = "";
$term->scrollrect( 3, 0, 7, 80, 3, 0 );
stream_is( "\e[4;10r\e[10H\n\n\n\e[r", '$term->scrollrect( 3,0,7,80, 3,0 )' );

$stream = "";
$term->scrollrect( 3, 0, 7, 80, -3, 0 );
stream_is( "\e[4;10r\e[4H\eM\eM\eM\e[r", '$term->scrollrect( 3,0,7,80, -3,0 )' );

# Horizontal scroll using ICH/DCH
$stream = "";
$term->scrollrect( 5, 0, 1, 80, 0, 3 );
#           CPA    ICH
stream_is( "\e[6;1H\e[3@", '$term->scrollrect( 5,0,1,80, 0,3 ) using ICH' );
$stream = "";
$term->scrollrect( 6, 10, 2, 70, 0, 5 );
#           CPA    ICH
stream_is( "\e[7;11H\e[5@\e[8;11H\e[5@", '$term->scrollrect( 6,10,2,70, 0,5 ) using ICH' );

$stream = "";
$term->scrollrect( 5, 0, 1, 80, 0, -3 );
#           CPA    DCH
stream_is( "\e[6;1H\e[3P", '$term->scrollrect( 5,0,1,80, 0,-3 ) using DCH' );
$stream = "";
$term->scrollrect( 6, 10, 2, 70, 0, -5 );
#           CPA    DCH
stream_is( "\e[7;11H\e[5P\e[8;11H\e[5P", '$term->scrollrect( 6,10,2,70, 0,-5 ) using DCH' );

$stream = "";
$term->chpen( b => 1 );
stream_is( "\e[1m", '$term->chpen( b => 1 )' );

$stream = "";
$term->chpen( b => 0 );
stream_is( "\e[m", '$term->chpen( b => 0 )' );

$stream = "";
$term->clear;
stream_is( "\e[2J", '$term->clear' );

$stream = "";
$term->eraseinline;
stream_is( "\e[K", '$term->eraseinline' );

$stream = "";
$term->erasech( 23 );
stream_is( "\e[23X", '$term->erasech( 23 )' );

$stream = "";
$term->mode_altscreen( 1 );
stream_is( "\e[?1049h", '$term->mode_altscreen( 1 )' );

$stream = "";
$term->mode_altscreen( 0 );
stream_is( "\e[?1049l", '$term->mode_altscreen( 0 )' );

$stream = "";
$term->mode_mouse( 1 );
stream_is( "\e[?1002h", '$term->mode_mouse( 1 )' );

$stream = "";
$term->mode_mouse( 0 );
stream_is( "\e[?1002l", '$term->mode_mouse( 0 )' );
