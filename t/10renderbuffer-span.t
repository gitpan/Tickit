#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use Tickit::Test;
use t::TestWindow qw( $win @methods );

use Tickit::RenderBuffer;

use Tickit::Pen;

my $term = mk_term;

my $rb = Tickit::RenderBuffer->new(
   lines => 10,
   cols  => 20,
);

isa_ok( $rb, "Tickit::RenderBuffer", '$rb isa Tickit::RenderContext' );

is( $rb->lines, 10, '$rb->lines' );
is( $rb->cols,  20, '$rb->cols' );

# Initially empty
{
   $rb->flush_to_window( $win );

   is_deeply( \@methods,
              [],
              'Empty RC renders nothing to window' );

   $rb->flush_to_term( $term );

   is_termlog( [],
               'Empty RC renders nothing to term' );
}

# Absolute spans
foreach my $op (qw( term win )) {
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

   if( $op eq "term" ) {
      $rb->flush_to_term( $term );

      is_termlog( [ GOTO(0,1), SETPEN(fg=>1), PRINT("text span"),
                    GOTO(1,1), SETPEN(fg=>1), ERASECH(5,undef),
                    GOTO(2,1), SETPEN(bg=>2), PRINT("another span"),
                    GOTO(3,1), SETPEN(bg=>2), ERASECH(10,undef),
                    GOTO(4,1), SETPEN(fg=>1,bg=>2), PRINT("third span"),
                    GOTO(5,1), SETPEN(fg=>1,bg=>2), ERASECH(7,undef) ],
                  'RC renders text to terminal' );
   }
   if( $op eq "win" ) {
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
                 'RC renders text to window' );
      undef @methods;
   }

   # cheating
   $rb->setpen( undef );

   if( $op eq "term" ) {
      $rb->flush_to_term( $term );
      is_termlog( [], 'RC now empty after render to terminal' );
   }
   if( $op eq "win" ) {
      $rb->flush_to_window( $win );
      is_deeply( \@methods, [], 'RC now empty after render to window' );
      undef @methods;
   }
}

# Span splitting
{
   my $pen = Tickit::Pen->new;
   my $pen2 = Tickit::Pen->new( b => 1 );

   # aaaAAaaa
   $rb->text_at( 0, 0, "aaaaaaaa", $pen );
   $rb->text_at( 0, 3, "AA", $pen2 );

   # BBBBBBBB
   $rb->text_at( 1, 2, "bbbb", $pen );
   $rb->text_at( 1, 0, "BBBBBBBB", $pen2 );

   # cccCCCCC
   $rb->text_at( 2, 0, "cccccc", $pen );
   $rb->text_at( 2, 3, "CCCCC", $pen2 );

   # DDDDDddd
   $rb->text_at( 3, 2, "dddddd", $pen );
   $rb->text_at( 3, 0, "DDDDD", $pen2 );

   $rb->text_at( 4, 4, "", $pen ); # empty text should do nothing

   $rb->flush_to_window( $win );
   is_deeply( \@methods,
              [
                 [ goto => 0, 0 ], [ print => "aaa", {} ], [ print => "AA", { b => 1 } ], [ print => "aaa", {} ],
                 [ goto => 1, 0 ], [ print => "BBBBBBBB", { b => 1 } ],
                 [ goto => 2, 0 ], [ print => "ccc", {} ], [ print => "CCCCC", { b => 1 } ],
                 [ goto => 3, 0 ], [ print => "DDDDD", { b => 1 } ], [ print => "ddd", {} ],
              ],
              'RC spans can be split' );
   undef @methods;
}

{
   my $pen = Tickit::Pen->new;
   $rb->text_at( 0, 0, "abcdefghijkl", $pen );
   $rb->text_at( 0, $_, "-", $pen ) for 2, 4, 6, 8;

   $rb->flush_to_window( $win );
   is_deeply( \@methods,
              [
                 [ goto => 0, 0 ],
                 [ print => "ab", {} ],
                 [ print => "-", {} ], # c
                 [ print => "d", {} ],
                 [ print => "-", {} ], # e
                 [ print => "f", {} ],
                 [ print => "-", {} ], # g
                 [ print => "h", {} ],
                 [ print => "-", {} ], # i
                 [ print => "jkl", {} ],
              ],
              'RC renders overwritten text split chunks' );
   undef @methods;
}

# Absolute skipping
{
   my $pen = Tickit::Pen->new;
   $rb->text_at( 6, 1, "This will be skipped", $pen );
   $rb->skip_at( 6, 10, 4 );

   $rb->erase_at( 7, 5, 15, $pen );
   $rb->skip_at( 7, 10, 2 );

   $rb->flush_to_window( $win );
   is_deeply( \@methods,
              [
                 [ goto => 6, 1 ],
                 [ print => "This will", {} ],
                 [ goto => 6, 14 ],
                 [ print => "skippe", {} ],
                 [ goto => 7, 5 ],
                 [ erasech => 5, undef, {} ],
                 [ goto => 7, 12 ],
                 [ erasech => 8, undef, {} ],
              ],
              'RC skipping' );
   undef @methods;
}

# VC spans
{
   # Direct pen
   my $pen = Tickit::Pen->new( fg => 3 );
   $rb->goto( 0, 2 ); $rb->text( "text span", $pen );
   $rb->goto( 1, 2 ); $rb->erase( 5, $pen );

   # Stored pen
   $rb->setpen( Tickit::Pen->new( bg => 4 ) );
   $rb->goto( 2, 2 ); $rb->text( "another span" );
   $rb->goto( 3, 2 ); $rb->erase( 10 );

   # Combined pens
   $rb->goto( 4, 2 ); $rb->text( "third span", $pen );
   $rb->goto( 5, 2 ); $rb->erase( 7, $pen );

   $rb->flush_to_window( $win );

   is_deeply( \@methods,
              [
                 [ goto => 0, 2 ], [ print => "text span", { fg => 3 } ],
                 [ goto => 1, 2 ], [ erasech => 5, undef, { fg => 3 } ],
                 [ goto => 2, 2 ], [ print => "another span", { bg => 4 } ],
                 [ goto => 3, 2 ], [ erasech => 10, undef, { bg => 4 } ],
                 [ goto => 4, 2 ], [ print => "third span", { fg => 3, bg => 4 } ],
                 [ goto => 5, 2 ], [ erasech => 7, undef, { fg => 3, bg => 4 } ],
              ],
              'RC renders text' );
   undef @methods;

   # cheating
   $rb->setpen( undef );
}

# VC skipping
{
   my $pen = Tickit::Pen->new;
   $rb->goto( 8, 0 );
   $rb->text( "Some", $pen );
   $rb->skip( 2 );
   $rb->text( "more", $pen );
   $rb->skip_to( 14 );
   $rb->text( "14", $pen );

   $rb->flush_to_window( $win );
   is_deeply( \@methods,
              [
                 [ goto => 8, 0 ],
                 [ print => "Some", {} ],
                 [ goto => 8, 6 ],
                 [ print => "more", {} ],
                 [ goto => 8, 14 ],
                 [ print => "14", {} ],
              ],
              'RC skipping at virtual-cursor' );
   undef @methods;
}

# Translation
{
   $rb->translate( 3, 5 );

   $rb->text_at( 0, 0, "at 0,0", Tickit::Pen->new );

   $rb->goto( 1, 0 );
   $rb->text( "at 1,0", Tickit::Pen->new );

   $rb->flush_to_window( $win );
   is_deeply( \@methods,
              [
                 [ goto => 3, 5 ],
                 [ print => "at 0,0", {} ],
                 [ goto => 4, 5 ],
                 [ print => "at 1,0", {} ],
              ],
              'RC renders text with translation' );
   undef @methods;
}

# ->eraserect
{
   $rb->eraserect( Tickit::Rect->new( top => 2, left => 3, lines => 5, cols => 8 ) );

   $rb->flush_to_window( $win );
   is_deeply( \@methods,
              [
                ( map {
                   [ goto => $_, 3 ],
                   [ erasech => 8, undef, {} ] } 2 .. 6 )
              ],
              'RC renders eraserect' );
   undef @methods;
}

# Clear
{
   $rb->clear( Tickit::Pen->new( bg => 3 ) );

   $rb->flush_to_window( $win );
   is_deeply( \@methods,
              [
               ( map {
                 [ goto => $_, 0 ],
                 [ erasech => 20, undef, { bg => 3 } ] } 0 .. 9 )
              ],
              'RC renders clear' );
   undef @methods;
}

done_testing;
