#!/usr/bin/perl

use strict;
use warnings;

use Tickit;

use Tickit::Widget::Static;

use Tickit::Widget::VBox;
use Tickit::Widget::HBox;

my $vbox = Tickit::Widget::VBox->new( spacing => 1 );

my $keydisplay;
$vbox->add( Tickit::Widget::Static->new( text => "Key:" ) );
$vbox->add( $keydisplay = Tickit::Widget::Static->new( text => "" ) );

my $mousedisplay;
$vbox->add( Tickit::Widget::Static->new( text => "Mouse:" ) );
$vbox->add( $mousedisplay = Tickit::Widget::Static->new( text => "" ) );

my $tickit = Tickit->new();

$tickit->set_root_widget( $vbox );

# Mass hackery
$tickit->term->set_on_key( sub {
   my ( undef, $type, $str ) = @_;
   $keydisplay->set_text( "$type $str" );
} );

$tickit->term->set_on_mouse( sub {
   my ( undef, $type, $button, $line, $col ) = @_;
   $mousedisplay->set_text( "$type button $button at ($line,$col)" );
} );

$tickit->run;
