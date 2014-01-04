#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use Test::More;
use t::TestWindow qw( $win @methods );

use Tickit::RenderBuffer qw( LINE_SINGLE );

use Tickit::Pen;
use Tickit::Rect;

my $rb = Tickit::RenderBuffer->new(
   lines => 10,
   cols  => 20,
);

my $mask = Tickit::Rect->new(
   top   => 3,
   left  => 5,
   lines => 4,
   cols  => 6,
);

# mask over text
{
   $rb->save;

   $rb->mask( $mask );

                       #   MMMMMM
   $rb->text_at( 3, 2, "ABCDEFG" );      # before
   $rb->text_at( 4, 6,     "HI" );       # inside
   $rb->text_at( 5, 8,       "JKLMN" );  # after
   $rb->text_at( 6, 2, "OPQRSTUVWXYZ" ); # spanning

   $rb->restore;

   $rb->flush_to_window( $win );

   is_deeply( \@methods,
              [
                 [ goto => 3,  2 ], [ print => "ABC", {} ],
                 [ goto => 5, 11 ], [ print => "MN", {} ],
                 [ goto => 6,  2 ], [ print => "OPQ", {} ],
                    [ goto => 6, 11 ], [ print => "XYZ", {} ],
              ],
              '@methods for text over mask' );
   undef @methods;
}

# mask over erase
{
   $rb->save;

   $rb->mask( $mask );

   $rb->erase_at( 3, 2,  6 ); # before
   $rb->erase_at( 4, 6,  2 ); # inside
   $rb->erase_at( 5, 8,  5 ); # after
   $rb->erase_at( 6, 2, 12 ); # spanning

   $rb->restore;

   $rb->flush_to_window( $win );

   is_deeply( \@methods,
              [
                 [ goto => 3,  2 ], [ erasech => 3, undef, {} ],
                 [ goto => 5, 11 ], [ erasech => 2, undef, {} ],
                 [ goto => 6,  2 ], [ erasech => 3, undef, {} ],
                    [ goto => 6, 11 ], [ erasech => 3, undef, {} ],
              ],
              '@methods for erase over mask' );
   undef @methods;
}

# mask over lines
{
   $rb->save;

   $rb->mask( $mask );

   $rb->hline_at( 3, 2,  8, LINE_SINGLE );
   $rb->hline_at( 4, 6,  8, LINE_SINGLE );
   $rb->hline_at( 5, 8, 13, LINE_SINGLE );
   $rb->hline_at( 6, 2, 14, LINE_SINGLE );

   $rb->restore;

   $rb->flush_to_window( $win );

   is_deeply( \@methods,
              [
                 [ goto => 3,  2 ], [ print => "╶──", {} ],
                 [ goto => 5, 11 ], [ print => "──╴", {} ],
                 [ goto => 6,  2 ], [ print => "╶──", {} ],
                    [ goto => 6, 11 ], [ print => "───╴", {} ],
              ],
              '@methods for erase over mask' );
   undef @methods;
}

# restore removes masks
{
   {
      $rb->save;

      $rb->mask( $mask );
      $rb->text_at( 3, 0, "A"x20 );

      $rb->restore;
   }

   $rb->text_at( 4, 0, "B"x20 );

   $rb->flush_to_window( $win );

   is_deeply( \@methods,
              [
                 [ goto => 3,  0 ], [ print => "AAAAA", {} ],
                    [ goto => 3, 11 ], [ print => "AAAAAAAAA", {} ],
                 [ goto => 4,  0 ], [ print => "BBBBBBBBBBBBBBBBBBBB", {} ],
              ],
              '@methods for text_at after save/mask/remove' );
   undef @methods;
}

done_testing;
