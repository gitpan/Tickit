#!/usr/bin/perl

use strict;
use warnings;

use Tickit;

use Tickit::Widget::Static;

use Tickit::Widget::VBox;
use Tickit::Widget::Frame;

my $vbox = Tickit::Widget::VBox->new( spacing => 1 );

my $fg = 1;
foreach my $style ( qw( ascii single double thick solid_inside solid_outside ) ) {
   $vbox->add( my $frame = Tickit::Widget::Frame->new(
      style => $style,
      child => Tickit::Widget::Static->new( text => $style, align => 0.5 )
   ) );
   $frame->frame_pen->chattr( fg => $fg++ );
}

my $tickit = Tickit->new();

$tickit->set_root_widget( $vbox );

$tickit->run;
