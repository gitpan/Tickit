#!/usr/bin/perl

use strict;
use warnings;

use Test::More;

use Tickit::Test;

use Tickit::Widget;

# This test invokes deprecation warnings.
my $old_WARN = $SIG{__WARN__};
$SIG{__WARN__} = sub {
   local $SIG{__WARN__} = $old_WARN;

   warn @_ unless $_[0] =~ m/Disabling WIDGET_PEN_FROM_STYLE is now deprecated /;
};

my $nonpen_widget = StyledWidget->new(
   af => 1,
   style => { af => 2 },
);

is( $nonpen_widget->pen->getattr( "af" ), 1, 'widget pen attr for no WIDGET_PEN_FROM_STYLE' );
is( $nonpen_widget->get_style_pen->getattr( "af" ), 2, 'style pen attr for no WIDGET_PEN_FROM_STYLE' );

done_testing;

package StyledWidget;

use base qw( Tickit::Widget );
use Tickit::Style;

sub cols  { 1 }
sub lines { 1 }

sub render_to_rb {}
