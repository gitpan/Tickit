#!/usr/bin/perl

use strict;
use warnings;

use Test::More;

use Tickit::Test;

use Tickit::Rect;

my $win = mk_window;

# Test that the Window direct drawing methods all still work inside a legacy
# expose without RB event.

$win->set_on_expose( sub { # no with_rb
   my ( $win, $rect ) = @_;

   $win->goto( 0, 0 );
   $win->print( "Text on line 0" );

   $win->goto( 1, 0 );
   $win->erasech( 20, undef );

   $win->clearrect( Tickit::Rect->new( top => 2, left => 0, lines => 2, cols => 10 ) );
});

$win->expose;
flush_tickit;

is_termlog( [ GOTO(0,0),
              SETPEN,
              PRINT("Text on line 0"),
              GOTO(1,0),
              SETPEN,
              ERASECH(20,0),
              GOTO(2,0),
              SETPEN,
              ERASECH(10,0),
              GOTO(3,0),
              SETPEN,
              ERASECH(10,0) ],
            'Termlog after legacy direct drawing from within Window expose' );

done_testing;
