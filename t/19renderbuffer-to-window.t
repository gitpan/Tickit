#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use Test::More;

use Tickit::RenderBuffer qw( LINE_SINGLE CAP_START CAP_END CAP_BOTH );

use Tickit::Pen;

my $rb = Tickit::RenderBuffer->new(
   lines => 30,
   cols  => 30,
);

my @methods;
{
   package TestWindow;

   use Tickit::Utils qw( string_count );
   use Tickit::StringPos;

   sub goto
   {
      shift;
      push @methods, [ goto => @_ ];
   }

   sub print
   {
      shift;
      push @methods, [ print => $_[0], { $_[1]->getattrs } ];
      string_count( $_[0], my $pos = Tickit::StringPos->zero );
      return $pos;
   }

   sub erasech
   {
      shift;
      push @methods, [ erasech => $_[0], $_[1], { $_[2]->getattrs } ];
      return Tickit::StringPos->limit_columns( $_[0] );
   }
}
my $win = bless [], "TestWindow";

# Initially empty
{
   $rb->flush_to_window( $win );

   is_deeply( \@methods,
              [],
              'Empty RenderBuffer renders nothing to window' );
}

# Absolute spans
{
   # Direct pen
   my $pen = Tickit::Pen->new( fg => 1 );
   $rb->text_at( 0, 1, "text span", $pen );
   $rb->erase_at( 1, 1, 5, $pen );

   # Stored pen
   $rb->setpen( Tickit::Pen->new( bg => 2 ) );
   $rb->text_at( 2, 1, "another span" );
   $rb->erase_at( 3, 1, 10 );

   # Combined pens
   $rb->text_at( 4, 1, "third span", $pen );
   $rb->erase_at( 5, 1, 7, $pen );

   $rb->flush_to_window( $win );

   is_deeply( \@methods,
              [
                 [ goto => 0, 1 ], [ print => "text span", { fg => 1 } ],
                 [ goto => 1, 1 ], [ erasech => 5, undef, { fg => 1 } ],
                 [ goto => 2, 1 ], [ print => "another span", { bg => 2 } ],
                 [ goto => 3, 1 ], [ erasech => 10, undef, { bg => 2 } ],
                 [ goto => 4, 1 ], [ print => "third span", { fg => 1, bg => 2 } ],
                 [ goto => 5, 1 ], [ erasech => 7, undef, { fg => 1, bg => 2 } ],
              ],
              'RenderBuffer renders text to window' );
   undef @methods;

   $rb->flush_to_window( $win );
   is_deeply( \@methods, [], 'RenderBuffer now empty after render to window' );
   undef @methods;
}

# Simple lines explicit pen
{
   my $pen = Tickit::Pen->new;

   $rb->hline_at( 10, 10, 20, LINE_SINGLE, $pen );
   $rb->hline_at( 11, 10, 20, LINE_SINGLE, $pen, CAP_START );
   $rb->hline_at( 12, 10, 20, LINE_SINGLE, $pen, CAP_END );
   $rb->hline_at( 13, 10, 20, LINE_SINGLE, $pen, CAP_BOTH );

   $rb->flush_to_window( $win );
   is_deeply( \@methods,
              [ [ goto => 10, 10 ], [ print => "╶" . ( "─" x 9 ) . "╴", {} ],
                [ goto => 11, 10 ], [ print => ( "─" x 10 ) . "╴", {} ],
                [ goto => 12, 10 ], [ print => "╶" . ( "─" x 10 ), {} ],
                [ goto => 13, 10 ], [ print => ( "─" x 11 ), {} ] ],
              'RenderBuffer renders hline_ats to window' );
   undef @methods;

   $rb->vline_at( 10, 20, 10, LINE_SINGLE, $pen );
   $rb->vline_at( 10, 20, 11, LINE_SINGLE, $pen, CAP_START );
   $rb->vline_at( 10, 20, 12, LINE_SINGLE, $pen, CAP_END );
   $rb->vline_at( 10, 20, 13, LINE_SINGLE, $pen, CAP_BOTH );

   $rb->flush_to_window( $win );
   is_deeply( \@methods,
              [ [ goto => 10, 10 ], [ print => "╷│╷│", {} ],
                ( map { [ goto => $_, 10 ], [ print => "││││", {} ] } 11 .. 19 ),
                [ goto => 20, 10 ], [ print => "╵╵││", {} ],
              ],
              'RenderBuffer renders vline_ats to window' );
   undef @methods;
}

# Characters
{
   my $pen = Tickit::Pen->new;

   $rb->char_at( 5, 5, 0x41, $pen );
   $rb->char_at( 5, 6, 0x42, $pen );
   $rb->char_at( 5, 7, 0x43, $pen );

   $rb->flush_to_window( $win );
   is_deeply( \@methods,
              [
                 [ goto => 5, 5 ],
                 [ print => "A", {} ],
                 [ print => "B", {} ],
                 [ print => "C", {} ],
              ],
              'RenderBuffer renders char_at to window' );
   undef @methods;
}

done_testing;
