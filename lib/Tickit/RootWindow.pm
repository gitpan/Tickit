#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2009-2011 -- leonerd@leonerd.org.uk

package Tickit::RootWindow;

use strict;
use warnings;
use base qw( Tickit::Window );

our $VERSION = '0.04';

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
   my ( $tickit ) = @_;

   my $term = $tickit->term;

   my $self = bless {
      tickit  => $tickit,
      term    => $term,
      cols    => $term->cols,
      lines   => $term->lines,
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

sub scroll_region
{
   my $self = shift;
   my ( $top, $left, $lines, $cols, $downward, $rightward ) = @_;

   if( $left == 0 and $cols == $self->cols and $rightward == 0 ) {
      $self->{term}->scroll( $top, $top + $lines - 1, $downward );
      return 1;
   }

   # TODO: Consider other possible scrolls

   return 0;
}

sub _requeue_focus
{
   my $self = shift;
   my ( $focuswin ) = @_;

   if( $focuswin ) {
      if( $self->{focused_window} and refaddr( $self->{focused_window} ) != refaddr( $focuswin ) ) {
         $self->{focused_window}->_lose_focus;
      }
      weaken( $self->{focused_window} = $focuswin );
   }

   $self->_enqueue_flush;
}

sub restore
{
   my $self = shift;

   if( my $focused_window = $self->{focused_window} ) {
      $self->{term}->mode_cursorvis( 1 );
      $focused_window->_gain_focus;
   }
}

sub clear
{
   my $self = shift;

   my $term = $self->{term};

   $term->setpen( $self->getpenattrs );
   $term->clear;
}

sub _on_key
{
   my $self = shift;

   if( my $win = $self->{focused_window} ) {
      do {
         $win->_handle_key( @_ ) and return 1;
      } while( $win = $win->parent );
   }

   return 0;
}

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
