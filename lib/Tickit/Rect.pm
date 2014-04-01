#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2011-2013 -- leonerd@leonerd.org.uk

package Tickit::Rect;

use strict;
use warnings;

use Carp;

our $VERSION = '0.43';

# Load the XS code
require Tickit;

=head1 NAME

C<Tickit::Rect> - a lightweight data structure representing a rectangle

=head1 SYNOPSIS

 use Tickit::Rect;

 my $rect = Tickit::Rect->new(
    top => 0, left => 5, lines => 3, cols => 10
 );

=head1 DESCRIPTION

Objects in this class represent a rectangle, by storing the top left corner
coordinate and the size in lines and columns. This data structure is purely
abstract and not tied to a particular window or coordinate system. It exists
simply as a convenient data store containing some useful utility methods.

=cut

=head1 CONSTRUCTORS

=cut

=head2 $rect = Tickit::Rect->new( %args )

Construct a new rectangle of the given geometry, given by C<top>, C<left> and
either C<lines> and C<cols>, or C<bottom> and C<right>.

=head2 $rect = Tickit::Rect->new( $str )

If given a single string, this will be parsed in the form

 (left,top)..(right,bottom)

=cut

sub new
{
   my $class = shift;
   my %args;
   if( @_ == 1 ) {
      @args{qw(left top right bottom)} =
         $_[0] =~ m/^\((\d+),(\d+)\)..\((\d+),(\d+)\)$/ or croak "Unrecognised Tickit::Rect string '$_[0]'";
   }
   else {
      %args = @_;
   }

   defined $args{lines} or $args{lines} = $args{bottom} - $args{top};
   defined $args{cols}  or $args{cols}  = $args{right}  - $args{left};

   return $class->_new( @args{qw( top left lines cols )} );
}

=head2 $rect = $existing_rect->intersect( $other_rect )

If there is an intersection between the given rectangles, return it. If not,
return C<undef>.

=cut

=head2 $rect = $existing_rect->translate( $downward, $rightward )

Returns a new rectangle of the same size as the given one, moved down and to
the right by the given argmuents (which may be negative)

=cut

=head1 ACCESSORS

=cut

=head2 $top = $rect->top

=head2 $left = $rect->left

=head2 $bottom = $rect->bottom

=head2 $right = $rect->right

Return the edge boundaries of the rectangle.

=head2 $lines = $rect->lines

=head2 $cols = $rect->cols

Return the size of the rectangle.

=cut

=head2 @lines = $rect->linerange( $min, $max )

A convenient shortcut to generate the list of lines covered that are within
the given bounds (either bound may be given as C<undef>). Without bounds,
equivalent to:

 $rect->top .. $rect->bottom - 1

=cut

sub linerange
{
   my $self = shift;
   my ( $min, $max ) = @_;

   my $start = $self->top;
   $start = $min if defined $min and $min > $start;

   my $stop = $self->bottom - 1;
   $stop = $max if defined $max and $max < $stop;

   return $start .. $stop;
}

=head1 METHODS

=cut

=head2 $bool = $rect->equals( $other )

=head2 $bool = ( $rect == $other )

Returns true if C<$other> represents the same area as C<$rect>.

=cut

use overload '==' => "equals", eq => "equals";

=head2 $bool = $rect->contains( $other )

Returns true if C<$other> is entirely contained within the bounds of C<$rect>.

=cut

=head2 $bool = $rect->intersects( $other )

Returns true if C<$other> and C<$rect> intersect at all, even if they overlap.

=cut

use overload
   '""' => sub {
      my $self = shift;
      sprintf "Tickit::Rect[(%d,%d)..(%d,%d)]", $self->left, $self->top, $self->right, $self->bottom;
   },
   bool => sub { 1 };

=head2 @r = $rect->add( $other )

Returns a list of the non-overlapping regions covered by either C<$rect> or
C<$other>.

In the trivial case that the two given rectangles do not touch, the result
will simply be a list of the two initial rectangles. Otherwise a list of
newly-constructed rectangles will be returned that covers the same area as
the original two. This list will contain anywhere between 1 and 3 rectangles.

=cut

=head2 @r = $rect->subtract( $other )

Returns a list of the non-overlapping regions covered by C<$rect> but not by
C<$other>.

In the trivial case that C<$other> completely covers C<$rect> then the empty
list is returned. In the trivial case that C<$other> and C<$rect> do not
intersect then a list containing C<$rect> is returned. Otherwise, a list of
newly-constructed rectangles will be returned that covers the required area.
This list will contain anywhere between 1 and 4 rectangles.

=cut

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
