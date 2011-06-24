#!/usr/bin/perl

use strict;

use Test::More tests => 11;
use Test::HexString;

use Tickit::Term;

my $stream = "";
my $writer = bless [], "TestWriter";
sub TestWriter::write { $stream .= $_[1] }

my $term = Tickit::Term->new( writer => $writer );

sub stream_is
{
   my ( $expect, $name ) = @_;

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
