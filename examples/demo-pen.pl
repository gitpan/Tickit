#!/usr/bin/perl

use strict;
use warnings;

use IO::Async::Loop;

use Tickit;

use Tickit::Widget::Static;

use Tickit::Widget::VBox;
use Tickit::Widget::HBox;

my $vbox = Tickit::Widget::VBox->new( spacing => 1 );

my $hbox;

$vbox->add( $hbox = Tickit::Widget::HBox->new( spacing => 2 ) );
for (qw( red blue green yellow )) {
   $hbox->add( Tickit::Widget::Static->new( text => "fg $_", fg => $_ ) );
}

$vbox->add( $hbox = Tickit::Widget::HBox->new( spacing => 2 ) );
for (qw( red blue green yellow )) {
   $hbox->add( Tickit::Widget::Static->new( text => "bg $_", bg => $_ ) );
}

$vbox->add( Tickit::Widget::Static->new( text => "bold", b => 1 ) );

$vbox->add( Tickit::Widget::Static->new( text => "underline", u => 1 ) );

$vbox->add( Tickit::Widget::Static->new( text => "italic", i => 1 ) );

$vbox->add( Tickit::Widget::Static->new( text => "reverse video", rv => 1 ) );

$vbox->add( Tickit::Widget::Static->new( text => "alternate font", af => 1 ) );

my $loop = IO::Async::Loop->new;

my $tickit = Tickit->new();
$loop->add( $tickit );

$tickit->set_root_widget( $vbox );

$tickit->run;
