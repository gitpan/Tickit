#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2009-2012 -- leonerd@leonerd.org.uk

package Tickit::Term;

use strict;
use warnings;

our $VERSION = '0.15';

use Encode qw( find_encoding );
use Term::Size;
use Term::TermKey 0.11 qw( FORMAT_ALTISMETA FLAG_UTF8 FLAG_RAW FLAG_EINTR RES_KEY RES_AGAIN );
use Term::Terminfo;
use Time::HiRes qw( time );

use constant FLAGS_UTF8_RAW => FLAG_UTF8|FLAG_RAW;

use Tickit::Pen;

my $ESC = "\e";
my $CSI = "$ESC\[";

=head1 NAME

C<Tickit::Term> - terminal formatting abstraction

=head1 SYNOPSIS

=head1 DESCRIPTION

Provides terminal control primatives for L<Tickit>; a number of methods that
control the terminal by writing control strings. This object itself performs
no acutal IO work; it writes bytes to a delegated object given to the
constructor called the writer.

This object is not normally constructed directly by the containing
application; instead it is used indirectly by other parts of the C<Tickit>
distribution.

=cut

=head1 CONSTRUCTOR

=cut

=head2 $term = Tickit::Term->find_for_term( %params )

Attempts to load and construct a subclass determined by the current terminal
type (as given by C<$ENV{TERM}>). If this fails, returns a normal
C<Tickit::Term> instead.

=cut

sub find_for_term
{
   my $class = shift;

   if( defined( my $term = $ENV{TERM} ) ) {
      my $subclass = "${class}::$term";
      ( my $file = "$subclass.pm" ) =~ s{::}{/}g;

      my $self;
      eval { require $file and $self = $subclass->new( @_ ) } and
         return $self;
   }

   return $class->new( @_ );
}

=head2 $term = Tickit::Term->new( %params )

Constructs a new C<Tickit::Term> object.

Takes the following named arguments at construction time:

=over 8

=item encoding => STRING

Optional. If supplied, applies the named encoding to the Unicode string
supplied to the C<print> method.

=item writer => OBJECT

An object delegated to for sending strings of terminal control bytes to the
terminal itself. This object must support a single method, C<write>, taking
a string of bytes.

 $writer->write( $data )

Such an interface is supported by an C<IO::Handle> object.

=item output_handle => HANDLE

Optional. If supplied, will be used as the terminal filehandle for querying
the size. Even if supplied, all writing operations will use the C<writer>
function rather than performing IO operations on this filehandle.

=item input_handle => HANDLE

Optional. If supplied, will be used as the terminal filehandle for reading
keypress and other events.

=item on_resize => CODE

Optional. Event handler function for when the terminal window is resized. Will
be passed the C<Tickit::Term> instance, and the new size.

 $on_resize->( $term, $lines, $cols )

=item on_key => CODE

Optional. Event handler function for when a key is pressed. Will be passed the
C<Tickit::Term> instance, a type string (either C<text> for unmodified Unicode
or C<key> for special keys or modified Unicode), a string containing a
representation of the text or key, and the underlying C<Term::TermKey::Key>
event.

 $on_key->( $term, $type, $str, $key )

=item on_mouse => CODE

Optional. Event handler function for when a mouse button is pressed or
released, or the cursor dragged with a button pressed. Will be passed the
C<Tickit::Term> instance, a string indicating C<press>, C<drag> or C<release>,
the button number, and the 0-based line and column index.

 $on_mouse->( $term, $ev, $button, $line, $col )

=back

=cut

sub new
{
   my $class = shift;
   my %params = @_;

   my $encoding = delete $params{encoding};

   my $termkey = Term::TermKey->new( $params{input_handle}, FLAG_EINTR );

   my $is_utf8 = defined $params{UTF8} ? $params{UTF8} : ${^UTF8LOCALE};
   $termkey->set_flags( ( $termkey->get_flags & ~FLAGS_UTF8_RAW ) |
                        ( $is_utf8 ? FLAG_UTF8 : FLAG_RAW ) );

   $encoding = "UTF-8" if $is_utf8;

   my $self = bless {
      writer => $params{writer},

      input_handle  => $params{input_handle},
      output_handle => $params{output_handle},

      lines => 0, # Will be filled in by refresh_size
      cols  => 0,

      termkey => $termkey,
   }, $class;

   my $ti = Term::Terminfo->new();

   # Precache some terminfo flags that we know won't change
   $self->{has_bce} = $ti->getflag( "bce" );

   $self->{lines} = $ti->getnum( "lines" );
   $self->{cols}  = $ti->getnum( "cols" );

   $self->refresh_size if $self->{output_handle};

   $self->set_on_resize( $params{on_resize} ) if $params{on_resize};
   $self->set_on_key   ( $params{on_key}    ) if $params{on_key};
   $self->set_on_mouse ( $params{on_mouse}  ) if $params{on_mouse};

   if( defined $encoding ) {
      $self->{encoder} = find_encoding( $encoding );
   }

   $self->{pen} = {};

   # Almost certainly we'll start in a mode where the cursor is still visible
   $self->{mode_cursorvis} = 1;

   return $self;
}

sub write
{
   my $self = shift;
   $self->{writer}->write( @_ );
}

=head1 METHODS

=cut

=head2 $fh = $term->get_input_handle

Returns the input handle set by the C<input_handle> constructor arg.

=cut

sub get_input_handle
{
   my $self = shift;
   return $self->{input_handle};
}

=head2 $fh = $term->get_output_handle

Returns the output handle set by the C<output_handle> constructor arg.

=cut

sub get_output_handle
{
   my $self = shift;
   return $self->{output_handle};
}

=head2 $term->set_on_resize( $on_resize )

=cut

sub set_on_resize
{
   my $self = shift;
   ( $self->{on_resize} ) = @_;
}

=head2 $term->set_on_key( $on_key )

=cut

sub set_on_key
{
   my $self = shift;
   ( $self->{on_key} ) = @_;
}

=head2 $term->set_on_mouse( $on_mouse )

Set a new CODE references to handle events.

=cut

sub set_on_mouse
{
   my $self = shift;
   ( $self->{on_mouse} ) = @_;
}

=head2 $term->refresh_size

If a filehandle was supplied to the constructor, fetch the size of the
terminal and update the cached sizes in the object. May invoke C<on_resize> if
the new size is different.

=cut

sub refresh_size
{
   my $self = shift;
   return unless my $fh = $self->get_output_handle;
   my ( $cols, $lines ) = Term::Size::chars $fh;
   # Due to Term::Size bug RT76292, $cols is always defined
   $self->set_size( $lines, $cols ) if defined $lines;
}

=head2 $term->set_size( $lines, $cols )

Defines the size of the terminal. Invoke C<on_resize> if the new size is
different.

=cut

sub set_size
{
   my $self = shift;
   my ( $lines, $cols ) = @_;

   if( $lines != $self->{lines} or $cols != $self->{cols} ) {
      $self->{lines} = $lines;
      $self->{cols}  = $cols;

      $self->{on_resize}->( $self, $lines, $cols ) if $self->{on_resize};
   }
}

=head2 $lines = $term->lines

=head2 $cols = $term->cols

Query the size of the terminal, as set by the most recent C<refresh_size> or
C<set_size> operation.

=cut

sub lines { shift->{lines} }
sub cols  { shift->{cols}  }

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

=head2 $success = $term->scrollrect( $top, $left, $lines, $cols, $downward, $rightward )

Attempt to scroll the rectangle of the screen defined by the first four
parameters by an amount given by the latter two. Since most terminals cannot
perform arbitrary rectangle scrolling, this method returns a boolean to
indicate if it was successful. The caller should test this return value and
fall back to another drawing strategy if the attempt was unsuccessful.

The cursor may move as a result of calling this method; its location is
undefined if this method returns successful.

=cut

sub scrollrect
{
   my $self = shift;
   my ( $top, $left, $lines, $cols, $downward, $rightward ) = @_;

   return 1 if !$downward and !$rightward;

   if( $left == 0 and $cols == $self->cols and $rightward == 0 ) {
      $self->_scroll_lines( $top, $top + $lines - 1, $downward );
      return 1;
   }

   if( $left + $cols == $self->cols and $downward == 0 ) {
      foreach my $line ( $top .. $top + $lines - 1 ) {
         $self->goto( $line, $left );
         $rightward > 0 ? $self->insertch(  $rightward )
                        : $self->deletech( -$rightward );
      }
      return 1;
   }

   return 0;
}

sub _scroll_lines
{
   my $self = shift;
   my ( $from, $to, $by ) = @_;

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
sub _make_sgr_b      { $_[1] ? 1 : 22 }
sub _make_sgr_u      { $_[1] ? 4 : 24 }
sub _make_sgr_i      { $_[1] ? 3 : 23 }
sub _make_sgr_rv     { $_[1] ? 7 : 27 }
sub _make_sgr_strike { $_[1] ? 9 : 29 }
sub _make_sgr_af     { $_[1] ? $_[1]+10 : 10 }

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

sub eraseinline
{
   my $self = shift;
   $self->write( "${CSI}K" );
}

=head2 $term->erasech( $count, $moveend )

Erase C<$count> characters forwards. If C<$moveend> is true, the cursor is
moved to the end of the erased region. If defined but false, the cursor will
remain where it is. If undefined, the terminal will perform whichever of these
behaviours is more efficient, and the cursor will end at some undefined
location.

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
      $self->write( sprintf "${CSI}%dD", $count ) if defined $moveend and !$moveend;
   }
   else {
      $self->write( sprintf "${CSI}%dX", $count );
      $self->write( sprintf "${CSI}%dC", $count ) if $moveend;
   }
}

sub insertch
{
   my $self = shift;
   my ( $count ) = @_;

   $self->write( sprintf "${CSI}%d@", $count );
}

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

=head2 $term->input_push_bytes( $bytes )

Feeds more bytes of input. May result in C<on_key> or C<on_mouse> events.

=cut

sub input_push_bytes
{
   my $self = shift;
   my ( $bytes ) = @_;

   my $termkey = $self->{termkey};

   $termkey->push_bytes( $bytes );

   $self->_get_keys;
}

=head2 $term->input_readable

Informs the term that the input handle may be readable. Attempts to read more
bytes of input. May result in C<on_key> or C<on_mouse> events.

=cut

sub input_readable
{
   my $self = shift;

   my $termkey = $self->{termkey};

   $termkey->advisereadable;

   $self->_get_keys;
}

=head2 $term->input_wait

Block until some input is available, and process it. Returns after one round
of input has been processed. May result in C<on_key> or C<on_mouse> events.

=cut

sub input_wait
{
   my $self = shift;

   my $termkey = $self->{termkey};

   my $key;
   $termkey->waitkey( $key );

   $self->_got_key( $key );

   # Might as well process the remaining if there are any
   while( $termkey->getkey( $key ) == RES_KEY ) {
      $self->_got_key( $key );
   }
}

sub _got_key
{
   my $self = shift;
   my ( $key ) = @_;

   my $termkey = $self->{termkey};

   if( $key->type_is_unicode and !$key->modifiers ) {
      $self->{on_key}->( $self, text => $key->utf8, $key ) if $self->{on_key};
   }
   elsif( $key->type_is_mouse ) {
      my ( $ev, $button, $line, $col ) = $termkey->interpret_mouse( $key );
      my $evname = (qw( * press drag release ))[$ev];
      $self->{on_mouse}->( $self, $evname, $button, $line - 1, $col - 1 ) if $self->{on_mouse};
   }
   else {
      $self->{on_key}->( $self, key => $termkey->format_key( $key, FORMAT_ALTISMETA ), $key ) if $self->{on_key};
   }
}

sub _get_keys
{
   my $self = shift;

   my $termkey = $self->{termkey};

   my $res;
   while( ( $res = $termkey->getkey( my $key ) ) == RES_KEY ) {
      $self->_got_key( $key );
   }

   if( $res == RES_AGAIN ) {
      $self->{input_timeout_at} = time + ( $termkey->get_waittime / 1000 ); # msec
   }
   else {
      undef $self->{input_timeout_at};
   }
}

sub _force_key
{
   my $self = shift;

   my $termkey = $self->{termkey};

   if( $termkey->getkey_force( my $key ) == RES_KEY ) {
      $self->_got_key( $key );
   }
}

=head2 $timeout = $term->check_timeout

Returns a number in seconds to represent when the next timeout should occur on
the terminal, or C<undef> if nothing is waiting. May invoke expired timeouts,
and cause a C<on_key> event to occur.

=cut

sub check_timeout
{
   my $self = shift;
   return undef unless defined( my $timeout_at = $self->{input_timeout_at} );

   my $timeout = $timeout_at - time;

   if( $timeout <= 0 ) {
      $self->_force_key;
      undef $self->{input_timeout_at};
      return undef;
   }
   else {
      return $timeout;
   }
}

=head1 TODO

=over 4

=item *

Track cursor position, and optimise (or eliminate entirely) C<goto> calls.

=back

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
