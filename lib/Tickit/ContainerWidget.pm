#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2009-2013 -- leonerd@leonerd.org.uk

package Tickit::ContainerWidget;

use strict;
use warnings;
use feature qw( switch );
use base qw( Tickit::Widget );
no if $] >= 5.017011, warnings => 'experimental::smartmatch';

our $VERSION = '0.38';

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

=head2 $child = $widget->find_child( $how, $other, %args )

Returns a child widget. The C<$how> argument determines how this is done,
relative to the child widget given by C<$other>:

=over 4

=item first

The first child returned by C<children> (C<$other> is ignored)

=item last

The last child returned by C<children> (C<$other> is ignored)

=item before

The child widget just before C<$other> in the order given by C<children>

=item after

The child widget just after C<$other> in the order given by C<children>

=back

Takes the following named arguments:

=over 8

=item where => CODE

Optional. If defined, gives a filter function to filter the list of children
before searching for the required one. Will be invoked once per child, with
the child widget set as C<$_>; it should return a boolean value to indicate if
that child should be included in the search.

=back

=cut

sub find_child
{
   my $self = shift;
   my ( $how, $other, %args ) = @_;

   my @children = $self->children;
   if( my $where = $args{where} ) {
      @children = grep { defined $other and $_ == $other or $where->() } @children;
   }

   for( $how ) {
      when( "first" ) {
         return $children[0];
      }
      when( "last" ) {
         return $children[-1];
      }
      when( "before" ) {
         $children[$_] == $other and return $children[$_-1] for 1 .. $#children;
         return undef;
      }
      when( "after" ) {
         $children[$_] == $other and return $children[$_+1] for 0 .. $#children-1;
         return undef;
      }
      default {
         croak "Unrecognised ->find_child mode '$how'";
      }
   }
}

use constant CONTAINER_OR_FOCUSABLE => sub {
   $_->isa( "Tickit::ContainerWidget" ) or $_->CAN_FOCUS
};

=head2 $widget->focus_next( $how, $other )

Moves the input focus to the next widget in the widget tree, by searching in
the direction given by C<$how> relative to the widget given by C<$other>
(which must be an immediate child of C<$widget>).

The direction C<$how> must be one of the following four values:

=over 4

=item first

=item last

Moves focus to the first or last child widget that can take focus. Recurses
into child widgets that are themselves containers. C<$other> is ignored.

=item after

=item before

Moves focus to the next or previous child widget in tree order from the one
given by C<$other>. Recurses into child widgets that are themselves
containers, and out into parent containers.

These searches will wrap around the widget tree; moving C<after> the last node
in the widget tree will move to the first, and vice versa.

=back

This differs from C<find_child> in that it performs a full tree search through
the widget tree, considering parents and children. If a C<before> or C<after>
search falls off the end of one node, it will recurse up to its parent and
search within the next child, and so on.

Usually this would be used via the widget itself:

 $self->parent->focus_next( $how => $self );

=cut

sub focus_next
{
   my $self = shift;
   my ( $how, $other ) = @_;

   # This tree search has the potential to loop infinitely, if there are no
   # focusable widgets at all. It would only do this if it cycles via the root
   # widget twice in a row. Technically we could detect it earlier, but that
   # is more difficult to arrange for
   my $done_root;

   my $next;

   while(1) {
      $next = $self->find_child( $how, $other, where => CONTAINER_OR_FOCUSABLE );
      last if $next and $next->CAN_FOCUS;

      # Either we found a container (recurse into it),
      if( $next ) {
         my $childhow = $how;
         if(    $how eq "after"  ) { $childhow = "first" }
         elsif( $how eq "before" ) { $childhow = "last" }

         # See if child has it
         return if $next->focus_next( $childhow => undef );

         $other = $next;
         redo;
      }
      # or we'll have to recurse up to my parent
      elsif( my $parent = $self->parent ) {
         if( $how eq "after" or $how eq "before" ) {
            $other = $self;
            $self = $parent;
            redo;
         }
         else {
            return undef;
         }
      }
      # or we'll have to cycle around the root
      else {
         die "Cycled through the entire widget tree and did not find a focusable widget" if $done_root;
         $done_root++;

         if(    $how eq "after"  ) { $how = "first" }
         elsif( $how eq "before" ) { $how = "last"  }
         else { die "Cannot cycle how=$how around root widget"; }

         $other = undef;
         redo;
      }
   }

   # if( !$next and my $parent = $self->parent ) {
   #    return undef if $how eq "first" || $how eq "last";

   #    return $parent->focus_next( $how, $self );
   # }

   $next->take_focus;
   return 1;
}

=head1 SUBCLASS METHODS

=head2 @children = $widget->children

Required. Should return a list of all the contained child widgets. The order
is not specified, but should be in some stable order that makes sense given
the layout of the widget's children.

This method is used by C<window_lost> to remove the windows from all the child
widgets automatically, and by C<find_child> to obtain a child relative to
another given one.

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
