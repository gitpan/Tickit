#!/usr/bin/perl

use strict;
use warnings;

use Tickit;

use Tickit::Widget::Static;

use Tickit::Widget::VBox;
use Tickit::Widget::HBox;

my $tickit = Tickit->new();

my @basekeys = qw( a i Space Tab Enter Up Insert );

my $vbox = Tickit::Widget::VBox->new( spacing => 1 );
my $hbox;

$vbox->add( $hbox = Tickit::Widget::HBox->new( spacing => 2 ) );

$hbox->add( Tickit::Widget::Static->new( text => "Modifier" ) );
foreach my $basekey (@basekeys) {
   $hbox->add( Tickit::Widget::Static->new( text => sprintf "%-6s", $basekey ) );
}

foreach my $mbits ( 0 .. 7 ) {
   my $modifier = "";
   $modifier .= "M-" if $mbits & 4;
   $modifier .= "C-" if $mbits & 2;
   $modifier .= "S-" if $mbits & 1;

   $vbox->add( $hbox = Tickit::Widget::HBox->new( spacing => 2 ) );
   $hbox->add( Tickit::Widget::Static->new( text => sprintf "%-8s", "$modifier*" ) );

   foreach ( @basekeys ) {
      my $basekey = $_; # avoid alias

      my $static;

      if( $modifier =~ m/S-/ && $basekey eq "Insert" ) {
         $static = Tickit::Widget::Static->new(
            text => "XX    ",
            fg   => "red",
         );
      }
      else {
         $static = Tickit::Widget::Static->new( text => "--    " );

         my $thismod = $modifier;
         # Keybindings are weirder
         if( length( $basekey ) == 1 ) {
            $thismod =~ s/S-// and $basekey = uc $basekey;
         }
         elsif( $basekey eq "Space" ) {
            $basekey = " ";
         }

         $tickit->bind_key(
            "$thismod$basekey" => sub {
               $static->pen->chattr( fg => "green" );
               $static->set_text( "OK    " );
            }
         );
      }

      $hbox->add( $static );
   }
}

$tickit->set_root_widget( $vbox );

$tickit->run;
