#!/usr/bin/perl

use strict;
use warnings;

use Test::More;

use Tickit::Test;

use Tickit::Widget;

my $win = mk_window;

# Needs declarative code
package StyledWidget;

use base qw( Tickit::Widget );
use Tickit::Style;

style_definition base =>
   fg => 2,
   text => "Hello, world!";

style_definition ':active' =>
   u => 1;

sub cols  { 1 }
sub lines { 1 }

use constant CLEAR_BEFORE_RENDER => 0;
sub render
{
}

my %style_changed_values;
sub on_style_changed_values
{
   shift;
   %style_changed_values = @_;
}

package main;

{
   my $widget = StyledWidget->new;

   is_deeply( { $widget->get_style_pen->getattrs }, { fg => 2 }, 'style pen for default' );
   is( $widget->get_style_text, "Hello, world!", 'render text for default' );
}

Tickit::Style->load_style( <<'EOF' );
StyledWidget {
   fg: 4;
   something-b: true; something-u: true; something-i: true;
}

StyledWidget.BOLD {
   b: true;
}

StyledWidget.PLAIN {
   !fg;
}

StyledWidget:active {
   bg: 2;
}
EOF

{
   my $widget = StyledWidget->new;

   is_deeply( { $widget->get_style_pen->getattrs },
              { fg => 4 },
              'style pen after loading style string' );

   is_deeply( { $widget->get_style_pen("something")->getattrs },
              { b => 1, u => 1, i => 1 },
              'pen can have boolean attributes' );
}

{
   my $widget = StyledWidget->new( class => "BOLD" );

   is_deeply( { $widget->get_style_pen->getattrs },
              { fg => 4, b => 1 },
              'style pen for widget with class' );
}

{
   my $widget = StyledWidget->new( class => "PLAIN" );

   is_deeply( { $widget->get_style_pen->getattrs },
              {},
              'style pen can cancel fg' );
}

{
   my $widget = StyledWidget->new;

   $widget->set_style_tag( active => 1 );

   is_deeply( { $widget->get_style_pen->getattrs },
              { fg => 4, u => 1, bg => 2 },
              'style pen for widget with style flag set' );

   is_deeply( \%style_changed_values,
              { bg => [ undef, 2 ], u => [ undef, 1 ] },
              'on_style_changed_values given style changes' );

   $widget->set_style_tag( active => 0 );

   is_deeply( { $widget->get_style_pen->getattrs },
              { fg => 4 },
              'style pen for widget with style flag cleared' );

   is_deeply( \%style_changed_values,
              { bg => [ 2, undef ], u => [ 1, undef ] },
              'on_style_changed_values given style changes after style flag clear' );
}

{
   my $widget = StyledWidget->new(
      style => {
         fg          => 5,
         'fg:active' => 6,
      }
   );

   is_deeply( { $widget->get_style_pen->getattrs },
              { fg => 5, },
              'style pen for widget with direct style' );

   $widget->set_style_tag( active => 1 );

   is_deeply( { $widget->get_style_pen->getattrs },
              { fg => 6, u => 1, bg => 2 },
              'style pen for widget with direct style tagged' );

   is_deeply( \%style_changed_values,
              { fg => [ 5, 6 ], u => [ undef, 1 ], bg => [ undef, 2 ] },
              'on_style_changed_values for widget with direct style' );
}

done_testing;
