#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2009-2012 -- leonerd@leonerd.org.uk

package Tickit::Widget::VBox;

use strict;
use warnings;
use base qw( Tickit::Widget::LinearBox );

our $VERSION = '0.20';

use List::Util qw( sum max );

=head1 NAME

C<Tickit::Widget::VBox> - distribute child widgets in a vertical column

=head1 SYNOPSIS

 use Tickit;
 use Tickit::Widget::VBox;
 use Tickit::Widget::Static;
 
 my $tickit = Tickit->new;
 
 my $vbox = Tickit::Widget::VBox->new;

 foreach my $position (qw( top middle bottom )) {
    $vbox->add(
       Tickit::Widget::Static->new(
          text   => $position,
          align  => "centre",
          valign => $position,
       ),
       expand => 1
    );
 }
 
 $tickit->set_root_widget( $vbox );
 
 $tickit->run;

=head1 DESCRIPTION

This container widget distributes its children in a vertical column.

=cut

sub lines
{
   my $self = shift;
   return ( sum( map { $_->lines } $self->children ) || 1 ) +
          $self->{spacing} * ( $self->children - 1 );
}

sub cols
{
   my $self = shift;
   return max( 1, map { $_->cols } $self->children );
}

sub get_total_quota
{
   my $self = shift;
   my ( $window ) = @_;
   return $window->lines;
}

sub get_child_base
{
   my $self = shift;
   my ( $child ) = @_;
   return $child->lines;
}

sub set_child_window
{
   my $self = shift;
   my ( $child, $top, $lines, $window ) = @_;

   if( $window and $lines ) {
      if( my $childwin = $child->window ) {
         $childwin->change_geometry( $top, 0, $lines, $window->cols );
      }
      else {
         my $childwin = $window->make_sub( $top, 0, $lines, $window->cols );
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
