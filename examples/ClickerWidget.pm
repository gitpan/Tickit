package ClickerWidget;
use base 'Tickit::Widget';

# In a real Widget this would be stored in an attribute of $self
my @points;

sub lines { 1 }
sub cols  { length $text }

sub render
{
   my $self = shift;
   my $win = $self->window;

   $win->clear;
   foreach my $point ( @points ) {
      $win->goto( $point->[0], $point->[1] );
      $win->print( "X" );
   }
}

sub on_mouse
{
   my $self = shift;
   my ( $ev, $button, $line, $col ) = @_;

   return unless $ev eq "press" and $button == 1;

   push @points, [ $line, $col ];
   shift @points while @points > 10;
   $self->redraw;
}

1;
