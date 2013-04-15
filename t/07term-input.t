#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use Test::Identity;

use Tickit::Term;

use Time::HiRes qw( sleep );

my $term = Tickit::Term->new( UTF8 => 1 );
$term->set_size( 25, 80 );

is( $term->get_input_handle, undef, '$term->get_input_handle undef' );

my ( $type, $str );
$term->bind_event( key => sub {
   my ( $term, $ev, $args ) = @_;
   identical( $_[0], $term, '$_[0] is term for resize event' );
   is( $ev, "key", '$ev is key' );
   $type = $args->{type};
   $str  = $args->{str};
} );

$term->input_push_bytes( "A" );

is( $type, "text", '$type after push_bytes A' );
is( $str,  "A",    '$str after push_bytes A' );

is( $term->check_timeout, undef, '$term has no timeout after A' );

# We'll test with a Unicode character outside of Latin-1, to ensure it
# roundtrips correctly
#
# 'ĉ' [U+0109] - LATIN SMALL LETTER C WITH CIRCUMFLEX
#  UTF-8: 0xc4 0x89

undef $type; undef $str;
$term->input_push_bytes( "\xc4\x89" );

is( $type, "text",    '$type after push_bytes for UTF-8' );
is( $str,  "\x{109}", '$str after push_bytes for UTF-8' );

$term->input_push_bytes( "\e[A" );

is( $type, "key", '$type after push_bytes Up' );
is( $str,  "Up",  '$str after push_bytes Up' );

is( $term->check_timeout, undef, '$term has no timeout after Up' );

undef $type; undef $str;
$term->input_push_bytes( "\e[" );

is( $type, undef, '$type undef after partial Down' );
ok( defined $term->check_timeout, '$term has timeout after partial Down' );

$term->input_push_bytes( "B" );

is( $type, "key",  '$type after push_bytes after completed Down' );
is( $str,  "Down", '$str after push_bytes after completed Down' );

is( $term->check_timeout, undef, '$term has no timeout after completed Down' );

undef $type; undef $str;
$term->input_push_bytes( "\e" );

is( $type, undef, '$type undef after partial Escape' );

my $timeout = $term->check_timeout;
ok( $timeout, '$term has timeout after partial Escape' );

sleep $timeout + 0.01; # account for timing overlaps

is( $term->check_timeout, undef, '$term has no timeout after timedout' );

is( $type, "key",    '$type after push_bytes after timedout' );
is( $str,  "Escape", '$str after push_bytes after timedout' );

# Legacy event handling
{
   my ( $type, $str );
   $term->set_on_key( sub { ( undef, $type, $str ) = @_; } );

   $term->input_push_bytes( "A" );
}

{
   pipe( my $rd, my $wr ) or die "pipe() - $!";

   my $term = Tickit::Term->new( input_handle => $rd );

   isa_ok( $term, "Tickit::Term", '$term isa Tickit::Term' );
   is( $term->get_input_handle, $rd, '$term->get_input_handle is $rd' );
}

done_testing;
