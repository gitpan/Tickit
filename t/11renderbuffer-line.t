#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use Test::More;
use Tickit::Test;
use t::TestWindow qw( $win @methods );

use Tickit::RenderBuffer qw( LINE_SINGLE CAP_START CAP_END CAP_BOTH );

use Tickit::Pen;

my $term = mk_term;

my $rb = Tickit::RenderBuffer->new(
   lines => 30,
   cols  => 30,
);

my $pen = Tickit::Pen->new;

# Simple lines explicit pen
foreach my $op (qw( term win )) {
   $rb->hline_at( 10, 10, 20, LINE_SINGLE, $pen );
   $rb->hline_at( 11, 10, 20, LINE_SINGLE, $pen, CAP_START );
   $rb->hline_at( 12, 10, 20, LINE_SINGLE, $pen, CAP_END );
   $rb->hline_at( 13, 10, 20, LINE_SINGLE, $pen, CAP_BOTH );

   if( $op eq "term" ) {
      $rb->flush_to_term( $term );
      is_termlog( [ GOTO(10,10), SETPEN, PRINT("╶".("─"x9)."╴"),
                    GOTO(11,10), SETPEN, PRINT(("─"x10)."╴"),
                    GOTO(12,10), SETPEN, PRINT("╶".("─"x10)),
                    GOTO(13,10), SETPEN, PRINT(("─"x11)) ],
                  'RC renders hline_ats to terminal' );
   }
   if( $op eq "win" ) {
      $rb->flush_to_window( $win );
      is_deeply( \@methods,
                 [ [ goto => 10, 10 ], [ print => "╶" . ( "─" x 9 ) . "╴", {} ],
                   [ goto => 11, 10 ], [ print => ( "─" x 10 ) . "╴", {} ],
                   [ goto => 12, 10 ], [ print => "╶" . ( "─" x 10 ), {} ],
                   [ goto => 13, 10 ], [ print => ( "─" x 11 ), {} ] ],
                 'RC renders hline_ats to window' );
      undef @methods;
   }

   $rb->vline_at( 10, 20, 10, LINE_SINGLE, $pen );
   $rb->vline_at( 10, 20, 11, LINE_SINGLE, $pen, CAP_START );
   $rb->vline_at( 10, 20, 12, LINE_SINGLE, $pen, CAP_END );
   $rb->vline_at( 10, 20, 13, LINE_SINGLE, $pen, CAP_BOTH );

   if( $op eq "term" ) {
      $rb->flush_to_term( $term );
      is_termlog( [ GOTO(10,10), SETPEN, PRINT("╷│╷│"),
                    ( map { GOTO($_,10), SETPEN, PRINT("││││") } 11 .. 19 ),
                    GOTO(20,10), SETPEN, PRINT("╵╵││") ],
                  'RC renders vline_ats to terminal' );
   }
   if( $op eq "win" ) {
      $rb->flush_to_window( $win );
      is_deeply( \@methods,
                 [ [ goto => 10, 10 ], [ print => "╷│╷│", {} ],
                   ( map { [ goto => $_, 10 ], [ print => "││││", {} ] } 11 .. 19 ),
                   [ goto => 20, 10 ], [ print => "╵╵││", {} ],
                 ],
                 'RC renders vline_ats to window' );
      undef @methods;
   }
}

# Lines setpen
{
   $rb->setpen( Tickit::Pen->new( bg => 3 ) );

   $rb->hline_at( 10, 5, 15, LINE_SINGLE );
   $rb->vline_at( 5, 15, 10, LINE_SINGLE );

   $rb->flush_to_window( $win );
   is_deeply( \@methods,
              [
                 [ goto => 5, 10 ], [ print => "╷", { bg => 3 } ],
               ( map {
                 [ goto => $_, 10 ], [ print => "│", { bg => 3 } ] } 6 .. 9 ),
                 [ goto => 10,  5 ], [ print => "╶────┼────╴", { bg => 3 } ],
               ( map {
                 [ goto => $_, 10 ], [ print => "│", { bg => 3 } ] } 11 .. 14 ),
                 [ goto => 15, 10 ], [ print => "╵", { bg => 3 } ],
              ],
              'RC renders lines with stored pen' );
   undef @methods;

   # cheating
   $rb->setpen( undef );
}

# Line merging
{
   $rb->hline_at( 10, 10, 14, LINE_SINGLE, $pen );
   $rb->hline_at( 12, 10, 14, LINE_SINGLE, $pen );
   $rb->hline_at( 14, 10, 14, LINE_SINGLE, $pen );
   $rb->vline_at( 10, 14, 10, LINE_SINGLE, $pen );
   $rb->vline_at( 10, 14, 12, LINE_SINGLE, $pen );
   $rb->vline_at( 10, 14, 14, LINE_SINGLE, $pen );

   $rb->flush_to_window( $win );
   is_deeply( \@methods,
              [
                 [ goto => 10, 10 ],
                 [ print => "┌─┬─┐", {} ],
                 [ goto => 11, 10 ],
                 [ print => "│", {} ],
                 [ goto => 11, 12 ],
                 [ print => "│", {} ],
                 [ goto => 11, 14 ],
                 [ print => "│", {} ],
                 [ goto => 12, 10 ],
                 [ print => "├─┼─┤", {} ],
                 [ goto => 13, 10 ],
                 [ print => "│", {} ],
                 [ goto => 13, 12 ],
                 [ print => "│", {} ],
                 [ goto => 13, 14 ],
                 [ print => "│", {} ],
                 [ goto => 14, 10 ],
                 [ print => "└─┴─┘", {} ],
              ],
              'RC renders line merging' );
   undef @methods;
}

done_testing;
