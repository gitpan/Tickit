#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2009-2013 -- leonerd@leonerd.org.uk

package Tickit::Widget::LinearBox;

use strict;
use warnings;
use base qw( Tickit::ContainerWidget );
use Tickit::RenderBuffer;

our $VERSION = '0.34';

use Carp;

use Tickit::Utils qw( distribute );

use List::Util qw( sum );

=head1 NAME

C<Tickit::Widget::LinearBox> - abstract base class for C<HBox> and C<VBox>

=head1 DESCRIPTION

This class is a base class for both L<Tickit::Widget::HBox> and
L<Tickit::Widget::VBox>. It is not intended to be used directly.

It maintains an ordered list of child widgets, and implements the following
child widget options:

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

   exists $args{$_} and $args{style}{$_} = delete $args{$_} for qw( spacing );

   my $self = $class->SUPER::new( %args );

   $self->{children} = [];

   return $self;
}

=head1 METHODS

=cut

=head2 @children = $widget->children

In scalar context, returns the number of contained children. In list context,
returns a list of all the child widgets.

=cut

sub children
{
   my $self = shift;

   return @{ $self->{children} };
}

sub _any2index
{
   my $self = shift;

   if( ref $_[0] ) {
      my $child = shift;
      my $index = firstidx { $_ == $child } $self->children;
      return $index if defined $index;
      croak "Unable to find child $child";
   }
   else {
      my $index = shift;
      return $index if $index >= 0 and $index < $self->children;
      croak "Index $index out of bounds";
   }
}

=head2 %opts = $widget->child_opts( $child_or_index )

Returns the options currently set for the given child, specified either by
reference or by index.

=cut

sub child_opts
{
   my $self = shift;
   my $child = ref $_[0] ? shift : $self->{children}[shift];

   return unless $child;

   return $self->SUPER::child_opts( $child );
}

=head2 $widget->set_child( $index, $child )

Replaces the child widget at the given index with the given new one;
preserving any options that are set on it.

=cut

sub set_child
{
   my $self = shift;
   my ( $index, $child ) = @_;

   my $old_child = $self->{children}[$index];

   my %opts;
   if( $old_child ) {
      %opts = $self->child_opts( $old_child );

      local $self->{suppress_redistribute} = 1;
      $self->SUPER::remove( $old_child );
   }

   $self->{children}[$index] = $child;

   $self->SUPER::add( $child, %opts );
}

=head2 $widget->set_child_opts( $child_or_index, %newopts )

Sets new options on the given child, specified either by reference or by
index. Any options whose value is given as C<undef> are deleted.

=cut

sub set_child_opts
{
   my $self = shift;
   my $child = ref $_[0] ? shift : $self->{children}[shift];

   return unless $child;

   return $self->SUPER::set_child_opts( $child, @_ );
}

sub render
{
   my $self = shift;
   my %args = @_;

   my $win = $self->window or return;
   my $rect = $args{rect};
   my $rb = Tickit::RenderBuffer->new( lines => $win->lines, cols => $win->cols );
   $rb->clip( $rect );
   $rb->setpen( $self->pen );

   $rb->erase_at( $_, $rect->left, $rect->cols ) for $rect->linerange;

   $rb->flush_to_window( $win );
}

=head2 $widget->add( $child, %opts )

Adds the widget as a new child of this one, with the given options

=cut

sub add
{
   my $self = shift;
   my ( $child, %opts ) = @_;

   push @{ $self->{children} }, $child;

   $self->SUPER::add( $child,
      expand     => $opts{expand} || 0,
      force_size => $opts{force_size},
   );
}

=head2 $widget->remove( $child_or_index )

Removes the given child widget if present, by reference or index

=cut

sub remove
{
   my $self = shift;
   my $index = $self->_any2index( shift );

   my ( $child ) = splice @{ $self->{children} }, $index, 1, ();

   $self->SUPER::remove( $child ) if $child;
}

sub reshape
{
   my $self = shift;
   $self->{suppress_redistribute} and return;

   my $window = $self->window;

   return unless $self->children;

   my $spacing = $self->get_style_values( "spacing" );

   my @buckets;
   foreach my $child ( $self->children ) {
      my %opts = $self->child_opts( $child );

      push @buckets, {
         fixed => $spacing,
      } if @buckets; # gap

      my $base = defined $opts{force_size} ? $opts{force_size}
                                           : $self->get_child_base( $child );
      warn "Child $child did not define a base size for $self\n", $base = 0
         unless defined $base;

      push @buckets, {
         base   => $base,
         expand => $opts{expand},
         child  => $child,
      };
   }

   distribute( $self->get_total_quota( $window ), @buckets );

   foreach my $b ( @buckets ) {
      my $child = $b->{child} or next;

      $self->set_child_window( $child, $b->{start}, $b->{value}, $window );
   }

   $self->redraw;
}

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
