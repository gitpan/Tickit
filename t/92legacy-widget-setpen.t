#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use Test::Identity;

use Tickit::Test;

use Tickit::Widget;

# This test invokes deprecation warnings.
my $old_WARN = $SIG{__WARN__};
$SIG{__WARN__} = sub {
   local $SIG{__WARN__} = $old_WARN;

   warn @_ unless $_[0] =~ m/Disabling WIDGET_PEN_FROM_STYLE is now deprecated /;
};

my $win = mk_window;

my $widget = TestWidget->new;

$widget->set_window( $win );

flush_tickit;

identical( $widget->window->pen, $widget->pen, '$widget->window shares pen' );

is_display( [ [TEXT("Hello")] ],
            'Display initially' );

$widget->set_pen( Tickit::Pen->new( fg => 4 ) );

identical( $widget->window->pen, $widget->pen, '$widget->window shares pen after ->set_pen' );

flush_tickit;

is_display( [ [TEXT("Hello",fg=>4), BLANK(75,fg=>2)] ],
            'Display with correct pen after ->set_pen' );

done_testing;

package TestWidget;

use base qw( Tickit::Widget );

sub render_to_rb
{
   my $self = shift;
   my ( $rb, $rect ) = @_;

   $rb->text_at( 0, 0, "Hello" );
}

sub lines { 1 }
sub cols  { 5 }
