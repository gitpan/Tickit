#!/usr/bin/perl

use strict;

use Test::More tests => 11;
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

$loop->add( $term );

sub stream_is
{
   my ( $expect, $name ) = @_;

   my $stream = "";

   wait_for_stream { length $stream >= length $expect } $rd => $stream;

   is_hexstr( substr( $stream, 0, length $expect, "" ), $expect, $name );
}

# Reset the pen
$term->setpen;
stream_is( "\e[m", '$term->setpen()' );

$term->chpen( b => 1 );
stream_is( "\e[1m", '$term->chpen( b => 1 )' );

$term->chpen( b => 1 );
stream_is( "", '$term->chpen( b => 1 ) again is no-op' );

$term->chpen( b => undef );
stream_is( "\e[m", '$term->chpen( b => undef ) resets SGR' );

$term->chpen( b => 1, u => 1 );
stream_is( "\e[1;4m", '$term->chpen( b => 1, u => 1 )' );

$term->chpen( b => undef );
stream_is( "\e[22m", '$term->chpen( b => undef )' );

$term->chpen( b => undef );
stream_is( "", '$term->chpen( b => undef ) again is no-op' );

$term->chpen( u => undef );
stream_is( "\e[m", '$term->chpen( u => undef )' );

$term->setpen( fg => 1, bg => 5 );
stream_is( "\e[31;45m", '$term->setpen( fg => 1, bg => 5 )' );

$term->chpen( fg => 9 );
stream_is( "\e[91m", '$term->setpen( fg => 9 )' );

$term->setpen( u => 1 );
stream_is( "\e[39;49;4m", '$term->setpen( u => 1 )' );
