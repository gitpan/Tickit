#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2009-2011 -- leonerd@leonerd.org.uk

package Tickit::Widget::LinearBox;

use strict;
use warnings;
use base qw( Tickit::ContainerWidget );

our $VERSION = '0.25';

use List::Util qw( sum );

=head1 NAME

C<Tickit::Widget::LinearBox> - abstract base class for C<HBox> and C<VBox>

=head1 DESCRIPTION

This class is a base class for both L<Tickit::Widget::HBox> and
L<Tickit::Widget::VBox>. It is not intended to be used directly.

It implements the following child widget options:

=over 8

=item expand => NUM

A number used to control how extra space is distributed among child widgets,
if the window containing this widget has more space available to it than the
children need. The actual value is unimportant, but extra space will be
distributed among the children in proportion with their C<expand> value.

For example, if all the children have a C<expand> value of 1, extra space is
distributed evenly. If one child has a value of 2, it will gain twice as much
extra space as its siblings. Any child with a value of 0 will obtain no extra
space.

=item force_size => NUM

If provided, forces the size of this child widget, overriding the value
returned by C<get_child_base>.

=back

=cut

sub new
{
   my $class = shift;
   my %args = @_;

   my $self = $class->SUPER::new( %args );

   $self->{spacing} = $args{spacing} || 0;

   return $self;
}

sub reshape
{
   my $self = shift;
   $self->redistribute_child_windows;
}

sub window_lost
{
   my $self = shift;

   $_->set_window( undef ) for $self->children;

   $self->SUPER::window_lost( @_ );
}

sub add
{
   my $self = shift;
   my ( $child, %opts ) = @_;

   $self->SUPER::add( $child, 
      expand     => $opts{expand} || 0,
      force_size => $opts{force_size},
   );
}

sub children_changed
{
   my $self = shift;

   $self->redistribute_child_windows if $self->window;
   $self->resized; # Tell my parent

   $self->redraw;
}

sub child_resized
{
   my $self = shift;
   $self->redistribute_child_windows if $self->window;

   $self->redraw;
}

sub redistribute_child_windows
{
   my $self = shift;

   my $window = $self->window;

   return unless $self->children;

   my $n_gaps = $self->children - 1;

   my $total = $self->get_total_quota( $window );

   # First determine how many spare lines
   my $spare = $total;
   my $expand_total = 0;

   my %base;

   $self->foreach_child( sub {
      my ( $child, %opts ) = @_;

      my $base = defined $opts{force_size} ? $opts{force_size} 
                                           : $self->get_child_base( $child );
      warn "Child $child did not define a base size for $self\n", $base = 0
         unless defined $base;

      $base{$child} = $base;

      $spare -= $base;
      $expand_total += $opts{expand};
   } );

   # Account for spacing
   $spare -= $n_gaps * $self->{spacing};

   my $err = 0;

   # This algorithm tries to allocate spare quota roughly evenly to the
   # children. It keeps track of rounding errors in $err, to ensure that
   # rounding-down-to-int() errors don't leave us some spare amount

   my $current = 0;

   $self->foreach_child( sub {
      my ( $child, %opts ) = @_;

      if( $current >= $total ) {
         $self->set_child_window( $child, undef, undef, undef );
         return; # next
      }

      my $extra = $expand_total ? ( $spare * $opts{expand} / $expand_total ) : 0;
      $err += $extra - int($extra);

      $extra = int($extra);
      $extra++, $err-- if $err >= 1;

      my $amount = $base{$child} + $extra;
      if( $current + $amount > $total ) {
         $amount = $total - $current; # All remaining space
      }

      $self->set_child_window( $child, $current, $amount, $window );

      $current += $amount + $self->{spacing};
   } );
}

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
