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

my $pen = Tickit::Pen->new;

# position
{
   $rb->goto( 2, 2 );

   {
      $rb->save;

      $rb->goto( 4, 4 );

      is( $rb->line, 4, '$rb->line before restore' );
      is( $rb->col,  4, '$rb->col before restore' );

      $rb->restore;
   }

   is( $rb->line, 2, '$rb->line after restore' );
   is( $rb->col,  2, '$rb->col after restore' );

   $rb->text( "some text", $pen );

   $rb->flush_to_window( $win );

   is_deeply( \@methods,
              [
                 [ goto => 2, 2 ],
                 [ print => "some text", {} ],
              ],
              'Stack saves/restores virtual cursor position' );
   undef @methods;
}

# clipping
{
   $rb->text_at( 0, 0, "0000000000", $pen );

   {
      $rb->save;
      $rb->clip( Tickit::Rect->new( top => 0, left => 2, lines => 10, cols => 16 ) );

      $rb->text_at( 1, 0, "1111111111", $pen );

      $rb->restore;
   }

   $rb->text_at( 2, 0, "2222222222", $pen );

   $rb->flush_to_window( $win );

   is_deeply( \@methods,
              [
                 [ goto => 0, 0 ],
                 [ print => "0000000000", {} ],
                 [ goto => 1, 2 ],
                 [ print => "11111111", {} ],
                 [ goto => 2, 0 ],
                 [ print => "2222222222", {} ],
              ],
              'Stack saves/restores clipping region' );
   undef @methods;
}

# pen
{
   $rb->save;
   {
      $rb->goto( 3, 0 );

      $rb->setpen( Tickit::Pen->new( bg => 1 ) );
      $rb->text( "123" );

      {
         $rb->savepen;

         $rb->setpen( Tickit::Pen->new( fg => 4 ) );
         $rb->text( "456" );

         $rb->restore;
      }

      $rb->text( "789" );
   }
   $rb->restore;

   $rb->flush_to_window( $win );

   is_deeply( \@methods,
              [
                 [ goto => 3, 0 ],
                 [ print => "123", { bg => 1 } ],
                 [ print => "456", { bg => 1, fg => 4 } ],
                 [ print => "789", { bg => 1 } ],
              ],
              'Stack saves/restores render pen' );
   undef @methods;
}

# translation
{
   $rb->text_at( 0, 0, "A", $pen );

   $rb->save;
   {
      $rb->translate( 2, 2 );

      $rb->text_at( 1, 1, "B", $pen );
   }
   $rb->restore;

   $rb->text_at( 2, 2, "C", $pen );

   $rb->flush_to_window( $win );

   is_deeply( \@methods,
              [
                 [ goto => 0, 0 ],
                 [ print => "A", {} ],
                 [ goto => 2, 2 ],
                 [ print => "C", {} ],
                 [ goto => 3, 3 ],
                 [ print => "B", {} ],
              ],
              'Stack saves/restores translation offset' );
   undef @methods;
}

done_testing;
