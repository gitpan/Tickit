#!/usr/bin/perl

use strict;

# We need a UTF-8 locale to force libtermkey into UTF-8 handling, even if the
# system locale is not
BEGIN {
   $ENV{LANG} .= ".UTF-8" unless $ENV{LANG} =~ m/\.UTF-8$/;
}

use Test::More tests => 2;
use Test::HexString;
use IO::Async::Test;

use IO::Async::Loop;

use Tickit::Term;

# TODO: Either Tickit or IO::Async itself should do this
$SIG{PIPE} = "IGNORE";

my $loop = IO::Async::Loop->new();
testing_loop( $loop );

my ( $rdI, $wrI, $rdO, $wrO ) = $loop->pipequad or die "Cannot pipequad - $!";

my @keys;

my $term = Tickit::Term->new(
   term_in  => $rdI,
   term_out => $wrO,

   on_key => sub {
      my ( $self, $type, $str, $key ) = @_;
      push @keys, [ $type => $str ];
   },
);

$loop->add( $term );

# Drain terminal initialisation strings
$rdO->sysread( my $dummy, 8192 );

# We'll test with a Unicode character outside of Latin-1, to ensure it
# roundtrips correctly
#
# 'ĉ' [U+0109] - LATIN SMALL LETTER C WITH CIRCUMFLEX
#  UTF-8: 0xc4 0x89

$wrI->syswrite( "\xc4\x89" );

undef @keys;
wait_for { @keys };

is_deeply( \@keys, [ [ text => "\x{109}" ] ], 'on_key reads UTF-8' );

$term->print( "\x{109}" );

my $stream = "";
wait_for_stream { length $stream >= 2 } $rdO => $stream;

is_hexstr( $stream, "\xc4\x89", 'print outputs UTF-8' );
