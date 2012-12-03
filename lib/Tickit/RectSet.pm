#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2012 -- leonerd@leonerd.org.uk

package Tickit::RectSet;

use strict;
use warnings;

our $VERSION = '0.24';

use List::Util qw( min max );

=head1 NAME

C<Tickit::RectSet> - store a set of rectangular regions

=head1 DESCRIPTION

Objects in this class store a set of rectangular regions. The object tracks
which areas are covered, to ensure that overlaps are avoided, and that
neighbouring regions are merged where possible. The order in which they are
added is not important.

New regions can be added using the C<add> method. The C<rects> method returns
a list of non-overlapping L<Tickit::Rect> regions, in top-to-bottom,
left-to-right order.

=cut

=head1 CONSTRUCTOR

=cut

=head2 $rectset = Tickit::RectSet->new

Returns a new C<Tickit::RectSet> instance, initially empty.

=cut

sub new
{
   my $class = shift;
   return bless {
      # Store rects in _cmprect order
      rects => [],
   }, $class;
}

=head1 METHODS

=cut

sub _cmprect
{
   my ( $x, $y ) = @_;
   return $x->top  <=> $y->top ||
          $x->left <=> $y->left;
}

# Debugging aid
sub _assert_ordered
{
   my $self = shift;
   my $prev;
   foreach my $rect ( $self->rects ) {
      next unless $prev;
      _cmprect( $prev, $rect ) > 0 or
         die "Ordering constraint; $prev <=> $rect";

      $prev = $rect;
   }
}

=head2 @rects = $rectset->rects

Returns a list of the covered regions, in order first top to bottom, then left
to right.

=cut

sub rects
{
   my $self = shift;
   return @{ $self->{rects} };
}

sub _insert
{
   my $self = shift;
   my ( $new ) = @_;

   my $idx;
   for ( $idx = 0; $idx < @{ $self->{rects} }; $idx++ ) {
      last if _cmprect( $self->{rects}[$idx], $new ) > 0;
   }

   splice @{ $self->{rects} }, $idx, 0, ( $new );

   $self->_assert_ordered;
}

=head2 $rectset->add( $rect )

Adds the region covered by C<$rect> to the stored region list.

=cut

sub add
{
   my $self = shift;
   my ( $rect ) = @_;

   # Add a new region recursively by determining either:
   #   * it's entirely covered already
   #   * it's a unique new region
   #   * it can be merged with an existing region

   my $top    = $rect->top;
   my $bottom = $rect->bottom;
   my $left   = $rect->left;
   my $right  = $rect->right;

   my $idx;
   for ( $idx = 0; $idx < @{ $self->{rects} }; $idx++ ) {
      my $r = $self->{rects}[$idx];

      # Compare $r and the addition candidate, and determine a list of 1 to 3
      # non-overlapping rectangles with neighbouring row limits which cover
      # the same region

      next if $top > $r->bottom;
      last if $bottom < $r->top;
      next if $left > $r->right or $right < $r->left;

      # There may be an interaction then

      my $top_eq    = $top    == $r->top;
      my $bottom_eq = $bottom == $r->bottom;
      my $left_eq   = $left   == $r->left;
      my $right_eq  = $right  == $r->right;

      my $rows_eq = $top_eq  && $bottom_eq;
      my $cols_eq = $left_eq && $right_eq;

      # Handle a few simple cases first
      if( $top >= $r->top and $bottom <= $r->bottom and $left >= $r->left and $right <= $r->right ) {
         # Already entirely covered; just return
         return;
      }

      if( $rows_eq or $cols_eq ) {
         # Stretch an existing rectangle horizontally or vertically

         splice @{ $self->{rects} }, $idx, 1, ();
         $self->add( Tickit::Rect->new(
            top    => min( $top,    $r->top ),
            bottom => max( $bottom, $r->bottom ),
            left   => min( $left,  $r->left ),
            right  => max( $right, $r->right ),
         ) );
         return
      }

      if( $top  == $r->bottom or $bottom == $r->top ) {
         # No actual interaction; just add it
         # This case handles the recursion implied at the end of this loop
         next;
      }

      # Non-simple case. Split the covered region into the 2 or 3 separate
      # line runs that it must necessarily be composed of by now.
      my @rects = $r->add( $rect );

      # Now we need to delete $r and insert all the candidate rects instead
      splice @{ $self->{rects} }, $idx, 1, ();

      $self->add( $_ ) for @rects;
      return;
   }

   # If we got this far then we need to add it
   my $new = Tickit::Rect->new( top => $top, bottom => $bottom, left => $left, right => $right );
   $self->_insert( $new );
}

=head2 $rectset->subtract( $rect )

Removes any covered region that intersects with C<$rect> from the stored
region list.

=cut

sub subtract
{
   my $self = shift;
   my ( $rect ) = @_;

   # Subtract a region by iterating each rect, and if the rect intersects,
   # removing it from the stored list and inserting the left-overs

   my @add;

   my $idx;
   for ( $idx = 0; $idx < @{ $self->{rects} }; $idx++ ) {
      my $r = $self->{rects}[$idx];
      next unless $r->intersects( $rect );

      push @add, $r->subtract( $rect );

      splice @{ $self->{rects} }, $idx, 1, ();
      $idx--;
   }

   $self->add( $_ ) for @add;
}

=head2 $rectset->clear

Remove all the regions from the set.

=cut

sub clear
{
   my $self = shift;
   @{ $self->{rects} } = ();
}

=head2 $bool = $rectset->intersects( $rect )

Returns true if C<$rect> intersects with any region in the set.

=cut

sub intersects
{
   my $self = shift;
   my ( $rect ) = @_;

   foreach my $r ( @{ $self->{rects} } ) {
      return 1 if $r->intersects( $rect );
   }

   return 0;
}

=head2 $bool = $rectset->contains( $rect )

Returns true if C<$rect> is entirely covered by the regions in the set. Note
that it may be that the rect requires two or more regions in the set to
completely cover it.

=cut

sub contains
{
   my $self = shift;
   my ( $rect ) = @_;

   foreach my $r ( @{ $self->{rects} } ) {
      next unless $r->intersects( $rect );

      # Because {rects} is in order, if there's any part of $rect above or
      # to the left of $r we know we didn't match it
      return 0 if $rect->top < $r->top or
                  $rect->left < $r->left;

      if( $rect->top < $r->bottom and $r->bottom < $rect->bottom ) {
         my $lower = Tickit::Rect->new(
            top    => $r->bottom,
            left   => $rect->left,
            bottom => $rect->bottom,
            right  => $rect->right,
         );
         $rect = Tickit::Rect->new(
            top    => $rect->top,
            left   => $rect->left,
            bottom => $r->bottom,
            right  => $rect->right,
         );

         # Test the lower half
         return 0 unless $self->contains( $lower );
      }

      return $r->contains( $rect );
   }

   return 0;
}

# TODO:
#  Consider some sort of bitmap-based system in the C implementation
#  Or rather, store per line of the main rectangle, a list of start/stop column
#  numbers for window obscurings. Render it once for the rectset, and use it to
#  generate a possibly-new set of rectangles as the output answer.

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
