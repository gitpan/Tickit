#!/usr/bin/perl

use strict;

use Test::More tests => 17;
use Tickit::Test;

my $term = mk_term lines => 3, cols => 10;

is_termlog( [],
            'Termlog initially' );
is_display( [ "", "", "" ],
            'Display initially' );

$term->goto( 1, 5 );

is_termlog( [ GOTO(1,5) ],
            'Termlog after ->goto' );
is_cursorpos( 1, 5, 'Cursor position after ->goto' );

$term->print( "foo" );

is_termlog( [ PRINT("foo") ],
            'Termlog after ->print' );
is_display( [ "", "     foo", "" ],
            'Display after ->print' );
is_cursorpos( 1, 8, 'Cursor position after ->print' );

$term->clear;

is_termlog( [ CLEAR ],
            'Termlog after ->clear' );
is_display( [ "", "", "" ],
            'Display after ->clear' );

# Now some test content for scrolling
for my $l ( 0 .. 2 ) { $term->goto( $l, 0 ); $term->print( $l x 10 ) }
$term->methodlog; # flush log

is_display( [ "0000000000", "1111111111", "2222222222" ],
            'Display after scroll fill' );

$term->scroll( 0, 2, +1 );
is_display( [ "1111111111", "2222222222", "" ],
            'Display after scroll +1' );

$term->scroll( 0, 2, -1 );
is_display( [ "", "1111111111", "2222222222" ],
            'Display after scroll -1' );

for my $l ( 0 .. 2 ) { $term->goto( $l, 0 ); $term->print( $l x 10 ) }
$term->methodlog; # flush log

$term->scroll( 0, 1, +1 );
is_display( [ "1111111111", "", "2222222222" ],
            'Display after scroll partial +1' );

$term->scroll( 0, 1, -1 );
is_display( [ "", "1111111111", "2222222222" ],
            'Display after scroll partial -1' );

# Now some test content for mangling
for my $l ( 0 .. 2 ) { $term->goto( $l, 0 ); $term->print( "ABCDEFGHIJ" ) }
$term->methodlog; # flush log

$term->goto( 0, 3 );
$term->erasech( 5 );
is_display( [ "ABC     IJ", "ABCDEFGHIJ", "ABCDEFGHIJ" ],
            'Display after ->erasech' );

$term->goto( 1, 3 );
$term->deletech( 5 );
is_display( [ "ABC     IJ", "ABCIJ     ", "ABCDEFGHIJ" ],
            'Display after ->deletech' );

$term->goto( 2, 3 );
$term->insertch( 5 );
is_display( [ "ABC     IJ", "ABCIJ     ", "ABC     DE" ],
            'Display after ->insertch' );
