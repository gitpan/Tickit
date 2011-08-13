package ClickAndDragWidget;
use base 'Tickit::Widget';

use Tickit::Widget::Frame;

use List::Util qw( min max );

sub lines { 1 }
sub cols  { 1 }

sub render {}

# In a real Widget these would be stored in an attribute of $self
my @start;
my $dragframe;

sub on_mouse
{
   my $self = shift;
   my ( $ev, $button, $line, $col ) = @_;

   if( $button eq "release" ) {
      $dragframe->set_window( undef );
      undef $dragframe;
      return;
   }

   return unless $button == 1;

   if( $ev eq "press" ) {
      @start = ( $line, $col );
      return;
   }

   my $top   = min( $start[0], $line );
   my $left  = min( $start[1], $col );
   my $lines = max( $start[0], $line ) - $top + 1;
   my $cols  = max( $start[1], $col ) - $left + 1;

   return if( $lines == 0 or $cols == 0 );

   $self->window->clear;

   if( $dragframe ) {
      $dragframe->window->change_geometry( $top, $left, $lines, $cols );
   }
   else {
      $dragframe = Tickit::Widget::Frame->new;

      $dragframe->set_window(
         $self->window->make_sub( $top, $left, $lines, $cols )
      );
   }
}

1;
