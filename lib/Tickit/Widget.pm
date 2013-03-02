#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2009-2012 -- leonerd@leonerd.org.uk

package Tickit::Widget;

use strict;
use warnings;

our $VERSION = '0.28';

use Carp;
use Scalar::Util qw( weaken );

use Tickit::Pen;

=head1 NAME

C<Tickit::Widget> - abstract base class for on-screen widgets

=head1 DESCRIPTION

This class acts as an abstract base class for on-screen widget objects. It
provides the lower-level machinery required by most or all widget types.

Objects cannot be directly constructed in this class. Instead, a subclass of
this class which provides a suitable implementation of the C<render> and other
provided methods is derived. Instances in that class are then constructed.

See the C<EXAMPLES> section below.

=cut

=head1 CONSTRUCTOR

=cut

=head2 $widget = Tickit::Widget->new( %args )

Constructs a new C<Tickit::Widget> object. Must be called on a subclass that
implements the required methods; see the B<SUBCLASS METHODS> section below.

Any pen attributes present in C<%args> will be used to set the default values
on the widget's pen object.

=cut

sub new
{
   my $class = shift;
   my %args = @_;

   foreach my $method (qw( render lines cols )) {
      $class->can( $method ) or
         croak "$class cannot ->$method - do you subclass and implement it?";
   }

   my $self = bless {
   }, $class;

   $self->set_pen( Tickit::Pen->new_from_attrs( \%args ) );

   return $self;
}

=head1 METHODS

=cut

=head2 $widget->set_window( $window )

Sets the L<Tickit::Window> for the widget to draw on. Setting C<undef> removes
the window.

If a window is associated to the widget, that window's pen is set to the
current widget pen. The widget is then drawn to the window by calling the
C<render> method. If a window is removed (by setting C<undef>) then no cleanup
of the window is performed; the new owner of the window is expected to do
this.

This method may invoke the C<window_gained> and C<window_lost> methods.

=cut

sub set_window
{
   my $self = shift;
   my ( $window ) = @_;

   # Early out if no change
   return if !$window and !$self->window;
   return if $window and $self->window and $self->window == $window;

   if( $self->{window} and !$window ) {
      $self->{window}->set_pen( undef );
      $self->window_lost( $self->{window} );
   }

   $self->{window} = $window;

   if( $window ) {
      $window->set_pen( $self->{pen} );

      $self->window_gained( $self->{window} );

      $self->reshape;

      $window->expose;
   }
}

use constant CLEAR_BEFORE_RENDER => 1;

sub window_gained
{
   my $self = shift;

   my $window = $self->window;

   weaken $self;

   $window->set_on_geom_changed( sub {
      $self->reshape;
      $self->redraw if !$self->parent;
   } );

   $window->set_on_expose( sub {
      my ( $win, $rect ) = @_;
      $self->_do_clear( $rect ) if $self->CLEAR_BEFORE_RENDER;
      $self->render(
         rect => $rect,
         top   => $rect->top,
         left  => $rect->left,
         lines => $rect->lines,
         cols  => $rect->cols,
      );
   } );

   if( $self->can( "on_key" ) ) {
      $window->set_on_key( sub {
         shift;
         $self->on_key( @_ );
      } );
   }
   if( $self->can( "on_mouse" ) ) {
      $window->set_on_mouse( sub {
         shift;
         $self->on_mouse( @_ );
      } );
   }
}

sub window_lost
{
   my $self = shift;

   my $window = $self->window;

   $window->set_on_geom_changed( undef );
   $window->set_on_expose( undef );
   $window->set_on_key( undef );
   $window->set_on_mouse( undef );
}

=head2 $window = $widget->window

Returns the current window of the widget, if one has been set using
C<set_window>.

=cut

sub window
{
   my $self = shift;
   return $self->{window};
}

=head2 $widget->set_parent( $parent )

Sets the parent widget; pass C<undef> to remove the parent.

C<$parent>, if defined, must be a subclass of L<Tickit::ContainerWidget>.

=cut

sub set_parent
{
   my $self = shift;
   my ( $parent ) = @_;

   !$parent or $parent->isa( "Tickit::ContainerWidget" ) or croak "Parent must be a ContainerWidget";

   weaken( $self->{parent} = $parent );
}

=head2 $parent = $widget->parent

Returns the current container widget

=cut

sub parent
{
   my $self = shift;
   return $self->{parent};
}

=head2 $widget->resized

Provided for subclasses to call when their size requirements have or may have
changed. Informs the parent that the widget may require a differently-sized
window.

=cut

sub resized
{
   my $self = shift;

   if( $self->parent ) {
      $self->parent->child_resized( $self );
   }
   else {
      $self->reshape if $self->window;
      $self->redraw;
   }
}

=head2 $widget->redraw

Clears the widget's window then invokes the C<render> method. This should
completely redraw the widget.

This redraw doesn't happen immediately. The widget is marked as needing to
redraw, and its parent is marked that it has a child needing redraw,
recursively to the root widget. These will then be flushed out down the widget
tree using an C<Tickit> C<later> call. This allows other widgets to register a
requirement to redraw, and have them all flushed in a fairly efficient manner.

=cut

sub redraw
{
   my $self = shift;

   $self->window or return;
   $self->window->expose;
}

sub _do_clear
{
   my $self = shift;
   my ( $rect ) = @_;
   my $window = $self->window or return;

   if( my $parentwin = $window->parent ) {
      my $bg       = $window->get_effective_penattr( 'bg' );
      my $parentbg = $parentwin->get_effective_penattr( 'bg' );

      return 0 if !defined $bg and !defined $parentbg;
      return 0 if  defined $bg and  defined $parentbg and $bg == $parentbg;
   }

   $window->clearrect( $rect );
   return 1;
}

=head2 $pen = $widget->pen

Returns the widget's L<Tickit::Pen>. Modifying an attribute of the returned
object results in the widget being redrawn if the widget has a window
associated.

=cut

sub pen
{
   my $self = shift;
   return $self->{pen};
}

=head2 $widget->set_pen( $pen )

Set a new C<Tickit::Pen> object. This is stored by reference; changes to the
pen will be reflected in the rendered look of the widget. The same pen may be
shared by more than one widget; updates will affect them all.

=cut

sub set_pen
{
   my $self = shift;
   my ( $newpen ) = @_;
   return if $self->{pen} and $self->{pen} == $newpen;

   $self->{pen}->remove_on_changed( $self ) if $self->{pen};
   $self->{pen} = $newpen;
   $newpen->add_on_changed( $self );
}

sub on_pen_changed
{
   my $self = shift;
   my ( $pen ) = @_;

   if( $self->window and $pen == $self->{pen} ) {
      $self->redraw;
   }
}

# Default empty implementation
sub reshape { }

=head1 SUBCLASS METHODS

Because this is an abstract class, the constructor must be called on a
subclass which implements the following methods.

=head2 $widget->render( %args )

Called to redraw the widget's content to its window. Methods can be called on
the contained L<Tickit::Window> object obtained from C<< $widget->window >>.

Will be passed hints on the region of the window that requires rendering; the
method implementation may choose to use this information to restrict drawing,
or it may ignore it entirely.

Before this method is called, the window area will be cleared if the
(optional) object method C<CLEAR_BEFORE_RENDER> returns true. Subclasses may
wish to override this and return false if their C<render> method will
completely redraw the window expose area anyway, for better performance and
less display flicker.

 use constant CLEAR_BEFORE_RENDER => 0;

=over 8

=item rect => Tickit::Rect

A L<Tickit::Rect> object representing the region of the screen that requires
rendering, relative to the widget's window.

Also provided by the following four named integers:

=item top => INT

=item left => INT

The top-left corner of the region that requires rendering, relative to the
widget's window.

=item lines => INT

=item cols => INT

The size of the region that requires rendering.

=back

=head2 $widget->reshape

Optional. Called after the window geometry is changed. Useful to distribute
window change sizes to contained child widgets.

=head2 $lines = $widget->lines

=head2 $cols = $widget->cols

Called to enquire on the requested window for this widget. It is possible that
the actual allocated window may be larger, or smaller than this amount.

=head2 $widget->window_gained( $window )

Optional. Called by C<set_window> when a window has been set for this widget.

=head2 $widget->window_lost( $window )

Optional. Called by C<set_window> when C<undef> has been set as the window for
this widget. The old window object is passed in.

=head2 $handled = $widget->on_key( $type, $str, $key )

Optional. If provided, this method will be set as the C<on_key> callback for
any window set on the widget. By providing this method a subclass can
implement widgets that respond to user input.

=head2 $handled = $widget->on_mouse( $ev, $button, $line, $col )

Optional. If provided, this method will be set as the C<on_mouse> callback for
any window set on the widget. By providing this method a subclass can
implement widgets that respond to user input.

=cut

=head1 EXAMPLES

=head2 A Trivial "Hello, World" Widget

The following is about the smallest possible C<Tickit::Widget> implementation,
containing the bare minimum of functionallity. It displays the fixed string
"Hello, world" at the top left corner of its window.

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

The C<lines> and C<cols> methods tell the container of the widget what its
minimum size requirements are, and the C<render> method actually draws it to
the window.

A slight improvement on this would be to obtain the size of the window, and
position the text in the centre rather than the top left corner.

 sub render
 {
    my $self = shift;
    my $win = $self->window;
 
    $win->clear;
    $win->goto( ( $win->lines - 1 ) / 2, ( $win->cols - 12 ) / 2 );
    $win->print( "Hello, world" );
 }

=head2 Reacting To User Input

If a widget subclass provides an C<on_key> method, then this will receive
keypress events if the widget's window has the focus. This example uses it to
change the pen foreground colour.

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
       $self->pen->chattr( fg => $str );
       $self->redraw;
       return 1;
    }

    return 0;
 }
 
 1;

The C<render> method sets the focus at the window's top left corner to ensure
that the window always has focus, so the widget will receive keypress events.
(A real widget implementation would likely pick a more sensible place to put
the cursor).

The C<on_key> method then gets invoked for keypresses. It returns a true value
to indicate the keys it handles, returning false for the others, to allow
parent widgets or the main C<Tickit> object to handle them instead.

Similarly, by providing an C<on_mouse> method, the widget subclass will
receive mouse events within the window of the widget. This example saves a
list of the last 10 mouse clicks and renders them with an C<X>.

 package ClickerWidget;
 use base 'Tickit::Widget';
 
 # In a real Widget this would be stored in an attribute of $self
 my @points;
 
 sub lines { 1 }
 sub cols  { 1 }
 
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

This time there is no need to set the window focus, because mouse events do
not need to follow the window that's in focus; they always affect the window
at the location of the mouse cursor.

The C<on_mouse> method then gets invoked whenever a mouse event happens within
the window occupied by the widget. In this particular case, the method filters
only for pressing button 1. It then stores the position of the mouse click in
the C<@points> array, for the C<render> method to use.

=cut

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
