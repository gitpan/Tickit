#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2009-2013 -- leonerd@leonerd.org.uk

package Tickit::Widget;

use strict;
use warnings;

our $VERSION = '0.29_002';

use Carp;
use Scalar::Util qw( weaken );
use List::MoreUtils qw( all );

use Tickit::Pen;
use Tickit::Style;

use constant PEN_ATTR_MAP => { map { $_ => 1 } @Tickit::Pen::ALL_ATTRS };

use constant WIDGET_PEN_FROM_STYLE => 0;

=head1 NAME

C<Tickit::Widget> - abstract base class for on-screen widgets

=head1 DESCRIPTION

This class acts as an abstract base class for on-screen widget objects. It
provides the lower-level machinery required by most or all widget types.

Objects cannot be directly constructed in this class. Instead, a subclass of
this class which provides a suitable implementation of the C<render> and other
provided methods is derived. Instances in that class are then constructed.

See the C<EXAMPLES> section below.

=cut

=head1 CONSTRUCTOR

=cut

=head2 $widget = Tickit::Widget->new( %args )

Constructs a new C<Tickit::Widget> object. Must be called on a subclass that
implements the required methods; see the B<SUBCLASS METHODS> section below.

Any pen attributes present in C<%args> will be used to set the default values
on the widget's pen object, other than the following:

=over 8

=item class => STRING

=item classes => ARRAY of STRING

If present, gives the C<Tickit::Style> class name or names applied to this
widget.

=item style => HASH

If present, gives a set of "direct applied" style to the Widget. This is
treated as an extra set of style definitions that apply more directly than any
of the style classes or the default definitions.

The hash should contain style keys, optionally suffixed by style tags, giving
values.

 style => {
   'fg'        => 3,
   'fg:active' => 5,
 }

=back

=cut

sub new
{
   my $class = shift;
   my %args = @_;

   foreach my $method (qw( render lines cols )) {
      $class->can( $method ) or
         croak "$class cannot ->$method - do you subclass and implement it?";
   }

   $class->CLEAR_BEFORE_RENDER and
      carp "Constructing a $class with CLEAR_BEFORE_RENDER";

   my $self = bless {
      classes => delete $args{classes} // [ delete $args{class} ],
   }, $class;

   if( $class->WIDGET_PEN_FROM_STYLE ) {
      $args{$_} and $args{style}{$_} = delete $args{$_} for @Tickit::Pen::ALL_ATTRS;
   }

   if( my $style = delete $args{style} ) {
      my $tagset = $self->{style_direct} = Tickit::Style::_Tagset->new;
      foreach my $key ( keys %$style ) {
         $tagset->add( $key, $style->{$key} );
      }
   }

   if( $class->WIDGET_PEN_FROM_STYLE ) {
      $self->set_pen( $self->get_style_pen->clone );
   }
   else {
      $self->set_pen( Tickit::Pen->new_from_attrs( \%args ) );
   }

   return $self;
}

=head1 METHODS

=cut

=head2 @classes = $widget->style_classes

Returns a list of the style class names this Widget has.

=cut

sub style_classes
{
   my $self = shift;
   return @{ $self->{classes} };
}

=head2 $widget->set_style_tag( $tag, $value )

Sets the (boolean) state of the named style tag. After calling this method,
the C<get_style_*> methods may return different results, but no resizing or
redrawing is automatically performed; the widget should do this itself. It may
find the C<on_style_changed_values> method useful for this.

=cut

# This is cached, so will need invalidating on style loads
my %KEYS_BY_TYPE_CLASS_TAG;
Tickit::Style::on_style_load( sub { undef %KEYS_BY_TYPE_CLASS_TAG } );

sub set_style_tag
{
   my $self = shift;
   my ( $tag, $value ) = @_;

   # Early-return on no change
   return if !$self->{style_tag}{$tag} == !$value;

   ( my $type = ref $self ) =~ s/^Tickit::Widget:://;

   # Work out what style keys might depend on this tag
   my %values;

   if( $self->{style_direct} ) {
      KEYSET: foreach my $keyset ( $self->{style_direct}->keysets ) {
         $keyset->tags->{$tag} or next KEYSET;

         $values{$_} ||= [] for keys %{ $keyset->style };
      }
   }

   foreach my $class ( $self->style_classes, undef ) {
      my $keys = $KEYS_BY_TYPE_CLASS_TAG{$type}{$class//""}{$tag} ||= do {
         my $tagset = Tickit::Style::_ref_tagset( $type, $class );

         my %keys;
         KEYSET: foreach my $keyset ( $tagset->keysets ) {
            $keyset->tags->{$tag} or next KEYSET;

            $keys{$_}++ for keys %{ $keyset->style };
         }

         [ keys %keys ];
      };

      $values{$_} ||= [] for @$keys;
   }

   my @keys = keys %values;

   my @old_values = $self->get_style_values( @keys );
   $values{$keys[$_]}[0] = $old_values[$_] for 0 .. $#keys;

   $self->{style_tag}{$tag} = !!$value;

   $self->_style_changed_values( \%values );
}

sub _style_tags
{
   my $self = shift;
   my $tags = $self->{style_tag};
   return join "|", sort grep { $tags->{$_} } keys %$tags;
}

=head2 @values = $widget->get_style_values( @keys )

=head2 $value = $widget->get_style_values( $key )

Returns a list of values for the given keys of the currently-applied style.
For more detail see the L<Tickit::Style> documentation. Returns just one value
in scalar context.

=cut

sub get_style_values
{
   my $self = shift;
   my @keys = @_;

   ( my $type = ref $self ) =~ s/^Tickit::Widget:://;

   my @set = ( 0 ) x @keys;
   my @values = ( undef ) x @keys;

   my $tags = $self->{style_tag};
   my $cache = $self->{style_cache}{$self->_style_tags} ||= {};

   foreach my $i ( 0 .. $#keys ) {
      next unless exists $cache->{$keys[$i]};

      $set[$i] = 1;
      $values[$i] = $cache->{$keys[$i]};
   }

   my @classes = ( $self->style_classes, undef );
   my $tagset = $self->{style_direct};

   while( !all { $_ } @set and @classes ) {
      # First time around this uses the direct style, if set. Thereafter uses
      # the style classes in order, finally the unclassed base.
      defined $tagset or $tagset = Tickit::Style::_ref_tagset( $type, shift @classes );

      KEYSET: foreach my $keyset ( $tagset->keysets ) {
         $tags->{$_} or next KEYSET for keys %{ $keyset->tags };

         my $style = $keyset->style;

         foreach ( 0 .. $#keys ) {
            exists $style->{$keys[$_]} or next;
            $set[$_] and next;

            $values[$_] = $style->{$keys[$_]};
            $set[$_] = 1;
         }
      }

      undef $tagset;
   }

   foreach my $i ( 0 .. $#keys ) {
      next if exists $cache->{$keys[$i]};

      $cache->{$keys[$i]} = $values[$i];
   }

   return @values if wantarray;
   return $values[0];
}

=head2 $pen = $widget->get_style_pen( $prefix )

A shortcut to calling C<get_style_values> to collect up the pen attributes,
and form a L<Tickit::Pen::Immutable> object from them. If C<$prefix> is
supplied, it will be prefixed on the pen attribute names with an underscore
(which would be read from the stylesheet file as a hypen). Note that the
returned pen instance is immutable, and may be cached.

If the class constant method C<WIDGET_PEN_FROM_STYLE> takes a true value, then
extra logic is applied to the constructor and during style changes, to set the
widget pen from the default style pen. Furthermore, plain attributes given to
the constructor that take the names of pen attributes will be set on the
widget's direct-applied style. This has the overall effect of unifying the
widget pen with the default style pen, and additionally allowing further
customisation for state changes or style classes.

It is likely that this behaviour will become the default in some future
version with the eventual aim to remove the idea of a widget pen entirely.

 use constant WIDGET_PEN_FROM_STYLE => 1;

The widget pen is set to be a mutable clone of the default style pen, to allow
the legacy behaviour that some code may attempt to mutate the widget pen
directly. In this case the widget's direct-applied style will not be updated
to reflect the changes, however. Code using widgets with style-managed pens
should not attempt to mutate the widget pen, but should use C<set_style>
instead. A future version may yield warnings or exceptions if the
style-managed widget pen is mutated.

=cut

sub get_style_pen
{
   my $self = shift;
   my $class = ref $self;
   my ( $prefix ) = @_;

   return $self->{style_pen_cache}{$self->_style_tags}{$prefix//""} ||= do {
      my @keys = map { defined $prefix ? "${prefix}_$_" : $_ } @Tickit::Pen::ALL_ATTRS;

      my %attrs;
      @attrs{@Tickit::Pen::ALL_ATTRS} = $self->get_style_values( @keys );

      Tickit::Pen::Immutable->new( %attrs );
   };
}

=head2 $text = $widget->get_style_text

A shortcut to calling C<get_style_values> for a single key called C<"text">.

=cut

sub get_style_text
{
   my $self = shift;
   my $class = ref $self;

   return $self->get_style_values( "text" ) // croak "$class style does not define text";
}

=head2 $widget->set_style( %defs )

Changes the widget's direct-applied style.

C<%defs> should contain style keys optionally suffixed with tags in the same
form as that given to the C<style> key to the constructor. Defined values will
add to or replace values already stored by the widget. Keys mapping to
C<undef> are deleted from the stored style.

Note that changing the direct applied style is moderately costly because it
must invalidate all of the cached style values and pens that depend on the
changed keys. For normal runtime changes of style, consider using a tag if
possible, because style caching takes tags into account, and simply changing
applied style tags does not invalidate the caches.

=cut

sub set_style
{
   my $self = shift;
   my %defs = @_;

   my $new = Tickit::Style::_Tagset->new;
   $new->add( $_, $defs{$_} ) for keys %defs;

   my %values;
   foreach my $keyset ( $new->keysets ) {
      $values{$_} ||= [] for keys %{ $keyset->style };
   }

   my @keys = keys %values;

   my @old_values = $self->get_style_values( @keys );
   $values{$keys[$_]}[0] = $old_values[$_] for 0 .. $#keys;

   $self->{style_direct} ? $self->{style_direct}->merge( $new )
                         : $self->{style_direct} = $new;

   $self->_style_changed_values( \%values, 1 );
}

sub _style_changed_values
{
   my $self = shift;
   my ( $values, $invalidate_caches ) = @_;

   my @keys = keys %$values;

   if( $invalidate_caches ) {
      foreach my $keyset ( values %{ $self->{style_cache} } ) {
         delete $keyset->{$_} for @keys;
      }
   }

   my @new_values = $self->get_style_values( @keys );

   # Remove unchanged keys
   foreach ( 0 .. $#keys ) {
      my $key = $keys[$_];
      my $old = $values->{$key}[0];
      my $new = $new_values[$_];

      delete $values->{$key}, next if !defined $old and !defined $new;
      delete $values->{$key}, next if defined $old and defined $new and $old eq $new;

      $values->{$key}[1] = $new;
   }

   my %changed_pens;
   foreach my $key ( @keys ) {
      PEN_ATTR_MAP->{$key} and
         $changed_pens{""}++;

      $key =~ m/^(.*)_([^_]+)$/ && PEN_ATTR_MAP->{$2} and
         $changed_pens{$1}++;
   }

   if( $invalidate_caches ) {
      foreach my $penset ( values %{ $self->{style_pen_cache} } ) {
         delete $penset->{$_} for keys %changed_pens;
      }
   }

   if( $changed_pens{""} and $self->WIDGET_PEN_FROM_STYLE ) {
      $self->set_pen( $self->get_style_pen->clone );
   }

   my $code = $self->can( "on_style_changed_values" );
   $self->$code( %$values ) if $code;
}

=head2 $widget->set_window( $window )

Sets the L<Tickit::Window> for the widget to draw on. Setting C<undef> removes
the window.

If a window is associated to the widget, that window's pen is set to the
current widget pen. The widget is then drawn to the window by calling the
C<render> method. If a window is removed (by setting C<undef>) then no cleanup
of the window is performed; the new owner of the window is expected to do
this.

This method may invoke the C<window_gained> and C<window_lost> methods.

=cut

sub set_window
{
   my $self = shift;
   my ( $window ) = @_;

   # Early out if no change
   return if !$window and !$self->window;
   return if $window and $self->window and $self->window == $window;

   if( $self->{window} and !$window ) {
      $self->{window}->set_pen( undef );
      $self->window_lost( $self->{window} );
   }

   $self->{window} = $window;

   if( $window ) {
      $window->set_pen( $self->{pen} );

      $self->window_gained( $self->{window} );

      $self->reshape;

      $window->expose;
   }
}

use constant CLEAR_BEFORE_RENDER => 1;

sub window_gained
{
   my $self = shift;

   my $window = $self->window;

   weaken $self;

   $window->set_on_geom_changed( sub {
      $self->reshape;
      $self->redraw if !$self->parent;
   } );

   $window->set_on_expose( sub {
      my ( $win, $rect ) = @_;
      $self->_do_clear( $rect ) if $self->CLEAR_BEFORE_RENDER;
      $self->render(
         rect => $rect,
         top   => $rect->top,
         left  => $rect->left,
         lines => $rect->lines,
         cols  => $rect->cols,
      );
   } );

   if( $self->can( "on_key" ) ) {
      $window->set_on_key( sub {
         shift;
         $self->on_key( @_ );
      } );
   }
   if( $self->can( "on_mouse" ) ) {
      $window->set_on_mouse( sub {
         shift;
         $self->on_mouse( @_ );
      } );
   }
}

sub window_lost
{
   my $self = shift;

   my $window = $self->window;

   $window->set_on_geom_changed( undef );
   $window->set_on_expose( undef );
   $window->set_on_key( undef );
   $window->set_on_mouse( undef );
}

=head2 $window = $widget->window

Returns the current window of the widget, if one has been set using
C<set_window>.

=cut

sub window
{
   my $self = shift;
   return $self->{window};
}

=head2 $widget->set_parent( $parent )

Sets the parent widget; pass C<undef> to remove the parent.

C<$parent>, if defined, must be a subclass of L<Tickit::ContainerWidget>.

=cut

sub set_parent
{
   my $self = shift;
   my ( $parent ) = @_;

   !$parent or $parent->isa( "Tickit::ContainerWidget" ) or croak "Parent must be a ContainerWidget";

   weaken( $self->{parent} = $parent );
}

=head2 $parent = $widget->parent

Returns the current container widget

=cut

sub parent
{
   my $self = shift;
   return $self->{parent};
}

=head2 $widget->resized

Provided for subclasses to call when their size requirements have or may have
changed. Informs the parent that the widget may require a differently-sized
window.

=cut

sub resized
{
   my $self = shift;

   if( $self->parent ) {
      $self->parent->child_resized( $self );
   }
   else {
      $self->reshape if $self->window;
      $self->redraw;
   }
}

=head2 $widget->redraw

Clears the widget's window then invokes the C<render> method. This should
completely redraw the widget.

This redraw doesn't happen immediately. The widget is marked as needing to
redraw, and its parent is marked that it has a child needing redraw,
recursively to the root widget. These will then be flushed out down the widget
tree using an C<Tickit> C<later> call. This allows other widgets to register a
requirement to redraw, and have them all flushed in a fairly efficient manner.

=cut

sub redraw
{
   my $self = shift;

   $self->window or return;
   $self->window->expose;
}

sub _do_clear
{
   my $self = shift;
   my ( $rect ) = @_;
   my $window = $self->window or return;

   if( my $parentwin = $window->parent ) {
      my $bg       = $window->get_effective_penattr( 'bg' );
      my $parentbg = $parentwin->get_effective_penattr( 'bg' );

      return 0 if !defined $bg and !defined $parentbg;
      return 0 if  defined $bg and  defined $parentbg and $bg == $parentbg;
   }

   $window->clearrect( $rect );
   return 1;
}

=head2 $pen = $widget->pen

Returns the widget's L<Tickit::Pen>. Modifying an attribute of the returned
object results in the widget being redrawn if the widget has a window
associated.

=cut

sub pen
{
   my $self = shift;
   return $self->{pen};
}

=head2 $widget->set_pen( $pen )

Set a new C<Tickit::Pen> object. This is stored by reference; changes to the
pen will be reflected in the rendered look of the widget. The same pen may be
shared by more than one widget; updates will affect them all.

=cut

sub set_pen
{
   my $self = shift;
   my ( $newpen ) = @_;

   croak ref($self)." uses Tickit::Style for its widget pen; ->set_pen cannot be used"
      if caller ne __PACKAGE__ and $self->WIDGET_PEN_FROM_STYLE;

   return if $self->{pen} and $self->{pen} == $newpen;

   $self->{pen}->remove_on_changed( $self ) if $self->{pen} and $self->{pen}->mutable;
   $self->{pen} = $newpen;
   $newpen->add_on_changed( $self ) if $newpen->mutable;

   if( $self->window ) {
      $self->window->set_pen( $newpen );
      $self->redraw;
   }
}

sub on_pen_changed
{
   my $self = shift;
   my ( $pen ) = @_;

   if( $self->window and $pen == $self->{pen} ) {
      $self->redraw;
   }
}

# Default empty implementation
sub reshape { }

=head1 SUBCLASS METHODS

Because this is an abstract class, the constructor must be called on a
subclass which implements the following methods.

=head2 $widget->render( %args )

Called to redraw the widget's content to its window. Methods can be called on
the contained L<Tickit::Window> object obtained from C<< $widget->window >>.

Will be passed hints on the region of the window that requires rendering; the
method implementation may choose to use this information to restrict drawing,
or it may ignore it entirely. Container widget should make sure to restrict
drawing to only this rectangle, however, as they may otherwise overwrite
content of contained widgets that will not be redrawn.

=over 8

=item rect => Tickit::Rect

A L<Tickit::Rect> object representing the region of the screen that requires
rendering, relative to the widget's window.

Also provided by the following four named integers:

=item top => INT

=item left => INT

The top-left corner of the region that requires rendering, relative to the
widget's window.

=item lines => INT

=item cols => INT

The size of the region that requires rendering.

=back

=head2 $widget->reshape

Optional. Called after the window geometry is changed. Useful to distribute
window change sizes to contained child widgets.

=head2 $lines = $widget->lines

=head2 $cols = $widget->cols

Called to enquire on the requested window for this widget. It is possible that
the actual allocated window may be larger, or smaller than this amount.

=head2 $widget->window_gained( $window )

Optional. Called by C<set_window> when a window has been set for this widget.

=head2 $widget->window_lost( $window )

Optional. Called by C<set_window> when C<undef> has been set as the window for
this widget. The old window object is passed in.

=head2 $handled = $widget->on_key( $type, $str, $key )

Optional. If provided, this method will be set as the C<on_key> callback for
any window set on the widget. By providing this method a subclass can
implement widgets that respond to user input.

=head2 $handled = $widget->on_mouse( $ev, $button, $line, $col )

Optional. If provided, this method will be set as the C<on_mouse> callback for
any window set on the widget. By providing this method a subclass can
implement widgets that respond to user input.

=head2 $widget->on_style_changed_values( %values )

Optional. If provided, this method will be called by C<set_style_tag> to
inform the widget which style keys may have changed values, as a result of the
tag change. The style values are passed in ARRAY references of two elements,
containing the old and new values.

The C<%values> hash may contain false positives in some cases, if the old and
the new value are actually the same, but it still appears from the style
definitions that certain keys are changed.

=cut

=head1 EXAMPLES

=head2 A Trivial "Hello, World" Widget

The following is about the smallest possible C<Tickit::Widget> implementation,
containing the bare minimum of functionallity. It displays the fixed string
"Hello, world" at the top left corner of its window.

 package HelloWorldWidget;
 use base 'Tickit::Widget';

 sub lines {  1 }
 sub cols  { 12 }

 sub render
 {
    my $self = shift;
    my $win = $self->window;

    $win->clear;
    $win->goto( 0, 0 );
    $win->print( "Hello, world" );
 }

 1;

The C<lines> and C<cols> methods tell the container of the widget what its
minimum size requirements are, and the C<render> method actually draws it to
the window.

A slight improvement on this would be to obtain the size of the window, and
position the text in the centre rather than the top left corner.

 sub render
 {
    my $self = shift;
    my $win = $self->window;

    $win->clear;
    $win->goto( ( $win->lines - 1 ) / 2, ( $win->cols - 12 ) / 2 );
    $win->print( "Hello, world" );
 }

A further improvement restricts rendering to only the lines specified by the
C<rect> argument, and also ensures not to double-print the line.

 sub render
 {
    my $self = shift;
    my %args = @_;
    my $win = $self->window;
    my $rect = $args{rect};

    my $content_line = int( ( $win->lines - 1 ) / 2 );

    foreach my $line ( $rect->top .. $content_line - 1 ) {
       $win->goto( $line, $rect->left );
       $win->erasech( $rect->cols );
    }

    if( $rect->top <= $content_line and $content_line < $rect->bottom ) {
       $win->goto( $content_line, ( $win->cols - 12 ) / 2 );
       $win->print( "Hello, world" );
    }

    foreach my $line ( $content_line + 1 .. $rect->bottom - 1 ) {
       $win->goto( $line, $rect->left );
       $win->erasech( $rect->cols );
    }
 }

=head2 Reacting To User Input

If a widget subclass provides an C<on_key> method, then this will receive
keypress events if the widget's window has the focus. This example uses it to
change the pen foreground colour.

 package ColourWidget;
 use base 'Tickit::Widget';

 my $text = "Press 0 to 7 to change the colour of this text";

 sub lines { 1 }
 sub cols  { length $text }

 sub render
 {
    my $self = shift;
    my $win = $self->window;

    $win->clear;
    $win->goto( ( $win->lines - $self->lines ) / 2, ( $win->cols - $self->cols ) / 2 );
    $win->print( $text );

    $win->focus( 0, 0 );
 }

 sub on_key
 {
    my $self = shift;
    my ( $type, $str ) = @_;

    if( $type eq "text" and $str =~ m/[0-7]/ ) {
       $self->pen->chattr( fg => $str );
       $self->redraw;
       return 1;
    }

    return 0;
 }

 1;

The C<render> method sets the focus at the window's top left corner to ensure
that the window always has focus, so the widget will receive keypress events.
(A real widget implementation would likely pick a more sensible place to put
the cursor).

The C<on_key> method then gets invoked for keypresses. It returns a true value
to indicate the keys it handles, returning false for the others, to allow
parent widgets or the main C<Tickit> object to handle them instead.

Similarly, by providing an C<on_mouse> method, the widget subclass will
receive mouse events within the window of the widget. This example saves a
list of the last 10 mouse clicks and renders them with an C<X>.

 package ClickerWidget;
 use base 'Tickit::Widget';

 # In a real Widget this would be stored in an attribute of $self
 my @points;

 sub lines { 1 }
 sub cols  { 1 }

 sub render
 {
    my $self = shift;
    my $win = $self->window;

    $win->clear;
    foreach my $point ( @points ) {
       $win->goto( $point->[0], $point->[1] );
       $win->print( "X" );
    }
 }

 sub on_mouse
 {
    my $self = shift;
    my ( $ev, $button, $line, $col ) = @_;

    return unless $ev eq "press" and $button == 1;

    push @points, [ $line, $col ];
    shift @points while @points > 10;
    $self->redraw;
 }

 1;

This time there is no need to set the window focus, because mouse events do
not need to follow the window that's in focus; they always affect the window
at the location of the mouse cursor.

The C<on_mouse> method then gets invoked whenever a mouse event happens within
the window occupied by the widget. In this particular case, the method filters
only for pressing button 1. It then stores the position of the mouse click in
the C<@points> array, for the C<render> method to use.

=cut

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
