#!/usr/bin/perl

use strict;
use warnings;

use Tickit;

use Tickit::Widgets qw( GridBox HBox Entry Static Button CheckButton RadioButton );
Tickit::Style->load_style( <<'EOF' );
Entry:focus {
   bg: "blue";
   b: 1;
}

CheckButton:focus {
   check-bg: "blue";
}

RadioButton:focus {
   tick-bg: "blue";
}
EOF

my $gridbox = Tickit::Widget::GridBox->new(
   style => {
      row_spacing => 1,
      col_spacing => 4,
   },
);

foreach my $row ( 0 .. 2 ) {
   $gridbox->add( $row, 0, Tickit::Widget::Static->new( text => "Entry $row" ) );
   $gridbox->add( $row, 1, Tickit::Widget::Entry->new, col_expand => 1 );
}

$gridbox->add( 3, 0, Tickit::Widget::Static->new( text => "Buttons" ) );
$gridbox->add( 3, 1, my $hbox = Tickit::Widget::HBox->new( spacing => 2 ) );

foreach my $label (qw( One Two Three )) {
   $hbox->add( Tickit::Widget::Button->new( label => $label, on_click => sub {} ), expand => 1 );
}

foreach my $row ( 0 .. 2 ) {
   $gridbox->add( $row + 4, 1, Tickit::Widget::CheckButton->new( label => "Check $row" ) );
}

my $group = Tickit::Widget::RadioButton::Group->new;
foreach my $row ( 0 .. 2 ) {
   $gridbox->add( $row + 7, 1, Tickit::Widget::RadioButton->new( label => "Radio $row", group => $group ) );
}

Tickit->new( root => $gridbox )->run;
