#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2009-2012 -- leonerd@leonerd.org.uk

package Tickit::Widget::HBox;

use strict;
use warnings;
use base qw( Tickit::Widget::LinearBox );

our $VERSION = '0.16';

use List::Util qw( sum max );

=head1 NAME

C<Tickit::Widget::HBox> - distribute child widgets in a horizontal row

=head1 SYNOPSIS

 use Tickit;
 use Tickit::Widget::HBox;
 use Tickit::Widget::Static;
 
 my $tickit = Tickit->new;
 
 my $hbox = Tickit::Widget::HBox->new;

 foreach my $position (qw( left centre right )) {
    $hbox->add(
       Tickit::Widget::Static->new(
          text   => $position,
          align  => $position,
          valign => "middle",
       ),
       expand => 1
    );
 }
 
 $tickit->set_root_widget( $hbox );
 
 $tickit->run;

=head1 DESCRIPTION

This container widget distributes its children in a horizontal row.

=cut

sub lines
{
   my $self = shift;
   return max( 1, map { $_->lines } $self->children );
}

sub cols
{
   my $self = shift;
   return ( sum( map { $_->cols } $self->children ) || 1 ) +
          $self->{spacing} * ( $self->children - 1 );
}

sub get_total_quota
{
   my $self = shift;
   my ( $window ) = @_;
   return $window->cols;
}

sub get_child_base
{
   my $self = shift;
   my ( $child ) = @_;
   return $child->cols;
}

sub set_child_window
{
   my $self = shift;
   my ( $child, $left, $cols, $window ) = @_;

   if( $window and $cols ) {
      if( my $childwin = $child->window ) {
         $childwin->change_geometry( 0, $left, $window->lines, $cols );
      }
      else {
         my $childwin = $window->make_sub( 0, $left, $window->lines, $cols );
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
