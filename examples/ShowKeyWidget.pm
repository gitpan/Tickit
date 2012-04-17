package ShowKeyWidget;
use base 'Tickit::Widget';

my $text;

sub lines {  1 }
sub cols  { 10 }

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

   $text = "$type: $str";
   $self->redraw;

   return 0;
}

1;
