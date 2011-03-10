package HelloWorldWidget;
use base 'Tickit::Widget';

sub lines {  1 }
sub cols  { 12 }

sub render
{
   my $self = shift;
   my $win = $self->window;

   $win->clear;
   $win->goto( ( $win->lines - 1 ) / 2, ( $win->cols - 12 ) / 2 );
   $win->print( "Hello, world" );
}

1;
