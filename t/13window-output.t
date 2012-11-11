#!/usr/bin/perl

use strict;

use Test::More tests => 43;

use Tickit::Test;

use Tickit::Pen;

my $rootwin = mk_window;

my $win = $rootwin->make_sub( 3, 10, 4, 30 );

$win->goto( 2, 3 );
$win->print( "Hello" );

is_termlog( [ GOTO(5,13),
              SETPEN,
              PRINT("Hello"), ],
            'Termlog' );

is_display( [ BLANKLINES(5),
              [BLANK(13), TEXT("Hello")] ],
            'Display' );
 
$win->pen->chattr( b => 1 );

is_deeply( { $win->pen->getattrs },
           { b => 1 },
           '$win->pen->getattrs has b => 1' );

is( $win->getpenattr( 'b' ), 1, '$win has pen b 1' );

is_deeply( { $win->get_effective_pen->getattrs },
           { b => 1 },
           '$win->get_effective_pen has b => 1' );

is( $win->get_effective_penattr( 'b' ), 1, '$win has effective pen b 1' );

$win->goto( 2, 3 );
$win->print( "Hello" );

is_termlog( [ GOTO(5,13),
              SETPEN(b => 1),
              PRINT("Hello"), ],
            'Termlog with correct pen' );

is_display( [ BLANKLINES(5),
              [BLANK(13), TEXT("Hello",b=>1)] ],
            'Display with correct pen' );

$win->print( "large", Tickit::Pen->new( fg => 'red' ) );

is_termlog( [ SETPEN(b => 1, fg => 1),
              PRINT("large"), ],
            'Termlog with passed pen' );

is_display( [ BLANKLINES(5),
              [BLANK(13), TEXT("Hello",b=>1), TEXT("large",fg=>1,b=>1)] ],
            'Display with passed pen' );

$win->print( "world", u => 1 );

is_termlog( [ SETPEN(b => 1, u => 1),
              PRINT("world"), ],
            'Termlog with pen attributes hash' );

is_display( [ BLANKLINES(5),
              [BLANK(13), TEXT("Hello",b=>1), TEXT("large",fg=>1,b=>1), TEXT("world",b=>1,u=>1)] ],
            'Display with pen attributes hash' );

$win->pen->chattr( bg => 4 );

$win->erasech( 4, 0 );

is_termlog( [ SETBG(4),
              ERASECH(4) ],
            'Termlog after erasech' );

is_display( [ BLANKLINES(5),
              [BLANK(13), TEXT("Hello",b=>1), TEXT("large",fg=>1,b=>1), TEXT("world",b=>1,u=>1), BLANK(4,bg=>4)] ],
            'Display after erasech' );

$win->erasech( 4, 0, Tickit::Pen->new( bg => 2 ) );

is_termlog( [ SETBG(2),
              ERASECH(4) ],
            'Termlog after erasech with passed pen' );

is_display( [ BLANKLINES(5),
              [BLANK(13), TEXT("Hello",b=>1), TEXT("large",fg=>1,b=>1), TEXT("world",b=>1,u=>1), BLANK(4,bg=>2)] ],
            'Display after erasech with passed pen' );

$win->erasech( 4, 0, bg => 6 );

is_termlog( [ SETBG(6),
              ERASECH(4) ],
            'Termlog after erasech with pen attributes hash' );

is_display( [ BLANKLINES(5),
              [BLANK(13), TEXT("Hello",b=>1), TEXT("large",fg=>1,b=>1), TEXT("world",b=>1,u=>1), BLANK(4,bg=>6)] ],
            'Display after erasech with pen attributes hash' );

$win->clearline( 0 );

is_termlog( [ GOTO(3,10), SETBG(4), ERASECH(30) ],
            'Termlog after $win->clearline' );

is_display( [ BLANKLINES(3),
              [BLANK(10), BLANK(30,bg=>4)],
              BLANKLINE,
              [BLANK(13), TEXT("Hello",b=>1), TEXT("large",fg=>1,b=>1), TEXT("world",b=>1,u=>1), BLANK(4,bg=>6)] ],
            'Display after $win->clearline' );

$win->clearrect( Tickit::Rect->new( top => 1, left => 4, lines => 2, cols => 10 ) );

is_termlog( [ GOTO(4,14), SETBG(4), ERASECH(10),
              GOTO(5,14), SETBG(4), ERASECH(10) ],
            'Termlog after $win->clearrect' );

is_display( [ BLANKLINES(3),
              [BLANK(10), BLANK(30,bg=>4)],
              [BLANK(14), BLANK(10,bg=>4)],
              [BLANK(13), TEXT("H",b=>1), BLANK(10,bg=>4), TEXT("orld",b=>1,u=>1), BLANK(4,bg=>6)] ],
            'Display after $win->clearrect' );

$win->clear;

is_termlog( [ GOTO(3,10), SETBG(4), ERASECH(30),
              GOTO(4,10), SETBG(4), ERASECH(30),
              GOTO(5,10), SETBG(4), ERASECH(30),
              GOTO(6,10), SETBG(4), ERASECH(30) ],
            'Termlog after $win->clear' );

is_display( [ BLANKLINES(3),
              ( [BLANK(10), BLANK(30,bg=>4)] ) x 4 ],
            'Display after $win->clear' );

ok( !$win->scroll( 1, 0 ), '$win does not support scrolling' );
drain_termlog;

{
   my $subwin = $win->make_sub( 2, 2, 1, 10 );

   is_deeply( [ $subwin->_get_span_visibility( 0, 0 ) ],
              [ 1, 10 ], '$subwin 0,0 visible for 10 columns' );
   is_deeply( [ $subwin->_get_span_visibility( 0, 7 ) ],
              [ 1, 3 ], '$subwin 0,7 visible for 3 columns' );

   $subwin->pen->chattr( fg => 3 );

   is_deeply( { $subwin->pen->getattrs },
              { fg => 3 },
              '$subwin has fg => 3' );

   is( $subwin->getpenattr( 'b' ),  undef, '$win has pen b undef' );
   is( $subwin->getpenattr( 'fg' ), 3,     '$win has pen fg 1' );

   is_deeply( { $subwin->get_effective_pen->getattrs },
              { b => 1, bg => 4, fg => 3 },
              '$subwin->get_effective_pen has all attrs' );

   is( $subwin->get_effective_penattr( 'b' ),  1, '$win has effective pen b 1' );
   is( $subwin->get_effective_penattr( 'fg' ), 3, '$win has effective pen fg 1' );

   $subwin->goto( 0, 0 );
   $subwin->print( "Foo" );

   is_termlog( [ GOTO(5,12),
                 SETPEN(fg => 3, bg => 4, b => 1),
                 PRINT("Foo"), ],
               'Termlog with correct pen' );

   is_display( [ BLANKLINES(3),
                 ( [BLANK(10), BLANK(30,bg=>4)] ) x 2,
                 ( [BLANK(10), BLANK(2,bg=>4), TEXT("Foo",fg=>3,bg=>4,b=>1), BLANK(25,bg=>4)] ) x 1,
                 ( [BLANK(10), BLANK(30,bg=>4)] ) x 1 ],
               'Display with correct pen' );
}

# Hidden windows
{
   $rootwin->clear;
   drain_termlog;

   my $win1 = $win;
   my $win2 = $rootwin->make_sub( 3, 10, 4, 30 );
   $win2->hide;

   ok(  $win1->is_visible, '$win1 is visible' );
   ok( !$win2->is_visible, '$win2 is hidden' );

   $win1->goto( 0, 0 );
   $win1->print( "Content from Window 1" );

   $win2->goto( 1, 0 );
   $win2->print( "Content from Window 2" );

   is_termlog( [ GOTO(3,10),
                 SETPEN(bg => 4, b => 1),
                 PRINT("Content from Window 1" ) ],
              'Termlog after print with $win2 hidden' );

   is_display( [ BLANKLINES(3),
                 [BLANK(10), TEXT("Content from Window 1",bg=>4,b=>1)] ],
              'Display after print with $win2 hidden' );

   $win1->hide;

   $rootwin->clear;
   drain_termlog;

   $win2->show;

   ok( !$win1->is_visible, '$win1 is now hidden' );
   ok(  $win2->is_visible, '$win2 is now visible' );

   $win1->goto( 0, 0 );
   $win1->print( "Content from Window 1" );

   $win2->goto( 1, 0 );
   $win2->print( "Content from Window 2" );

   is_termlog( [ GOTO(4,10),
                 SETPEN,
                 PRINT("Content from Window 2" ) ],
              'Termlog after print with $win1 hidden' );

   is_display( [ BLANKLINES(4),
                 [BLANK(10), TEXT("Content from Window 2")] ],
              'Display after print with $win1 hidden' );
}
