#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2013-2014 -- leonerd@leonerd.org.uk

package Tickit::RenderBuffer;

use strict;
use warnings;
use feature qw( switch );
no if $] >= 5.017011, warnings => 'experimental::smartmatch';

our $VERSION = '0.44';

use Carp;
use Scalar::Util qw( refaddr );

# Load the XS code
require Tickit;

use Tickit::Utils qw( textwidth );
use Tickit::Rect;
use Tickit::Pen 0.31;

use Struct::Dumb qw( readonly_struct );

# Exported API constants
use Exporter 'import';
our @EXPORT_OK = qw(
   LINE_SINGLE LINE_DOUBLE LINE_THICK
   CAP_START CAP_END CAP_BOTH
);
use constant {
   LINE_SINGLE => 0x01,
   LINE_DOUBLE => 0x02,
   LINE_THICK  => 0x03,
};
use constant {
   CAP_START => 0x01,
   CAP_END   => 0x02,
   CAP_BOTH  => 0x03,
};

# cell states
use constant {
   SKIP  => 0,
   TEXT  => 1,
   ERASE => 2,
   CONT  => 3,
   LINE  => 4,
   CHAR  => 5,
};

=head1 NAME

C<Tickit::RenderBuffer> - efficiently render text and linedrawing on
L<Tickit> windows

=head1 SYNOPSIS

 package Tickit::Widget::Something;
 ...

 sub render_to_rb
 {
    my $self = shift;
    my ( $rb, $rect ) = @_;

    $rb->eraserect( $rect );
    $rb->text_at( 2, 2, "Hello, world!", $self->pen );
 }

Z<>

 $win->set_on_expose( with_rb => sub {
    my ( $win, $rb, $rect ) = @_;

    $rb->eraserect( $rect );
    $rb->text_at( 2, 2, "Hello, world!" );
 });

=head1 DESCRIPTION

Provides a buffer of pending rendering operations to apply to a Window. The
buffer is modified by rendering operations performed by the widget, and
flushed to the widget's window when complete.

This provides the following advantages:

=over 2

=item *

Changes can be made in any order, and will be flushed in top-to-bottom,
left-to-right order, minimising cursor movements.

=item *

Buffered content can be overwritten or partly erased once stored, simplifying
some styles of drawing operation. Large areas can be erased, and then redrawn
with text or lines, without causing a double-drawing flicker on the output
terminal.

=item *

The buffer supports line-drawing, complete with merging of line segments that
meet in a character cell. Boxes, grids, and other shapes can be easily formed
by drawing separate line segments, and the C<RenderBuffer> will handle the
corners and other junctions formed.

=back

Drawing methods come in two forms; absolute, and cursor-relative:

=over 2

=item *

Absolute methods, identified by their name having a suffixed C<_at>, operate
on a position within the buffer specified by their argument.

=item *

Cursor-relative methods, identified by their lack of C<_at> suffix, operate at
and update the position of the "virtual cursor". This is a position within the
buffer that can be set using the C<goto> method. The position of the virtual
cursor is not affected by the absolute-position methods.

=back

=head2 State Stack

The C<RenderBuffer> stores a stack of saved state. The state of the buffer can
be stored using the C<save> method, so that changes can be made, before
finally restoring back to that state using C<restore>. The following items of
state are saved:

=over 2

=item *

The virtual cursor position

=item *

The clipping rectangle

=item *

The render pen

=item *

The translation offset

=item *

The set of masked regions

=back

When the state is saved to the stack, the render pen is remembered and merged
with any pen set using the C<setpen> method.

The queued content to render is not part of the state stack. It is intended
that the state stack be used to implement recursive delegation of drawing
operations down a tree of code, allowing child contexts to be created by
saving state and modifying it, to later restore it again afterwards.

=cut

=head1 CONSTRUCTOR

=cut

=head2 $rb = Tickit::RenderBuffer->new( %args )

Returns a new instance of a C<Tickit::RenderBuffer>.

Takes the following named arguments:

=over 8

=item lines => INT

=item cols => INT

The size of the buffer area.

=back

=cut

sub new
{
   my $class = shift;
   my %args = @_;

   my $lines = $args{lines};
   my $cols  = $args{cols};

   return $class->_xs_new( $lines, $cols );
}

=head1 METHODS

=cut

=head2 $lines = $rb->lines

=head2 $cols = $rb->cols

Returns the size of the buffer area

=cut

=head2 $line = $rb->line

=head2 $col = $rb->col

Returns the current position of the virtual cursor, or C<undef> if it is not
set.

=cut

=head2 $rb->save

Pushes a new state-saving context to the stack, which can later be returned to
by the C<restore> method.

=cut

=head2 $rb->savepen

Pushes a new state-saving context to the stack that only stores the pen. This
can later be returned to by the C<restore> method, but will only restore the
pen. Other attributes such as the virtual cursor position will be unaffected.

This may be more efficient for rendering runs of text in a different pen, than
multiple calls to C<text> or C<erase> using the same pen. For a single call it
is better just to pass a different pen directly.

=cut

=head2 $rb->restore

Pops and restores a saved state previously created with C<save>.

=cut

=head2 $rb->clip( $rect )

Restricts the clipping rectangle of drawing operations to be no further than
the limits of the given rectangle. This will apply to subsequent rendering
operations but does not affect existing content, nor the actual rendering to
the window.

Clipping rectangles cumulative; each call further restricts the drawing
region. To revert back to a larger drawing area, use the C<save> and
C<restore> stack.

=cut

=head2 $rb->mask( $rect )

Masks off the given area against any further changes. This will apply to
subsequent rendering operations but does not affect the existing content, nor
the actual rendering to the window.

Areas within the clipping region may be arbitrarily masked. Masks are scoped
to the depth of the stack they are applied at; once the C<restore> method is
invoked, any masks applied since its corresponding C<save> will be removed.

=head2 $rb->translate( $downward, $rightward )

Applies a translation to the coordinate system used by C<goto> and the
absolute-position methods C<*_at>. After this call, all positions used will be
offset by the given amount.

=cut

=head2 $rb->reset

Removes any pending changes and reverts the C<RenderBuffer> to its default
empty state. Undefines the virtual cursor position, resets the clipping
rectangle, and clears the stack of saved state.

=cut

=head2 $rb->clear( $pen )

Resets every cell in the buffer to an erased state. 
A shortcut to calling C<erase_at> for every line.

=cut

=head2 $rb->goto( $line, $col )

Sets the position of the virtual cursor.

=cut

=head2 $rb->setpen( $pen )

Sets the rendering pen to use for drawing operations. If a pen is set then a
C<$pen> argument is optional to any of the drawing methods. If a pen argument
is supplied as well as having a stored pen, then the attributes are merged,
with the directly-applied pen taking precedence.

Successive calls to this method will replace the active pen used, but if there
is a saved state on the stack it will be merged with the rendering pen of the
most recent saved state.

This method may be preferrable to passing pens into multiple C<text> or
C<erase> calls as it may be more efficient than merging the same pen on every
call. If the original pen is still required afterwards, the C<savepen> /
C<restore> pair may be useful.

=cut

=head2 $rb->skip_at( $line, $col, $len )

Sets the range of cells given to a skipped state. No content will be drawn
here, nor will any content existing on the window be erased.

Initially, or after calling C<reset>, all cells are set to this state.

=cut

=head2 $rb->skip( $len )

Sets the range of cells at the virtual cursor position to a skipped state, and
updates the position.

=cut

=head2 $rb->skip_to( $col )

Sets the range of cells from the virtual cursor position until before the
given column to a skipped state, and updates the position to the column.

If the position is already past this column then the cursor is moved backwards
and no buffer changes are made.

=cut

=head2 $cols = $rb->text_at( $line, $col, $text, $pen )

Sets the range of cells starting at the given position, to render the given
text in the given pen.

Returns the number of columns wide the actual C<$text> is (which may be more
than was actually printed).

=cut

=head2 $cols = $rb->text( $text, $pen )

Sets the range of cells at the virtual cursor position to render the given
text in the given pen, and updates the position.

Returns the number of columns wide the actual C<$text> is (which may be more
than was actually printed).

=cut

=head2 $rb->erase_at( $line, $col, $len, $pen )

Sets the range of cells given to erase with the given pen.

=cut

=head2 $rb->erase( $len, $pen )

Sets the range of cells at the virtual cursor position to erase with the given
pen, and updates the position.

=cut

=head2 $rb->erase_to( $col, $pen )

Sets the range of cells from the virtual cursor position until before the
given column to erase with the given pen, and updates the position to the
column.

If the position is already past this column then the cursor is moved backwards
and no buffer changes are made.

=cut

=head2 $rb->eraserect( $rect, $pen )

Sets the range of cells given by the rectangle to erase with the given pen.

=cut

=head1 LINE DRAWING

The C<RenderBuffer> supports storing line-drawing characters in cells, and can
merge line segments where they meet, attempting to draw the correct character
for the segments that meet in each cell.

There are three exported constants giving supported styles of line drawing:

=over 4

=item * LINE_SINGLE

A single, thin line

=item * LINE_DOUBLE

A pair of double, thin lines

=item * LINE_THICK

A single, thick line

=back

Note that linedrawing is performed by Unicode characters, and not every
possible combination of line segments of differing styles meeting in a cell is
supported by Unicode. The following sets of styles may be relied upon:

=over 4

=item *

Any possible combination of only C<SINGLE> segments, C<THICK> segments, or
both.

=item *

Any combination of only C<DOUBLE> segments, except cells that only have one of
the four borders occupied.

=item *

Any combination of C<SINGLE> and C<DOUBLE> segments except where the style
changes between C<SINGLE> to C<DOUBLE> on a vertical or horizontal run.

=back

Other combinations are not directly supported (i.e. any combination of
C<DOUBLE> and C<THICK> in the same cell, or any attempt to change from
C<SINGLE> to C<DOUBLE> in either the vertical or horizontal direction). To
handle these cases, a cell may be rendered with a substitution character which
replaces a C<DOUBLE> or C<THICK> segment with a C<SINGLE> one within that
cell. The effect will be the overall shape of the line is retained, but close
to the edge or corner it will have the wrong segment type.

Conceptually, every cell involved in line drawing has a potential line segment
type at each of its four borders to its neighbours. Horizontal lines are drawn
though the vertical centre of each cell, and vertical lines are drawn through
the horizontal centre.

There is a choice of how to handle the ends of line segments, as to whether
the segment should go to the centre of each cell, or should continue through
the entire body of the cell and stop at the boundary. By default line segments
will start and end at the centre of the cells, so that horizontal and vertical
lines meeting in a cell will form a neat corner. When drawing isolated lines
such as horizontal or vertical rules, it is preferrable that the line go right
through the cells at the start and end. To control this behaviour, the
C<$caps> bitmask is used. C<CAP_START> and C<CAP_END> state that the line
should consume the whole of the start or end cell, respectively; C<CAP_BOTH>
is a convenient shortcut specifying both behaviours.

A rectangle may be formed by combining two C<hline_at> and two C<vline_at>
calls, without end caps:

 $rb->hline_at( $top,    $left, $right, $style, $pen );
 $rb->hline_at( $bottom, $left, $right, $style, $pen );
 $rb->vline_at( $top, $bottom, $left,  $style, $pen );
 $rb->vline_at( $top, $bottom, $right, $style, $pen );

=cut

# Various parts of this code borrowed from Tom Molesworth's Tickit::Canvas

# Bitmasks on Cell linemask
use constant {
   # Connections to the next cell upwards
   NORTH        => 0x03,
   NORTH_SINGLE => 0x01,
   NORTH_DOUBLE => 0x02,
   NORTH_THICK  => 0x03,
   NORTH_SHIFT  => 0,

   # Connections to the next cell to the right
   EAST         => 0x0C,
   EAST_SINGLE  => 0x04,
   EAST_DOUBLE  => 0x08,
   EAST_THICK   => 0x0C,
   EAST_SHIFT   => 2,

   # Connections to the next cell downwards
   SOUTH        => 0x30,
   SOUTH_SINGLE => 0x10,
   SOUTH_DOUBLE => 0x20,
   SOUTH_THICK  => 0x30,
   SOUTH_SHIFT  => 4,

   # Connections to the next cell to the left
   WEST         => 0xC0,
   WEST_SINGLE  => 0x40,
   WEST_DOUBLE  => 0x80,
   WEST_THICK   => 0xC0,
   WEST_SHIFT   => 6,
};

my @linechars;
{
   local $_;
   while( <DATA> ) {
      chomp;
      my ( $char, $spec ) = split( m/\s+=>\s+/, $_, 2 );

      my $mask = 0;
      $mask |= __PACKAGE__->$_ for $spec =~ m/([A-Z_]+)/g;

      $linechars[$mask] = $char;
   }

   close DATA;

   # Fill in the gaps
   foreach my $mask ( 1 .. 255 ) {
      next if defined $linechars[$mask];

      # Try with SINGLE instead of THICK, so mask away 0xAA
      if( my $char = $linechars[$mask & 0xAA] ) {
         $linechars[$mask] = $char;
         next;
      }

      # The only ones left now are awkward mixes of single/double
      # Turn DOUBLE into SINGLE
      my $singlemask = $mask;
      foreach my $dir (qw( NORTH EAST SOUTH WEST )) {
         my $dirmask = __PACKAGE__->$dir;
         my $dirshift = __PACKAGE__->${\"${dir}_SHIFT"};

         my $dirsingle = LINE_SINGLE << $dirshift;
         my $dirdouble = LINE_DOUBLE << $dirshift;

         $singlemask = ( $singlemask & ~$dirmask ) | $dirsingle
            if ( $singlemask & $dirmask ) == $dirdouble;
      }

      if( my $char = $linechars[$singlemask] ) {
         $linechars[$mask] = $char;
         next;
      }

      die sprintf "TODO: Couldn't find a linechar for %02x\n", $mask;
   }
}

=head2 $rb->hline_at( $line, $startcol, $endcol, $style, $pen, $caps )

Draws a horizontal line between the given columns (both are inclusive), in the
given line style, with the given pen.

=cut

=head2 $rb->vline_at( $startline, $endline, $col, $style, $pen, $caps )

Draws a vertical line between the centres of the given lines (both are
inclusive), in the given line style, with the given pen.

=cut

=head2 $rb->linebox_at( $startline, $endline, $startcol, $endcol, $style, $pen )

A convenient shortcut to calling two C<hline_at> and two C<vline_at> in order
to draw a rectangular box.

=cut

sub linebox_at
{
   my $self = shift;
   my ( $startline, $endline, $startcol, $endcol, $style, $pen ) = @_;

   $self->hline_at( $startline, $startcol, $endcol, $style, $pen );
   $self->hline_at( $endline,   $startcol, $endcol, $style, $pen );

   $self->vline_at( $startline, $endline, $startcol, $style, $pen );
   $self->vline_at( $startline, $endline, $endcol,   $style, $pen );
}

=head2 $rb->char_at( $line, $col, $codepoint, $pen )

Sets the given cell to render the given Unicode character (as given by
codepoint number, not character string) in the given pen.

While this is also achieveable by the C<text_at> method, this method is
implemented without storing a text segment, so can be more efficient than many
single-column wide C<text_at> calls. It will also be more efficient in the C
library rewrite.

=cut

=head2 $cell = $rb->get_cell( $line, $col )

Returns a structure containing the content stored in the given cell. The
C<$cell> structure responds to the following methods:

=over 4

=item $cell->char

On a skipped cell, returns C<undef>. On a text or char cell, returns the
unicode codepoint number. On a line or erased cell, returns 0.

=item $cell->linemask

On a line cell, returns a representation of the line segments in the cell.
This is a sub-structure with four fields; C<north>, C<south>, C<east>, C<west>
to represent the four cell borders; the value of each is either zero, or one
of the C<LINE_> constants.

On any other kind of cell, returns C<undef>.

=item $cell->pen

Returns the C<Tickit::Pen> for non-skipped cells, or C<undef> for skipped
cells.

=back

=cut

readonly_struct Cell => [qw( char linemask pen )];
readonly_struct LineMask => [qw( north south east west )];

sub get_cell
{
   my $self = shift;
   my ( $line, $col ) = @_;

   my $offs = 0;
   my $xscell;
   while(1) {
      $xscell = $self->_xs_getcell( $line, $col );
      last unless $xscell->state == CONT;

      my $startcol = $xscell->startcol;
      $offs = $col - $startcol;
      $col = $startcol;
   }

   given( $xscell->state ) {
      when( SKIP ) {
         return Cell( undef, undef, undef );
      }
      when( TEXT ) {
         my $text = $self->_xs_get_text_substr( $xscell->textidx, $xscell->textoffs + $offs, 1 );
         return Cell( ord $text, undef, $xscell->pen );
      }
      when( CHAR ) {
         return Cell( $xscell->codepoint, undef, $xscell->pen );
      }
      when( ERASE ) {
         return Cell( 0, undef, $xscell->pen );
      }
      when( LINE ) {
         my $bits = $xscell->linemask;
         my $mask = LineMask(
            ( $bits & NORTH ) >> NORTH_SHIFT,
            ( $bits & SOUTH ) >> SOUTH_SHIFT,
            ( $bits & EAST  ) >> EAST_SHIFT,
            ( $bits & WEST  ) >> WEST_SHIFT,
         );
         return Cell( 0, $mask, $xscell->pen );
      }
      # No CONT
   }
}

=head2 $rb->flush_to_window( $win )

Renders the stored content to the given L<Tickit::Window>. After this, the
buffer will be cleared and reset back to initial state.

=head2 $rb->flush_to_term( $term )

Renders the stored content to the given L<Tickit::Term>. After this, the
buffer will be cleared and reset back to initial state.

=cut

sub flush_to_window
{
   my $self = shift;
   my ( $win ) = @_;
   $self->_flush( win => $win );
}

sub flush_to_term
{
   my $self = shift;
   my ( $term ) = @_;
   $self->_flush( term => $term );
}

sub _flush
{
   my $self = shift;
   my ( $type, $target ) = @_;

   foreach my $line ( 0 .. $self->lines-1 ) {
      my $phycol;

      for ( my $col = 0; $col < $self->cols ; ) {
         my $cell = $self->_xs_getcell( $line, $col );

         $col += $cell->len, next if $cell->state == SKIP;

         if( !defined $phycol or $phycol < $col ) {
            $target->goto( $line, $col );
         }
         $phycol = $col;

         given( $cell->state ) {
            when( TEXT ) {
               $target->print( $self->_xs_get_text_substr( $cell->textidx, $cell->textoffs, $cell->len ), $cell->pen );
               $phycol += $cell->len;
            }
            when( ERASE ) {
               # No need to set moveend=true to erasech unless we actually
               # have more content;
               my $moveend = $col + $cell->len < $self->cols &&
                             $self->_xs_getcell( $line, $col + $cell->len )->state != SKIP;

               $target->erasech( $cell->len, $moveend || undef, $cell->pen );
               $phycol += $cell->len;
               undef $phycol unless $moveend;
            }
            when( LINE ) {
               # This is more efficient and works better with unit testing in
               # the Perl case but in the C version this is easier just done a
               # cell at a time
               my $pen = $cell->pen;
               my $chars = "";
               do {
                  $chars .= $linechars[$cell->linemask];
                  $col++;
                  $phycol += $cell->len;
               } while( $col < $self->cols and
                        $cell = $self->_xs_getcell( $line, $col ) and
                        $cell->state == LINE and
                        $cell->pen->equiv( $pen ) );

               $target->print( $chars, $pen );

               next;
            }
            when( CHAR ) {
               $target->print( chr $cell->codepoint, $cell->pen );
               $phycol += $cell->len;
            }
            default {
               die "TODO: cell in state ". $cell->state;
            }
         }

         $col += $cell->len;
      }
   }

   $self->reset;
}

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;

use utf8;
__DATA__
─ => WEST_SINGLE | EAST_SINGLE
━ => WEST_THICK | EAST_THICK
│ => NORTH_SINGLE | SOUTH_SINGLE
┃ => NORTH_THICK | SOUTH_THICK
┌ => SOUTH_SINGLE | EAST_SINGLE
┍ => SOUTH_SINGLE | EAST_THICK
┎ => SOUTH_THICK | EAST_SINGLE
┏ => SOUTH_THICK | EAST_THICK
┐ => SOUTH_SINGLE | WEST_SINGLE
┑ => SOUTH_SINGLE | WEST_THICK
┒ => SOUTH_THICK | WEST_SINGLE
┓ => SOUTH_THICK | WEST_THICK
└ => NORTH_SINGLE | EAST_SINGLE
┕ => NORTH_SINGLE | EAST_THICK
┖ => NORTH_THICK | EAST_SINGLE
┗ => NORTH_THICK | EAST_THICK
┘ => NORTH_SINGLE | WEST_SINGLE
┙ => NORTH_SINGLE | WEST_THICK
┚ => NORTH_THICK | WEST_SINGLE
┛ => NORTH_THICK | WEST_THICK
├ => NORTH_SINGLE | EAST_SINGLE | SOUTH_SINGLE
┝ => NORTH_SINGLE | SOUTH_SINGLE | EAST_THICK
┞ => NORTH_THICK | EAST_SINGLE | SOUTH_SINGLE
┟ => NORTH_SINGLE | EAST_SINGLE | SOUTH_THICK
┠ => NORTH_THICK | EAST_SINGLE | SOUTH_THICK
┡ => NORTH_THICK | EAST_THICK | SOUTH_SINGLE
┢ => NORTH_SINGLE | EAST_THICK | SOUTH_THICK
┣ => NORTH_THICK | EAST_THICK | SOUTH_THICK
┤ => NORTH_SINGLE | WEST_SINGLE | SOUTH_SINGLE
┥ => NORTH_SINGLE | SOUTH_SINGLE | WEST_THICK
┦ => WEST_SINGLE | NORTH_THICK | SOUTH_SINGLE
┧ => NORTH_SINGLE | WEST_SINGLE | SOUTH_THICK
┨ => WEST_SINGLE | NORTH_THICK | SOUTH_THICK
┩ => WEST_THICK | NORTH_THICK | SOUTH_SINGLE
┪ => WEST_THICK | NORTH_SINGLE | SOUTH_THICK
┫ => WEST_THICK | NORTH_THICK | SOUTH_THICK
┬ => WEST_SINGLE | SOUTH_SINGLE | EAST_SINGLE
┭ => WEST_THICK | SOUTH_SINGLE | EAST_SINGLE
┮ => WEST_SINGLE | SOUTH_SINGLE | EAST_THICK
┯ => WEST_THICK | SOUTH_SINGLE | EAST_THICK
┰ => WEST_SINGLE | SOUTH_THICK | EAST_SINGLE
┱ => WEST_THICK | SOUTH_THICK | EAST_SINGLE
┲ => WEST_SINGLE | SOUTH_THICK | EAST_THICK
┳ => WEST_THICK | SOUTH_THICK | EAST_THICK
┴ => WEST_SINGLE | NORTH_SINGLE | EAST_SINGLE
┵ => WEST_THICK | NORTH_SINGLE | EAST_SINGLE
┶ => WEST_SINGLE | NORTH_SINGLE | EAST_THICK
┷ => WEST_THICK | NORTH_SINGLE | EAST_THICK
┸ => WEST_SINGLE | NORTH_THICK | EAST_SINGLE
┹ => WEST_THICK | NORTH_THICK | EAST_SINGLE
┺ => WEST_SINGLE | NORTH_THICK | EAST_THICK
┻ => WEST_THICK | NORTH_THICK | EAST_THICK
┼ => WEST_SINGLE | NORTH_SINGLE | EAST_SINGLE | SOUTH_SINGLE
┽ => WEST_THICK | NORTH_SINGLE | EAST_SINGLE | SOUTH_SINGLE
┾ => WEST_SINGLE | NORTH_SINGLE | EAST_THICK | SOUTH_SINGLE
┿ => WEST_THICK | NORTH_SINGLE | EAST_THICK | SOUTH_SINGLE
╀ => WEST_SINGLE | NORTH_THICK | EAST_SINGLE | SOUTH_SINGLE
╁ => WEST_SINGLE | NORTH_SINGLE | EAST_SINGLE | SOUTH_THICK
╂ => WEST_SINGLE | NORTH_THICK | EAST_SINGLE | SOUTH_THICK
╃ => WEST_THICK | NORTH_THICK | EAST_SINGLE | SOUTH_SINGLE
╄ => WEST_SINGLE | NORTH_THICK | EAST_THICK | SOUTH_SINGLE
╅ => WEST_THICK | NORTH_SINGLE | EAST_SINGLE | SOUTH_THICK
╆ => WEST_SINGLE | NORTH_SINGLE | EAST_THICK | SOUTH_THICK
╇ => WEST_THICK | NORTH_THICK | EAST_THICK | SOUTH_SINGLE
╈ => WEST_THICK | NORTH_SINGLE | EAST_THICK | SOUTH_THICK
╉ => WEST_THICK | NORTH_THICK | EAST_SINGLE | SOUTH_THICK
╊ => WEST_SINGLE | NORTH_THICK | EAST_THICK | SOUTH_THICK
╋ => WEST_THICK | NORTH_THICK | EAST_THICK | SOUTH_THICK
═ => WEST_DOUBLE | EAST_DOUBLE
║ => NORTH_DOUBLE | SOUTH_DOUBLE
╒ => EAST_DOUBLE | SOUTH_SINGLE
╓ => EAST_SINGLE | SOUTH_DOUBLE
╔ => SOUTH_DOUBLE | EAST_DOUBLE
╕ => WEST_DOUBLE | SOUTH_SINGLE
╖ => WEST_SINGLE | SOUTH_DOUBLE
╗ => WEST_DOUBLE | SOUTH_DOUBLE
╘ => NORTH_SINGLE | EAST_DOUBLE
╙ => NORTH_DOUBLE | EAST_SINGLE
╚ => NORTH_DOUBLE | EAST_DOUBLE
╛ => WEST_DOUBLE | NORTH_SINGLE
╜ => WEST_SINGLE | NORTH_DOUBLE
╝ => WEST_DOUBLE | NORTH_DOUBLE
╞ => NORTH_SINGLE | EAST_DOUBLE | SOUTH_SINGLE
╟ => NORTH_DOUBLE | EAST_SINGLE | SOUTH_DOUBLE
╠ => NORTH_DOUBLE | EAST_DOUBLE | SOUTH_DOUBLE
╡ => WEST_DOUBLE | NORTH_SINGLE | SOUTH_SINGLE
╢ => WEST_SINGLE | NORTH_DOUBLE | SOUTH_DOUBLE
╣ => WEST_DOUBLE | NORTH_DOUBLE | SOUTH_DOUBLE
╤ => WEST_DOUBLE | SOUTH_SINGLE | EAST_DOUBLE
╥ => WEST_SINGLE | SOUTH_DOUBLE | EAST_SINGLE
╦ => WEST_DOUBLE | SOUTH_DOUBLE | EAST_DOUBLE
╧ => WEST_DOUBLE | NORTH_SINGLE | EAST_DOUBLE
╨ => WEST_SINGLE | NORTH_DOUBLE | EAST_SINGLE
╩ => WEST_DOUBLE | NORTH_DOUBLE | EAST_DOUBLE
╪ => WEST_DOUBLE | NORTH_SINGLE | EAST_DOUBLE | SOUTH_SINGLE
╫ => WEST_SINGLE | NORTH_DOUBLE | EAST_SINGLE | SOUTH_DOUBLE
╬ => WEST_DOUBLE | NORTH_DOUBLE | EAST_DOUBLE | SOUTH_DOUBLE
╴ => WEST_SINGLE
╵ => NORTH_SINGLE
╶ => EAST_SINGLE
╷ => SOUTH_SINGLE
╸ => WEST_THICK
╹ => NORTH_THICK
╺ => EAST_THICK
╻ => SOUTH_THICK
╼ => WEST_SINGLE | EAST_THICK
╽ => NORTH_SINGLE | SOUTH_THICK
╾ => WEST_THICK | EAST_SINGLE
╿ => NORTH_THICK | SOUTH_SINGLE
