#!/usr/bin/perl

use strict;

use Test::More tests => 5;
use Test::HexString;
use IO::Async::Test;

use IO::Async::Loop;

use Tickit::Term;

my $loop = IO::Async::Loop->new();
testing_loop( $loop );

my ( $rd, $wr ) = $loop->pipepair or die "Cannot pipe() - $!";

my @keys;

my $term = Tickit::Term->new(
   term_in => $rd,
   on_key  => sub {
      my ( $self, $type, $str, $key ) = @_;
      push @keys, [ $type => $str ];
      isa_ok( $key, "Term::TermKey::Key", '$key' );
   },
);

isa_ok( $term, "Tickit::Term", '$term isa Tickit::Term' );

$loop->add( $term );

$wr->syswrite( "h" );

undef @keys;
wait_for { @keys };

is_deeply( \@keys, [ [ text => "h" ] ], 'on_key h' );

$wr->syswrite( "\cA" );

undef @keys;
wait_for { @keys };

is_deeply( \@keys, [ [ key => "C-a" ] ], 'on_key Ctrl-A' );
