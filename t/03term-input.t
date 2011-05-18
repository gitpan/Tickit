#!/usr/bin/perl

use strict;

use Test::More tests => 6;
use Test::HexString;
use IO::Async::Test;

use IO::Async::Loop;

use Tickit::Term;

# TODO: Either Tickit or IO::Async itself should do this
$SIG{PIPE} = "IGNORE";

my $loop = IO::Async::Loop->new();
testing_loop( $loop );

my ( $rd, $wr ) = $loop->pipepair or die "Cannot pipe() - $!";

my @key_events;
my @mouse_events;

my $term = Tickit::Term->new(
   term_in => $rd,
   on_key  => sub {
      my ( $self, $type, $str, $key ) = @_;
      push @key_events, [ $type => $str ];
      isa_ok( $key, "Term::TermKey::Key", '$key' );
   },
   on_mouse => sub {
      my ( $self, $ev, $button, $line, $col ) = @_;
      push @mouse_events, [ $ev => $button, $line, $col ];
   },
);

isa_ok( $term, "Tickit::Term", '$term isa Tickit::Term' );

$loop->add( $term );

$wr->syswrite( "h" );

undef @key_events;
wait_for { @key_events };

is_deeply( \@key_events, [ [ text => "h" ] ], 'on_key h' );

$wr->syswrite( "\cA" );

undef @key_events;
wait_for { @key_events };

is_deeply( \@key_events, [ [ key => "C-a" ] ], 'on_key Ctrl-A' );

# Mouse encoding == CSI M $b $x $y
# where $b, $l, $c are encoded as chr(32+$). Position is 1-based
$wr->syswrite( "\e[M".chr(32+0).chr(32+21).chr(32+11) );

undef @mouse_events;
wait_for { @mouse_events };

# Tickit::Term reports position 0-based
is_deeply( \@mouse_events, [ [ press => 1, 10, 20 ] ], 'on_mouse press(1) @20,10' );
