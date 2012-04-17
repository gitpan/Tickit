#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2009-2011 -- leonerd@leonerd.org.uk

package Tickit::ContainerWidget;

use strict;
use warnings;
use base qw( Tickit::Widget );

our $VERSION = '0.14';

use Carp;

use List::MoreUtils qw( firstidx );

=head1 NAME

C<Tickit::ContainerWidget> - abstract base class for widgets that contain
other widgets

=head1 SYNOPSIS

 TODO

=head1 DESCRIPTION

This class acts as an abstract base class for widgets that contain at leaast
one other widget object.

It maintains an ordered list of child widgets, and associates a hash of
named/value pairs as options for each child. Concrete subclasses of this base
can use these options to implement their required behaviour.

=cut

sub new
{
   my $class = shift;
   my $self = $class->SUPER::new( @_ );

   $self->{children} = [];

   return $self;
}

=head1 METHODS

=cut

sub render { }

=head2 @children = $widget->children

In scalar context, returns the number of contained children. In list context,
returns a list of all the child widgets.

=cut

sub children
{
   my $self = shift;

   return @{ $self->{children} } unless wantarray;
   return map { $_->[0] } @{ $self->{children} };
}

sub _any2index
{
   my $self = shift;

   if( ref $_[0] ) {
      my $child = shift;
      my $index = firstidx { $_ == $child } $self->children;
      return $index if defined $index;
      croak "Unable to find child $child";
   }
   else {
      my $index = shift;
      return $index if $index >= 0 and $index < $self->children;
      croak "Index $index out of bounds";
   }
}

=head2 %opts = $widget->child_opts( $child_or_index )

Returns the options currently set for the given child, specified either by
reference or by index.

=cut

sub child_opts
{
   my $self = shift;
   my $index = $self->_any2index( shift );

   return unless defined $index;

   return %{ $self->{children}[$index][1] };
}

=head2 $widget->set_child_opts( $child_or_index, %newopts )

Sets new options on the given child, specified either by reference or by
index. Any options whose value is given as C<undef> are deleted.

=cut

sub set_child_opts
{
   my $self = shift;
   my $index = $self->_any2index( shift );
   my %newopts = @_;

   return unless defined $index;

   my $opts = $self->{children}[$index][1];

   foreach ( keys %newopts ) {
      defined $newopts{$_} ? ( $opts->{$_} = $newopts{$_} ) : ( delete $opts->{$_} );
   }

   $self->children_changed if $self->can( "children_changed" );
}

=head2 $widget->foreach_child( \&code )

Executes the code block once for each stored child, in order. The code block
is passed the child widget and the options, as key/value pairs

 $code->( $child, %opts )

=cut

sub foreach_child
{
   my $self = shift;
   my ( $code ) = @_;

   foreach my $c ( @{ $self->{children} } ) {
      $code->( $c->[0], %{ $c->[1] } );
   }
}

=head2 $widget->add( $child, %opts )

Adds the widget as a new child of this one, with the given options

=cut

sub add
{
   my $self = shift;
   my ( $child, %opts ) = @_;

   $child->set_parent( $self );

   push @{ $self->{children} }, [ $child, \%opts ];

   $self->children_changed if $self->can( "children_changed" );
}

=head2 $widget->remove( $child_or_index )

Removes the given child widget if present, by reference or index

=cut

sub remove
{
   my $self = shift;
   my $index = $self->_any2index( shift );

   my ( $c ) = splice @{ $self->{children} }, $index, 1, ();

   if( $c ) {
      my $child = $c->[0];
      $child->set_parent( undef );
   }

   $self->children_changed if $self->can( "children_changed" );
}

# Provide default empty implementations of optional methods which other
# classes might call
sub child_resized {}

=head1 SUBCLASS METHODS

=head2 $widget->render( %args )

Optional. An empty C<render> method is provided for the case where the widget
is purely a layout container that does not directly draw to its window. If the
container requires drawing, this method may be overridden. Since the default
implementation is empty, there is no need for a subclass to C<SUPER> call it.

=head2 $widget->children_changed

Optional. If implemented, this method will be called after any change of the
contained child widgets or their options. Typically this will be used to set
windows on them by sub-dividing the window of the parent.

=head2 $widget->child_resized( $child )

Optional. If implemented, this method will be called after a child widget
changes or may have changed its size requirements. Typically this will be used
to adjusts the windows allocated to children.

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
