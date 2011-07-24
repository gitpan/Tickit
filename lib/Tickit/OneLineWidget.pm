#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2011 -- leonerd@leonerd.org.uk

package Tickit::OneLineWidget;

use strict;
use warnings;
use base qw( Tickit::Widget );

our $VERSION = '0.08';

use Carp;

use Tickit::Utils qw( align );

=head1 NAME

C<Tickit::OneLineWidget> - a widget which occupies only one line

=head1 DESCRIPTION

This subclass of L<Tickit::Widget> provides a convenient base for widgets that
only want to occupy a single line of the window. It provides the C<valign>
accessor to control alignment of the widget's content within the window, and
a C<render> method that clears all the unused lines of the window. This class
also provides the C<lines> method, returning a constant value of C<1>.

=cut

sub new
{
   my $class = shift;
   my %args = @_;

   foreach my $method (qw( render_line )) {
      $class->can( $method ) or
         croak "$class cannot ->$method - do you subclass and implement it?";
   }

   my $self = $class->SUPER::new( %args );

   $self->set_valign( $args{valign} || 0 );

   return $self;
}

=head1 ACCESSORS

=cut

sub lines
{
   return 1;
}

=head2 $valign = $widget->valign

=cut

sub valign
{
   my $self = shift;
   return $self->{valign};
}

=head2 $widget->set_valign( $valign )

Accessor for vertical alignment value.

Gives a value in the range from C<0.0> to C<1.0> to align the content display
within the window. If the window is taller than one line, it will be aligned
according to this value; with C<0.0> at the top, C<1.0> at the bottom, and
other values inbetween.

The symbolic values C<top>, C<middle> and C<bottom> can be supplied instead of
C<0.0>, C<0.5> and C<1.0> respectively.

=cut

sub set_valign
{
   my $self = shift;
   my ( $valign ) = @_;

   # Convert symbolics
   $valign = 0.0 if $valign eq "top";
   $valign = 0.5 if $valign eq "middle";
   $valign = 1.0 if $valign eq "bottom";

   $self->{valign} = $valign;

   $self->redraw;
}

sub render
{
   my $self = shift;
   my %args = @_;

   my $bottom = $args{top} + $args{lines} - 1;

   my $window = $self->window or return;

   my ( $above ) =
      Tickit::Utils::align( 1, $window->lines, $self->valign );

   my $cols = $window->cols;

   $window->goto( $_, 0 ), $window->erasech( $cols ) for $args{top} .. $above - 1;

   $window->goto( $above, 0 );
   $self->render_line;

   $window->goto( $_, 0 ), $window->erasech( $cols ) for $above + 1 .. $bottom;
}

=head1 SUBCLASS METHODS

Because this is an abstract class, the constructor must be called on a
subclass which implements the following methods.

=head2 $widget->render_line

Called to redraw the widget's content to its window. When invoked, the window
cursor will already be in column C<0> of the required line of the window, as
determined by the C<valign> value.

=cut

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
