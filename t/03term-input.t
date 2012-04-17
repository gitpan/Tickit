#!/usr/bin/perl

use strict;

use Test::More tests => 16;

use Tickit::Term;

use Time::HiRes qw( sleep );

my $term = Tickit::Term->new;
$term->set_size( 25, 80 );

my ( $type, $str );
$term->set_on_key( sub { ( undef, $type, $str ) = @_; } );

$term->input_push_bytes( "A" );

is( $type, "text", '$type after push_bytes A' );
is( $str,  "A",    '$str after push_bytes A' );

is( $term->check_timeout, undef, '$term has no timeout after A' );

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
