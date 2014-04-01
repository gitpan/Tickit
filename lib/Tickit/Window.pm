#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2009-2014 -- leonerd@leonerd.org.uk

package Tickit::Window;

use strict;
use warnings;
use 5.010; # //

our $VERSION = '0.43';

use Carp;

use Scalar::Util qw( weaken refaddr blessed );
use List::Util qw( first );

use Tickit::Pen;
use Tickit::Rect;
use Tickit::RectSet;
use Tickit::RenderBuffer;
use Tickit::Utils qw( string_countmore );

use constant WEAKEN_CHILDREN => 1;
use constant CHILD_WINDOWS_LATER => $ENV{TICKIT_CHILD_WINDOWS_LATER} // 1;

=head1 NAME

C<Tickit::Window> - a window for drawing operations

=head1 SYNOPSIS

 use Tickit;
 use Tickit::Pen;

 my $tickit = Tickit->new;

 my $rootwin = $tickit->rootwin;

 $rootwin->set_on_expose( with_rb => sub {
    my ( $win, $rb, $rect ) = @_;

    $rb->clear;

    $rb->text_at(
       int( $win->lines / 2 ), int( ($win->cols - 12) / 2 ),
       "Hello, world"
    );
 });
 $rootwin->set_on_geom_changed( sub { shift->expose } );
 $rootwin->set_pen( Tickit::Pen->new( fg => "white" ) );

 $rootwin->expose;
 $tickit->run;

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

=head2 Sub Windows

A division of a window made by calling C<make_sub> or C<make_float> obtains a
window that represents some portion of the drawing area of the parent window.
Child windows are stored in order; C<make_sub> adds a new child to the end of
the list, and C<make_float> adds one at the start.

Higher windows (windows more towards the start of the list), will always handle
input events before lower siblings. The extent of windows also obscures lower
windows; drawing on lower windows may not be visible because higher windows
are above it.

=head2 Deferred Child Window Operations

In order to minimise the chances of ordering-specific bugs in window event
handlers that cause child window creation, reordering or deletion, the actual
child window list is only mutated after the event processing has finished, by
using a L<Tickit> C<later> block. As this behaviour is relatively new, it may
result in bugs in legacy code that isn't expecting it. For now, it can be
disabled by setting the environment variable C<TICKIT_CHILD_WINDOWS_LATER> to
a false value; though this is a temporary measure and will be removed in a
subsequent version.

 $ TICKIT_CHILD_WINDOWS_LATER=0 perl my-program.pl

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
      # Only root window now accumulates damage
      damage  => Tickit::RectSet->new,
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
   $self->{expose_after_scroll} = 1;
   $self->{cursor_visible} = 1;
}

# We need to ensure all geomety changes happen before any redrawing

sub _needs_restore
{
   my $self = shift;
   my $root = $self->root;

   $root->{needs_restore} and return;
   $root->{needs_restore}++;
   $root->_needs_later;
}

sub _needs_later
{
   my $self = shift;

   $self->{later_queued} and return;
   $self->{later_queued}++;
   $self->tickit->later( sub { $self->_on_later } );
}

sub _on_later
{
   my $self = shift;
   undef $self->{later_queued};

   if( $self->{needs_geom_change} ) {
      foreach ( @{ delete $self->{needs_geom_change} } ) {
         my ( $win, @change ) = @$_;
         $win->_do_change_children( @change );
      }
   }

   if( $self->{needs_expose} ) {
      undef $self->{needs_expose};
      my @rects = $self->{damage}->rects;
      $self->{damage}->clear;

      $self->term->setctl_int( cursorvis => 0 );

      $self->_do_expose( $_ ) for @rects;

      $self->{needs_restore}++;
   }

   if( $self->{needs_restore} ) {
      undef $self->{needs_restore};
      $self->restore;
   }
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

sub _close
{
   my $self = shift;

   $self->set_on_geom_changed( undef );
   $self->set_on_key( undef );
   $self->set_on_mouse( undef );
   $self->set_on_expose( undef );
   $self->set_on_focus( undef );

   defined and $_->_close for @{ $self->{child_windows} };
   undef $self->{child_windows};
   @{ $self->{pending_geom_changes} } = ();
}

sub DESTROY
{
   my $self = shift;
   $self->_close;
   $self->{parent}->_do_change_children( remove => $self ) if $self->{parent};
}

sub close
{
   my $self = shift;
   $self->_close;
   $self->{parent}->_change_children( remove => $self ) if $self->{parent};
}

sub _do_change_children
{
   my $self = shift;
   my $how = shift;

   my $children = $self->{child_windows} ||= [];
   $self->_reap_dead_children;

   if( $how eq "insert" ) {
      my ( $sub, $index ) = @_;

      $index = @$children if $index == -1;
      splice @$children, $index, 0, ( $sub );
      weaken $children->[$index] if WEAKEN_CHILDREN;
   }
   elsif( $how eq "remove" ) {
      my ( $child ) = @_;
      for( my $i = 0; $i < @$children; ) {
         $i++, next if defined $children->[$i] and $children->[$i] != $child;
         splice @$children, $i, 1, ();
      }

      if( $self->{focused_child} and $self->{focused_child} == $child ) {
         undef $self->{focused_child};
      }
   }
}

sub _change_children
{
   my $self = shift;
   my @change = @_;

   if( CHILD_WINDOWS_LATER ) {
      my $root = $self->root;
      push @{ $root->{needs_geom_change} }, [ $self => @change ];
      $root->_needs_later;
   }
   else {
      $self->_do_change_children( @change );
   }
}

=head2 $sub = $win->make_sub( $top, $left, $lines, $cols )

Constructs a new sub-window of the given geometry, and places it at the end of
the child window list; below any other siblings.

=cut

sub make_sub
{
   my $self = shift;
   my ( $top, $left, $lines, $cols ) = @_;

   my $sub = bless {
      parent  => $self,
   }, ref $self;
   $sub->_init;

   $self->_reap_dead_children;

   $sub->change_geometry( $top, $left, $lines, $cols );
   $self->_change_children( insert => $sub, -1 );

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

Constructs a new sub-window of the given geometry, and places it at the start
of the child window list; above any other siblings.

=cut

sub make_float
{
   my $self = shift;
   my ( $top, $left, $lines, $cols ) = @_;

   my $sub = bless {
      parent  => $self,
   }, ref $self;
   $sub->_init;

   $self->_reap_dead_children;

   $sub->change_geometry( $top, $left, $lines, $cols );
   $self->_change_children( insert => $sub, 0 );

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

=head2 $win->raise

=cut

sub raise
{
   my $self = shift;
   croak "Cannot ->raise the root window" unless my $parent = $self->parent;
   $self->parent->_reorder_child( $self, -1 );
}

=head2 $win->lower

Moves the order of the window in its parent one higher or lower relative to
its siblings.

=cut

sub lower
{
   my $self = shift;
   croak "Cannot ->lower the root window" unless my $parent = $self->parent;
   $self->parent->_reorder_child( $self, +1 );
}

=head2 $win->raise_to_front

Moves the order of the window in its parent to be the front-most among its
siblings.

=cut

sub raise_to_front
{
   my $self = shift;
   croak "Cannot ->raise_to_front the root window" unless my $parent = $self->parent;
   $self->parent->_reorder_child( $self, "front" );
}

=head2 $win->lower_to_back

Moves the order of the window in its parent to be the back-most among its
siblings.

=cut

sub lower_to_back
{
   my $self = shift;
   croak "Cannot ->lower_to_back the root window" unless my $parent = $self->parent;
   $self->parent->_reorder_child( $self, "back" );
}

sub _reorder_child
{
   my $self = shift;
   my ( $child, $where ) = @_;

   my $children = $self->{child_windows} or return;
   my $idx = first { refaddr($child) == refaddr($children->[$_]) } 0 .. $#$children;
   defined $idx or croak "$child is not a child of $self";

   # Remove it
   splice @$children, $idx, 1, ();

   if( $where eq "front" ) {
      unshift @$children, $child;
   }
   elsif( $where eq "back" ) {
      push @$children, $child;
   }
   else {
      splice @$children, $idx + $where, 0, ( $child );
   }

   $self->expose( $child->rect );
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

=head2 @windows = $win->subwindows

Returns a list of the subwindows of this one. They are returned in order,
highest first.

=cut

sub subwindows
{
   my $self = shift;
   return unless my $children = $self->{child_windows};
   return grep { defined } @$children;
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

   if( my $parent = $self->parent ) {
      if( !$parent->{focused_child} and $self->{focused_child} || $self->is_focused ) {
         $parent->{focused_child} = $self;
         weaken $parent->{focused_child} if WEAKEN_CHILDREN;
      }
   }

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
      if( $parent->{focused_child} and $parent->{focused_child} == $self ) {
         undef $parent->{focused_child};
      }
      $parent->expose( $self->rect );
   }
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
   $self->_needs_restore if $self->is_focused;
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

=head2 $win->set_on_key( with_ev => $on_key )

Set the callback to invoke whenever a key is pressed while this window, or one
of its child windows, has the input focus. The callback will be passed the
window and an event structure.

 $handled = $on_key->( $win, $event )

C<$event> is an object supporting methods called C<type>, C<str> and C<mod>.
C<type> will be C<"text"> for normal unmodified Unicode, or C<"key"> for
special keys or modified Unicode. C<str> will be the UTF-8 string for C<text>
events, or the textual description of the key as rendered by L<Term::TermKey>
for C<key> events. C<mod> will be a bitmask of the modifier state.

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

=head2 $win->set_on_key( $on_key )

A backward-compatibility wrapper which passes the event details as positional
arguments rather than as a structure.

 $handled = $on_key->( $win, $type, $str, $mod )

This form is now discouraged, and may be removed in a later version.

=cut

sub set_on_key
{
   my $self = shift;

   if( @_ > 1 and $_[0] eq "with_ev" ) {
      $self->{on_key_with_ev} = 1;
      shift;
   }
   else {
      $self->{on_key_with_ev} = 0;
   }

   ( $self->{on_key} ) = @_;
}

sub _handle_key
{
   my $self = shift;
   my ( $args ) = @_;

   return 0 unless $self->is_visible;

   $self->_reap_dead_children;
   my $children = $self->{child_windows};
   if( $children and @$children and $children->[0]->{steal_input} ) {
      $children->[0]->_handle_key( $args ) and return;
   }

   my $focused_child = $self->{focused_child};

   if( $focused_child ) {
      $focused_child->_handle_key( $args ) and return 1;
   }

   if( my $on_key = $self->{on_key} ) {
      my @args = ( $self, Tickit::Window::Event->new( %$args ) );
      push @args, @{$args}{qw( str mod )} unless $self->{on_key_with_ev};

      $on_key->( @args ) and return 1;
   }

   if( $children ) {
      foreach my $child ( @$children ) {
         next unless $child; # weakrefs; may be undef
         next if $focused_child and $child == $focused_child;

         $child->_handle_key( $args );
      }
   }

   return 0;
}

=head2 $win->set_on_mouse( with_ev => $on_mouse )

Set the callback to invoke whenever a mouse event is received within the
window's rectangle. The callback will be passed the window and an event
structure.

 $handled = $on_mouse->( $win, $event )

C<$event> is an object supporting methods called C<type>, C<button>, C<line>,
C<col> and C<mod>. C<type> will contain the event name. C<button> will contain
the button number, though it may not be present for C<release> events. C<line>
and C<col> are 0-based. C<mod> is a bitmask of modifier state. Behaviour of
events involving more than one mouse button is not well-specified by
terminals.

The following event names may be observed:

=over 8

=item press

A mouse button has been pressed down on this cell

=item drag_start

The mouse was moved while a button was held, and was initially in the given
cell

=item drag

The mouse was moved while a button was held, and is now in the given cell

=item drag_outside

The mouse was moved outside of the window that handled the C<drag_start>
event, and is still being dragged.

=item drag_drop

A mouse button was released after having been moved, while in the given cell

=item drag_stop

The drag operation has finished. This event is always given directly to the
window that handled the C<drag_start> event, rather than the window on which
the mouse release event happened.

=item release

A mouse button was released after being pressed

=back

The invoked code should return a true value if it considers the mouse event
dealt with, or false to pass it up to its parent window.

Once a dragging operation has begun via C<drag_start>, the window that handled
the event will always receive C<drag>, C<drag_outside>, and an eventual
C<drag_stop> event even if the mouse moves outside that window. No other
window will receive a C<drag_outside> or C<drag_stop> event than the one that
started the operation.

=head2 $win->set_on_mouse( $on_mouse )

A backward-compatibility wrapper which passes the event detials as positional
arguments rather than as a structure.

 $handled = $on_mouse->( $win, $type, $button, $line, $col, $mod )

This form is now discouraged, and may be removed in a later version.

=cut

sub set_on_mouse
{
   my $self = shift;

   if( @_ > 1 and $_[0] eq "with_ev" ) {
      $self->{on_mouse_with_ev} = 1;
      shift;
   }
   else {
      $self->{on_mouse_with_ev} = 0;
   }

   ( $self->{on_mouse} ) = @_;
}

sub _handle_mouse
{
   my $self = shift;
   my ( $args ) = @_;

   return unless $self->is_visible;

   my $line = $args->{line};
   my $col  = $args->{col};

   if( my $children = $self->{child_windows} ) {
      foreach my $child ( @$children ) {
         next unless $child; # weakrefs; may be undef

         my $child_line = $line - $child->top;
         my $child_col  = $col  - $child->left;

         if( !$child->{steal_input} ) {
            next if $child_line < 0 or $child_line >= $child->lines;
            next if $child_col  < 0 or $child_col  >= $child->cols;
         }

         my $childargs = {
            %$args,
            line => $child_line,
            col  => $child_col,
         };

         my $ret = $child->_handle_mouse( $childargs );
         return $ret if $ret;
      }
   }

   if( my $on_mouse = $self->{on_mouse} ) {
      my @args = ( $self, Tickit::Window::Event->new( %$args ) );
      push @args, @{$args}{qw( button line col mod )} unless $self->{on_mouse_with_ev};

      $on_mouse->( @args ) and return $self;
   }

   return 0;
}

=head2 $win->set_on_expose( with_rb => $on_expose )

Set the callback to invoke whenever a region of the window is exposed by the
C<expose> event. When invoked, it is passed the window itself, a
L<Tickit::RenderBuffer> and a L<Tickit::Rect> representing the portion of the
window that was exposed.

 $on_expose->( $win, $rb, $rect )

The buffer's origin will be that of the window, and its clipping region will
already be set to the expose rect. This will automatically be flushed to the
window when the callback returns.

=head2 $win->set_on_expose( $on_expose )

Legacy form that is passes only the rect and not a render buffer to the
callback. Callbacks in this form will have to call the direct window drawing
methods themselves.

 $on_expose->( $win, $rect )

This form is now discouraged, and may be removed in a later version.

=cut

sub set_on_expose
{
   my $self = shift;

   if( @_ > 1 and $_[0] eq "with_rb" ) {
      $self->{expose_with_rb} = 1;
      shift;
   }
   else {
      $self->{expose_with_rb} = 0;
   }

   ( $self->{on_expose} ) = @_;
}

sub _do_expose
{
   my $self = shift;
   my ( $rect ) = @_;

   if( my $on_expose = $self->{on_expose} ) {
      my $rb = Tickit::RenderBuffer->new(
         lines => $self->lines,
         cols  => $self->cols,
      );
      $rb->setpen( $self->pen );

      local $self->{exposure_rb} = $rb;

      $rb->save;

      $rb->clip( $rect );

      if( $self->{expose_with_rb} ) {
         $on_expose->( $self, $rb, $rect );
      }
      else {
         $on_expose->( $self, $rect );
      }

      $rb->restore;

      undef $self->{exposure_rb};
      $rb->flush_to_window( $self );
   }

   my $children = $self->{child_windows} or return;

   foreach my $win ( sort { $a->top <=> $b->top || $a->left <=> $b->left } grep { defined } @$children ) {
      next unless my $winrect = $rect->intersect( $win->rect );
      next unless $win->{visible};
      $win->_do_expose( $winrect->translate( -$win->top, -$win->left ) );
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

   if( $rect ) {
      $rect = $rect->intersect( $self->selfrect ) or return;
   }
   else {
      $rect = $self->selfrect;
   }

   if( my $parent = $self->parent ) {
      return $parent->expose( $rect->translate( $self->top, $self->left ) );
   }

   return if $self->{damage}->contains( $rect );

   $self->{damage}->add( $rect );

   $self->{needs_expose} = 1;
   $self->_needs_later;
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

This behaviour now defaults to true, and this is a temporary method to handle
the transition of behaviours. This method exists only to allow this behaviour
to be disabled as a temporary transition measure. It will be removed in a
later version.

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

=head2 $rect = $win->selfrect

Returns a L<Tickit::Rect> containing representing the window's extent within
itself. This will have C<top> and C<left> equal to 0.

=cut

sub selfrect
{
   my $self = shift;
   # TODO: Cache this, invalidate it in ->change_geometry
   return Tickit::Rect->new(
      top   => 0,
      left  => 0,
      lines => $self->lines,
      cols  => $self->cols,
   );
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

   my $pen = $win->pen->as_mutable;
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

      $win->_reap_dead_children;
      foreach my $child ( @{ $win->{child_windows} } ) {
         last if $prev and $child == $prev;
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

   if( my $rb = $win->{exposure_rb} ) {
      $rb->goto( $line, $col );
      return;
   }

   $win->{output_line}   = $line;
   $win->{output_column} = $col;
   $win->{output_needs_goto} = 0;

   my ( $vis ) = $win->_get_span_visibility( $line, $col );
   return unless $vis;

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

   my $pen = ( @_ == 1 ) ? shift->as_mutable : Tickit::Pen::Mutable->new( @_ );

   if( my $rb = $self->{exposure_rb} ) {
      return $rb->text( $text, $pen );
   }

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
      defined string_countmore( $text, $pos, Tickit::StringPos->limit_columns( $cols + $pos->columns ), $pos->bytes ) or
         croak "Encountered non-Unicode text in ->print; bailing out";

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

=head2 $pos = $win->erasech( $count, $moveend, $pen )

=head2 $pos = $win->erasech( $count, $moveend, %attrs )

Erase C<$count> columns forwards. If C<$moveend> is true, the cursor will be
placed at the end of the erased region. If defined but false, it will not move
from its current location. If undefined, the terminal will take which ever
option it can implement most efficiently.

If a C<Tickit::Pen> or pen attributes are provided, they are used to override
the background colour for the erased region.

Returns a L<Tickit::StringPos> object giving the total count of string
printed, including in obscured sections covered by other windows, or clipped
by window boundaries. Only the C<columns> field will be valid; the others will
be C<-1>.

=cut

sub erasech
{
   my $self = shift;
   my $count = shift;
   my $moveend = shift;

   my $pen = ( @_ == 1 ) ? shift->as_mutable : Tickit::Pen::Mutable->new( @_ );

   if( my $rb = $self->{exposure_rb} ) {
      return $rb->erase( $count, $pen );
   }

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

   my $orig_count = $count;
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

   return if !defined wantarray;
   return Tickit::StringPos->limit_columns( $orig_count );
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

   my $pen = ( @_ == 1 ) ? shift->as_mutable : Tickit::Pen::Mutable->new( @_ );

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

=head2 $success = $win->scrollrect( $rect, $downward, $rightward )

=head2 $success = $win->scrollrect( $top, $left, $lines, $cols, $downward, $rightward )

=head2 $success = $win->scrollrect( ..., $pen )

=head2 $success = $win->scrollrect( ..., %attrs )

Attempt to scroll the rectangle of the window (either given by a
C<Tickit::Rect> or defined by the first four parameters) by an amount given
by the latter two. Since most terminals cannot perform arbitrary rectangle
scrolling, this method returns a boolean to indicate if it was successful.
The caller should test this return value and fall back to another drawing
strategy if the attempt was unsuccessful.

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

sub _scrollrectset
{
   my $win = shift;
   my ( $rectset, $downward, $rightward, $pen ) = @_;

   my $origwin = $win;
   my $expose_after_scroll = $win->{expose_after_scroll};

   while( $win ) {
      return 0 unless $win->is_visible;

      $pen->default_from( $win->pen );

      my $parent = $win->parent or last;

      my $parentset = Tickit::RectSet->new;
      $parentset->add( $_->translate( $win->top, $win->left ) ) for $rectset->rects;

      foreach my $sibling ( $parent->subwindows ) {
         last if $sibling == $win;
         next unless $sibling->is_visible;

         $parentset->subtract( $sibling->rect );
      }

      $win = $parent;
      $rectset = $parentset;
   }

   my $term = $win->term;

   $term->setpen( bg => $pen->getattr( 'bg' ) );

   my $ret = 1;
   foreach my $rect ( $rectset->rects ) {
      my $top  = $rect->top;
      my $left = $rect->left;

      my $lines = $rect->lines;
      my $cols  = $rect->cols;

      my $origrect = $rect->translate( -$origwin->abs_top, -$origwin->abs_left );

      if( abs($downward) >= $lines or abs($rightward) >= $cols ) {
         $origwin->expose( $rect ) if $expose_after_scroll;
         next;
      }

      # Move damage
      my $damageset = $win->{damage};
      my @damage = $damageset->rects;
      $damageset->clear;
      foreach my $r ( @damage ) {
         $damageset->add( $r ), next if $r->bottom < $rect->top or $r->top > $rect->bottom or
                                        $r->right < $rect->left or $r->left > $rect->right;
         my $inside = $r->intersect( $rect );
         my @outside = $r->subtract( $rect );

         $damageset->add( $_ ) for @outside;
         $damageset->add( $inside->translate( -$downward, -$rightward ) ) if $inside;
      }

      if( not $term->scrollrect( $top, $left, $lines, $cols, $downward, $rightward ) ) {
         $ret = 0;
         if( $expose_after_scroll ) {
            $origwin->expose( $origrect );
         }
      }

      if( $expose_after_scroll ) {
         if( $downward > 0 ) {
            # "scroll down" means lines moved upward, so the bottom needs redrawing
            $origwin->expose( Tickit::Rect->new(
                  top  => $origrect->bottom - $downward, lines => $downward,
                  left => $origrect->left,               cols  => $cols,
            ) );
         }
         elsif( $downward < 0 ) {
            # "scroll up" means lines moved downward, so top needs redrawing
            $origwin->expose( Tickit::Rect->new(
                  top  => $origrect->top,  lines => -$downward,
                  left => $origrect->left, cols  => $cols,
            ) );
         }

         if( $rightward > 0 ) {
            # "scroll right" means columns moved leftward, so the right edge needs redrawing
            $origwin->expose( Tickit::Rect->new(
                  top  => $origrect->top,                lines => $lines,
                  left => $origrect->right - $rightward, cols  => $rightward,
            ) );
         }
         elsif( $rightward < 0 ) {
            # "scroll left" means lines moved rightward, so left edge needs redrawing
            $origwin->expose( Tickit::Rect->new(
                  top  => $origrect->top,  lines => $lines,
                  left => $origrect->left, cols  => -$rightward,
            ) );
         }
      }
      else {
         $origwin->_needs_flush;
      }
   }

   return $ret;
}

sub scrollrect
{
   my $self = shift;
   my $rect;
   if( blessed $_[0] and $_[0]->isa( "Tickit::Rect" ) ) {
      $rect = shift;
   }
   else {
      my ( $top, $left, $lines, $cols ) = splice @_, 0, 4;
      $rect = Tickit::Rect->new(
         top   => $top,
         left  => $left,
         lines => $lines,
         cols  => $cols,
      );
   }
   my ( $downward, $rightward, @args ) = @_;

   my $pen = ( @args == 1 ) ? $args[0]->as_mutable : Tickit::Pen::Mutable->new( @args );

   my $visible = Tickit::RectSet->new;
   $visible->add( $rect );

   foreach my $child ( $self->subwindows ) {
      $visible->subtract( $child->rect );
   }

   $self->_scrollrectset( $visible, $downward, $rightward, $pen );
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

=head2 $win->scroll_with_children( $downward, $rightward )

Similar to C<scroll> but ignores child windows of this one, moving all of
the terminal content paying attention only to obscuring by newer siblings of
ancestor windows.

This method is experimental, intended only for use by
L<Tickit::Widget::ScrollBox>. After calling this method, the terminal content
will have moved and the windows drawing them will be confused unless the
window position was also updated. C<ScrollBox> takes care to do this.

=cut

sub scroll_with_children
{
   my $self = shift;
   my ( $downward, $rightward, @args ) = @_;

   my $pen = ( @args == 1 ) ? $args[0]->as_mutable : Tickit::Pen::Mutable->new( @args );

   my $visible = Tickit::RectSet->new;
   $visible->add( $self->selfrect );

   $self->_scrollrectset( $visible, $downward, $rightward, $pen );
}

=head2 $win->cursor_at( $line, $col )

Sets the position in the window at which the terminal cursor will be placed if
this window has focus. This method does I<not> force the window to take the
focus though; for that see C<take_focus>.

=cut

sub cursor_at
{
   my $self = shift;
   ( $self->{cursor_line}, $self->{cursor_col} ) = @_;
   $self->_needs_restore if $self->is_focused;
}

=head2 $win->cursor_visible( $visible )

Sets whether the terminal cursor is visible on the window when it has focus.
Normally it is, but passing a false value will make the cursor hidden even
when the window is focused.

=cut

sub cursor_visible
{
   my $self = shift;
   ( $self->{cursor_visible} ) = @_;
   $self->_needs_restore if $self->is_focused;
}

=head2 $win->cursor_shape( $shape )

Sets the shape that the terminal cursor will have if this window has focus.
This method does I<not> force the window to take the focus though; for that
see C<take_focus>. Valid values for C<$shape> are the various
C<TERM_CURSORSHAPE_*> constants from L<Tickit::Term>.

=cut

sub cursor_shape
{
   my $self = shift;
   ( $self->{cursor_shape} ) = @_;
   $self->_needs_restore if $self->is_focused;
}

=head2 $win->take_focus

Causes this window to take the input focus, and updates the cursor position to
the stored active position given by C<cursor_at>.

=cut

sub take_focus
{
   my $self = shift;
   my ( $focuswin ) = @_;

   $self->_focus_gained
}

=head2 $win->focus( $line, $col )

A convenient shortcut combining C<cursor_at> with C<take_focus>; setting the
focus cursor position and taking the input focus.

=cut

sub focus
{
   my $self = shift;
   $self->cursor_at( @_ );
   $self->take_focus;
}

sub _focus_gained
{
   my $self = shift;
   my ( $child ) = @_;

   if( $self->{focused_child} and defined $child and $self->{focused_child} != $child ) {
      $self->{focused_child}->_focus_lost;
   }

   if( my $parent = $self->parent ) {
      # Still update without ourself but don't inform parent if we're invisible
      $parent->_focus_gained( $self ) if $self->is_visible;
   }
   else {
      $self->_needs_restore;
   }

   if( !$child ) {
      $self->{focused} = 1;
      $self->{on_focus}->( $self, 1 ) if $self->{on_focus};
   }

   $self->{focused_child} = $child;
   weaken $self->{focused_child} if WEAKEN_CHILDREN;
}

sub _focus_lost
{
   my $self = shift;

   if( my $focused_child = $self->{focused_child} ) {
      $focused_child->_focus_lost;
   }

   if( $self->{focused} ) {
      undef $self->{focused};
      $self->{on_focus}->( $self, 0 ) if $self->{on_focus};
   }
}

=head2 $focused = $win->is_focused

Returns true if this window currently has the input focus

=cut

sub is_focused
{
   my $self = shift;
   return defined $self->{focused};
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

   my $win = $root;
   while( $win ) {
      last unless $win->is_visible;
      last unless $win->{focused_child};
      $win = $win->{focused_child};
   }

   if( $win and $win->is_visible and $win->is_focused and $win->{cursor_visible} ) {
      my $cursorshape = $win->{cursor_shape} // Tickit::Term::TERM_CURSORSHAPE_BLOCK;
      $term->setctl_int( cursorvis => 1 );
      $win->goto( $win->{cursor_line}, $win->{cursor_col} );
      $win->term->setctl_int( cursorshape => $cursorshape );
   }
   else {
      $term->setctl_int( cursorvis => 0 );
   }

   $term->flush;
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
   bool => sub { 1 },
   fallback => 1;

package # hide from indexer
   Tickit::Window::Event;

use Carp;

sub new
{
   my $class = shift;
   bless { @_ }, $class;
}

foreach my $key (qw( type str mod button line col )) {
   no strict 'refs';
   *$key = sub { exists $_[0]{$key} ? $_[0]{$key} : croak "Event has no '$key' field" }
}

# This horrible overload is just short-term for back-compat so we can pass
# the event structure itself as the first method argument, to code that still
# expects to find the event type name there
use overload
   '""' => "type",
   fallback => 1;

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
