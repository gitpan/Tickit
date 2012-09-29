#!/usr/bin/perl

use strict;

use Test::More tests => 45;
use Test::Identity;
use Test::Refcount;

use Tickit::Test;

my ( $term, $win ) = mk_term_and_window;

isa_ok( $win, "Tickit::Window", '$win isa Tickit::Window' );

# Already 2 references; Tickit object keeps a permanent one, and we have one
# here. This is fine.
is_refcount( $win, 2, '$win has refcount 2 initially' );

my $geom_changed = 0;
$win->set_on_geom_changed( sub { $geom_changed++ } );

my $exposed_rect;
$win->set_on_expose( sub { shift; ( $exposed_rect ) = @_ } );

is( $win->top,  0, '$win->top is 0' );
is( $win->left, 0, '$win->left is 0' );

is( $win->abs_top,  0, '$win->abs_top is 0' );
is( $win->abs_left, 0, '$win->abs_left is 0' );

is( $win->lines, 25, '$win->lines is 25' );
is( $win->cols,  80, '$win->cols is 80' );

identical( $win->term, $term, '$win->term returns $term' );

isa_ok( $win->pen, "Tickit::Pen", '$win->pen isa Tickit::Pen' );

is_deeply( { $win->pen->getattrs },
           {},
           '$win->pen has no attrs set' );

is( $win->getpenattr( 'fg' ), undef, '$win has pen fg undef' );

is_deeply( { $win->get_effective_pen->getattrs },
           {},
           '$win->get_effective_pen has no attrs set' );

is( $win->get_effective_penattr( 'fg' ), undef, '$win has effective pen fg undef' );

$win->expose;

ok( !$exposed_rect, 'on_expose not yet invoked' );

flush_tickit;

is( $exposed_rect->top,    0, '$exposed_rect->top after exposure' );
is( $exposed_rect->left,   0, '$exposed_rect->left after exposure' );
is( $exposed_rect->lines, 25, '$exposed_rect->lines after exposure' );
is( $exposed_rect->cols,  80, '$exposed_rect->cols after exposure' );

$win->goto( 2, 3 );
my $len = $win->print( "Hello" );

is_termlog( [ GOTO(2,3),
              SETPEN,
              PRINT("Hello"), ],
            'Termlog initially' );

is_display( [ BLANKLINE,
              BLANKLINE,
              [BLANK(3), TEXT("Hello")], ],
            'Display initially' );

is( $len->bytes,      5, '->print()->bytes is 5' );
is( $len->codepoints, 5, '->print()->codepoints is 5' );
is( $len->graphemes,  5, '->print()->graphemes is 5' );
is( $len->columns,    5, '->print()->columns is 5' );

$win->pen->chattr( fg => 3 );

is_deeply( { $win->pen->getattrs },
           { fg => 3 },
           '$win->pen->getattrs has fg => 3' );

is( $win->getpenattr( 'fg' ), 3, '$win has pen fg 3' );

is_deeply( { $win->get_effective_pen->getattrs },
           { fg => 3 },
           '$win->get_effective_pen has fg => 3' );

is( $win->get_effective_penattr( 'fg' ), 3, '$win has effective pen fg 3' );

my $newpen = Tickit::Pen->new;
$newpen->chattr( fg => 3 );
$newpen->chattr( u => 1 );

$win->set_pen( $newpen );

is_deeply( { $win->pen->getattrs },
           { fg => 3, u => 1 },
           '$win->set_pen replaces window pen' );

$win->pen->chattr( u => undef );

$win->goto( 2, 3 );
$win->print( "Hello" );

is_termlog( [ GOTO(2,3),
              SETPEN(fg => 3),
              PRINT("Hello") ],
            'Termlog with correct pen' );

is_display( [ BLANKLINE,
              BLANKLINE,
              [BLANK(3), TEXT("Hello",fg => 3)], ],
            'Display with correct pen' );

$win->scroll( 1, 0 );

is_termlog( [ SETBG(undef),
              SCROLLRECT(0,0,25,80, 1,0) ],
            'Termlog scrolled' );

is_display( [ BLANKLINE,
              [BLANK(3), TEXT("Hello",fg => 3)], ],
            'Display scrolled' );

$win->scrollrect( 5,0,10,80, 3,0 );

is_termlog( [ SETBG(undef),
              SCROLLRECT(5,0,10,80, 3,0) ],
            'Termlog after scrollrect' );

ok( !$win->scrollrect( 5,20,10,40, 3,0 ), '$win does not support partial line scrolling' );
drain_termlog;

$win->scrollrect( 20,0,1,80, 0,1 );

is_termlog( [ SETBG(undef),
              GOTO(20,0),
              INSERTCH(1) ],
            'Termlog after scrollrect ICH emulation' );

$win->scrollrect( 21,10,1,70, 0,-1 );

is_termlog( [ SETBG(undef),
              GOTO(21,10),
              DELETECH(1) ],
            'Termlog after scrollrect DCH emulation' );

$win->erasech( 15 );

is_termlog( [ SETBG(undef),
              ERASECH(15) ],
            'Termlog chars erased' );

$win->clear;

flush_tickit;

is_termlog( [ SETPEN(fg => 3),
              CLEAR ],
            'Termlog cleared' );

is( $geom_changed, 0, '$reshaped is 0 before term resize' );

resize_term( 30, 100 );

is( $win->lines, 30, '$win->lines is 30 after term resize' );
is( $win->cols, 100, '$win->cols is 100 after term resize' );

is( $geom_changed, 1, '$reshaped is 1 after term resize' );

is_refcount( $win, 2, '$win has refcount 2 before dropping Tickit' );
