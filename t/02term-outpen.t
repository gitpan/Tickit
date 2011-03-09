#!/usr/bin/perl

use strict;

use Test::More tests => 7;
use Test::HexString;
use IO::Async::Test;

use IO::Async::Loop;

use Tickit::Term;

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

$term->setpen( b => 1 );
stream_is( "\e[1m", '$term->setpen( b => 1 )' );

$term->setpen( b => 1 );
stream_is( "", '$term->setpen( b => 1 ) again is no-op' );

$term->setpen( b => 0 );
stream_is( "\e[m", '$term->setpen( b => 0 ) resets SGR' );

$term->setpen( b => 1, u => 1 );
stream_is( "\e[1;4m", '$term->setpen( b => 1, u => 1 )' );

$term->setpen( b => 0 );
stream_is( "\e[22m", '$term->setpen( b => 0 )' );

$term->setpen( b => 0 );
stream_is( "", '$term->setpen( b => 0 ) again is no-op' );

$term->setpen( u => 0 );
stream_is( "\e[m", '$term->setpen( u => 0 )' );
