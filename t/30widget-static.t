#!/usr/bin/perl

use strict;

use Test::More tests => 18;
use Test::Refcount;
use IO::Async::Test;

use t::MockTerm;
use t::TestWindow;

use Tickit::Widget::Static;

my ( $term, $win ) = mk_term_and_window;

my $widget = Tickit::Widget::Static->new(
   text => "Your message here",
);

ok( defined $widget, 'defined $widget' );

is( $widget->text,  "Your message here", '$widget->text' );
is( $widget->align, 0,                   '$widget->align' );

is( $widget->lines, 1, '$widget->lines' );
is( $widget->cols, 17, '$widget->cols' );

$widget->set_text( "Another message" );

is( $widget->text, "Another message", '$widget->set_text modifies text' );
is( $widget->cols, 15, '$widget->cols after changed text' );

$widget->set_align( 0.2 );

is( $widget->align, 0.2, '$widget->set_align modifies alignment' );

$widget->set_align( 'centre' );

is( $widget->align, 0.5, '$widget->set_align converts symbolic names' );

$widget->set_align( 0.0 );
$widget->set_window( $win );

wait_for { $term->is_changed };

is_deeply( [ $term->methodlog ],
           [ SETPEN,
             CLEAR,
             GOTO(0,0),
             SETPEN,
             PRINT("Another message"),
             SETBG(undef),
             ERASECH(65) ],
           '$term written to' );

is_deeply( [ $term->get_display ],
           [ PAD("Another message"),
             BLANKS(24) ],
           '$term display' );

$widget->set_text( "Changed message" );

wait_for { $term->is_changed };

is_deeply( [ $term->methodlog ],
           [ SETPEN,
             CLEAR,
             GOTO(0,0),
             SETPEN,
             PRINT("Changed message"),
             SETBG(undef),
             ERASECH(65) ],
           '$term written again after changed text' );

is_deeply( [ $term->get_display ],
           [ PAD("Changed message"),
             BLANKS(24) ],
           '$term display after changed text' );

# Terminal is 80 columns wide. Text is 15 characters long. Therefore, right-
# aligned it would start in the 65th column

$widget->set_align( 1.0 );

wait_for { $term->is_changed };

is_deeply( [ $term->methodlog ],
           [ SETPEN,
             CLEAR,
             GOTO(0,0),
             SETBG(undef),
             ERASECH(65,1),
             SETPEN,
             PRINT("Changed message"), ],
           '$term written in correct location' );

is_deeply( [ $term->get_display ],
           [ PAD((" " x 65) . "Changed message"),
             BLANKS(24) ],
           '$term display in correct location' );

$term->resize( 30, 100 );

wait_for { $term->is_changed };

is_deeply( [ $term->methodlog ],
           [ SETPEN,
             CLEAR,
             GOTO(0,0),
             SETBG(undef),
             ERASECH(85,1),
             SETPEN,
             PRINT("Changed message"),
           ],
           '$term redrawn after resize' );

is_deeply( [ $term->get_display ],
           [ PAD((" " x 85) . "Changed message"),
             BLANKS(29) ],
           '$term display in correct location' );

$widget->chpen( bg => 4 );

wait_for { $term->is_changed };

is_deeply( [ $term->methodlog ],
           [ SETPEN(bg => 4),
             CLEAR,
             GOTO(0,0),
             SETBG(4),
             ERASECH(85,1),
             SETPEN(bg => 4),
             PRINT("Changed message"),
           ],
           '$term redrawn after setpen bg' );
