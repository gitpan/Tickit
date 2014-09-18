#!/usr/bin/perl

use strict;
use warnings;

use Tickit;
use Tickit::Rect;
use List::Util qw( min max );

my $fillchar = "1";
sub fillwin
{
   my $win = shift;
   my ( $rb, $rect ) = @_;
   foreach my $line ( $rect->linerange ) {
      $rb->text_at( $line, $rect->left, $fillchar x $rect->cols );
   }
}

my $tickit = Tickit->new();

foreach ( 1 .. 9 ) {
   my $key = $_;
   $tickit->bind_key( $key => sub { $fillchar = $key } );
}

my $rootwin = $tickit->rootwin;

my @start;
$rootwin->set_on_mouse( sub {
   my ( $self, $ev ) = @_;
   @start = ( $ev->line, $ev->col ) and return if $ev->type eq "press";
   return unless $ev->type eq "release";

   my $top  = min( $start[0], $ev->line );
   my $left = min( $start[1], $ev->col );

   my $bottom = max( $start[0], $ev->line ) + 1;
   my $right  = max( $start[1], $ev->col )  + 1;

   $rootwin->expose( Tickit::Rect->new(
      top   => $top,
      left  => $left,
      bottom => $bottom,
      right  => $right,
   ) );
});

my $win = $rootwin->make_sub( 5, 10, 15, 60 );
$win->pen->chattr( fg => 1 );
$win->set_on_expose( \&fillwin );

my @subwins;

push @subwins, $win->make_sub( 0, 0, 4, 4 );
$subwins[-1]->pen->chattr( fg => 2 );
$subwins[-1]->set_on_expose( \&fillwin );

push @subwins, $win->make_sub( 6, 40, 2, 15 );
$subwins[-1]->pen->chattr( fg => 3 );
$subwins[-1]->set_on_expose( \&fillwin );

$tickit->later( sub {
      $rootwin->expose;
} );

$tickit->run;
