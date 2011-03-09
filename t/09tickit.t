#!/usr/bin/perl

use strict;

use Test::More tests => 8;
use Test::HexString;
use Test::Refcount;
use IO::Async::Test;

use IO::Async::Loop;

use Tickit;

my $loop = IO::Async::Loop->new();
testing_loop( $loop );

my ( $my_rd, $term_wr, $term_rd, $my_wr ) = $loop->pipequad or die "Cannot pipequad - $!";

my $tickit = Tickit->new(
   term_in  => $term_rd,
   term_out => $term_wr,
);

isa_ok( $tickit, 'Tickit', '$tickit' );
is_oneref( $tickit, '$tickit has refcount 1 initially' );

my $term = $tickit->term;

isa_ok( $term, 'Tickit::Term', '$tickit->term' );

$loop->add( $tickit );

is_refcount( $tickit, 2, '$tickit has refcount 2 after $loop->add' );

# There might be some terminal setup code here... Flush it
sysread( $my_rd, my $buffer, 8192 );

my $stream = "";
sub stream_is
{
   my ( $expect, $name ) = @_;

   wait_for_stream { length $stream >= length $expect } $my_rd => $stream;

   is_hexstr( substr( $stream, 0, length $expect, "" ), $expect, $name );
}

$term->print( "Hello" );

$stream = "";
stream_is( "Hello", '$term->print' );

my $got_Ctrl_A;
$tickit->bind_key( "C-a" => sub { $got_Ctrl_A++ } );

$my_wr->syswrite( "\cA" );

wait_for { $got_Ctrl_A };

is( $got_Ctrl_A, 1, 'bind Ctrl-A' );

is_refcount( $tickit, 2, '$tickit has refcount 2 before $loop->remove' );

$loop->remove( $tickit );

is_oneref( $tickit, '$tickit has refcount 1 at EOF' );
