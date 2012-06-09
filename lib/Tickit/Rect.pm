#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2011 -- leonerd@leonerd.org.uk

package Tickit::Rect;

use strict;
use warnings;

use List::Util qw( min max );

our $VERSION = '0.16_001';

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

=cut

sub new
{
   my $class = shift;
   my %args = @_;

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

use overload '""' => sub {
   my $self = shift;
   sprintf "Tickit::Rect[(%d,%d)..(%d,%d)]", $self->left, $self->top, $self->right, $self->bottom;
};

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
