#!/usr/bin/perl

use strict;

use Test::More tests => 11;

use Tickit::Test;

my ( $term, $rootwin ) = mk_term_and_window;

my $win = $rootwin->make_sub( 3, 10, 4, 20 );

my $root_exposed;
$rootwin->set_on_expose( sub { $root_exposed++ } );

my $win_exposed;
my %exposed_args;
$win->set_on_expose( sub { shift; %exposed_args = @_; $win_exposed++ } );

$rootwin->expose;

ok( !scalar keys %exposed_args, 'on_expose not yet invoked' );

flush_tickit;

is_deeply( \%exposed_args, 
           { top => 0, left => 0, lines => 4, cols => 20 },
           '%exposed_args after $rootwin->expose' );
is( $root_exposed, 1, '$root expose count 1 after $rootwin->expose' );
is( $win_exposed,  1, '$win expose count 1 after $rootwin->expose' );
undef %exposed_args;

$win->expose;

flush_tickit;

is_deeply( \%exposed_args, 
           { top => 0, left => 0, lines => 4, cols => 20 },
           '%exposed_args after $win->expose' );
is( $root_exposed, 1, '$root expose count 1 after $win->expose' );
is( $win_exposed, 2, '$win expose count 2 after $win->expose' );

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
