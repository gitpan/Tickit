#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2009-2011 -- leonerd@leonerd.org.uk

package Tickit::RootWindow;

use strict;
use warnings;
use base qw( Tickit::Window );

our $VERSION = '0.11';

use Carp;
use Scalar::Util qw( weaken refaddr );

use Tickit::Pen;

=head1 NAME

C<Tickit::RootWindow> - root window for drawing operations

=head1 SYNOPSIS

=head1 DESCRIPTION

Provides a L<Tickit::Window> API object to represent the root window. All
other windows come from this one.

Provides the methods given in C<Tickit::Window>.

=cut

sub new
{
   my $class = shift;
   my ( $tickit, $lines, $cols ) = @_;

   my $term = $tickit->term;

   my $self = bless {
      tickit  => $tickit,
      term    => $term,
      cols    => $cols,
      lines   => $lines,
      updates => [],
      pen     => Tickit::Pen->new,
   }, $class;

   weaken( $self->{tickit} );

   return $self;
}

sub get_effective_penattrs
{
   my $self = shift;
   return $self->getpenattrs;
}

sub get_effective_penattr
{
   my $self = shift;
   my ( $attr ) = @_;
   return $self->getpenattr( $attr );
}

sub change_geometry
{
   my $self = shift;
   my ( undef, undef, $lines, $cols ) = @_;

   if( $self->{lines} != $lines or $self->{cols} != $cols ) {
      $self->{lines} = $lines;
      $self->{cols} = $cols;

      $self->{on_geom_changed}->( $self ) if $self->{on_geom_changed};
   }
}

sub enqueue_redraw
{
   my $self = shift;
   my ( $code ) = @_;

   push @{ $self->{redraw_queue} }, $code;

   $self->_enqueue_flush;
}

sub _enqueue_flush
{
   my $self = shift;

   return if $self->{flush_queued};

   $self->{flush_queued} = 1;
   $self->{tickit}->later( sub {
      my $term = $self->{term};

      my $queue = $self->{redraw_queue};
      undef $self->{redraw_queue};

      $term->mode_cursorvis( 0 );

      $_->() for @$queue;

      $self->restore;

      delete $self->{flush_queued}
   } );
}

sub root
{
   my $self = shift;
   return $self;
}

sub term
{
   my $self = shift;
   return $self->{term};
}

sub top      { 0 }
sub left     { 0 }
sub abs_top  { 0 }
sub abs_left { 0 }

sub goto
{
   my $self = shift;
   my ( $line, $col ) = @_;

   $line >= 0 and $line < $self->lines or croak '$line out of bounds';
   $col  >= 0 and $col  < $self->cols  or croak '$col out of bounds';

   $self->{output_column} = $col;

   $self->term->goto( $line, $col );
}

sub scrollrect
{
   my $self = shift;
   my ( $top, $left, $lines, $cols, $downward, $rightward, @args ) = @_;

   $top  >= 0 and $top  < $self->lines or croak '$top out of bounds';
   $left >= 0 and $left < $self->cols  or croak '$left out of bounds';

   $lines > 0 and $top + $lines <= $self->lines or croak '$lines out of bounds';
   $cols  > 0 and $left + $cols <= $self->cols  or croak '$cols out of bounds';

   my %attrs = ( @args == 1 ) ? $args[0]->getattrs : @args;
   exists $attrs{bg} or $attrs{bg} = $self->get_effective_penattr( 'bg' );

   $self->term->chpen( bg => $attrs{bg} );
   return $self->term->scrollrect(
      $top, $left, $lines, $cols,
      $downward, $rightward
   );
}

sub _requeue_focus_parent
{
   my $self = shift;

   $self->_enqueue_flush;
}

sub restore
{
   my $self = shift;

   if( my $focus_child = $self->{focus_child} ) {
      $self->{term}->mode_cursorvis( 1 );
      $focus_child->_gain_focus;
   }
   elsif( defined $self->{focus_line} ) {
      $self->{term}->mode_cursorvis( 1 );
      $self->_gain_focus;
   }
}

sub clear
{
   my $self = shift;

   my $term = $self->{term};

   $term->setpen( $self->getpenattrs );
   $term->clear;
}

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
