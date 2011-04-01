#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2011 -- leonerd@leonerd.org.uk

package Tickit::Pen;

use strict;
use warnings;

our $VERSION = '0.03';

use Carp;

our @ALL_ATTRS = qw( fg bg b u i rv af );

=head1 NAME

C<Tickit::Pen> - store a collection of rendering attributes

=head1 DESCRIPTION

Stores rendering attributes for text to display.

Supports the following named pen attributes:

=over 8

=item fg => COL

=item bg => COL

Foreground or background colour. C<COL> may be an integer C<0-7> or one of the
eight colour names.

=item b => BOOL

=item u => BOOL

=item i => BOOL

=item rv => BOOL

Bold, underline, italics, reverse video.

=item af => INT

Alternate font.

=back

Note that not all terminals can render the italics or alternate font
attributes.

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

   my $self = bless {}, $class;

   $self->chattrs( $attrs );

   return $self;
}

=head1 METHODS

=cut

=head2 $value = $pen->getattr( $attr )

Returns the current value of the given attribute

=cut

sub getattr
{
   my $self = shift;
   my ( $attr ) = @_;

   return $self->{$attr};
}

=head2 %values = $pen->getattrs

Returns a key/value list of all the attributes

=cut

sub getattrs
{
   my $self = shift;

   return %$self;
}

=head2 $pen->chattr( $attr, $value )

Change the value of an attribute. Setting C<undef> implies default value. To
delete an attribute altogether, see instead C<delattr>.

=cut

sub chattr
{
   my $self = shift;
   my ( $attr, $val ) = @_;

   my $canonicalise = $self->can( "_canonicalise_$attr" );
   $val = $self->$canonicalise( $val ) if $canonicalise;

   $self->{$attr} = $val;
}

my @COLOURNAMES = qw(
   black
   red
   green
   yellow
   blue
   magenta
   cyan
   white
);

*_canonicalise_fg = *_canonicalise_bg = \&_canonicalise_colour;
sub _canonicalise_colour
{
   my ( undef, $colour ) = @_;

   return undef if !defined $colour;

   return $colour if $colour =~ m/^\d+$/ and $colour < 8;

   foreach my $num ( 0 .. $#COLOURNAMES ) {
      return $num if $colour eq $COLOURNAMES[$num];
   }

   croak "Unrecognised colour value $colour";
}

*_canonicalise_b = *_canonicalise_u = *_canonicalise_i = *_canonicalise_rv =
   \&_canonicalise_bool;
sub _canonicalise_bool
{
   my ( undef, $val ) = @_;
   return $val ? 1 : undef;
}

sub _canonicalise_af
{
   my ( undef, $val ) = @_;
   return $val =~ m/^\d$/ ? $val : undef;
}

=head2 $pen->chattrs( \%attrs )

Change the values of all the attributes given in the hash. Recgonised
attributes will be deleted from the hash.

=cut

sub chattrs
{
   my $self = shift;
   my ( $attrs ) = @_;

   exists $attrs->{$_} and $self->chattr( $_, delete $attrs->{$_} ) for @ALL_ATTRS;
}

=head2 $pen->delattr( $attr )

Delete an attribute from this pen. This attribute will no longer be modified
by this pen.

=cut

sub delattr
{
   my $self = shift;
   my ( $attr ) = @_;

   delete $self->{$attr};
}

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
