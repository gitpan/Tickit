package ColourWidget;
use base 'Tickit::Widget';

my $text = "Press 0 to 7 to change the colour of this text";

sub lines { 1 }
sub cols  { length $text }

sub render
{
   my $self = shift;
   my $win = $self->window;

   $win->clear;
   $win->goto( ( $win->lines - $self->lines ) / 2, ( $win->cols - $self->cols ) / 2 );
   $win->print( $text );

   $win->focus( 0, 0 );
}

sub on_key
{
   my $self = shift;
   my ( $type, $str ) = @_;

   if( $type eq "text" and $str =~ m/[0-7]/ ) {
      $self->chpen( fg => $str );
      $self->redraw;
      return 1;
   }

   return 0;
}

1;
