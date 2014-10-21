#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2013 -- leonerd@leonerd.org.uk

package Tickit::Style;

use strict;
use warnings;
use 5.010;

our $VERSION = '0.32';

use Carp;

use Tickit::Pen;
use Tickit::Style::Parser;

our @EXPORTS = qw(
   style_definition
   style_reshape_keys
   style_reshape_textwidth_keys
);

# {$type}->{$class} = $tagset
my %TAGSETS_BY_TYPE_CLASS;

# {$type}->{$key} = 1
my %RESHAPE_KEYS;
my %RESHAPE_TEXTWIDTH_KEYS;

=head1 NAME

C<Tickit::Style> - declare customisable style information on widgets

=head1 SYNOPSIS

 package My::Widget::Class
 use base qw( Tickit::Widget );
 use Tickit::Style;

 style_definition base =>
    fg => "red";

 style_definition ':active' =>
    b => 1;

 ...

 sub render
 {
    my $self = shift;
    my $win = $self->window or return;

    $win->goto( 0, 0 );
    $win->print( "Here is my text", $self->get_style_pen );
 }

=head1 DESCRIPTION

This module adds the ability to a L<Tickit::Widget> class to declare a set of
named keys that take values, and provides convenient accessors for the widget
to determine what the values are at any given moment in time. The values
currently in effect are determined by the widget class code, and any 
stylesheet files loaded by the application.

The widget itself can store a set of tags; named entities that may be present
or absent. The set of tags currently active on a widget helps to determine
which definitions style are to be used.

Finally, the widget itself stores a list of style class names. These classes
also help determine which style definitions from a loaded stylesheet file are
applied.

=head2 Stylesheet Files

A stylesheet file contains a list of definitions of styles. Each definition
gives a C<Tickit::Widget> class name, optionally a style class name prefixed
by a period (C<.>), optionally a set of tags prefixed with colons (C<:>), and
a body definition in a brace-delimited (C<{}>) block.

 WidgetClass {
   # basic style goes here
 }

 WidgetClass.styleclass {
   # style to apply for this class goes here
 }

 WidgetClass:tag {
   # style to apply when this tag is active goes here
 }

Each style definition contains a set semicolon-delimited (C<;>) assignments of
values to keys. Each key is suffixed by a colon (C<:>), and the values may be
integers, quoted strings (C<"...">), or the special identifiers C<true> or
C<false>.

 WidgetClass.styleclass {
   key1: "value 1";
   key2: 123;
   key3: true;
 }

While it is more traditional for keys in stylesheet files to contain hypens
(C<->), it is more convenient in Perl code to use underscores (C<_>) instead.
The parser will convert hypens in key names into underscores.

=head2 How Style is Determined

The full set of style definitions applied to one named class of one widget
type for all its style tags is called a "tagset". Each tagset consists of a
partially-ordered list of entities called "keysets", which give a mapping from
style keys to values for one particular set of active style tags. The widget
may also have a special tagset containing the "direct-applied" style
definition given to the constructor.

The style at any given moment is determined by taking into account the style
classes and tags that are in effect. The value of each key is determined by a
first-match-wins search along the "direct applied" tagset (if present), then
the tagset for each of the style classes, in order, followed finally by the
base tagset for the widget type without class.

Within each tagset, only the keysets that do not depend on a style tag that is
inactive are considered. That is, a keyset that depends on no tags will always
be considered, and any keyset that only depends on active keys will be
considered, even if there are other active tags that the keyset does not
consider. Tags are always additive, in this regard.

While the order of the tagsets is exactly defined by the order of the style
classes applied to the widget, the order of keysets within each tagset is not
fully specified. Tagsets are stored partially ordered, sorted by the number of
style tags that each keyset depends on. This ensures that more specific
keysets are found before, and therefore override, less specific ones. However,
it is not defined the ordering of keysets with equal numbers of (distinct)
tags.

For instance, if both C<tag1> and C<tag2> are active, the following
stylesheet does not precisely determine the foreground colour:

 WidgetClass      { fg: "red"; }
 WidgetClass:tag1 { fg: "blue"; }
 WidgetClass:tag2 { fg: "green"; }

While it is not specified which tagged definition takes precedence, and
therefore whether it shall be red or blue, it is specified that both of the
tagged definitions take precedence over the untagged definition, so the colour
will not be green.

=head1 SUBCLASSING

If a Widget class is subclassed and the subclass does not declare
C<use Tickit::Style> again, the subclass will be transparent from the point of
view of style. Any style applied to the base class will apply equally to the
subclass, and the name of the subclass does not take part in style decisions.

If the subclass does C<use Tickit::Style> again then the new subclass will be
a distinct widget type for style purposes, and it will require its own new set
of base style definitions.

=cut

# This class imports functions and sets up initial state
sub import
{
   my $class = shift;
   my $pkg = caller;

   ( my $type = $pkg ) =~ s/^Tickit::Widget:://;

   # Import the symbols
   {
      no strict 'refs';
      *{"${pkg}::$_"} = \&{"Tickit::Style::$_"} for @EXPORTS;
      *{"${pkg}::_widget_style_type"} = sub () { $type };
   }

   $TAGSETS_BY_TYPE_CLASS{$type} ||= {};
}

sub _ref_tagset
{
   my ( $type, $class ) = @_;

   $TAGSETS_BY_TYPE_CLASS{$type} or croak "$type is not a styled Widget type";

   $class = "" if !defined $class;
   return $TAGSETS_BY_TYPE_CLASS{$type}{$class} ||= Tickit::Style::_Tagset->new;
}

=head1 FUNCTIONS

=cut

=head2 style_definition( $tags, %definition )

In addition to any loaded stylesheets, the widget class itself can provide
style information, via the C<style_definition> function. It provides a definition
equivalent to a stylesheet definition with no style class, optionally with a
single set of tags. To supply no tags, use the special string C<"base">.

 style_definition base =>
    key1 => "value",
    key2 => 123;

To provide definitions with tags, use the colon-prefixed notation.

 style_definition ':active' =>
    key3 => "value";

=cut

sub style_definition
{
   my $class = caller;
   my ( $tags, %definition ) = @_;

   my %tags;
   $tags{$1}++ while $tags =~ s/:([A-Z0-9_]+)//i;

   die "Expected '\$tags' to be 'base' or a set of :tag names" unless $tags eq "base" or $tags eq "";

   my $type = $class->_widget_style_type;
   _ref_tagset( $type, undef )->merge_with_tags( \%tags, \%definition );
}

=head2 style_reshape_keys( @keys )

Declares that the given list of keys are somehow responsible for determining
the shape of the widget. If their values are changed, the C<reshape> method is
called.

=cut

sub style_reshape_keys
{
   my $class = caller;

   my $type = $class->_widget_style_type;
   $RESHAPE_KEYS{$type}{$_} = 1 for @_;
}

sub _reshape_keys
{
   my ( $type ) = @_;
   return keys %{ $RESHAPE_KEYS{$type} };
}

=head2 style_reshape_textwidth_keys( @keys )

Declares that the given list of keys contain text, the C<textwidth()> of which
is used to determine the shape of the widget. If their values are changed such
that the C<textwidth()> differs, the C<reshape> method is called.

Between them these two methods may help avoid C<Tickit::Widget> classes from
needing to override the C<on_style_changed_values> method.

=cut

sub style_reshape_textwidth_keys
{
   my $class = caller;

   my $type = $class->_widget_style_type;
   $RESHAPE_TEXTWIDTH_KEYS{$type}{$_} = 1 for @_;
}

sub _reshape_textwidth_keys
{
   my ( $type ) = @_;
   return keys %{ $RESHAPE_TEXTWIDTH_KEYS{$type} };
}

my @ON_STYLE_LOAD;

# Not exported
sub _load_style
{
   my ( $defs ) = @_;

   foreach my $def ( @$defs ) {
      my $type = $def->type;
      $TAGSETS_BY_TYPE_CLASS{$type} ||= {};
      my $tagset = _ref_tagset( $type, $def->class );
      $tagset->merge_with_tags( $def->tags, $def->style );
   }

   foreach my $code ( @ON_STYLE_LOAD ) {
      $code->();
   }
}

=head1 ADDITIONAL FUNCTIONS

These functions are not exported, but may be called directly.

=cut

=head2 Tickit::Style::load_style( $string )

Loads definitions from a stylesheet given in a string.

Definitions will be merged with existing definitions in memory, with new
values overwriting existing values.

=cut

sub load_style
{
   shift;
   my ( $str ) = @_;
   _load_style( Tickit::Style::Parser->new->from_string( $str ) );
}

=head2 Tickit::Style::load_style_file( $path )

Loads definitions from a stylesheet file given by the path.

Definitions will be merged the same way as C<load_style>.

=cut

sub load_style_file
{
   shift;
   my ( $path ) = @_;
   # TODO: use ->from_file( $path, binmode => ":encoding(UTF-8)" ) when available
   my $str = do {
      open my $fh, "<:encoding(UTF-8)", $path or croak "Cannot read $path - $!";
      local $/;
      <$fh>;
   };
   _load_style( Tickit::Style::Parser->new->from_string( $str ) );
}

=head2 Tickit::Style::on_style_load( \&code )

Adds a CODE reference to be invoked after either C<load_style> or
C<load_style_file> are called. This may be useful to flush any caches or
invalidate any state that depends on style information.

=cut

sub on_style_load
{
   my ( $code ) = @_;
   push @ON_STYLE_LOAD, $code;
}

package # hide from indexer
   Tickit::Style::_Tagset;

use Struct::Dumb;

# A "Keyset" is the set of style keys applied to one particular set of style
# tags
struct Keyset => [qw( tags style )];

sub new
{
   my $class = shift;
   return bless [], $class;
}

sub add
{
   my $self = shift;
   my ( $key, $value ) = @_;

   my %tags;
   $tags{$1}++ while $key =~ s/:([A-Z0-9_]+)//i;

   $self->merge_with_tags( \%tags, { $key => $value } );
}

sub merge
{
   my $self = shift;
   my ( $other ) = @_;

   foreach my $keyset ( $other->keysets ) {
      $self->merge_with_tags( $keyset->tags, $keyset->style );
   }
}

sub merge_with_tags
{
   my $self = shift;
   my ( $tags, $style ) = @_;

   my $keyset = Keyset( $tags, $style );
   @$self = ( $keyset ) and return if !@$self;

   # First see if we have to merge an existing one
   KEYSET: foreach my $keyset ( @$self ) {
      $keyset->tags->{$_} or next KEYSET for keys %$tags;
      $tags->{$_} or next KEYSET for keys %{ $keyset->tags };

      # Merge
      foreach my $key ( keys %$style ) {
         defined $style->{$key} ? $keyset->style->{$key} = $style->{$key}
                                : delete $keyset->style->{$key};
      }
      return;
   }

   # Keep sorted, most tags first
   # TODO: this might be doable more efficiently but we don't care for now
   @$self = sort { scalar keys %{ $b->tags } <=> scalar keys %{ $a->tags } } ( @$self, $keyset );
}

sub keysets
{
   my $self = shift;
   return @$self;
}

0x55AA;
