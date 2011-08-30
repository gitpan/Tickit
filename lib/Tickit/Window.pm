#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2009-2011 -- leonerd@leonerd.org.uk

package Tickit::Window;

use strict;
use warnings;

our $VERSION = '0.10';

use Carp;

use Scalar::Util qw( weaken );

use Tickit::Pen;

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

   $lines > 0 or croak 'lines zero or negative';
   $cols  > 0 or croak 'cols zero or negative';

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

C<$type> will be C<text> for normal unmodified Unicode, or C<key> for special
keys or modified Unicode. C<$str> will be the UTF-8 string for C<text> events,
or the textual description of the key as rendered by L<Term::TermKey> for
C<key> events. C<$key> will be the underlying C<Term::TermKey::Key> event
structure.

The invoked code should return a true value if it considers the keypress dealt
with, or false to pass it up to its parent window.

Before passing it to its parent, a window will also try any other non-focused
sibling windows of the currently-focused window in order of creation (though
note this order is not necessarily the order the child widgets that own those
windows were created or added to their container).

If no window actually handles the keypress, then every window will eventually
be consulted about it, preferring windows closer to the focused one.

This broadcast-like behaviour allows widgets to handle keypresses that should
make sense even though their window does not actually have the keyboard focus.
This feature should be used sparingly, to only capture one or two keypresses
that really make sense; for example to capture the C<PageUp> and C<PageDown>
keys in a scrolling list, or a numbered function key that performs some
special action.

=cut

sub set_on_key
{
   my $self = shift;
   ( $self->{on_key} ) = @_;
}

sub _handle_key
{
   my $self = shift;

   my $focus_child = $self->{focus_child};
   if( $focus_child ) {
      $focus_child->_handle_key( @_ ) and return 1;
   }

   if( my $on_key = $self->{on_key} ) {
      $on_key->( $self, @_ ) and return 1;
   }

   if( my $children = $self->{child_windows} ) {
      foreach my $child ( @$children ) {
         next unless $child; # weakrefs; may be undef
         next if $focus_child and $child == $focus_child;

         $child->_handle_key( @_ );
      }
   }

   return 0;
}

=head2 $win->set_on_mouse( $on_mouse )

Set the callback to invoke whenever a mouse event is received within the
window's rectangle.

 $handled = $on_mouse->( $win, $ev, $buttons, $line, $col )

C<$ev> will be C<press>, C<drag> or C<release>. The button number will be in
C<$button>, though may not be present for C<release> events. C<$line> and
C<$col> are 0-based. Behaviour of events involving more than one mouse button
is not well-specified by terminals.

The invoked code should return a true value if it considers the mouse event
dealt with, or false to pass it up to its parent window. The mouse event is
passed as defined by L<Tickit::Term>'s C<on_mouse> event, except that the
line and column counts will be relative to the window, not to the screen.

=cut

sub set_on_mouse
{
   my $self = shift;
   ( $self->{on_mouse} ) = @_;
}

sub _handle_mouse
{
   my $self = shift;
   my ( $ev, $button, $line, $col ) = @_;

   if( my $children = $self->{child_windows} ) {
      foreach my $child ( @$children ) {
         next unless $child; # weakrefs; may be undef

         my $child_line = $line - $child->top;
         my $child_col  = $col  - $child->left;

         next if $child_line < 0 or $child_line >= $child->lines;
         next if $child_col  < 0 or $child_col  >= $child->cols;

         return 1 if $child->_handle_mouse( $ev, $button, $child_line, $child_col );
      }
   }

   if( my $on_mouse = $self->{on_mouse} ) {
      return $on_mouse->( $self, $ev, $button, $line, $col );
   }

   return 0;
}

=head2 $win->set_on_expose( $on_expose )

Set the callback to invoke whenever a region of the window is exposed by the
C<expose> event.

 $on_expose->( %args )

Will be passed the following named parameters:

=over 8

=item top => INT

=item left => INT

Position of the top left corner of the exposed region, relative to the window

=item lines => INT

=item cols => INT

Size of the exposed region.

=back

=cut

sub set_on_expose
{
   my $self = shift;
   ( $self->{on_expose} ) = @_;
}

sub _do_expose
{
   my $self = shift;

   undef $self->{expose_pending};

   if( my $on_expose = $self->{on_expose} ) {
      $on_expose->( $self, 
         top   => 0,
         left  => 0,
         lines => $self->lines,
         cols  => $self->cols,
      );
   }

   my $children = $self->{child_windows} or return;

   foreach my $win ( sort { $a->top <=> $b->top || $a->left <=> $b->left } grep { defined } @$children ) {
      $win->_do_expose;
   }
}

=head2 $win->expose

Marks the window as having been exposed, to invoke the C<on_expose> event
handler on itself, and all its child windows. The window's own handler will be
invoked first, followed by all the child windows, in screen order (top to
bottom, then left to right).

The C<on_expose> event handler isn't invoked immediately; instead, the
C<Tickit> C<later> method is used to invoke it at the next round of IO event
handling. Until then, any other window could be exposed. Duplicates are
suppressed; so if a window and any of its ancestors are both queued for
expose, the actual handler will only be invoked once.

=cut

sub expose
{
   my $self = shift;

   return if $self->_expose_pending;

   $self->{expose_pending} = 1;

   $self->root->enqueue_redraw( sub {
      return if $self->parent && $self->parent->_expose_pending;

      $self->_do_expose;
   } );
}

sub _expose_pending
{
   my $self = shift;
   return $self->{expose_pending} ||
          ( $self->parent && $self->parent->_expose_pending );
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

=head2 $pen = $win->pen

Returns the current L<Tickit::Pen> object associated with this window

=cut

sub pen
{
   my $self = shift;
   return $self->{pen};
}

=head2 $win->set_pen( $pen )

Replace the current L<Tickit::Pen> object for this window with a new one. The
object reference will be stored, allowing it to be shared with other objects.
If C<undef> is set, then a new, blank pen will be constructed.

=cut

sub set_pen
{
   my $self = shift;
   ( $self->{pen} ) = @_;
   defined $self->{pen} or $self->{pen} = Tickit::Pen->new;
}

=head2 $val = $win->getpenattr( $attr )

Returns a single attribue from the current pen

=cut

sub getpenattr
{
   my $self = shift;
   my ( $attr ) = @_;

   return $self->{pen}->getattr( $attr );
}

=head2 %attrs = $win->getpenattrs

Retrieve the current pen settings for the window.

=cut

sub getpenattrs
{
   my $self = shift;

   return $self->{pen}->getattrs;
}

=head2 $val = $win->get_effective_penattr( $attr )

Returns the effective value of a pen attribute. This will be the value of this
window's attribute if set, or the effective value of the attribute from its
parent.

=cut

sub get_effective_penattr
{
   my $self = shift;
   my ( $attr ) = @_;

   return $self->{pen}->getattr( $attr ) // $self->parent->get_effective_penattr( $attr );
}

=head2 %attrs = $win->get_effective_penattrs

Retrieve the effective pen settings for the window. This will be the settings
of the window and all its parents down to the root window, merged together.

=cut

sub get_effective_penattrs
{
   my $self = shift;

   my %epen = ( $self->parent->get_effective_penattrs,
                $self->{pen}->getattrs );

   return %epen;
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
      pen    => Tickit::Pen->new,
   }, __PACKAGE__; # not ref $self in case of RootWindow

   $sub->change_geometry( $top, $left, $lines, $cols );

   $self->_reap_dead_children;
   push @{ $self->{child_windows} }, $sub;
   weaken $self->{child_windows}[-1];

   return $sub;
}

sub _reap_dead_children
{
   my $self = shift;
   my $children = $self->{child_windows} or return;
   for( my $i = 0; $i < @$children; ) {
      $i++, next if defined $children->[$i];
      splice @$children, $i, 1, ();
   }
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

   $self->parent->goto( $self->top + $line, $self->left + $col );
}

=head2 $win->print( $text, $pen )

=head2 $win->print( $text, %attrs )

Print the given text to the terminal at the current cursor position using the
pen of the window, possibly overridden by any extra attributes in the given
C<Tickit::Pen> instance, or directly in the given hash, if one is provided.

=cut

sub print
{
   my $self = shift;
   my $text = shift;

   return unless length $text;

   my %attrs = ( @_ == 1 ) ? shift->getattrs : @_;

   $self->term->setpen( $self->get_effective_penattrs, %attrs );
   $self->term->print( $text );
}

=head2 $win->penprint( ... )

A deprecated synonym for C<print>.

=cut

sub penprint
{
   warnings::warnif( deprecated => "Tickit::Window->penprint is deprecated; use ->print instead" );
   goto &print;
}

=head2 $win->erasech( $count, $moveend, $pen )

=head2 $win->erasech( $count, $moveend, %attrs )

Erase C<$count> columns forwards. If C<$moveend> is true, the cursor will be
placed at the end of the erased region. If defined but false, it will not move
from its current location. If undefined, the terminal will take which ever
option it can implement most efficiently.

If a C<Tickit::Pen> or pen attributes are provided, they are used to override
the background colour for the erased region.

=cut

sub erasech
{
   my $self = shift;
   my $count = shift;
   my $moveend = shift;

   my %attrs = ( @_ == 1 ) ? shift->getattrs : @_;

   my $bg = exists $attrs{bg} ? $attrs{bg} : $self->get_effective_penattr( 'bg' );

   $self->term->chpen( bg => $bg );
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

This method is deprecated; instead you should use the C<scrollrect> method.

=cut

sub insertch
{
   my $self = shift;
   my ( $count ) = @_;

   warnings::warnif( deprecated => "Tickit::Window->insertch is deprecated; use ->scrollrect instead" );

   return 0 unless $self->left + $self->cols == $self->term->cols;

   $self->term->chpen( bg => $self->get_effective_penattr( 'bg' ) );
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

This method is deprecated; instead you should use the C<scrollrect> method.

=cut

sub deletech
{
   my $self = shift;
   my ( $count ) = @_;

   warnings::warnif( deprecated => "Tickit::Window->deletech is deprecated; use ->scrollrect instead" );

   return 0 unless $self->left + $self->cols == $self->term->cols;

   $self->term->chpen( bg => $self->get_effective_penattr( 'bg' ) );
   $self->term->deletech( $count );
   return 1;
}

=head2 $success = $win->scrollrect( $top, $left, $lines, $cols, $downward, $rightward )

=head2 $success = $win->scrollrect( ..., $pen )

=head2 $success = $win->scrollrect( ..., %attrs )

Attempt to scroll the rectangle of the window defined by the first four
parameters by an amount given by the latter two. Since most terminals cannot
perform arbitrary rectangle scrolling, this method returns a boolean to
indicate if it was successful. The caller should test this return value and
fall back to another drawing strategy if the attempt was unsuccessful.

Optionally, a C<Tickit::Pen> instance or hash of pen attributes may be
provided, to override the background colour used for erased sections behind
the scroll.

The cursor may move as a result of calling this method; its location is
undefined if this method returns successful. The terminal pen, in particular
the background colour, may be modified by this method even if it fails to
scroll the terminal (and returns false).

=cut

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

   return $self->parent->scrollrect(
      $self->top  + $top, $self->left + $left, $lines, $cols,
      $downward, $rightward,
      bg => $attrs{bg},
   );
}

=head2 $success = $win->scroll( $downward, $rightward )

A shortcut for calling C<scrollrect> on the entire region of the window.

=cut

sub scroll
{
   my $self = shift;
   my ( $downward, $rightward ) = @_;

   return $self->scrollrect(
      0, 0, $self->lines, $self->cols,
      $downward, $rightward
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

   $self->_requeue_focus
}

sub _requeue_focus
{
   my $self = shift;
   my ( $focuswin ) = @_;

   if( $self->{focus_child} and defined $focuswin and $self->{focus_child} != $focuswin ) {
      $self->{focus_child}->_lose_focus;
   }

   weaken( $self->{focus_child} = $focuswin );
   $self->_requeue_focus_parent;
}

sub _requeue_focus_parent
{
   my $self = shift;
   $self->parent->_requeue_focus( $self );
}

sub _gain_focus
{
   my $self = shift;

   if( my $focus_child = $self->{focus_child} ) {
      $focus_child->_gain_focus;
   }
   else {
      $self->goto( $self->{focus_line}, $self->{focus_col} );
   }
}

sub _lose_focus
{
   my $self = shift;

   undef $self->{focus_line};
   undef $self->{focus_col};
}

=head2 $win->restore

Restore the state of the terminal to its idle state. Places the cursor back
at the focus position, and restores the pen.

=cut

sub restore
{
   my $self = shift;
   $self->root->restore;
}

=head2 $win->clearline( $line )

Erase the entire content of one line of the window

=cut

sub clearline
{
   my $self = shift;
   my ( $line ) = @_;

   $self->goto( $line, 0 );
   $self->erasech( $self->cols );
}

=head2 $win->clear

Erase the entire content of the window and reset it to the current background
colour.

=cut

sub clear
{
   my $self = shift;

   $self->clearline( $_ ) for 0 .. $self->lines - 1;
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
      $term->setpen( %$penattrs );
      $code->( $term );
   }
}

use overload
   '""' => sub {
      my $self = shift;
      return sprintf "%s[%dx%d abs@%d,%d]",
         ref $self,
         $self->cols, $self->lines, $self->abs_left, $self->abs_top;
   },
   '0+' => sub {
      my $self = shift;
      return $self;
   },
   fallback => 1; 

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
