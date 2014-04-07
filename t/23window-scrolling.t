#!/usr/bin/perl

use strict;
use warnings;

use Test::More;

use Tickit::Test;

my $rootwin = mk_window;

{
   my $win = $rootwin->make_sub( 3, 10, 4, 30 );

   ok( !$win->scroll( 1, 0 ), '$win does not support scrolling' );
   drain_termlog;

   $win->close; undef $win;
   flush_tickit;
}

# Scrollable window probably needs to be fullwidth
my $win = $rootwin->make_sub( 5, 0, 10, 80 );

my @exposed_rects;
$win->set_on_expose( with_rb => sub { push @exposed_rects, $_[2] } );

# scroll down
{
   ok( $win->scroll( 1, 0 ), 'Fullwidth $win supports vertical scrolling' );
   flush_tickit;

   is_termlog( [ SETPEN,
                 SCROLLRECT(5,0,10,80,1,0) ],
               'Termlog after fullwidth $win->scroll downward' );

   is_deeply( \@exposed_rects,
              [ Tickit::Rect->new( top => 9, lines => 1, left => 0, cols => 80 ) ],
              'Exposed area after ->scroll downward' );

   undef @exposed_rects;
}

# scroll up
{
   $win->scroll( -1, 0 );
   flush_tickit;

   is_termlog( [ SETPEN,
                 SCROLLRECT(5,0,10,80,-1,0) ],
               'Termlog after fullwidth $win->scroll upward' );

   is_deeply( \@exposed_rects,
              [ Tickit::Rect->new( top => 0, lines => 1, left => 0, cols => 80 ) ],
              'Exposed area after ->scroll upward' );

   undef @exposed_rects;
}

# scroll right
{
   ok( $win->scroll( 0, 1 ), 'Fullwidth $win supports horizontal scrolling' );
   flush_tickit;

   is_termlog( [ SETPEN,
                 # TODO: declare VSSM so we can get a single SCROLLRECT() call
                 ( map { GOTO($_,0), DELETECH(1) } 5 .. 14 ) ],
               'Termlog after fullwidth $win->scroll rightward' );

   is_deeply( \@exposed_rects,
              [ Tickit::Rect->new( top => 0, lines => 10, left => 79, cols => 1 ) ],
              'Exposed area after ->scroll rightward' );

   undef @exposed_rects;
}

# scroll left
{
   $win->scroll( 0, -1 );
   flush_tickit;

   is_termlog( [ SETPEN,
                 # TODO: declare VSSM so we can get a single SCROLLRECT() call
                 ( map { GOTO($_,0), INSERTCH(1) } 5 .. 14 ) ],
               'Termlog after fullwidth $win->scroll leftward' );

   is_deeply( \@exposed_rects,
              [ Tickit::Rect->new( top => 0, lines => 10, left => 0, cols => 1 ) ],
              'Exposed area after ->scroll leftward' );

   undef @exposed_rects;
}

# scrollrect up
{
   ok( $win->scrollrect( Tickit::Rect->new( top => 2, left => 0, lines => 3, cols => 80 ),
                         -1, 0 ),
       'Fullwidth $win supports scrolling a region' );
   flush_tickit;

   is_termlog( [ SETPEN,
                 SCROLLRECT(7,0,3,80,-1,0) ],
               'Termlog after fullwidth $win->scrollrect downward' );

   is_deeply( \@exposed_rects,
              [ Tickit::Rect->new( top => 2, lines => 1, left => 0, cols => 80 ) ],
              'Exposed area after ->scroll downward' );

   undef @exposed_rects;
}

# scrollrect down
{
   $win->scrollrect( Tickit::Rect->new( top => 2, left => 0, lines => 3, cols => 80 ),
                     1, 0 );
   flush_tickit;

   is_termlog( [ SETPEN,
                 SCROLLRECT(7,0,3,80,1,0) ],
               'Termlog after fullwidth $win->scrollrect upward' );

   is_deeply( \@exposed_rects,
              [ Tickit::Rect->new( top => 4, lines => 1, left => 0, cols => 80 ) ],
              'Exposed area after ->scroll upward' );

   undef @exposed_rects;
}

# scrollrect further than area just exposes
{
   $win->scrollrect( Tickit::Rect->new( top => 2, left => 0, lines => 3, cols => 80 ),
                     5, 0 );
   flush_tickit;

   is_termlog( [],
               'Termlog empty after scrollrect further than area' );

   is_deeply( \@exposed_rects,
              [ Tickit::Rect->new( top => 2, left => 0, lines => 3, cols => 80 ) ],
              'Exposed area after ->scrollrect further than area' );

   undef @exposed_rects;
}

# scroll_with_children up
{
   my $child = $win->make_sub( 0, 70, 1, 10 );

   $win->scroll_with_children( -2, 0 );
   flush_tickit;

   is_termlog( [ SETPEN,
                 SCROLLRECT(5,0,10,80, -2,0) ],
               'Termlog after ->scroll_with_children' );

   is_deeply( \@exposed_rects,
              [ Tickit::Rect->new( top => 0, left => 0, lines => 2, cols => 80 ) ],
              'Exposed area after ->scroll_with_children' );

   $child->close;
   flush_tickit;
   undef @exposed_rects;
}

# Sibling to obscure part of it
{
   my $sibling = $rootwin->make_sub( 0, 0, 10, 20 );
   flush_tickit;

   $sibling->raise;
   flush_tickit;
   undef @exposed_rects;

   $win->scroll_with_children( -2, 0 );
   flush_tickit;

   is_termlog( [ SETPEN,
                 SCROLLRECT(10,0,5,80, -2,0) ],
               'Termlog after ->scroll_with_children with sibling' );

   is_deeply( \@exposed_rects,
              [ Tickit::Rect->new( top => 0, left => 20, lines => 5, cols => 60 ),
                Tickit::Rect->new( top => 5, left =>  0, lines => 2, cols => 80 ) ],
              'Exposed area after ->scroll_with_children with sibling' );

   undef @exposed_rects;

   # Hiding the sibling makes it ignored
   $sibling->hide;
   flush_tickit;
   undef @exposed_rects;

   $win->scroll_with_children( -2, 0 );
   flush_tickit;

   is_termlog( [ SETPEN,
                 SCROLLRECT(5,0,10,80, -2,0) ],
               'Termlog after ->scroll_with_children with hidden sibling' );

   is_deeply( \@exposed_rects,
              [ Tickit::Rect->new( top => 0, left => 0, lines => 2, cols => 80 ) ],
              'Exposed area after ->scroll_with_children with hidden sibling' );

   $win->close;
   $sibling->close;
   flush_tickit;
}

# Hidden windows should be ignored
{
   $win->hide;
   flush_tickit;

   $win->scroll( 2, 0 );

   is_termlog( [],
               'Termlog empty after ->scroll on hidden window' );
}

done_testing;
