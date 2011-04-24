#!/usr/bin/perl

use strict;

use Test::More tests => 5;
use IO::Async::Test;

use t::MockTerm;
use t::TestTickit;

my ( $term, $rootwin ) = mk_term_and_window;

my $win = $rootwin->make_sub( 3, 10, 4, 20 );

$win->focus( 0, 0 );

my @keys;
$win->set_on_key( sub {
   push @keys, [ $_[1] => $_[2] ];
   return 1;
} );

$term->presskey( text => "A" );

is_deeply( \@keys, [ [ text => "A" ] ], 'on_key A' );

my $subwin = $win->make_sub( 2, 2, 1, 10 );

$subwin->focus( 0, 0 );

my @subkeys;
my $subret = 1;
$subwin->set_on_key( sub {
   push @subkeys, [ $_[1] => $_[2] ];
   return $subret;
} );

undef @keys;

$term->presskey( text => "B" );

is_deeply( \@subkeys, [ [ text => "B" ] ], 'on_key B on subwin' );
is_deeply( \@keys,    [ ],                 'on_key B on win' );

$subret = 0;

undef @keys;
undef @subkeys;

$term->presskey( text => "C" );

is_deeply( \@subkeys, [ [ text => "C" ] ], 'on_key C on subwin' );
is_deeply( \@keys,    [ [ text => "C" ] ], 'on_key C on win' );
