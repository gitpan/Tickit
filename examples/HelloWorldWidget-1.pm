package HelloWorldWidget;
use base 'Tickit::Widget';

sub lines {  1 }
sub cols  { 12 }

sub render
{
   my $self = shift;
   my $win = $self->window;

   $win->clear;
   $win->goto( 0, 0 );
   $win->print( "Hello, world" );
}

1;
