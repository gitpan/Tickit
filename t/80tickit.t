#!/usr/bin/perl

use strict;

use Test::More tests => 7;
use Test::HexString;
use Test::Refcount;

use Tickit;

pipe my( $my_rd, $term_wr ) or die "Cannot pipepair - $!";

my $tickit = Tickit->new(
   UTF8     => 1,
   term_out => $term_wr,
);

isa_ok( $tickit, "Tickit", '$tickit' );
is_oneref( $tickit, '$tickit has refcount 1 initially' );

my $term = $tickit->term;

isa_ok( $term, "Tickit::Term", '$tickit->term' );

# For unit-test purposes force the size of the terminal to 80x24
$term->set_size( 24, 80 );

# There might be some terminal setup code here... Flush it
$my_rd->blocking( 0 );
sysread( $my_rd, my $buffer, 8192 );

sub stream_is
{
   my ( $expect, $name ) = @_;

   my $stream = "";
   do { 
      sysread( $my_rd, $stream, 8192, length $stream );
   } while length $stream < length $expect and $stream eq substr( $expect, 0, length $stream );

   is_hexstr( substr( $stream, 0, length $expect, "" ), $expect, $name );
}

$term->print( "Hello" );
$term->flush;
stream_is( "Hello", '$term->print' );

# We'll test with a Unicode character outside of Latin-1, to ensure it
# roundtrips correctly
#
# 'ĉ' [U+0109] - LATIN SMALL LETTER C WITH CIRCUMFLEX
#  UTF-8: 0xc4 0x89

$term->print( "\x{109}" );
$term->flush;
stream_is( "\xc4\x89", 'print outputs UTF-8' );

is_oneref( $tickit, '$tickit has refcount 1 at EOF' );

$tickit->set_root_widget( TestWidget->new );

$tickit->setup_term;

# Gut-wrenching
$tickit->_flush_later;
$term->flush;

# These strings are fragile but there's not much else we can do for an end-to-end
# test. If this unit test breaks likely these strings need updating. Sorry.
stream_is(
   "\e[?1049h\e[?25l\e[?1002h" .     # Terminal setup
   "\e[2J\e[m\e[2J\e[13;38HHello",   # Widget
   'root widget rendered'
);

package TestWidget;

use base qw( Tickit::Widget );

sub lines { 1 }
sub cols  { 5 }

sub render
{
   my $self = shift;
   my $win = $self->window or return;

   $win->goto( $win->lines / 2, ( $win->cols - 5 ) / 2 );
   $win->print( "Hello" );
}