#!/usr/bin/perl

use strict;

use Test::More tests => 9;
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

$win->focus( 0, 0 );

flush_tickit;

is_termlog( [ GOTO(3,10), ],
            'Termlog initially' );

ok( $term->{cursorvis}, 'Cursor is visible after window focus' );

$win->reposition( 5, 15 );

flush_tickit;

is_termlog( [ GOTO(5,15), ],
            'Termlog after window reposition' );

is_oneref( $win, '$win has refcount 1 at EOF' );
is_refcount( $rootwin, 3, '$rootwin has refcount 3 at EOF' );
