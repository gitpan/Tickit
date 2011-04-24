#!/usr/bin/perl

use strict;

use Test::More tests => 23;

use t::MockTerm;
use t::TestTickit;

use Tickit::Widget::Static;

my ( $term, $win ) = mk_term_and_window;

my $static = Tickit::Widget::Static->new(
   text => "Your message here",
);

ok( defined $static, 'defined $static' );

is( $static->text,   "Your message here", '$static->text' );
is( $static->align,  0,                   '$static->align' );
is( $static->valign, 0,                   '$static->valign' );

is( $static->lines, 1, '$static->lines' );
is( $static->cols, 17, '$static->cols' );

$static->set_text( "Another message" );

is( $static->text, "Another message", '$static->set_text modifies text' );
is( $static->cols, 15, '$static->cols after changed text' );

$static->set_align( 0.2 );

is( $static->align, 0.2, '$static->set_align modifies alignment' );

$static->set_align( 'centre' );

is( $static->align, 0.5, '$static->set_align converts symbolic names' );

$static->set_valign( 0.3 );

is( $static->valign, 0.3, '$static->set_valign modifies vertical alignment' );

$static->set_valign( 'middle' );

is( $static->valign, 0.5, '$static->set_valign converts symbolic names' );

$static->set_align( 0.0 );
$static->set_valign( 0.0 );
$static->set_window( $win );

flush_tickit;

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

$static->set_text( "Changed message" );

flush_tickit;

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

$static->set_align( 1.0 );

flush_tickit;

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

# Terminal is 25 columns wide. Text is 1 line tall. Therefore, middle-
# valigned it would start on the 13th line

$static->set_valign( 0.5 );

flush_tickit;

is_deeply( [ $term->methodlog ],
           [ SETPEN,
             CLEAR,
             GOTO(12,0),
             SETBG(undef),
             ERASECH(65,1),
             SETPEN,
             PRINT("Changed message"), ],
           '$term written in correct location' );

is_deeply( [ $term->get_display ],
           [ BLANKS(12),
             PAD((" " x 65) . "Changed message"),
             BLANKS(12) ],
           '$term display in correct location' );

$static->set_valign( 0.0 );
$term->methodlog; # clear the log

$term->resize( 30, 100 );

flush_tickit;

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

$static->pen->chattr( bg => 4 );

flush_tickit;

is_deeply( [ $term->methodlog ],
           [ SETPEN(bg => 4),
             CLEAR,
             GOTO(0,0),
             SETBG(4),
             ERASECH(85,1),
             SETPEN(bg => 4),
             PRINT("Changed message"),
           ],
           '$term redrawn after chpen bg' );
