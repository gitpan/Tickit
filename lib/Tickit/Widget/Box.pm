#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2011 -- leonerd@leonerd.org.uk

package Tickit::Widget::Box;

use strict;
use warnings;
use base qw( Tickit::SingleChildWidget Tickit::WidgetRole::Borderable );

our $VERSION = '0.10';

=head1 NAME

C<Tickit::Widget::Box> - contain a single child widget

=head1 SYNOPSIS

 TODO

=head1 DESCRIPTION

TODO

=cut

sub new
{
   my $class = shift;
   my %args = @_;
   my $self = $class->SUPER::new( %args );

   $self->_border_init( \%args );

   return $self;
}

sub lines
{
   my $self = shift;
   my $child = $self->child;
   return $self->top_border +
          ( $child ? $child->lines : 0 ) +
          $self->bottom_border;
}

sub cols
{
   my $self = shift;
   my $child = $self->child;
   return $self->left_border +
          ( $child ? $child->cols : 0 ) +
          $self->right_border;
}

sub children_changed { shift->set_child_window }
sub reshape          { shift->set_child_window }

sub set_child_window
{
   my $self = shift;

   my $window = $self->window or return;
   my $child  = $self->child  or return;

   my @geom = $self->get_border_geom;

   if( @geom ) {
      if( my $childwin = $child->window ) {
         $childwin->change_geometry( @geom );
      }
      else {
         my $childwin = $window->make_sub( @geom );
         $child->set_window( $childwin );
      }
   }
   else {
      if( $child->window ) {
         $child->set_window( undef );
      }
   }
}

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
