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
$tickit->term->bind_event( key => sub {
   my ( undef, $ev, $args ) = @_;
   my ( $type, $str ) = @{$args}{qw( type str )};
   $keydisplay->set_text( "$type $str" );
} );

$tickit->term->bind_event( mouse => sub {
   my ( undef, $ev, $args ) = @_;
   my ( $type, $button, $line, $col ) = @{$args}{qw( type button line col )};
   $mousedisplay->set_text( "$type button $button at ($line,$col)" );
} );

$tickit->run;
