#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2011-2012 -- leonerd@leonerd.org.uk

package Tickit::WidgetRole::Borderable;

use strict;
use warnings;

our $VERSION = '0.24';

=head1 NAME

C<Tickit::WidgetRole::Borderable> - implement widgets with a surrounding
border

=head1 DESCRIPTION

Mixing this role into a L<Tickit::Widget> subclass adds behaviour to handle a
border around the widget's contents.

=cut

=head1 METHODS

The following methods are provided on the caller package when this module is
imported by

 use Tickit::WidgetRole::Borderable;

=cut

sub import
{
   my $pkg = caller;

   no strict 'refs';
   foreach ( qw( _border_init set_v_border set_h_border set_border get_border_geom ),
             map { $_, "set_$_" } qw( top_border bottom_border left_border right_border ) ) {
      *{"${pkg}::$_"} = \&$_;
   }
}

=head2 $widget->_border_init( $argsref )

Initialises the border state from constructor arguments in the referenced
hash. Deletes keys that are used. Arguments may be the names any of the
C<set_*> methods named below.

=cut

sub _border_init
{
   my $self = shift;
   my ( $argsref ) = @_;

   $self->{"${_}_border"} = 0 for qw( top bottom left right );

   defined $argsref->{$_} and $self->${\"set_$_"}( delete $argsref->{$_} ) for qw(
      border
      h_border v_border
      top_border bottom_border left_border right_border
   );
}

=head2 $lines = $widget->top_border

=head2 $widget->set_top_border( $lines )

Return or set the number of lines of border at the top of the widget

=cut

sub top_border
{
   my $self = shift;
   return $self->{top_border};
}

sub set_top_border
{
   my $self = shift;
   $self->{top_border} = $_[0];
   $self->resized;
}

=head2 $lines = $widget->bottom_border

=head2 $widget->set_bottom_border( $lines )

Return or set the number of lines of border at the bottom of the widget

=cut

sub bottom_border
{
   my $self = shift;
   return $self->{bottom_border};
}

sub set_bottom_border
{
   my $self = shift;
   $self->{bottom_border} = $_[0];
   $self->resized;
}

=head2 $cols = $widget->left_border

=head2 $widget->set_left_border( $cols )

Return or set the number of cols of border at the left of the widget

=cut

sub left_border
{
   my $self = shift;
   return $self->{left_border};
}

sub set_left_border
{
   my $self = shift;
   $self->{left_border} = $_[0];
   $self->resized;
}

=head2 $cols = $widget->right_border

=head2 $widget->set_right_border( $cols )

Return or set the number of cols of border at the right of the widget

=cut

sub right_border
{
   my $self = shift;
   return $self->{right_border};
}

sub set_right_border
{
   my $self = shift;
   $self->{right_border} = $_[0];
   $self->resized;
}

=head2 $widget->set_h_border( $cols )

Set the number of cols of both horizontal (left and right) borders simultaneously

=cut

sub set_h_border
{
   my $self = shift;
   $self->{left_border} = $self->{right_border} = $_[0];
   $self->resized;
}

=head2 $widget->set_v_border( $cols )

Set the number of lines of both vertical (top and bottom) borders simultaneously

=cut

sub set_v_border
{
   my $self = shift;
   $self->{top_border} = $self->{bottom_border} = $_[0];
   $self->resized;
}

=head2 $widget->set_border( $count )

Set the number of cols or lines in all four borders simultaneously

=cut

sub set_border
{
   my $self = shift;
   $self->{top_border} = $self->{bottom_border} = $self->{left_border} = $self->{right_border} = $_[0];
   $self->resized;
}

=head2 ( $top, $left, $lines, $cols ) = $widget->get_border_geom

Returns a 4-element list giving the geometry of the inside of the border; the
area in which the bordered widget should draw.

=cut

sub get_border_geom
{
   my $self = shift;

   my $window = $self->window or return;

   my $content_top  = $self->top_border;
   my $content_left = $self->left_border;

   ( my $lines = $window->lines - $content_top  - $self->bottom_border ) > 0 or return;
   ( my $cols  = $window->cols  - $content_left - $self->right_border  ) > 0 or return;

   return ( $content_top, $content_left, $lines, $cols );
}

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
