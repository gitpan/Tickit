#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use t::TestWindow qw( $win @methods );

use Tickit::RenderBuffer;

use Tickit::Pen;
use Tickit::Rect;

my $rb = Tickit::RenderBuffer->new(
   lines => 10,
   cols  => 20,
);

# Clipping to edge
{
   my $pen = Tickit::Pen->new;

   $rb->text_at( -1, 5, "TTTTTTTTTT", $pen );
   $rb->text_at( 11, 5, "BBBBBBBBBB", $pen );
   $rb->text_at( 4, -3, "[LLLLLLLL]", $pen );
   $rb->text_at( 5, 15, "[RRRRRRRR]", $pen );

   $rb->flush_to_window( $win );
   is_deeply( \@methods,
              [
                 [ goto => 4, 0 ],
                 [ print => "LLLLLL]", {} ],
                 [ goto => 5, 15 ],
                 [ print => "[RRRR", {} ],
              ],
              'RC text rendering with clipping' );
   undef @methods;

   $rb->erase_at( -1, 5, 10, Tickit::Pen->new( fg => 1 ) );
   $rb->erase_at( 11, 5, 10, Tickit::Pen->new( fg => 2 ) );
   $rb->erase_at( 4, -3, 10, Tickit::Pen->new( fg => 3 ) );
   $rb->erase_at( 5, 15, 10, Tickit::Pen->new( fg => 4 ) );

   $rb->flush_to_window( $win );
   is_deeply( \@methods,
              [
                 [ goto => 4, 0 ],
                 [ erasech => 7, undef, { fg => 3 } ],
                 [ goto => 5, 15 ],
                 [ erasech => 5, undef, { fg => 4 } ],
              ],
              'RC text rendering with clipping' );
   undef @methods;

   $rb->goto( 2, 18 );
   $rb->text( $_, $pen ) for qw( A B C D E );

   $rb->flush_to_window( $win );
   is_deeply( \@methods,
              [
                 [ goto => 2, 18 ],
                 [ print => "A", {} ],
                 [ print => "B", {} ],
              ],
              'RC text at VC with clipping' );
   undef @methods;
}

# Clipping to rect
{
   my $pen = Tickit::Pen->new;

   $rb->clip( Tickit::Rect->new(
         top => 2,
         left => 2,
         bottom => 8,
         right => 18
   ) );

   $rb->text_at( 1, 5, "TTTTTTTTTT", $pen );
   $rb->text_at( 9, 5, "BBBBBBBBBB", $pen );
   $rb->text_at( 4, -3, "[LLLLLLLL]", $pen );
   $rb->text_at( 5, 15, "[RRRRRRRR]", $pen );

   $rb->flush_to_window( $win );
   is_deeply( \@methods,
              [
                 [ goto => 4, 2 ],
                 [ print => "LLLL]", {} ],
                 [ goto => 5, 15 ],
                 [ print => "[RR", {} ],
              ],
              'RC text rendering with clipping' );
   undef @methods;

   $rb->clip( Tickit::Rect->new(
         top => 2,
         left => 2,
         bottom => 8,
         right => 18
   ) );

   $rb->erase_at( 1, 5, 10, Tickit::Pen->new( fg => 1 ) );
   $rb->erase_at( 9, 5, 10, Tickit::Pen->new( fg => 2 ) );
   $rb->erase_at( 4, -3, 10, Tickit::Pen->new( fg => 3 ) );
   $rb->erase_at( 5, 15, 10, Tickit::Pen->new( fg => 4 ) );

   $rb->flush_to_window( $win );
   is_deeply( \@methods,
              [
                 [ goto => 4, 2 ],
                 [ erasech => 5, undef, { fg => 3 } ],
                 [ goto => 5, 15 ],
                 [ erasech => 3, undef, { fg => 4 } ],
              ],
              'RC text rendering with clipping' );
   undef @methods;
}

# clipping with translation
{
   $rb->translate( 3, 5 );

   $rb->clip( Tickit::Rect->new(
         top   => 2,
         left  => 2,
         lines => 3,
         cols  => 5
   ) );

   $rb->text_at( $_, 0, "$_"x10, Tickit::Pen->new ) for 0 .. 8;

   $rb->flush_to_window( $win );
   is_deeply( \@methods,
              [
                 [ goto => 5, 7 ],
                 [ print => "22222", {} ],
                 [ goto => 6, 7 ],
                 [ print => "33333", {} ],
                 [ goto => 7, 7 ],
                 [ print => "44444", {} ],
              ],
              'RC clipping rectangle translated' );
   undef @methods;
}

done_testing;
