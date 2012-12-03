#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2011 -- leonerd@leonerd.org.uk

package Tickit::Rect;

use strict;
use warnings;

use Carp;

use List::Util qw( min max );

our $VERSION = '0.24';

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

   my $self = bless [ @args{qw( top left lines cols )} ], $class;
}

=head2 $rect = $existing_rect->intersect( $other_rect )

If there is an intersection between the given rectangles, return it. If not,
return C<undef>.

=cut

sub intersect
{
   my $self = shift;
   my ( $other ) = @_;

   my $top    = max $self->top,    $other->top;
   my $bottom = min $self->bottom, $other->bottom;

   return undef if $top >= $bottom;

   my $left  = max $self->left,  $other->left;
   my $right = min $self->right, $other->right;

   return undef if $left >= $right;

   return (ref $self)->new( top => $top, left => $left, bottom => $bottom, right => $right );
}

=head2 $rect = $existing_rect->translate( $downward, $rightward )

Returns a new rectangle of the same size as the given one, moved down and to
the right by the given argmuents (which may be negative)

=cut

sub translate
{
   my $self = shift;
   my ( $downward, $rightward ) = @_;

   return (ref $self)->new(
      top   => $self->top  + $downward,
      left  => $self->left + $rightward,
      lines => $self->lines,
      cols  => $self->cols,
   );
}

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

sub top   { $_[0]->[0] }
sub left  { $_[0]->[1] }
sub lines { $_[0]->[2] }
sub cols  { $_[0]->[3] }

sub bottom { $_[0]->[0] + $_[0]->[2] }
sub right  { $_[0]->[1] + $_[0]->[3] }

=head2 @lines = $rect->linerange

A convenient shortcut to generate the list of lines covered; being

 $rect->top .. $rect->bottom - 1

=cut

sub linerange
{
   my $self = shift;
   return $self->top .. $self->bottom - 1;
}

=head1 METHODS

=cut

=head2 $bool = $rect->contains( $other )

Returns true if C<$other> is entirely contained within the bounds of C<$rect>.

=cut

sub contains
{
   my $self = shift;
   my ( $other ) = @_;
   return $other->top    >= $self->top    &&
          $other->bottom <= $self->bottom &&
          $other->left   >= $self->left   &&
          $other->right  <= $self->right;
}

=head2 $bool = $rect->intersects( $other )

Returns true if C<$other> and C<$rect> intersect at all, even if they overlap.

=cut

sub intersects
{
   my $self = shift;
   my ( $other ) = @_;
   return 0 if $self->top >= $other->bottom || $other->top >= $self->bottom;
   return 0 if $self->left >= $other->right || $other->left >= $self->right;
   return 1;
}

use overload '""' => sub {
   my $self = shift;
   sprintf "Tickit::Rect[(%d,%d)..(%d,%d)]", $self->left, $self->top, $self->right, $self->bottom;
};

=head2 @r = $rect->add( $other )

Returns a list of the non-overlapping regions covered by either C<$rect> or
C<$other>.

In the trivial case that the two given rectangles do not touch, the result
will simply be a list of the two initial rectangles. Otherwise a list of
newly-constructed rectangles will be returned that covers the same area as
the original two. This list will contain anywhere between 1 and 3 rectangles.

=cut

sub add
{
   my $x = shift;
   my ( $y ) = @_;

   return ( $x, $y ) if $x->left > $y->right or $y->left > $x->right
                     or $x->top > $y->bottom or $y->top > $x->bottom;

   my @rects;

   my @rows = sort { $a <=> $b } $x->top, $x->bottom, $y->top, $y->bottom;

   # We know there must be between 2 and 4 distinct values here
   foreach my $i ( 0 .. $#rows-1 ) {
      my $this_top    = $rows[$i];
      my $this_bottom = $rows[$i+1];

      # Skip non-unique
      next if $this_bottom == $this_top;

      my $has_x = $this_top >= $x->top && $this_bottom <= $x->bottom;
      my $has_y = $this_top >= $y->top && $this_bottom <= $y->bottom;

      my $this_left =  ( $has_x and $has_y ) ? min( $x->left, $y->left ) :
                         $has_x              ? $x->left :
                                               $y->left;
      my $this_right = ( $has_x and $has_y ) ? max( $x->right, $y->right ) :
                         $has_x              ? $x->right :
                                               $y->right;

      if( @rects and $this_left == $rects[-1]->left and 
                     $this_right == $rects[-1]->right ) {
         $this_top = ( pop @rects )->top;
      }

      push @rects, Tickit::Rect->new(
         top    => $this_top,
         bottom => $this_bottom,
         left   => $this_left,
         right  => $this_right,
      );
   }

   return @rects;
}

=head2 @r = $rect->subtract( $other )

Returns a list of the non-overlapping regions covered by C<$rect> but not by
C<$other>.

In the trivial case that C<$other> completely covers C<$rect> then the empty
list is returned. In the trivial case that C<$other> and C<$rect> do not
intersect then a list containing C<$rect> is returned. Otherwise, a list of
newly-constructed rectangles will be returned that covers the required area.
This list will contain anywhere between 1 and 4 rectangles.

=cut

sub subtract
{
   my $self = shift;
   my ( $hole ) = @_;

   return () if $hole->contains( $self );
   return $self unless $self->intersects( $hole );

   my @rects;

   if( $self->top < $hole->top ) {
      push @rects, Tickit::Rect->new(
         top    => $self->top,
         bottom => $hole->top,
         left   => $self->left,
         right  => $self->right,
      );
   }

   if( $self->left < $hole->left ) {
      push @rects, Tickit::Rect->new(
         top    => max( $self->top, $hole->top ),
         bottom => min( $self->bottom, $hole->bottom ),
         left   => $self->left,
         right  => $hole->left,
      );
   }

   if( $self->right > $hole->right ) {
      push @rects, Tickit::Rect->new(
         top    => max( $self->top, $hole->top ),
         bottom => min( $self->bottom, $hole->bottom ),
         left   => $hole->right,
         right  => $self->right,
      );
   }

   if( $self->bottom > $hole->bottom ) {
      push @rects, Tickit::Rect->new(
         top    => $hole->bottom,
         bottom => $self->bottom,
         left   => $self->left,
         right  => $self->right,
      );
   }

   return @rects;
}

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
