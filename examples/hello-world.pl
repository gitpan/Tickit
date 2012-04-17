#!/usr/bin/perl

use strict;
use warnings;

use Tickit;

use Tickit::Widget::Box;
use Tickit::Widget::Static;

my $box = Tickit::Widget::Box->new(
   h_border => 4, v_border => 2,
   bg => "green",
   child => Tickit::Widget::Static->new(
      text => "Hello, world!",
      align => "centre", valign => "middle",
      bg => "black",
   ),
);

my $tickit = Tickit->new;
$tickit->set_root_widget( $box );
$tickit->run;
