#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2013-2014 -- leonerd@leonerd.org.uk

package Tickit::RenderBuffer;

use strict;
use warnings;
use feature qw( switch );
no if $] >= 5.017011, warnings => 'experimental::smartmatch';

our $VERSION = '0.47';

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


=head1 NAME

C<Tickit::RenderBuffer> - efficiently render text and line-drawing

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

Provides a buffer of pending rendering operations to apply to the terminal.
The buffer is modified by rendering operations performed by widgets or other
code, and flushed to the terminal when complete.

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

=item *

A single buffer can be passed around all of the windows or widgets to properly
combine line segments and layering effects, making it possible to create many
kinds of sub-divided or layered output.

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
the terminal.

Clipping rectangles cumulative; each call further restricts the drawing
region. To revert back to a larger drawing area, use the C<save> and
C<restore> stack.

=cut

=head2 $rb->mask( $rect )

Masks off the given area against any further changes. This will apply to
subsequent rendering operations but does not affect the existing content, nor
the actual rendering to the terminal.

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
here, nor will any content existing on the terminal be erased.

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

=cut

=head2 $rb->char( $codepoint, $pen )

Sets the cell at the virtual cursor position to render the given Unicode
character (as given by codepoint number, not character string) in the given
pen, and updates the position.

While this is also achieveable by the C<text> and C<text_at> methods, these
methods are implemented without storing a text segment, so can be more
efficient than many single-column wide C<text_at> calls.

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

   my ( $text, $pen, $north, $south, $east, $west ) = $self->_xs_get_cell( $line, $col );

   if( !defined $text ) {
      # SKIP
      return Cell( undef, undef, undef );
   }
   if( !length $text ) {
      # ERASE
      return Cell( 0, undef, $pen );
   }
   if( !defined $north ) {
      # TEXT or CHAR
      return Cell( ord $text, undef, $pen );
   }
   else {
      # LINE
      return Cell( 0, LineMask( $north, $south, $east, $west ), $pen );
   }
}

=head2 $rb->flush_to_window( $win )

Renders the stored content to the given L<Tickit::Window>. After this, the
buffer will be cleared and reset back to initial state.

Flushing to the window is now deprecated. Widgets should render to the
renderbuffer given to their C<render_to_rb> method. Applications that wish to
perform lower-level drawing without Widgets or Windows should construct a
renderbuffer and use the C<flush_to_term> method.

=head2 $rb->flush_to_term( $term )

Renders the stored content to the given L<Tickit::Term>. After this, the
buffer will be cleared and reset back to initial state.

=cut

sub flush_to_window
{
   my $self = shift;
   my ( $target ) = @_;

   foreach my $line ( 0 .. $self->lines-1 ) {
      my $phycol;

      for ( my $col = 0; $col < $self->cols ; ) {
         my ( $len, $text, $pen ) = $self->_xs_get_span( $line, $col );

         $col += $len, next if !defined $text; # SKIP

         if( !defined $phycol or $phycol < $col ) {
            $target->goto( $line, $col );
         }
         $phycol = $col;

         if( length $text ) {
            # TEXT, LINE, CHAR
            $target->print( $text, $pen );
            $phycol += $len;
         }
         else {
            # ERASE
            # No need to set moveend=true to erasech unless we actually
            # have more content;
            my $moveend = $col + $len < $self->cols &&
                          defined +( $self->_xs_get_span( $line, $col + $len ) )[1];

            $target->erasech( $len, $moveend || undef, $pen );
            $phycol += $len;
            undef $phycol unless $moveend;
         }

         $col += $len;
      }
   }

   $self->reset;
}

=head2 $rb->flush_to_term( $term )

Renders the stored content to the given L<Tickit::Term>. After this, the
buffer will be cleared and reset back to initial state.

=cut

## Tickit::Debug wrapping support
use Tickit::Debug;

if( Tickit::Debug::DEBUG ) {
   local *around = sub {
      my ( $method, $code ) = @_;

      my $orig = __PACKAGE__->can( $method ) or croak __PACKAGE__." cannot ->$method";

      no strict 'refs';
      no warnings 'redefine';
      *$method = sub { $code->( $orig, @_ ) };
   };

   my $INDENT = "";
   *lg = sub {
      Tickit::Debug->log( $_[0], "${INDENT}$_[1]", @_[2..$#_] );
   };

   # Bs == stack
   around( save => sub {
      my $orig = shift;
      lg( Bs => "+-Save" );
      $INDENT = "|  $INDENT";
      $orig->( @_ );
   });
   around( savepen => sub {
      my $orig = shift;
      lg( Bs => "+-Savepen" );
      $INDENT = "|  $INDENT";
      $orig->( @_ );
   });
   around( restore => sub {
      my $orig = shift;
      $INDENT =~ s/^\|  //;
      lg( Bs => "+-Restore" );
      $orig->( @_ );
   });
   around( reset => sub {
      my $orig = shift;
      $INDENT = "";
      $orig->( @_ );
   });

   # Bd == drawing operations
   around( clear => sub {
      my $orig = shift;
      lg( Bd => "Clear" );
      $orig->( @_ );
   });

   around( skip => sub {
      my $orig = shift;
      my ( $rb, $len ) = @_;
      lg( Bd => "Skip (%d..%d,%d) +%d", sub { $rb->col, $rb->col + $len, $rb->line, $len } );
      $orig->( @_ );
   });
   around( skip_at => sub {
      my $orig = shift;
      my ( $rb, $line, $col, $len ) = @_;
      lg( Bd => "Skip (%d..%d,%d)", sub { $line, $col, $col + $len, $line } );
      $orig->( @_ );
   });
   around( skip_to => sub {
      my $orig = shift;
      my ( $rb, $col ) = @_;
      lg( Bd => "Skip (%d..%d,%d) +%d", sub { $rb->col, $col, $rb->line, $col - $rb->col } ) if $col > $rb->col;
      $orig->( @_ );
   });

   around( erase => sub {
      my $orig = shift;
      my ( $rb, $len ) = @_;
      lg( Bd => "Erase (%d..%d,%d) +%d", sub { $rb->col, $rb->col + $len, $rb->line, $len } );
      $orig->( @_ );
   });
   around( erase_at => sub {
      my $orig = shift;
      my ( $rb, $line, $col, $len ) = @_;
      lg( Bd => "Erase (%d..%d,%d)", sub { $col, $col + $len, $line } );
      $orig->( @_ );
   });
   around( erase_to => sub {
      my $orig = shift;
      my ( $rb, $col ) = @_;
      lg( Bd => "Erase (%d..%d,%d) +%d", sub { $rb->col, $col, $rb->line, $col - $rb->col } ) if $col > $rb->col;
      $orig->( @_ );
   });
   around( eraserect => sub {
      my $orig = shift;
      my ( $rb, $rect ) = @_;
      lg( Bd => "Erase (%d,%d)..(%d,%d)", sub { $rect->left, $rect->top, $rect->right, $rect->bottom } );
      $orig->( @_ );
   });

   around( text => sub {
      my $orig = shift;
      my ( $rb ) = @_;
      my $col = $rb->col;
      my $len = $orig->( @_ );
      lg( Bd => "Text (%d..%d,%d) +%d", sub { $col, $col + $len, $rb->line, $len } );
      return $len;
   });
   around( text_at => sub {
      my $orig = shift;
      my ( $rb, $line, $col ) = @_;
      my $len = $orig->( @_ );
      lg( Bd => "Text (%d..%d,%d)", sub { $col, $col + $len, $line } );
      return $len;
   });

   around( char => sub {
      my $orig = shift;
      my ( $rb ) = @_;
      lg( Bd => "Char (%d..%d,%d) +%d", sub { $rb->col, $rb->col + 1, $rb->line, 1 } );
      $orig->( @_ );
   });
   around( char_at => sub {
      my $orig = shift;
      my ( $rb, $line, $col ) = @_;
      lg( Bd => "Char (%d..%d,%d)", sub { $col, $col + 1, $line } );
      $orig->( @_ );
   });

   around( hline_at => sub {
      my $orig = shift;
      my ( $rb, $line, $startcol, $endcol ) = @_;
      lg( Bd => "HLine (%d..%d,%d)", $startcol, $endcol, $line );
      $orig->( @_ );
   });
   around( vline_at => sub {
      my $orig = shift;
      my ( $rb, $startline, $endline, $col ) = @_;
      lg( Bd => "VLine (%d,%d..%d)", $col, $startline, $endline );
      $orig->( @_ );
   });

   # Bf == flush
   around( flush_to_term => sub {
      my $orig = shift;
      $INDENT = "";
      lg( Bf => "Flush" );
      $orig->( @_ );
   });

   # Bt == transformations (translate, clip, mask)
   around( translate => sub {
      my $orig = shift;
      my ( $rb, $downward, $rightward ) = @_;
      lg( Bt => "Translate (+%d,+%d)", $rightward, $downward );
      $orig->( @_ );
   });
   around( clip => sub {
      my $orig = shift;
      my ( $rb, $rect ) = @_;
      lg( Bd => "Clip (%d,%d)..(%d,%d)", sub { $rect->left, $rect->top, $rect->right, $rect->bottom } );
      $orig->( @_ );
   });
   around( mask => sub {
      my $orig = shift;
      my ( $rb, $rect ) = @_;
      lg( Bd => "Mask (%d,%d)..(%d,%d)", sub { $rect->left, $rect->top, $rect->right, $rect->bottom } );
      $orig->( @_ );
   });
}

undef *around; # delete it as a method

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
