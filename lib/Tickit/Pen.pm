#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2011-2012 -- leonerd@leonerd.org.uk

package Tickit::Pen;

use strict;
use warnings;

our $VERSION = '0.27';

use Carp;

our @ALL_ATTRS = qw( fg bg b u i rv strike af );

# Load the XS code
require Tickit;

=head1 NAME

C<Tickit::Pen> - store a collection of rendering attributes

=head1 DESCRIPTION

Stores rendering attributes for text to display.

Supports the following named pen attributes:

=over 8

=item fg => COL

=item bg => COL

Foreground or background colour. C<COL> may be an integer or one of the eight
colour names. A colour name may optionally be prefixed by C<hi-> for the
high-intensity version (may not be supported by all terminals). Some terminals
may support a palette of 256 colours instead, some 16, and some only 8. The
C<Pen> object will not check this as it cannot be reliably detected in all
cases.

=item b => BOOL

=item u => BOOL

=item i => BOOL

=item rv => BOOL

=item strike => BOOL

Bold, underline, italics, reverse video, strikethrough.

=item af => INT

Alternate font.

=back

Note that not all terminals can render the italics, strikethrough, or
alternate font attributes.

=cut

=head1 CONSTRUCTORS

=cut

=head2 $pen = Tickit::Pen->new( %attrs )

Returns a new pen, initialised from the given attributes.

=cut

sub new
{
   my $class = shift;
   my %attrs = @_;
   my $self = $class->new_from_attrs( \%attrs );
   croak "Unrecognised pen attributes " . join( ", ", sort keys %attrs ) if %attrs;
   return $self;
}

=head2 $pen = Tickit::Pen->new_from_attrs( $attrs )

Returns a new pen, initialised from keys in the given HASH reference. Used
keys are deleted from the hash.

=cut

sub new_from_attrs
{
   my $class = shift;
   my ( $attrs ) = @_;

   my $self = $class->_new;

   $self->chattrs( $attrs );

   return $self;
}

=head2 $pen = $orig->clone

Returns a new pen, initialised by copying the attributes of the original.

=cut

sub clone
{
   my $orig = shift;
   my $new = (ref $orig)->new;
   $new->copy_from( $orig );
   return $new;
}

=head1 METHODS

=cut

=head2 $exists = $pen->hasattr( $attr )

Returns true if the given attribute exists on this object

=cut

=head2 $value = $pen->getattr( $attr )

Returns the current value of the given attribute

=cut

=head2 %values = $pen->getattrs

Returns a key/value list of all the attributes

=cut

=head2 $pen->chattr( $attr, $value )

Change the value of an attribute. Setting C<undef> deletes the attribute
entirely. See also C<delattr>.

=cut

=head2 $pen->chattrs( \%attrs )

Change the values of all the attributes given in the hash. Recgonised
attributes will be deleted from the hash.

=cut

=head2 $pen->delattr( $attr )

Delete an attribute from this pen. This attribute will no longer be modified
by this pen.

=cut

=head2 $pen->copy_from( $other )

=head2 $pen->default_from( $other )

Copy attributes from the given pen. C<copy_from> will override attributes
already defined by C<$pen>; C<default_from> will only copy attributes that are
not yet defined by C<$pen>.

As a convenience both methods return C<$pen>.

=cut

sub copy_from
{
   my $self = shift;
   my ( $other ) = @_;
   $self->copy( $other, 1 );
   return $self;
}

sub default_from
{
   my $self = shift;
   my ( $other ) = @_;
   $self->copy( $other, 0 );
   return $self;
}

=head2 $pen->add_on_changed( $observer, $id )

Add an observer to the list of objects which will be informed when the pen
attributes change. The observer will be informed by invoking a method
C<on_pen_changed>, passing in the pen reference and the opaque ID value given
to this method.

 $observer->on_pen_changed( $pen, $id )

The observer object is stored weakly, so it is safe to add the
C<Tickit::Widget> object that is using the pen as an observer. The ID value is
not weakened.

=cut

=head2 $pen->remove_on_changed( $observer )

Remove an observer previously added by C<add_on_changed>.

=cut

use overload '""' => "STRING";

sub STRING
{
   my $self = shift;

   return ref($self) . "={" . join( ",", map {
      $self->hasattr($_) ? "$_=" . $self->getattr($_) : () 
   } @ALL_ATTRS ) . "}";
}

use Scalar::Util qw( refaddr );
use overload '==' => sub { refaddr($_[0]) == refaddr($_[1]) };

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
