#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2009-2013 -- leonerd@leonerd.org.uk

package Tickit::Window;

use strict;
use warnings;
use 5.010; # //

our $VERSION = '0.28';

use Carp;

use Scalar::Util qw( weaken );

use Tickit::Pen;
use Tickit::Rect;
use Tickit::RectSet;
use Tickit::Utils qw( string_countmore );

use constant FLOAT_ALL_THE_WINDOWS => $ENV{TICKIT_FLOAT_ALL_THE_WINDOWS} // 1;

use constant WEAKEN_CHILDREN => 1;

=head1 NAME

C<Tickit::Window> - a window for drawing operations

=head1 SYNOPSIS

=head1 DESCRIPTION

Provides coordination of widget drawing activities. A C<Window> represents a
region of the screen that a widget occupies.

Windows cannot directly be constructed. Instead they are obtained by
sub-division of other windows, ultimately coming from the
root window associated with the terminal.

Normally all windows are visible, but a window may be hidden by calling the
C<hide> method. After this, the window will not respond to any of the drawing
methods, until it is made visible again with the C<show> method. A hidden
window will not receive focus or input events. It may still receive geometry
change events if it is resized.

=head2 Sub Windows and Floating Windows

A division of a window made by calling C<make_sub> obtains a window that
represents some portion of the drawing area of the parent window. All sibling
subdivisions are considered equal; if they happen to overlap then it is
undefined how input events on overlapping regions are handled among them, or
how drawing may interact. It is recommended that C<make_sub> be used to obtain
only windows that cover non-overlapping areas of the parent; such as to
distribute space within a container.

By comparison, any window created by C<make_float> is considered to sit
"above" the area of its parent. It will always handle input events before
other siblings, and any drawing that happens within it overwrites that of its
non-floating siblings. Any drawing on a non-floating sibling that happens
within the area of a float is obscured by the contents of the floating window.

To disable the new shared implementation of floating and non-floating windows
for legacy bug-testing purposes, set the environment variable
C<TICKIT_FLOAT_ALL_THE_WINDOWS> to a false value ("0" or empty string)

 $ TICKIT_FLOAT_ALL_THE_WINDOWS=0 ./Build test

This variable will be removed in a later version.

=cut

# Internal constructor
sub new
{
   my $class = shift;
   my ( $tickit, $lines, $cols ) = @_;

   my $term = $tickit->term;

   my $self = bless {
      tickit  => $tickit,
      term    => $term,
      top     => 0,
      left    => 0,
      cols    => $cols,
      lines   => $lines,
   }, $class;
   $self->_init;

   weaken( $self->{tickit} );

   return $self;
}

# Shared initialisation by both ->new and ->make_sub
sub _init
{
   my $self = shift;
   $self->{visible} = 1;
   $self->{pen}     = Tickit::Pen->new;
   $self->{damage}  = Tickit::RectSet->new;
}

=head1 METHODS

=cut

=head2 $win->close

Removes the window from its parent and clears any event handlers set using any
of the C<set_on_*> methods. Also recursively closes any child windows.

Currently this is an optional method, as child windows are stored as weakrefs,
so should be destroyed when the last reference to them is dropped. Widgets
should make sure to call this method anyway, because this will be changed in a
future version.

=cut

sub DESTROY
{
   my $self = shift;
   $self->close;
}

sub close
{
   my $self = shift;

   $self->set_on_geom_changed( undef );
   $self->set_on_key( undef );
   $self->set_on_mouse( undef );
   $self->set_on_expose( undef );
   $self->set_on_focus( undef );

   $self->{parent}->_remove( $self ) if $self->{parent};
   $_->close for @{ $self->{child_windows} };
}

sub _remove
{
   my $self = shift;
   my ( $child ) = @_;

   my $children = $self->{child_windows};
   for( my $i = 0; $i < @$children; ) {
      $i++, next if $children->[$i] != $child;
      splice @$children, $i, 1, ();
   }
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
      parent  => $self,
      float   => FLOAT_ALL_THE_WINDOWS,
   }, ref $self;
   $sub->_init;

   $sub->change_geometry( $top, $left, $lines, $cols );

   $self->_reap_dead_children;
   push @{ $self->{child_windows} }, $sub;
   weaken $self->{child_windows}[-1] if WEAKEN_CHILDREN;

   return $sub;
}

=head2 $sub = $win->make_hidden_sub( $top, $left, $lines, $cols )

Constructs a new sub-window like C<make_sub>, but the window starts initially
hidden. This avoids having to call C<hide> separately afterwards.

=cut

sub make_hidden_sub
{
   my $self = shift;

   my $sub = $self->make_sub( @_ );
   $sub->{visible} = 0;

   return $sub;
}

=head2 $float = $win->make_float( $top, $left, $lines, $cols )

Constructs a new floating child window starting at the given coordinates of
this window. It will be sized to the given limits.

=cut

sub make_float
{
   my $self = shift;
   my ( $top, $left, $lines, $cols ) = @_;

   my $sub = bless {
      parent  => $self,
      float   => 1,
   }, ref $self;
   $sub->_init;

   $sub->change_geometry( $top, $left, $lines, $cols );

   $self->_reap_dead_children;
   # floats go first
   unshift @{ $self->{child_windows} }, $sub;
   weaken $self->{child_windows}[0] if WEAKEN_CHILDREN;

   return $sub;
}

=head2 $popup = $win->make_popup( $top, $left, $lines, $cols )

Constructs a new floating popup window starting at the given coordinates
relative to this window. It will be sized to the given limits.

This window will have the root window as its parent, rather than the window
the method was called on. Additionally, a popup window will steal all keyboard
and mouse events that happen, regardless of focus or mouse position. It is
possible that, if the window has an C<on_mouse> handler, that it may receive
mouse events from outwide the bounds of the window.

=cut

sub make_popup
{
   my $win = shift;
   my ( $top, $left, $lines, $cols ) = @_;

   while( $win->parent ) {
      $top  += $win->top;
      $left += $win->left;
      $win = $win->parent;
   }

   my $popup = $win->make_float( $top, $left, $lines, $cols );
   $popup->{steal_input} = 1;
   return $popup;
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

=head2 $parentwin = $win->parent

Returns the parent window; i.e. the window on which C<make_sub> or
C<make_float> was called to create this one

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
   my $win = shift;
   while( my $parent = $win->{parent} ) {
      $win = $parent;
   }
   return $win;
}

=head2 $term = $win->term

Returns the L<Tickit::Term> instance of the terminal on which this window
lives.

=cut

sub term
{
   my $self = shift;
   return $self->root->{term};
}

=head2

Returns the L<Tickit> instance with which this window is associated.

=cut

sub tickit
{
   my $self = shift;
   return $self->root->{tickit};
}

=head2 $win->show

Makes the window visible. Allows drawing methods to output to the terminal.
Calling this method also exposes the window, invoking the C<on_expose>
handler. Shows the cursor if this window currently has focus.

=cut

sub show
{
   my $self = shift;
   $self->{visible} = 1;

   $self->expose;
}

=head2 $win->hide

Makes the window invisible. Prevents drawing methods outputting to the
terminal. Hides the cursor if this window currently has focus.

=cut

sub hide
{
   my $self = shift;
   $self->{visible} = 0;

   if( my $parent = $self->parent ) {
      $parent->_do_expose( $self->rect );
   }
   $self->restore;
}

=head2 $visible = $win->is_visible

Returns true if the window is currently visible.

=cut

sub is_visible
{
   my $self = shift;
   return $self->{visible};
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

   return 0 unless $self->is_visible;

   $self->_reap_dead_children;
   my $children = $self->{child_windows};
   if( $children and @$children and $children->[0]->{steal_input} ) {
      $children->[0]->_handle_key( @_ ) and return;
   }

   my $focus_child = $self->{focus_child};
   if( $focus_child ) {
      $focus_child->_handle_key( @_ ) and return 1;
   }

   if( my $on_key = $self->{on_key} ) {
      $on_key->( $self, @_ ) and return 1;
   }

   if( $children ) {
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

   return 0 unless $self->is_visible;

   if( my $children = $self->{child_windows} ) {
      foreach my $child ( @$children ) {
         next unless $child; # weakrefs; may be undef

         my $child_line = $line - $child->top;
         my $child_col  = $col  - $child->left;

         if( !$child->{steal_input} ) {
            next if $child_line < 0 or $child_line >= $child->lines;
            next if $child_col  < 0 or $child_col  >= $child->cols;
         }

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

 $on_expose->( $win, $rect )

Will be passed a L<Tickit::Rect> representing the exposed region.

=cut

sub set_on_expose
{
   my $self = shift;
   ( $self->{on_expose} ) = @_;
}

sub _do_expose
{
   my $self = shift;
   my ( $rect ) = @_;

   # This might be a call from the parent, so flush all pending areas as well
   $self->{damage}->add( $rect );

   my @rects = $self->{damage}->rects;
   $self->{damage}->clear;

   if( my $on_expose = $self->{on_expose} ) {
      $on_expose->( $self, $_ ) for @rects;
   }

   my $children = $self->{child_windows} or return;

   foreach my $win ( sort { $a->top <=> $b->top || $a->left <=> $b->left } grep { defined } @$children ) {
      foreach my $rect ( @rects ) {
         next unless my $winrect = $rect->intersect( $win->rect );
         next unless $win->{visible};
         $win->_do_expose( $winrect->translate( -$win->top, -$win->left ) );
      }
   }
}

=head2 $win->expose( $rect )

Marks the given region of the window as having been exposed, to invoke the
C<on_expose> event handler on itself, and all its child windows. The window's
own handler will be invoked first, followed by all the child windows, in
screen order (top to bottom, then left to right).

If C<$rect> is not supplied it defaults to exposing the entire window area.

The C<on_expose> event handler isn't invoked immediately; instead, the
C<Tickit> C<later> method is used to invoke it at the next round of IO event
handling. Until then, any other window could be exposed. Duplicates are
suppressed; so if a window and any of its ancestors are both queued for
expose, the actual handler will only be invoked once per unique region of the
window.

=cut

sub expose
{
   my $self = shift;
   my ( $rect ) = @_;
   $rect ||= Tickit::Rect->new(
      top   => 0,
      left  => 0,
      lines => $self->lines,
      cols  => $self->cols,
   );

   return if $self->_expose_pending( $rect );

   $self->{damage}->add( $rect );

   $self->tickit->enqueue_redraw( sub {
      my @rects = $self->{damage}->rects;
      $self->{damage}->clear;

      $self->_expose_pending( $_ ) or $self->_do_expose( $_ ) for @rects;
   } );
}

sub _expose_pending
{
   my $self = shift;
   my ( $rect ) = @_;
   return 1 if $self->{damage}->contains( $rect );
   return 0 unless $self->parent;
   return $self->parent->_expose_pending( $rect->translate( $self->top, $self->left ) );
}

=head2 $win->set_on_focus( $on_refocus )

Set the callback to invoke whenever the window gains or loses focus.

 $on_refocus->( $win, $has_focus )

Will be passed a boolean value, true if the focus was just gained, false if
the focus was just lost.

=cut

sub set_on_focus
{
   my $self = shift;
   ( $self->{on_focus} ) = @_;
}

=head2 $win->set_expose_after_scroll( $expose_after_scroll )

If set to a true value, the C<scrollrect> method will expose the region of
the window that requires redrawing. If C<scrollrect> was successful, this will
be just the newly-exposed portion that was scrolled in. If it was unsuccessful
it will be the entire window region. If set false, no expose will happen, and
the code calling C<scrollrect> must re-expose as required.

This is a temporary method to handle the transition of behaviours; it may be
removed in the future and its behaviour implied true always.

=cut

sub set_expose_after_scroll
{
   my $self = shift;
   ( $self->{expose_after_scroll} ) = @_;
}

=head2 $top = $win->top

=head2 $bottom = $win->bottom

=head2 $left = $win->left

=head2 $right = $win->right

Returns the coordinates of the start of the window, relative to the parent
window.

=cut

sub top
{
   my $self = shift;
   return $self->{top};
}

sub bottom
{
   my $self = shift;
   return $self->top + $self->lines;
}

sub left
{
   my $self = shift;
   return $self->{left};
}

sub right
{
   my $self = shift;
   return $self->left + $self->cols;
}

=head2 $top  = $win->abs_top

=head2 $left = $win->abs_left

Returns the coordinates of the start of the window, relative to the root
window.

=cut

sub abs_top
{
   my $win = shift;
   my $top = $win->{top};
   while( $win = $win->{parent} ) {
      $top += $win->{top};
   }
   return $top;
}

sub abs_left
{
   my $win = shift;
   my $left = $win->{left};
   while( $win = $win->{parent} ) {
      $left += $win->{left};
   }
   return $left;
}

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

=head2 $rect = $win->rect

Returns a L<Tickit::Rect> containing representing the window's extent relative
to its parent

=cut

sub rect
{
   my $self = shift;
   # TODO: Cache this, invalidate it in ->change_geometry
   return Tickit::Rect->new(
      top   => $self->top,
      left  => $self->left,
      lines => $self->lines,
      cols  => $self->cols,
   );
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

This method is now deprecated and should not be used; instead use

 $win->pen->getattrs

=cut

sub getpenattrs
{
   my $self = shift;

   return $self->{pen}->getattrs;
}

=head2 $pen = $win->get_effective_pen

Returns a new L<Tickit::Pen> containing the effective pen attributes for the
window, combined by those of all its parents.

=cut

sub get_effective_pen
{
   my $win = shift;

   my $pen = $win->pen->clone;
   for( my $parent = $win->parent; $parent; $parent = $parent->parent ) {
      $pen->default_from( $parent->pen );
   }

   return $pen;
}

=head2 $val = $win->get_effective_penattr( $attr )

Returns the effective value of a pen attribute. This will be the value of this
window's attribute if set, or the effective value of the attribute from its
parent.

=cut

sub get_effective_penattr
{
   my $win = shift;
   my ( $attr ) = @_;

   for( ; $win; $win = $win->parent ) {
      my $value = $win->pen->getattr( $attr );
      return $value if defined $value;
   }

   return undef;
}

=head2 %attrs = $win->get_effective_penattrs

Retrieve the effective pen settings for the window. This will be the settings
of the window and all its parents down to the root window, merged together.

This method is now deprecated and should not be used; instead use

 $win->get_effective_pen->getattrs

=cut

sub get_effective_penattrs
{
   my $self = shift;
   return $self->get_effective_pen->getattrs;
}

sub _get_span_visibility
{
   my $win = shift;
   my ( $line, $col ) = @_;

   my ( $vis, $len ) = ( 1, $win->cols - $col );

   my $prev;
   while( $win ) {
      # Off top, bottom or right: invisible and always going to be
      if( $line < 0 or $line >= $win->lines or $col >= $win->cols ) {
         return ( 0, undef );
      }

      # Off left: invisible for at least as far as it's off by
      if( $col < 0 ) {
         $len = -$col if $vis or -$col > $len;
         $vis = 0;
      }
      # Within the window - visible for at most the width of the window
      elsif( $vis ) {
         my $remains = $win->cols - $col;
         $len = $remains if $len > $remains;
      }

      # Now obscure any floats. Floats always come first so we can stop at the
      # first non-float for efficiency
      $win->_reap_dead_children;
      foreach my $child ( @{ $win->{child_windows} } ) {
         last if $prev and $child == $prev;
         last unless $child->{float};
         next unless $child->{visible};
         next if $child->top > $line or $child->bottom <= $line;

         next if $col >= $child->right;

         if( $child->left <= $col ) {
            my $child_cols_hidden = $child->right - $col;
            if( $vis ) {
               $len = $child_cols_hidden;
               $vis = 0;
            }
            else {
               $len = $child_cols_hidden if $child_cols_hidden > $len;
            }
         }
         elsif( $vis ) {
            my $remaining_visible = $child->left - $col;
            $len = $remaining_visible if $remaining_visible < $len;
         }
      }

      $line += $win->top;
      $col  += $win->left;

      $prev = $win;
      $win = $win->parent;
   }

   return ( $vis, $len );
}

=head2 $win->goto( $line, $col )

Moves the cursor to the given position within the window. Both C<$line> and
C<$col> are 0-based. The given position does not have to lie within the bounds
of the window. Lines above or below the window are never displayed, columns to
the left or right are clipped as appropriate. The virtual position of the
cursor is still tracked even if it is not visibly displayed on the actual
terminal.

=cut

sub goto
{
   my $win = shift;
   my ( $line, $col ) = @_;

   $win->{output_line}   = $line;
   $win->{output_column} = $col;
   $win->{output_needs_goto} = 0;

   while( $win ) {
      return if $line < 0 or $line >= $win->lines;
      return if $col  < 0 or $col  >= $win->cols;

      return unless $win->{visible};

      $line += $win->top;
      $col  += $win->left;

      my $parent = $win->parent or last;
      $win = $parent;
   }

   $win->term->goto( $line, $col );
   $win->_needs_flush;
}

=head2 $pos = $win->print( $text, $pen )

=head2 $pos = $win->print( $text, %attrs )

Print the given text to the terminal at the current cursor position using the
pen of the window, possibly overridden by any extra attributes in the given
C<Tickit::Pen> instance, or directly in the given hash, if one is provided.

Returns a L<Tickit::StringPos> object giving the total count of string
printed, including in obscured sections covered by other windows, or clipped
by window boundaries.

=cut

sub print
{
   my $self = shift;
   my $text = shift;

   my $pen = ( @_ == 1 ) ? shift->clone : Tickit::Pen->new( @_ );

   # First collect up the pen attributes and abort early if any window is
   # invisible
   for( my $win = $self; $win; $win = $win->parent ) {
      return unless $win->{visible};
      $pen->default_from( $win->pen );
   }

   my $line = $self->{output_line};
   my $term = $self->term;

   my $need_goto = $self->{output_needs_goto};
   my ( $abs_top, $abs_left );
   my $need_flush = 0;

   my $pos = Tickit::StringPos->zero;

   my $total_len = length $text;

   while( $pos->codepoints < $total_len ) {
      my ( $vis, $cols ) = $self->_get_span_visibility( $line, $self->{output_column} + $pos->columns );

      if( !$vis and !defined $cols ) {
         string_countmore( $text, $pos, undef, $pos->bytes );
         last;
      }

      my $prev_cp  = $pos->codepoints;
      my $prev_col = $pos->columns;
      string_countmore( $text, $pos, Tickit::StringPos->limit_columns( $cols + $pos->columns ), $pos->bytes );

      # TODO: This would be more efficient in bytes, but 'use bytes' breaks
      # the UTF-8ness of the return value
      my $chunk = substr $text, $prev_cp, $pos->codepoints - $prev_cp;

      if( $vis ) {
         if( $need_goto ) {
            $abs_top  //= $self->abs_top;
            $abs_left //= $self->abs_left;
            $term->goto( $abs_top + $line, $abs_left + $self->{output_column} + $prev_col );
            $need_goto = 0;
         }

         $term->setpen( $pen );
         $term->print( $chunk );

         $need_flush = 1;
      }
      else {
         # TODO: $term->move( undef, $pos->columns - $prev_col )
         $need_goto = 1;
      }
   }

   $self->{output_column} += $pos->columns;

   $self->root->_needs_flush if $need_flush;
   $self->{output_needs_goto} = $need_goto;

   return $pos;
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

   my $pen = ( @_ == 1 ) ? shift->clone : Tickit::Pen->new( @_ );

   # First collect up the pen attributes and abort early if any window is
   # invisible
   for( my $win = $self; $win; $win = $win->parent ) {
      return unless $win->{visible};
      $pen->default_from( $win->pen );
   }

   my $line = $self->{output_line};
   my $term = $self->term;

   my $need_goto = $self->{output_needs_goto};
   my ( $abs_top, $abs_left );
   my $need_flush = 0;

   while( $count ) {
      my ( $vis, $len ) = $self->_get_span_visibility( $line, $self->{output_column} );

      last if !$vis and !defined $len;

      $len = $count if $len > $count;

      if( $vis ) {
         if( $need_goto ) {
            $abs_top  //= $self->abs_top;
            $abs_left //= $self->abs_left;
            $term->goto( $abs_top + $line, $abs_left + $self->{output_column} );
            $need_goto = 0;
         }

         $term->setpen( $pen );
         $term->erasech( $len, $moveend );

         $need_flush = 1;
      }
      else {
         $need_goto = 1;
      }

      $self->{output_column} += $len;
      $count -= $len;
   }

   $self->root->_needs_flush if $need_flush;
   $self->{output_needs_goto} = $need_goto;
}

=head2 $win->clearrect( $rect )

=head2 $win->clearrect( $rect, $pen )

=head2 $win->clearrect( $rect, %attrs )

Erase the content of the window within the given L<Tickit::Rect>. If a
C<Tickit::Pen> or pen attributes are provided, they are used to override the
background colour for the erased region.

=cut

sub clearrect
{
   my $self = shift;
   my $rect = shift;

   my $pen = ( @_ == 1 ) ? shift->clone : Tickit::Pen->new( @_ );

   if( $rect->top == 0 and $rect->left == 0 and
       $rect->bottom == $self->lines and $rect->right == $self->cols ) {
      $self->clear;
      return;
   }

   foreach my $line ( $rect->linerange ) {
      $self->goto( $line, $rect->left );
      $self->erasech( $rect->cols, undef, $pen );
   }
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

If the C<expose_after_scroll> behavior is enabled, then this method will
enqueue all of the required expose requests before returning, so in this case
the return value is not interesting.

=cut

sub _scrollrect_inner
{
   my $self = shift;
   my ( $rect, $downward, $rightward, @args ) = @_;

   if( abs($downward) >= $rect->lines or abs($rightward) >= $rect->cols ) {
      $self->expose( $rect ) if $self->{expose_after_scroll};
      return 1;
   }

   my $pen = ( @args == 1 ) ? $args[0]->clone : Tickit::Pen->new( @args );

   my $top  = $rect->top;
   my $left = $rect->left;

   my $lines = $rect->lines;
   my $cols  = $rect->cols;

   my $win = $self;
   while( $win ) {
      $top  >= 0 and $top  < $win->lines or croak '$top out of bounds';
      $left >= 0 and $left < $win->cols  or croak '$left out of bounds';

      $lines > 0 and $top + $lines <= $win->lines or croak '$lines out of bounds';
      $cols  > 0 and $left + $cols <= $win->cols  or croak '$cols out of bounds';

      return unless $win->{visible};

      $pen->default_from( $win->pen );

      $top  += $win->top;
      $left += $win->left;

      my $parent = $win->parent or last;
      $win = $parent;
   }

   my $term = $win->term;

   $term->setpen( bg => $pen->getattr( 'bg' ) );

   unless( $term->scrollrect( $top, $left, $lines, $cols, $downward, $rightward ) ) {
      $self->expose( $rect ) if $self->{expose_after_scroll};
      return 0;
   }

   if( $self->{expose_after_scroll} ) {
      if( $downward > 0 ) {
         # "scroll down" means lines moved upward, so the bottom needs redrawing
         $self->expose( Tickit::Rect->new(
               top  => $rect->bottom - $downward, lines => $downward,
               left => $rect->left,               cols  => $rect->cols,
         ) );
      }
      elsif( $downward < 0 ) {
         # "scroll up" means lines moved downward, so top needs redrawing
         $self->expose( Tickit::Rect->new(
               top  => $rect->top,  lines => -$downward,
               left => $rect->left, cols  => $rect->cols,
         ) );
      }

      if( $rightward > 0 ) {
         # "scroll right" means columns moved leftward, so the right edge needs redrawing
         $self->expose( Tickit::Rect->new(
               top  => $rect->top,                lines => $rect->lines,
               left => $rect->right - $rightward, cols  => $rightward,
         ) );
      }
      elsif( $rightward < 0 ) {
         # "scroll left" means lines moved rightward, so left edge needs redrawing
         $self->expose( Tickit::Rect->new(
               top  => $rect->top,  lines => $rect->lines,
               left => $rect->left, cols  => -$rightward,
         ) );
      }
   }
   else {
      $self->_needs_flush;
   }

   return 1;
}

# TODO: This ought probably to take a Tickit::Rect instead of 4 ints
sub scrollrect
{
   my $self = shift;
   my ( $top, $left, $lines, $cols, $downward, $rightward, @args ) = @_;

   my $rect = Tickit::Rect->new(
      top   => $top,
      left  => $left,
      lines => $lines,
      cols  => $cols,
   );

   my $visible = Tickit::RectSet->new;
   $visible->add( $rect );

   my $right = $left + $cols;

   foreach my $line ( $top .. $top + $lines - 1 ) {
      my $col = $left;
      while( $col < $right ) {
         my ( $vis, $len ) = $self->_get_span_visibility( $line, $col );
         $col += $len and next if $vis;
         my $until = defined $len ? $col + $len : $right;

         return 0 unless $self->{expose_after_scroll};

         $visible->subtract( Tickit::Rect->new( 
            top    => $line,
            bottom => $line+1,
            left   => $col,
            right  => $until,
         ) );

         $col = $until;
      }
   }

   my @rects = $self->{damage}->rects;
   $self->{damage}->clear;
   foreach my $r ( @rects ) {
      $self->{damage}->add( $r ), next if $r->bottom < $top or $r->top > $top + $lines or
                                          $r->right < $left or $r->left > $left + $cols;
      my $inside = $r->intersect( $rect );
      my @outside = $r->subtract( $rect );

      $self->{damage}->add( $_ ) for @outside;
      $self->{damage}->add( $inside->translate( -$downward, -$rightward ) ) if $inside;
   }

   my $ret = 1;
   foreach my $r ( $visible->rects ) {
      $self->_scrollrect_inner( $r, $downward, $rightward, @args ) or $ret = 0;
   }

   return $ret;
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

   $self->{on_focus}->( $self, 1 ) if $self->{on_focus};

   $self->_requeue_focus
}

sub _requeue_focus
{
   my $self = shift;
   my ( $focuswin ) = @_;

   if( $self->{focus_child} and defined $focuswin and $self->{focus_child} != $focuswin ) {
      $self->{focus_child}->_lose_focus;
   }

   $self->{focus_child} = $focuswin;
   weaken $self->{focus_child} if WEAKEN_CHILDREN;

   if( my $parent = $self->parent ) {
      $parent->_requeue_focus( $self );
   }
   else {
      $self->tickit->enqueue_redraw;
   }
}

sub _gain_focus
{
   my $self = shift;

   if( my $focus_child = $self->{focus_child} ) {
      $focus_child->_gain_focus;
   }
   elsif( $self->is_visible ) {
      $self->goto( $self->{focus_line}, $self->{focus_col} );
   }
}

sub _lose_focus
{
   my $self = shift;

   undef $self->{focus_line};
   undef $self->{focus_col};

   $self->{on_focus}->( $self, 0 ) if $self->{on_focus};
}

=head2 $focused = $win->is_focused

Returns true if this window currently has the input focus

=cut

sub is_focused
{
   my $self = shift;
   return defined $self->{focus_line};
}

=head2 $win->restore

Restore the state of the terminal to its idle state. Places the cursor back
at the focus position, and restores the pen.

=cut

sub restore
{
   my $self = shift;
   my $root = $self->root;

   my $term = $root->term;

   if( my $focus_child = $root->{focus_child} ) {
      if( $focus_child->is_visible ) {
         $term->mode_cursorvis( 1 );
         $focus_child->_gain_focus;
      }
      else {
         $term->mode_cursorvis( 0 );
      }
   }
   elsif( defined $root->{focus_line} ) {
      $term->mode_cursorvis( 1 );
      $root->_gain_focus;
   }

   $root->_needs_flush;
}

=head2 $win->clearline( $line )

Erase the entire content of one line of the window

=cut

sub clearline
{
   my $self = shift;
   my ( $line ) = @_;

   return unless $self->{visible};

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

   return unless $self->{visible};

   if( $self->parent ) {
      $self->clearline( $_ ) for 0 .. $self->lines - 1;
   }
   else {
      my $term = $self->term;
      $term->setpen( $self->get_effective_pen );
      $term->clear;

      $self->_needs_flush;
   }
}

sub _needs_flush
{
   my $self = shift;
   return if $self->{flush_queued};

   $self->tickit->later( sub {
      $self->term->flush;
      undef $self->{flush_queued};
   } );

   $self->{flush_queued}++;
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
