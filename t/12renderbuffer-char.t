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

my $pen = Tickit::Pen->new;

# Characters
foreach my $op (qw( term win )) {
   $rb->char_at( 5, 5, 0x41, $pen );
   $rb->char_at( 5, 6, 0x42, $pen );
   $rb->char_at( 5, 7, 0x43, $pen );

   if( $op eq "term" ) {
      $rb->flush_to_term( $term );
      is_termlog( [ GOTO(5,5),
                    SETPEN, PRINT("A"),
                    SETPEN, PRINT("B"),
                    SETPEN, PRINT("C") ],
                  'RC renders char_at to terminal' );
   }
   if( $op eq "win" ) {
      $rb->flush_to_window( $win );
      is_deeply( \@methods,
                 [
                    [ goto => 5, 5 ],
                    [ print => "A", {} ],
                    [ print => "B", {} ],
                    [ print => "C", {} ],
                 ],
                 'RC renders char_at to window' );
      undef @methods;
   }
}

# Characters setpen
{
   $rb->setpen( Tickit::Pen->new( fg => 6 ) );

   $rb->char_at( 5, 5, 0x44 );
   $rb->char_at( 5, 6, 0x45 );
   $rb->char_at( 5, 7, 0x46 );

   $rb->flush_to_window( $win );
   is_deeply( \@methods,
              [
                 [ goto => 5, 5 ],
                 [ print => "D", { fg => 6 } ],
                 [ print => "E", { fg => 6 } ],
                 [ print => "F", { fg => 6 } ],
              ],
              'RC renders char_at' );
   undef @methods;

   # cheating
   $rb->setpen( undef );
}

# Characters with translation
{
   $rb->translate( 3, 5 );

   $rb->char_at( 1, 1, 0x31, $pen );
   $rb->char_at( 1, 2, 0x32, $pen );

   $rb->flush_to_window( $win );
   is_deeply( \@methods,
              [
                 [ goto => 4, 6 ],
                 [ print => "1", {} ],
                 [ print => "2", {} ],
              ],
              'RC renders char_at with translation' );
   undef @methods;
}

done_testing;
