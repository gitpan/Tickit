#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2009-2013 -- leonerd@leonerd.org.uk

package Tickit::ContainerWidget;

use strict;
use warnings;
use base qw( Tickit::Widget );

our $VERSION = '0.34';

use Carp;

use Scalar::Util qw( refaddr );
use List::MoreUtils qw( firstidx );

use constant CLEAR_BEFORE_RENDER => 0;

=head1 NAME

C<Tickit::ContainerWidget> - abstract base class for widgets that contain
other widgets

=head1 SYNOPSIS

 TODO

=head1 DESCRIPTION

This class acts as an abstract base class for widgets that contain at leaast
one other widget object. It provides storage for a hash of "options"
associated with each child widget.

=cut

sub new
{
   my $class = shift;

   foreach my $method (qw( children )) {
      $class->can( $method ) or
         croak "$class cannot ->$method - do you subclass and implement it?";
   }

   my $self = $class->SUPER::new( @_ );

   $self->{child_opts} = {};

   return $self;
}

=head2 $widget->add( $child, %opts )

Sets the child widget's parent, stores the options for the child, and calls
the C<children_changed> method. The concrete implementation will have to
implement storage of this child widget.

=cut

sub add
{
   my $self = shift;
   my ( $child, %opts ) = @_;

   $child->set_parent( $self );

   $self->{child_opts}{refaddr $child} = \%opts;

   $self->children_changed;
}

=head2 $widget->remove( $child_or_index )

Removes the child widget's parent, and calls the C<children_changed> method.
The concrete implementation will have to remove this child from its storage.

=cut

sub remove
{
   my $self = shift;
   my ( $child ) = @_;

   $child->set_parent( undef );
   $child->window->close if $child->window;
   $child->set_window( undef );

   delete $self->{child_opts}{refaddr $child};

   $self->children_changed;
}

=head2 %opts = $widget->child_opts( $child )

=head2 $opts = $widget->child_opts( $child )

Returns the options currently set for the given child as a key/value list in
list context, or as a HASH reference in scalar context. The HASH reference in
scalar context is the actual hash used to store the options - modifications to
it will be preserved.

=cut

sub child_opts
{
   my $self = shift;
   my ( $child ) = @_;

   my $opts = $self->{child_opts}{refaddr $child};
   return $opts if !wantarray;
   return %$opts;
}

=head2 $widget->set_child_opts( $child, %newopts )

Sets new options on the given child. Any options whose value is given as
C<undef> are deleted.

=cut

sub set_child_opts
{
   my $self = shift;
   my ( $child, %newopts ) = @_;

   my $opts = $self->{child_opts}{refaddr $child};

   foreach ( keys %newopts ) {
      defined $newopts{$_} ? ( $opts->{$_} = $newopts{$_} ) : ( delete $opts->{$_} );
   }

   $self->children_changed;
}

sub child_resized
{
   my $self = shift;
   $self->reshape if $self->window;
   $self->resized;
}

sub children_changed
{
   my $self = shift;

   $self->reshape if $self->window;
   $self->resized;
}

sub window_lost
{
   my $self = shift;

   $_->set_window( undef ) for $self->children;

   $self->SUPER::window_lost( @_ );
}

=head1 SUBCLASS METHODS

=head2 @children = $widget->children

Required. Should return a list of all the contained child widgets. The order
is not specified. This method is used by C<window_lost> to remove the windows
from all the child widgets automatically.

=head2 $widget->render( %args )

Optional. An empty C<render> method is provided for the case where the widget
is purely a layout container that does not directly draw to its window. If the
container requires drawing, this method may be overridden. Since the default
implementation is empty, there is no need for a subclass to C<SUPER> call it.

=head2 $widget->children_changed

Optional. If implemented, this method will be called after any change of the
contained child widgets or their options. Typically this will be used to set
windows on them by sub-dividing the window of the parent.

If not overridden, the base implementation will call C<reshape>.

=head2 $widget->child_resized( $child )

Optional. If implemented, this method will be called after a child widget
changes or may have changed its size requirements. Typically this will be used
to adjusts the windows allocated to children.

If not overridden, the base implementation will call C<reshape>.

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
