#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2011 -- leonerd@leonerd.org.uk

package Tickit::SingleChildWidget;

use strict;
use warnings;
use base qw( Tickit::ContainerWidget );

our $VERSION = '0.16';

use Carp;

=head1 NAME

C<Tickit::SingleChildWidget> - abstract base class for widgets that contain a
single other widget

=head1 SYNOPSIS

 TODO

=head1 DESCRIPTION

This subclass of L<Tickit::ContainerWidget> acts as an abstract base class for
widgets that contain exactly one other widget. It enforces that only one child
widget may be contained at any one time, and provides a convenient accessor to
obtain it.

=cut

=head1 CONSTRUCTOR

=cut

=head2 $widget = Tickit::SingleChildWidget->new( %args )

Constructs a new C<Tickit::SingleChildWidget> object. If passed an argument
called C<child> this will be added as the contained child widget.

=cut

sub new
{
   my $class = shift;
   my %args = @_;

   my $self = $class->SUPER::new( %args );

   $self->add( $args{child} ) if exists $args{child};

   return $self;
}

=head1 METHODS

=cut

=head2 $child = $widget->child

Returns the contained child widget.

=cut

sub child
{
   my $self = shift;
   return ( $self->children )[0];
}

sub add
{
   my $self = shift;
   croak "Already have a child; cannot add another" if $self->child;
   $self->SUPER::add( @_ );
}

sub window_lost
{
   my $self = shift;

   my $child = $self->child;
   $child->set_window( undef ) if $child;

   $self->SUPER::window_lost( @_ );
}

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
