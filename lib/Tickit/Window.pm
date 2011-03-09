#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2009-2011 -- leonerd@leonerd.org.uk

package Tickit::Window;

use strict;
use warnings;

our $VERSION = '0.01';

use Carp;

=head1 NAME

C<Tickit::Window> - a window for drawing operations

=head1 SYNOPSIS

=head1 DESCRIPTION

Provides coordination of widget drawing activities. A C<Window> represents a
region of the screen that a widget occupies.

Windows cannot directly be constructed. Instead they are obtained by
sub-division of other windows, ultimately coming from the
C<Tickit::RootWindow> associated with the terminal.

=cut

=head1 METHODS

=cut

=head2 $cols = $win->cols

=head2 $lines = $win->lines

Obtain the size of the window

=cut

sub cols
{
   my $self = shift;
   return $self->{cols};
}

sub lines
{
   my $self = shift;
   return $self->{lines};
}

=head2 $win->resize( $lines, $cols )

Change the size of the window.

=cut

sub resize
{
   my $self = shift;
   my ( $lines, $cols ) = @_;

   $self->change_geometry( $self->top, $self->left, $lines, $cols );
}

=head2 $win->reposition( $top, $left )

Move the window relative to its parent.

=cut

sub reposition
{
   my $self = shift;
   my ( $top, $left ) = @_;

   $self->change_geometry( $top, $left, $self->lines, $self->cols );

   $self->_requeue_focus if defined $self->{focus_col};
}

=head2 $win->change_geometry( $top, $left, $lines, $cols )

A combination of C<resize> and C<reposition>, to atomically change all the
coordinates of the window. Will only invoke C<on_geom_changed> once, rather
than twice as would be the case calling the above methods individually.

=cut

sub change_geometry
{
   my $self = shift;
   my ( $top, $left, $lines, $cols ) = @_;

   $top >= 0 or croak 'top out of bounds';
   $left >= 0 or croak 'left out of bounds';

   $top + $lines <= $self->parent->lines or croak 'bottom out of bounds';
   $left + $cols <= $self->parent->cols or croak 'right out of bounds';

   if( !defined $self->{top} or 
       $self->{lines} != $lines or $self->{cols} != $cols or
       $self->{top} != $top or $self->{left} != $left ) {
      $self->{lines} = $lines;
      $self->{cols} = $cols;
      $self->{top} = $top;
      $self->{left} = $left;

      $self->{on_geom_changed}->( $self ) if $self->{on_geom_changed};
   }
}

=head2 $win->set_on_geom_changed( $on_geom_changed )

Set the callback to invoke whenever the window is resized or repositioned;
i.e. whenever its geometry changes.

 $on_geom_changed->( $win )

=cut

sub set_on_geom_changed
{
   my $self = shift;
   ( $self->{on_geom_changed} ) = @_;
}

=head2 $win->set_on_key( $on_key )

Set the callback to invoke whenever a key is pressed while this window, or one
of its child windows, has the input focus.

 $handled = $on_key->( $win, $type, $str, $key )

The invoked code should return a true value if it considers the keypress dealt
with, or false to pass it up to its parent window.

=cut

sub set_on_key
{
   my $self = shift;
   ( $self->{on_key} ) = @_;
}

sub _handle_key
{
   my $self = shift;
   my $on_key = $self->{on_key} or return 0;
   return $on_key->( $self, @_ );
}

=head2 $parentwin = $win->parent

Returns the parent window; i.e. the window on which C<make_sub> was called to
create this one

=cut

sub parent
{
   my $self = shift;
   return $self->{parent};
}

=head2 $rootwin = $win->root

Returns the root window

=cut

sub root
{
   my $self = shift;
   return $self->parent->root if $self->parent;
   return $self;
}

=head2 $term = $win->term

Returns the L<Tickit::Term> instance of the terminal on which this window
lives.

=cut

sub term
{
   my $self = shift;
   return $self->root->term;
}

=head2 $top  = $win->top

=head2 $left = $win->left

Returns the coordinates of the start of the window, relative to the parent
window.

=cut

sub top
{
   my $self = shift;
   return $self->{top};
}

sub left
{
   my $self = shift;
   return $self->{left};
}

=head2 $top  = $win->abs_top

=head2 $left = $win->abs_left

Returns the coordinates of the start of the window, relative to the root
window.

=cut

sub abs_top
{
   my $self = shift;
   return $self->parent->abs_top + $self->{top};
}

sub abs_left
{
   my $self = shift;
   return $self->parent->abs_left + $self->{left};
}

=head2 $val = $win->getpen( $attr )

=head2 %attrs = $win->getpen

Retrieve the current pen settings for the window.

=cut

sub getpen
{
   my $self = shift;

   return $self->{pen}{$_[0]} if @_;
   return %{ $self->{pen} };
}

=head2 $val = $win->get_effective_pen( $attr )

=head2 %attrs = $win->get_effective_pen

Retrieve the effective pen settings for the window. This will be the settings
of the window and all its parents down to the root window, merged together.

=cut

sub get_effective_pen
{
   my $self = shift;

   return $self->{pen}{$_[0]} || $self->parent->get_effective_pen( $_[0] ) if @_;

   my %epen = $self->parent->get_effective_pen;
   $epen{$_} = $self->{pen}{$_} for keys %{ $self->{pen} };

   return %epen;
}

=head2 $win->chpen( $attr, $val )

Change a pen attribute. Setting C<undef> implies default value. To delete the
attribute altogether see instead C<delpen>.

=cut

sub chpen
{
   my $self = shift;
   my ( $attr, $val ) = @_;

   $self->{pen}{$attr} = $val;
}

=head2 $win->delpen( $attr )

Delete a pen attribute. Removes the value from the window's pen attributes,
implying this window uses its parent value. To set default, see instead
C<chpen> with C<undef> value.

=cut

sub delpen
{
   my $self = shift;
   my ( $attr ) = @_;

   delete $self->{pen}{$attr};
}

=head2 $sub = $win->make_sub( $top, $left, $lines, $cols )

Constructs a new sub-window starting at the given coordinates of this window.
It will be sized to the given limits.

=cut

sub make_sub
{
   my $self = shift;
   my ( $top, $left, $lines, $cols ) = @_;

   my $sub = bless {
      parent => $self,
      pen    => {},
   }, __PACKAGE__; # not ref $self in case of RootWindow

   $sub->change_geometry( $top, $left, $lines, $cols );

   return $sub;
}

=head2 $win->goto( $line, $col )

Moves the cursor to the given position within the window. Both C<$line> and
C<$col> are 0-based.

=cut

sub goto
{
   my $self = shift;
   my ( $line, $col ) = @_;

   $line >= 0 and $line < $self->lines or croak '$line out of bounds';
   $col  >= 0 and $col  < $self->cols  or croak '$col out of bounds';

   $self->term->goto( $self->abs_top + $line, $self->abs_left + $col );
}

=head2 $win->print( $text )

Print the given text to the terminal at the current cursor position using the
pen of the window.

=cut

sub print
{
   my $self = shift;
   my ( $text ) = @_;

   return unless length $text;

   $self->term->setpen( $self->get_effective_pen );
   $self->term->print( $text );
}

=head2 $win->penprint( $text, %attrs )

Print the given text to the terminal at the current cursor position using the
pen of the window, overridden by any extra attributes passed.

=cut

sub penprint
{
   my $self = shift;
   my ( $text, %attrs ) = @_;

   return unless length $text;

   $self->term->setpen( $self->get_effective_pen, %attrs );
   $self->term->print( $text );
}

=head2 $win->erasech( $count, $moveend )

Erase C<$count> columns forwards.

=cut

sub erasech
{
   my $self = shift;
   my ( $count, $moveend ) = @_;

   $self->term->setpen( bg => $self->get_effective_pen( 'bg' ) );
   $self->term->erasech( $count, $moveend );
}

=head2 $success = $win->insertch( $count )

Insert C<$count> blank characters, moving subsequent ones to the right. Note
this can only be achieved if the window extends all the way to the righthand
edge of the terminal, or else the operation would corrupt further windows
beyond it.

If this window does not extend to the righthand edge, then this method will
simply return false. If it does, the characters are inserted and the method
returns true.

=cut

sub insertch
{
   my $self = shift;
   my ( $count ) = @_;

   return 0 unless $self->left + $self->cols == $self->term->cols;

   $self->term->setpen( bg => $self->get_effective_pen( 'bg' ) );
   $self->term->insertch( $count );
   return 1;
}

=head2 $success = $win->deletech( $count )

Delete C<$count> characters, moving subsequent ones to the left, and inserting
blanks at the end of the line. Note this can only be achieved if the window
extends all the way to the righthand edge of the terminal, or else the
operation would corrupt further windows beyond it.

If this window does not extend to the righthand edge, then this method will
simply return false. If it does, the characters are inserted and the method
returns true.

=cut

sub deletech
{
   my $self = shift;
   my ( $count ) = @_;

   return 0 unless $self->left + $self->cols == $self->term->cols;

   $self->term->setpen( bg => $self->get_effective_pen( 'bg' ) );
   $self->term->deletech( $count );
   return 1;
}

=head2 $win->scroll( $downward, $rightward )

Attempt to scroll the contents of the window in the given direction. Most
terminals cannot scroll arbitrary regions. If the terminal does not support
the type of scrolling requested, this method returns false to indicate that
the caller should instead redraw the required contents. If the scrolling was
sucessful, the method returns true.

=cut

sub scroll
{
   my $self = shift;
   my ( $downward, $rightward ) = @_;

   return $self->root->scroll_region(
      $self->abs_top,
      $self->abs_left,
      $self->lines,
      $self->cols,
      $downward,
      $rightward
   );
}

=head2 $win->focus( $line, $col )

Put the cursor at the given position in this window. Ensures the cursor
remains at this position after drawing.

=cut

sub focus
{
   my $self = shift;
   my ( $line, $col ) = @_;

   $self->{focus_line} = $line;
   $self->{focus_col}  = $col;

   $self->_requeue_focus( $self );
}

sub _requeue_focus
{
   my $self = shift;
   my ( $focuswin ) = @_;
   $self->parent->_requeue_focus( $focuswin );
}

sub _gain_focus
{
   my $self = shift;

   $self->term->setpen( $self->get_effective_pen );
   $self->goto( $self->{focus_line}, $self->{focus_col} );
}

sub _lose_focus
{
   my $self = shift;

   undef $self->{focus_line};
   undef $self->{focus_col};
}

=head2 $win->clear

Erase the entire content of the window and reset it to the current background
colour.

=cut

sub clear
{
   my $self = shift;

   foreach my $line ( 0 .. $self->lines - 1 ) {
      $self->goto( $line, 0 );
      $self->erasech( $self->cols );
   }
}

sub _flush_line
{
   my $self = shift;
   my ( $line, $term, $athome ) = @_;

   my $lineupdates = delete $self->{updates}[$line] or return;

   foreach my $col ( 0 .. $#$lineupdates ) {
      my $update = $lineupdates->[$col] or next;
      my ( $code, $penattrs ) = @$update;

      $term->goto( $self->abs_top + $line, $self->abs_left + $col ) if !$athome or $col > 0;
      $term->setpen( map { $_ => $penattrs->{$_} } qw( fg bg b u i ) );
      $code->( $term );
   }
}

use overload '""' => sub {
   my $self = shift;
   return sprintf "%s[%dx%d abs@%d,%d]",
      ref $self,
      $self->cols, $self->lines, $self->abs_left, $self->abs_top;
};

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
