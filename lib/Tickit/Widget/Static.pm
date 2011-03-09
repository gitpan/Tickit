#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2009-2011 -- leonerd@leonerd.org.uk

package Tickit::Widget::Static;

use strict;
use warnings;
use base qw( Tickit::Widget );

our $VERSION = '0.01';

use Text::CharWidth qw( mbswidth );

=head1 NAME

C<Tickit::Widget::Static> - a widget displaying static text

=head1 SYNOPSIS

 TODO

=head1 DESCRIPTION

This class provides a widget which displays a single piece of static text.

=cut

=head1 CONSTRUCTOR

=cut

=head2 $widget = Tickit::Widget::Static->new( %args )

Constructs a new C<Tickit::Widget::Static> object.

Takes the following named arguments in addition to those taken by the base
L<Tickit::Widget> constructor:

=over 8

=item text => STRING

The text to display

=item align => FLOAT|STRING

Optional. Defaults to C<0.0> if unspecified.

=back

For more details see the accessors below.

=cut

sub new
{
   my $class = shift;
   my %args = @_;

   my $self = $class->SUPER::new( %args );

   $self->set_text( $args{text} );
   $self->set_align( $args{align} || 0 );

   return $self;
}

=head1 ACCESSORS

=cut

sub lines
{
   return 1;
}

sub cols
{
   my $self = shift;
   return mbswidth( $self->{text} );
}

=head2 $text = $widget->text

=cut

sub text
{
   my $self = shift;
   return $self->{text};
}

=head2 $widget->set_text( $text )

Accessor for C<text> property; the actual text on display in the widget

=cut

sub set_text
{
   my $self = shift;
   ( $self->{text} ) = @_;
   $self->resized;
}

=head2 $align = $widget->align

=cut

sub align
{
   my $self = shift;
   return $self->{align};
}

=head2 $widget->set_align( $align )

Accessor for horizontal alignment value.

Gives a value in the range from C<0.0> to C<1.0> to align the text display
within the window. If the window is larger than the width of the text, it will
be aligned according to this value; with C<0.0> on the left, C<1.0> on the
right, and other values inbetween.

The symbolic values C<left>, C<centre> and C<right> can be supplied instead of
C<0.0>, C<0.5> and C<1.0> respectively.

=cut

sub set_align
{
   my $self = shift;
   my ( $align ) = @_;

   # Convert symbolics
   $align = 0 if $align eq "left";
   $align = 1 if $align eq "right";
   $align = 0.5 if $align eq "centre";

   $self->{align} = $align;

   $self->redraw;
}

sub render
{
   my $self = shift;

   my $window = $self->window or return;

   my $cols = $window->cols;

   my $text = $self->{text};

   my $spare = $cols - mbswidth( $text );

   my $left  = 0;
   my $right = 0;

   if( $spare >= 0 ) {
      $left  = int( $spare * $self->{align} );
      $right = $spare - $left;
   }
   else {
      $text = substr( $text, 0, $cols ); # TODO - Unicode awareness
   }

   $window->goto( 0, 0 );
   $window->erasech( $left, 1 ) if $left;
   $window->print( $text );
   $window->erasech( $right ) if $right;
}

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
