#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use Test::Refcount;

use Tickit::Test;

my ( $term, $rootwin ) = mk_term_and_window;

# Already 2 references; Tickit object keeps a permanent one, and we have one
# here. This is fine.
is_refcount( $rootwin, 2, '$rootwin has refcount 2 initially' );

ok( !$term->{cursorvis}, 'Cursor not yet visible initially' );

my $win = $rootwin->make_sub( 3, 10, 4, 20 );

is_oneref( $win, '$win has refcount 1 initially' );
is_refcount( $rootwin, 3, '$rootwin has refcount 3 after ->make_sub' );

my $focused;
$win->set_on_focus( sub {
   $focused = $_[1] ? "in" : "out";
} );

ok( !$win->is_focused, '$win->is_focused initially false' );
is( $focused, undef, '$focused not yet defined' );

$win->focus( 0, 0 );

ok( $win->is_focused, '$win->is_focused true after ->focus' );
is( $focused, "in", '$focused is "in" after ->focus' );

flush_tickit;

is_termlog( [ GOTO(3,10), ],
            'Termlog initially' );

ok( $term->{cursorvis}, 'Cursor is visible after window focus' );

$win->reposition( 5, 15 );

flush_tickit;

is_termlog( [ GOTO(5,15), ],
            'Termlog after window reposition' );

$win->hide;
flush_tickit;

ok( !$term->{cursorvis}, 'Cursor is invisible after focus window hide' );

is_termlog( [ ],
            'Termlog empty after focus window hide' );

$win->show;
flush_tickit;

ok( $term->{cursorvis}, 'Cursor is visible after focus window show' );

is_termlog( [ GOTO(5,15), ],
            'Termlog after focus window show' );

is_oneref( $win, '$win has refcount 1 at EOF' );
is_refcount( $rootwin, 3, '$rootwin has refcount 3 at EOF' );

my $otherwin = $rootwin->make_sub( 10, 5, 2, 2 );
$otherwin->focus( 0, 0 );

ok( !$win->is_focused, '$win->is_focused false after ->focus on other window' );
is( $focused, "out", '$focused is "out" after ->focus on other window' );

done_testing;
