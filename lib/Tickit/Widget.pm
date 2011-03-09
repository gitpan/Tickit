#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2009-2011 -- leonerd@leonerd.org.uk

package Tickit::Widget;

use strict;
use warnings;

our $VERSION = '0.01';

use Carp;
use Scalar::Util qw( weaken );

use constant REDRAW_SELF     => 0x01;
use constant REDRAW_CHILDREN => 0x02;

=head1 NAME

C<Tickit::Widget> - abstract base class for on-screen widgets

=head1 SYNOPSIS

 TODO

=head1 DESCRIPTION

This class acts as an abstract base class for on-screen widget objects. It
provides the lower-level machinery required by most or all widget types.

=cut

=head1 CONSTRUCTOR

=cut

=head2 $widget = Tickit::Widget->new( %args )

Constructs a new C<Tickit::Widget> object. Must be called on a subclass that
implements the required methods; see the B<SUBCLASS METHODS> section below.

Takes the following named arguments at construction time:

=over 8

=item fg => COL

=item bg => COL

=item b => BOOL

=item i => BOOL

=item u => BOOL

Default pen attributes. See also L<Tickit::Term>'s C<chpen> method.

=back

=cut

sub new
{
   my $class = shift;
   my %args = @_;

   foreach my $method (qw( render lines cols )) {
      $class->can( $method ) or
         croak "$class cannot ->$method - do you subclass and implement it?";
   }

   my %penattrs;
   exists $args{$_} and $penattrs{$_} = $args{$_} for qw( fg bg b u i );

   return bless {
      penattrs     => \%penattrs,
      needs_redraw => 0,
   }, $class;
}

=head1 METHODS

=cut

=head2 $widget->set_window( $window )

Sets the drawing window for the widget. This method associates the widget with
a window, for it to use as its drawing area. Setting C<undef> removes the
window.

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
      $self->window_lost( $self->{window} );
   }

   $self->{window} = $window;

   if( $window ) {
      my $penattrs = $self->{penattrs};
      $window->chpen( $_ => $penattrs->{$_} ) for keys %$penattrs;

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
}

sub window_lost
{
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

C<$parent>, if defined, must be a subclass of C<Tickit::ContainerWidget>.

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
      my $bg       = $window->get_effective_pen( 'bg' );
      my $parentbg = $parentwin->get_effective_pen( 'bg' );

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

=head2 %attrs = $widget->getpen

Returns a hash of the currently-applied pen attributes

=cut

sub getpen
{
   my $self = shift;
   return %{ $self->{penattrs} };
}

=head2 $value = $widget->getpenattr( $name )

Returns the value of the given pen attribute, or C<undef> if it does not exist

=cut

sub getpenattr
{
   my $self = shift;
   my ( $name ) = @_;
   return $self->{penattrs}{$name};
}

=head2 $widget->chpen( $name, $value )

Changes the value of the given pen attribute. Set the value C<undef> to remove
it.

If the widget has a window associated with it, the window will be redrawn to
reflect the pen change.

=cut

sub chpen
{
   my $self = shift;
   my ( $name, $value ) = @_;

   # Optimise
   my $curvalue = $self->getpenattr( $name );
   return if !defined $curvalue and !defined $value;
   return if  defined $curvalue and  defined $value and $value == $curvalue;

   $self->{penattrs}{$name} = $value;

   if( $self->window ) {
      $self->window->chpen( $name, $value );
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
the contained L<Widget::Window> object obtained from C<< $widget->window >>.

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

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
