#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2009-2011 -- leonerd@leonerd.org.uk

package Tickit::Term;

use strict;
use warnings;

our $VERSION = '0.05';

use base qw( IO::Async::Stream );
IO::Async::Stream->VERSION( 0.34 );

use IO::Async::Signal;

use Encode qw( find_encoding );
use Term::Terminfo;
use Term::Size;
use Term::TermKey::Async qw( FORMAT_ALTISMETA FLAG_UTF8 );

use Tickit::Pen;

my $ESC = "\e";
my $CSI = "$ESC\[";

=head1 NAME

C<Tickit::Term> - terminal IO handler

=head1 SYNOPSIS

=head1 DESCRIPTION

Provides terminal IO primatives for C<Tickit>. Split into two primary
sections:

=over 4

=item * Output

Methods to provide terminal output; writing text, changing pen attributes,
moving the cursor, etc.

=item * Input

Event callbacks for keypress events.

=back

=cut

=head1 CONSTRUCTOR

=cut

=head2 $term = Tickit::Term->new( %params )

As well as the configuration named parameters, takes the following named
arguments at construction time:

=over 8

=item term_in => IO

IO handle for terminal input. Will default to C<STDIN>.

=item term_out => IO

IO handle for terminal output. Will default to C<STDOUT>.

=back

=cut

sub new
{
   my $class = shift;
   my %params = @_;

   my $in  = delete $params{term_in}  || \*STDIN;
   my $out = delete $params{term_out} || \*STDOUT;

   my $self = $class->SUPER::new( %params );
   $self->SUPER::configure(
      write_handle => $out,
      autoflush => 1,
   );

   my $ti = Term::Terminfo->new();

   # Precache some terminfo flags that we know won't change
   $self->{has_bce} = $ti->getflag( "bce" );

   my $spacesym;

   my $tka = Term::TermKey::Async->new(
      term => $in,
      on_key => $self->_capture_weakself( sub {
         my $self = shift;
         my ( $tka, $key ) = @_;

         # libtermkey represents unmodified Space as a keysym, whereas we'd
         # prefer to treat it as plain text
         if( $key->type_is_unicode and !$key->modifiers ) {
            $self->maybe_invoke_event( on_key => text => $key->utf8, $key );
         }
         elsif( $key->type_is_keysym  and !$key->modifiers and $key->sym == $spacesym ) {
            $self->maybe_invoke_event( on_key => text => " ", $key );
         }
         elsif( $key->type_is_mouse ) {
            my ( $ev, $button, $line, $col ) = $tka->interpret_mouse( $key );
            my $evname = (qw( * press drag release ))[$ev];
            $self->maybe_invoke_event( on_mouse => $evname, $button, $line - 1, $col - 1 );
         }
         else {
            $self->maybe_invoke_event( on_key => key => $tka->format_key( $key, FORMAT_ALTISMETA ), $key );
         }
      } ),
   );

   $spacesym = $tka->keyname2sym( "Space" );

   if( $tka->get_flags & FLAG_UTF8 ) {
      $self->{encoder} = find_encoding( "UTF-8" );
   }

   $self->add_child( $tka );

   $self->add_child( IO::Async::Signal->new( 
      name => "WINCH",
      on_receipt => $self->_capture_weakself( sub {
         my $self = shift;
         $self->_recache_size;
         $self->maybe_invoke_event( on_resize => );
      } ),
   ) );

   $self->{pen} = {};

   # Almost certainly we'll start in a mode where the cursor is still visible
   $self->{mode_cursorvis} = 1;

   $self->_recache_size;

   return $self;
}

=head1 EVENTS

The following events are invoked, either using subclass methods or CODE
references in parameters:

=head2 on_resize

The terminal window has been resized.

=head2 on_key $type, $str, $key

A key was pressed. C<$type> will be C<text> for normal unmodified Unicode, or
C<key> for special keys or modified Unicode. C<$str> will be the UTF-8 string
for C<text> events, or the textual description of the key as rendered by
L<Term::TermKey> for C<key> events. C<$key> will be the underlying
C<Term::TermKey::Key> event structure.

=head2 on_mouse $ev, $button, $line, $col

A mouse event was received. C<$ev> will be C<press>, C<drag> or C<release>.
The button number will be in C<$button>, though may not be present for
C<release> events. C<$line> and C<$col> are 0-based. Behaviour of events
involving more than one mouse button is not well-specified by terminals.

=head1 PARAMETERS

The following named parameters may be passed to C<new> or C<configure>:

=over 8

=item on_resize => CODE

=item on_key => CODE

CODE references for event handlers.

=back

=cut

sub configure
{
   my $self = shift;
   my %params = @_;

   foreach (qw( on_resize on_key on_mouse )) {
      $self->{$_} = delete $params{$_} if exists $params{$_};
   }
}

=head1 METHODS

=cut

sub _recache_size
{
   my $self = shift;

   ( $self->{cols}, $self->{lines} ) = Term::Size::chars $self->write_handle;
}

=head2 $cols = $term->cols

=head2 $lines = $term->lines

Query the current size of the terminal. Will be cached and updated on receipt
of C<SIGWINCH> signals.

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

=head2 $term->print( $text )

Print the given text to the terminal at the current cursor position

=cut

sub print
{
   my $self = shift;
   my ( $text ) = @_;

   $text = $self->{encoder}->encode( $text ) if $self->{encoder};

   $self->write( $text );
}

=head2 $term->goto( $line, $col )

Move the cursor to the given position on the screen. If only one parameter is
defined, does not alter the other. Both C<$line> and C<$col> are 0-based.

=cut

sub goto
{
   my $self = shift;
   my ( $line, $col ) = @_;

   if( defined $col and defined $line ) {
      $self->write( sprintf "${CSI}%d;%dH", $line+1, $col+1 );
   }
   elsif( defined $line ) {
      $self->write( sprintf "${CSI}%dH", $line+1 );
   }
   elsif( defined $col ) {
      $self->write( sprintf "${CSI}%dG", $col+1 );
   }
}

=head2 $term->move( $downward, $rightward )

Move the cursor relative to where it currently is.

=cut

sub move
{
   my $self = shift;
   my ( $downward, $rightward ) = @_;

   if( $downward and $downward > 0 ) {
      $self->write( sprintf "${CSI}%dB", $downward );
   }
   elsif( $downward and $downward < 0 ) {
      $self->write( sprintf "${CSI}%dA", -$downward );
   }

   if( $rightward and $rightward > 0 ) {
      $self->write( sprintf "${CSI}%dC", $rightward );
   }
   elsif( $rightward and $rightward < 0 ) {
      $self->write( sprintf "${CSI}%dD", -$rightward );
   }
}

=head2 $term->scroll( $from, $to, $by )

Scroll the region of the screen that starts on line C<$from> until (and
including) line C<$to> down, C<$by> lines (upwards if negative).

=cut

sub scroll
{
   my $self = shift;
   my ( $from, $to, $by ) = @_;

   return if $by == 0;

   $self->write( sprintf "${CSI}%d;%dr", $from+1, $to+1 );

   if( $by > 0 ) {
      $self->goto( $to );
      $self->write( "\n" x $by );
   }
   else {
      $self->goto( $from );
      $self->write( "${ESC}M" x abs($by) ); # ESC M = Reverse Index
   }

   $self->write( "${CSI}r" );
}

sub _colspec_to_sgr
{
   my $self = shift;
   my ( $spec, $is_bg ) = @_;

   return $spec + ($is_bg?40:30) if $spec < 8;
   return +($spec-8) + ($is_bg?100:90) if $spec >= 8 and $spec < 16;

   # Defaults
   return $is_bg?49:39;
}

# Methods to make SGRs out of attribute values
sub _make_sgr_fg { defined $_[1] ? $_[0]->_colspec_to_sgr( $_[1], 0 ) : 39 }
sub _make_sgr_bg { defined $_[1] ? $_[0]->_colspec_to_sgr( $_[1], 1 ) : 49 }
sub _make_sgr_b  { $_[1] ? 1 : 22 }
sub _make_sgr_u  { $_[1] ? 4 : 24 }
sub _make_sgr_i  { $_[1] ? 3 : 23 }
sub _make_sgr_rv { $_[1] ? 7 : 27 }
sub _make_sgr_af { $_[1] ? $_[1]+10 : 10 }

=head2 $term->chpen( %attrs )

Changes the current pen attributes to those given. Any attribute whose value
is given as C<undef> is reset. Any attributes not named are unchanged.

For details of the supported pen attributes, see L<Tickit::Pen>.

=cut

sub chpen
{
   my $self = shift;
   my %new = @_;

   my $pen = $self->{pen};

   my @SGR;

   foreach my $attr (@Tickit::Pen::ALL_ATTRS) {
      next unless exists $new{$attr};

      my $val = $new{$attr};

      next if !defined $pen->{$attr} and !defined $val and exists $pen->{$attr};
      next if  defined $pen->{$attr} and  defined $val and $pen->{$attr} eq $val;

      $pen->{$attr} = $val;

      my $method = "_make_sgr_$attr";
      push @SGR, $self->$method( $val );
   }

   # Shortcut - if there's no pen attributes left, just send SGR reset. Fewer
   # bytes down possibly-slow terminal link that way.
   if( grep { $pen->{$_} } keys %$pen ) {
      $self->write( "${CSI}" . join( ";", @SGR ) . "m" ) if @SGR;
   }
   else {
      $self->write( "${CSI}m" );
   }
}

=head2 $term->setpen( %attrs )

Similar to C<chpen>, but completely defines the state of the terminal pen. Any
attribute not given will be reset to its default value.

=cut

sub setpen
{
   my $self = shift;
   my %new = @_;

   $self->chpen( map { $_ => $new{$_} } @Tickit::Pen::ALL_ATTRS );
}

=head2 $term->clear

Erase the entire screen

=cut

sub clear
{
   my $self = shift;
   $self->write( "${CSI}2J" );
}

=head2 $term->eraseinline

Clear the current line from the cursor onwards.

=cut

sub eraseinline
{
   my $self = shift;
   $self->write( "${CSI}K" );
}

=head2 $term->erasech( $count, $moveend )

Erase C<$count> characters forwards. If C<$moveend> is true, the cursor is
moved to the end of the erased region. If false, the cursor will remain where
it is.

Using C<$moveend> may be more efficient than separate C<erasech> and C<goto>
calls on terminals that do not have an erase function, as it will be
implemented by printing spaces. This removes the need for two cursor jumps.

=cut

sub erasech
{
   my $self = shift;
   my ( $count, $moveend ) = @_;

   # If we have a background colour and the term does not have background
   # colour erase, we'll need to print spaces to set the colour
   if( $self->{pen}{bg} and !$self->{has_bce} ) {
      $self->write( " " x $count );
      $self->write( sprintf "${CSI}%dD", $count ) if !$moveend;
   }
   else {
      $self->write( sprintf "${CSI}%dX", $count );
      $self->write( sprintf "${CSI}%dC", $count ) if $moveend;
   }
}

=head2 $term->insertch( $count )

Insert C<$count> blank characters, shifting following text to the right.

=cut

sub insertch
{
   my $self = shift;
   my ( $count ) = @_;

   $self->write( sprintf "${CSI}%d@", $count );
}

=head2 $term->deletech( $count )

Delete the following C<$count> characters, shifting the remaining text to the
left. The terminal will fill the empty region with blanks.

=cut

sub deletech
{
   my $self = shift;
   my ( $count ) = @_;

   $self->write( sprintf "${CSI}%dP", $count );
}

=head2 $term->mode_altscreen( $on )

Set or clear the DEC Alternate Screen mode

=cut

sub mode_altscreen
{
   my $self = shift;
   my ( $on ) = @_;

   $self->write( $on ? "${CSI}?1049h" : "${CSI}?1049l" );
}

=head2 $term->mode_cursorvis( $on )

Set or clear the cursor visible mode

=cut

sub mode_cursorvis
{
   my $self = shift;
   my ( $on ) = @_;

   return if $self->{mode_cursorvis} == $on;
   $self->{mode_cursorvis} = $on;

   $self->write( $on ? "${CSI}?25h" : "${CSI}?25l" );
}

=head2 $term->mode_mouse( $on )

Set or clear the mouse tracking mode

=cut

sub mode_mouse
{
   my $self = shift;
   my ( $on ) = @_;

   $self->write( $on ? "${CSI}?1002h" : "${CSI}?1002l" );
}

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
