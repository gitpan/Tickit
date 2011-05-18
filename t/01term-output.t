#!/usr/bin/perl

use strict;

use Test::More tests => 20;
use Test::HexString;
use IO::Async::Test;

use IO::Async::Loop;

use Tickit::Term;

# TODO: Either Tickit or IO::Async itself should do this
$SIG{PIPE} = "IGNORE";

my $loop = IO::Async::Loop->new();
testing_loop( $loop );

my ( $rd, $wr ) = $loop->pipepair or die "Cannot pipe() - $!";

my $term = Tickit::Term->new( term_out => $wr );

isa_ok( $term, "Tickit::Term", '$term isa Tickit::Term' );

$loop->add( $term );

my $stream = "";
sub stream_is
{
   my ( $expect, $name ) = @_;

   wait_for_stream { length $stream >= length $expect } $rd => $stream;

   is_hexstr( substr( $stream, 0, length $expect, "" ), $expect, $name );
}

$term->print( "Hello" );

$stream = "";
stream_is( "Hello", '$term->print' );

$term->goto( 0, 0 );

$stream = "";
stream_is( "\e[1;1H", '$term->goto( 0, 0 )' );

$term->goto( 1 );

$stream = "";
stream_is( "\e[2H", '$term->goto( 1 )' );

$term->goto( undef, 2 );

$stream = "";
stream_is( "\e[3G", '$term->goto( undef, 2 )' );

$term->move( 4, undef );

$stream = "";
stream_is( "\e[4B", '$term->move( 4, undef )' );

$term->move( undef, 7 );

$stream = "";
stream_is( "\e[7C", '$term->move( 4, undef )' );

$term->scroll( 3, 9, 3 );

$stream = "";
stream_is( "\e[4;10r\e[10H\n\n\n\e[r", '$term->scroll( 3, 9, 3 )' );

$term->scroll( 3, 9, -3 );

$stream = "";
stream_is( "\e[4;10r\e[4H\eM\eM\eM\e[r", '$term->scroll( 3, 9, -3 )' );

$term->chpen( b => 1 );

$stream = "";
stream_is( "\e[1m", '$term->chpen( b => 1 )' );

$term->chpen( b => 0 );

$stream = "";
stream_is( "\e[m", '$term->chpen( b => 0 )' );

$term->clear;

$stream = "";
stream_is( "\e[2J", '$term->clear' );

$term->eraseinline;

$stream = "";
stream_is( "\e[K", '$term->eraseinline' );

$term->erasech( 23 );

$stream = "";
stream_is( "\e[23X", '$term->erasech( 23 )' );

$term->insertch( 8 );

$stream = "";
stream_is( "\e[8@", '$term->insertch( 8 )' );

$term->deletech( 17 );

$stream = "";
stream_is( "\e[17P", '$term->deletech( 17 )' );

$term->mode_altscreen( 1 );

$stream = "";
stream_is( "\e[?1049h", '$term->mode_altscreen( 1 )' );

$term->mode_altscreen( 0 );

$stream = "";
stream_is( "\e[?1049l", '$term->mode_altscreen( 0 )' );

$term->mode_mouse( 1 );

$stream = "";
stream_is( "\e[?1002h", '$term->mode_mouse( 1 )' );

$term->mode_mouse( 0 );

$stream = "";
stream_is( "\e[?1002l", '$term->mode_mouse( 0 )' );
