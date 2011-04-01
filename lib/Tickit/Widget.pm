#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2009-2011 -- leonerd@leonerd.org.uk

package Tickit::Widget;

use strict;
use warnings;

our $VERSION = '0.03';

use Carp;
use Scalar::Util qw( weaken );

use Tickit::Pen;

use constant REDRAW_SELF     => 0x01;
use constant REDRAW_CHILDREN => 0x02;

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

   my $pen = Tickit::Pen->new_from_attrs( \%args );

   return bless {
      pen          => $pen,
      needs_redraw => 0,
   }, $class;
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

      $self->reshape;
      $self->_do_redraw( 1 ) if !$self->parent;

      weaken( my $weakself = $self );
      $window->set_on_geom_changed( sub {
         $weakself->reshape;
         $weakself->redraw if !$weakself->parent;
      } );

      $self->window_gained( $self->{window} );
   }
}

sub window_gained
{
   my $self = shift;

   weaken $self;
   if( $self->can( "on_key" ) ) {
      $self->window->set_on_key( sub {
         shift;
         $self->on_key( @_ );
      } );
   }
}

sub window_lost
{
   my $self = shift;

   $self->window->set_on_key( undef );
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
      $self->redraw;
   }
}

=head2 $widget->redraw

Clears the widget's window then invokes the C<render> method. This should
completely redraw the widget.

This redraw doesn't happen immediately. The widget is marked as needing to
redraw, and its parent is marked that it has a child needing redraw,
recursively to the root widget. These will then be flushed out down the widget
tree using an C<IO::Async::Loop> C<later> call. This allows other widgets to
register a requirement to redraw, and have them all flushed in a fairly
efficient manner.

=cut

sub redraw
{
   my $self = shift;

   $self->window or return;

   $self->_need_redraw( REDRAW_SELF );
}

sub _need_redraw
{
   my $self = shift;
   my ( $flag ) = @_;

   return if $self->{needs_redraw} & REDRAW_SELF;

   $self->{needs_redraw} |= $flag;

   if( my $parent = $self->parent ) {
      $parent->_need_redraw( REDRAW_CHILDREN );
   }
   else {
      $self->window->enqueue_redraw( sub {
         $self->_do_redraw( @_ );
      } );
   }
}

sub _do_clear
{
   my $self = shift;
   my $window = $self->window or return;

   if( my $parentwin = $window->parent ) {
      my $bg       = $window->get_effective_penattr( 'bg' );
      my $parentbg = $parentwin->get_effective_penattr( 'bg' );

      return 0 if !defined $bg and !defined $parentbg;
      return 0 if  defined $bg and  defined $parentbg and $bg == $parentbg;
   }

   $window->clear;
   return 1;
}

sub _do_redraw
{
   my $self = shift;
   my ( $force ) = @_;

   my $flag = $self->{needs_redraw};
   $self->{needs_redraw} = 0;

   my $window = $self->window or return;

   if( $flag & REDRAW_SELF or $force ) {
      $self->_do_clear;
      $self->render;
   }
}

=head2 %attrs = $widget->getpenattrs

Returns a hash of the currently-applied pen attributes

=cut

sub getpenattrs
{
   my $self = shift;
   return $self->{pen}->getattrs;
}

=head2 $value = $widget->getpenattr( $name )

Returns the value of the given pen attribute, or C<undef> if it does not exist

=cut

sub getpenattr
{
   my $self = shift;
   my ( $name ) = @_;
   return $self->{pen}->getattr( $name );
}

=head2 $widget->chpenattr( $name, $value )

Changes the value of the given pen attribute. Set the value C<undef> to remove
it.

If the widget has a window associated with it, the window will be redrawn to
reflect the pen change.

For details of the supported pen attributes, see L<Tickit::Pen>.

=cut

sub chpenattr
{
   my $self = shift;
   my ( $name, $value ) = @_;

   # Optimise
   my $curvalue = $self->getpenattr( $name );
   return if !defined $curvalue and !defined $value;
   return if  defined $curvalue and  defined $value and $value == $curvalue;

   $self->{pen}->chattr( $name, $value );

   if( $self->window ) {
      $self->redraw;
   }
}

# Default empty implementation
sub reshape { }

=head1 SUBCLASS METHODS

Because this is an abstract class, the constructor must be called on a
subclass which implements the following methods.

=head2 $widget->render

Called to redraw the widget's content to its window. Methods can be called on
the contained L<Tickit::Window> object obtained from C<< $widget->window >>.

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
       $self->chpenattr( fg => $str );
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

=cut

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
