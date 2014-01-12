#!/usr/bin/perl

use strict;
use warnings;

use Test::More;

use Tickit::Test;

my ( $term, $rootwin ) = mk_term_and_window;

my $win = $rootwin->make_sub( 3, 10, 4, 20 );

my $root_exposed;
$rootwin->set_on_expose( with_rb => sub { $root_exposed++ } );

# New RB+rect callback
{
   my $win_exposed;

   my $exposed_rb;
   my @exposed_rects;
   $win->set_on_expose( with_rb => sub {
      ( undef, $exposed_rb, my $rect ) = @_;
      push @exposed_rects, $rect;
      $win_exposed++;
   });

   $rootwin->expose;

   ok( !$win_exposed, 'on_expose not yet invoked' );

   flush_tickit;

   is( $root_exposed, 1, '$root expose count 1 after $rootwin->expose' );
   is( $win_exposed,  1, '$win expose count 1 after $rootwin->expose' );

   isa_ok( $exposed_rb, "Tickit::RenderBuffer", '$exposed_rb' );

   is_deeply( \@exposed_rects,
      [ Tickit::Rect->new( top => 0, left => 0, lines => 4, cols => 20 ) ],
      'Exposed regions after $rootwin->expose'
   );

   undef @exposed_rects;

   $win->expose;

   flush_tickit;

   is( $root_exposed, 1, '$root expose count 1 after $win->expose' );
   is( $win_exposed, 2, '$win expose count 2 after $win->expose' );

   is_deeply( \@exposed_rects,
      [ Tickit::Rect->new( top => 0, left => 0, lines => 4, cols => 20 ) ],
      'Exposed regions after $win->expose'
   );

   undef @exposed_rects;

   $rootwin->expose;
   $win->expose;

   flush_tickit;

   is( $root_exposed, 2, '$root expose count 2 after root-then-win' );
   is( $win_exposed, 3, '$win expose count 3 after root-then-win' );

   $win->expose;
   $rootwin->expose;

   flush_tickit;

   is( $root_exposed, 3, '$root expose count 3 after win-then-root' );
   is( $win_exposed, 4, '$win expose count 4 after win-then-root' );

   $win->hide;

   flush_tickit;

   is( $root_exposed, 4, '$root expose count 4 after $win hide' );
   is( $win_exposed, 4, '$win expose count 5 after $win hide' );

   $win->show;

   flush_tickit;

   is( $root_exposed, 4, '$root expose count 4 after $win show' );
   is( $win_exposed, 5, '$win expose count 5 after $win show' );

   undef @exposed_rects;

   $win->expose( Tickit::Rect->new( top => 0, left => 0, lines => 1, cols => 20 ) );
   $win->expose( Tickit::Rect->new( top => 2, left => 0, lines => 1, cols => 20 ) );

   flush_tickit;

   is( $win_exposed, 7, '$win expose count 7 after expose two regions' );

   is_deeply( \@exposed_rects,
      [ Tickit::Rect->new( top => 0, left => 0, lines => 1, cols => 20 ),
        Tickit::Rect->new( top => 2, left => 0, lines => 1, cols => 20 ) ],
      'Exposed regions after expose two regions'
   );

   undef @exposed_rects;

   $rootwin->expose( Tickit::Rect->new( top => 0, left => 0, lines => 1, cols => 20 ) );
   $win->expose( Tickit::Rect->new( top => 0, left => 5, lines => 1, cols => 10 ) );

   flush_tickit;

   is( $win_exposed, 8, '$win expose count 8 after expose separate root+win' );

   is_deeply( \@exposed_rects,
      [ Tickit::Rect->new( top => 0, left => 5, lines => 1, cols => 10 ) ],
      'Exposed regions after expose separate root+win'
   );
}

# Legacy rect-only callback
{
   my $win_exposed;
   my @exposed_rects;
   $win->set_on_expose( with_rb => sub {
      push @exposed_rects, $_[2];
      $win_exposed++;
   });

   $rootwin->expose;

   ok( !$win_exposed, 'Legacy on_expose not yet invoked' );

   flush_tickit;

   is( $win_exposed,  1, '$win expose count 1 after $rootwin->expose' );

   is_deeply( \@exposed_rects,
      [ Tickit::Rect->new( top => 0, left => 0, lines => 4, cols => 20 ) ],
      'Exposed regions after $rootwin->expose'
   );
}

{
   my $subwin = $rootwin->make_sub( 2, 2, 20, 50 );

   my $exposed = 0;
   $subwin->set_on_expose( with_rb => sub { $exposed++ } );

   for ( 1 .. 100 ) {
      $subwin->expose( Tickit::Rect->new( top => 1, left => 1, lines => 3, cols => 20 ) );
      flush_tickit;
   }

   is( $exposed, 100, '$exposed 100 times' );
}

done_testing;
