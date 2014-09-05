#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2009-2014 -- leonerd@leonerd.org.uk

package Tickit::Term;

use strict;
use warnings;

our $VERSION = '0.47';

use Carp;

# Load the XS code
require Tickit;

# We export some constants
use Exporter 'import';

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

=item UTF8 => BOOL

If defined, overrides locale detection to enable or disable UTF-8 mode. If not
defined then this will be detected from the locale by using Perl's
C<${^UTF8LOCALE}> variable.

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

=back

=cut

sub new
{
   my $class = shift;
   my %params = @_;

   my $self = $class->_new( $ENV{TERM} ) or croak "Cannot construct Tickit::Term - $!";

   $self->set_input_handle ( $params{input_handle}  ) if $params{input_handle};
   $self->set_output_handle( $params{output_handle} ) if $params{output_handle};

   my $writer = $params{writer};
   $self->set_output_func( sub { $writer->write( @_ ) } ) if $writer;

   $self->set_utf8( $params{UTF8} ) if defined $params{UTF8};

   $self->set_on_resize( $params{on_resize} ) if $params{on_resize};
   $self->set_on_key   ( $params{on_key}    ) if $params{on_key};
   $self->set_on_mouse ( $params{on_mouse}  ) if $params{on_mouse};

   return $self;
}

=head1 METHODS

=cut

=head2 $fh = $term->get_input_handle

Returns the input handle set by the C<input_handle> constructor arg.

=cut

=head2 $fh = $term->get_output_handle

Returns the output handle set by the C<output_handle> constructor arg.

=cut

=head2 $term->set_output_buffer( $len )

Sets the size of the output buffer

=cut

=head2 $term->await_started( $timeout )

Waits for the terminal startup process to complete, up to the timeout given in
seconds.

=cut

=head2 $term->flush

Flushes the output buffer to the terminal

=cut

=head2 $id = $term->bind_event( $ev, $code, $data )

Installs a new event handler to watch for the event specified by C<$ev>,
invoking the C<$code> reference when it occurs. C<$code> will be invoked with
the given the terminal, the event name, a C<HASH> reference containing event
arguments, and the C<$data> value. It returns an ID value that may be used to
remove the handler by calling C<unbind_event_id>.

 $code->( $term, $ev, $args, $data )

The C<$args> hash will contain keys depending on the event type:

=over 8

=item key

The hash will contain C<type> (a dualvar giving the key event type as an
integer or string event name, C<text> or C<key>), C<str> (a string containing
the key event string), and C<mod> (an integer bitmask indicating the modifier
state).

=item mouse

The hash will contain C<type> (a dualvar giving the mouse event type as an
integer or string event name, C<press>, C<drag>, C<release> or C<wheel>),
C<button> (an integer for non-wheel events, or a dualvar for wheel events
giving the wheel direction as C<up> or C<down>), C<line> and C<col> as
integers, and C<mod> (an integer bitmask indicating the modifier state).

=item resize

The hash will contain C<lines> and C<cols> as integers.

=back

=cut

=head2 $term->unbind_event_id( $id )

Removes an event handler that returned the given C<$id> value.

=cut

sub set_on_resize
{
   my $self = shift;
   my ( $code ) = @_;

   $self->unbind_event_id( delete $self->_event_ids->{resize} ) if exists $self->_event_ids->{resize};
   $self->_event_ids->{resize} = $self->bind_event( resize => sub {
      my ( undef, $ev, $args ) = @_;
      $code->( $self, $args->{lines}, $args->{cols} );
   } );
}

sub set_on_key
{
   my $self = shift;
   my ( $code ) = @_;

   $self->unbind_event_id( delete $self->_event_ids->{key} ) if exists $self->_event_ids->{key};
   $self->_event_ids->{key} = $self->bind_event( key => sub {
      my ( undef, $ev, $args ) = @_;
      $code->( $self, $args->{type}, $args->{str} );
   } );
}

sub set_on_mouse
{
   my $self = shift;
   my ( $code ) = @_;

   $self->unbind_event_id( delete $self->_event_ids->{mouse} ) if exists $self->_event_ids->{mouse};
   $self->_event_ids->{mouse} = $self->bind_event( mouse => sub {
      my ( undef, $ev, $args ) = @_;
      $code->( $self, $args->{type}, $args->{button}, $args->{line}, $args->{col} );
   } );
}

=head2 $term->refresh_size

If a filehandle was supplied to the constructor, fetch the size of the
terminal and update the cached sizes in the object. May invoke C<on_resize> if
the new size is different.

=cut

=head2 $term->set_size( $lines, $cols )

Defines the size of the terminal. Invoke C<on_resize> if the new size is
different.

=cut

=head2 $lines = $term->lines

=head2 $cols = $term->cols

Query the size of the terminal, as set by the most recent C<refresh_size> or
C<set_size> operation.

=cut

sub lines { ( shift->get_size )[0] }
sub cols  { ( shift->get_size )[1]  }

=head2 $success = $term->goto( $line, $col )

Move the cursor to the given position on the screen. If only one parameter is
defined, does not alter the other. Both C<$line> and C<$col> are 0-based.

Note that not all terminals can support these partial moves. This method
returns a boolean indicating success; if the terminal could not perform the
move it will need to be retried using a fully-specified call.

=cut

=head2 $term->move( $downward, $rightward )

Move the cursor relative to where it currently is.

=cut

=head2 $success = $term->scrollrect( $top, $left, $lines, $cols, $downward, $rightward )

Attempt to scroll the rectangle of the screen defined by the first four
parameters by an amount given by the latter two. Since most terminals cannot
perform arbitrary rectangle scrolling, this method returns a boolean to
indicate if it was successful. The caller should test this return value and
fall back to another drawing strategy if the attempt was unsuccessful.

The cursor may move as a result of calling this method; its location is
undefined if this method returns successful.

=cut

=head2 $term->chpen( $pen )

=head2 $term->chpen( %attrs )

Changes the current pen attributes to those given. Any attribute whose value
is given as C<undef> is reset. Any attributes not named are unchanged.

For details of the supported pen attributes, see L<Tickit::Pen>.

=cut

=head2 $term->setpen( $pen )

=head2 $term->setpen( %attrs )

Similar to C<chpen>, but completely defines the state of the terminal pen. Any
attribute not given will be reset to its default value.

=cut

=head2 $term->print( $text, [ $pen ] )

Print the given text to the terminal at the current cursor position.

An optional C<Tickit::Pen> may be provided; if present it will be set as if
given to C<setpen> first.

=cut

=head2 $term->clear( [ $pen ] )

Erase the entire screen.

An optional C<Tickit::Pen> may be provided; if present it will be set as if
given to C<setpen> first.

=cut

=head2 $term->erasech( $count, $moveend, [ $pen ] )

Erase C<$count> characters forwards. If C<$moveend> is true, the cursor is
moved to the end of the erased region. If defined but false, the cursor will
remain where it is. If undefined, the terminal will perform whichever of these
behaviours is more efficient, and the cursor will end at some undefined
location.

Using C<$moveend> may be more efficient than separate C<erasech> and C<goto>
calls on terminals that do not have an erase function, as it will be
implemented by printing spaces. This removes the need for two cursor jumps.

An optional C<Tickit::Pen> may be provided; if present it will be set as if
given to C<setpen> first.

=cut

=head2 $value = $term->getctl_int( $ctl )

=head2 $success = $term->setctl_int( $ctl, $value )

Gets or sets the value of an integer terminal control option. C<$ctl> should
be one of the following options. They can be specified either as integers,
using the following named constants, or as strings giving the part following
C<TERMCTL_> in lower-case.

On failure, each method returns C<undef>.

=over 8

=item TERMCTL_ALTSCREEN

Enables DEC Alternate Screen mode

=item TERMCTL_CURSORVIS

Enables cursor visible mode

=item TERMCTL_CURSORBLINK

Enables cursor blinking mode

=item TERMCTL_CURSORSHAPE

Sets the shape of the cursor. C<$value> should be one of
C<TERM_CURSORSHAPE_BLOCK>, C<TERM_CURSORSHAPE_UNDER> or
C<TERM_CURSORSHAPE_LEFT_BAR>.

=item TERMCTL_KEYPAD_APP

Enables keypad application mode

=item TERMCTL_MOUSE

Enables mouse tracking mode. C<$vaule> should be one of
C<TERM_MOUSEMODE_CLICK>, C<TERM_MOUSEMODE_DRAG>, C<TERM_MOUSEMODE_MOVE> or
C<TERM_MOUSEMODE_OFF>.

=back

=head2 $success = $term->setctl_str( $ctl, $value )

Sets the value of a string terminal control option. C<$ctrl> should be one of
the following options. They can be specified either as integers or strings, as
for C<setctl_int>.

=over 8

=item TERMCTL_ICON_TEXT

=item TERMCTL_TITLE_TEXT

=item TERMCTL_ICONTITLE_TEXT

Sets the terminal window icon text, title, or both.

=back

=cut

sub mode_altscreen
{
   croak "\$term->mode_altscreen should not be used; see ->setctl_int instead";
}

sub mode_cursorvis
{
   croak "\$term->mode_cursorvis should not be used; see ->setctl_int instead";
}

sub mode_mouse
{
   carp "\$term->mode_mouse should not be used; see ->setctl_int instead";
}

=head2 $term->input_push_bytes( $bytes )

Feeds more bytes of input. May result in C<on_key> or C<on_mouse> events.

=cut

=head2 $term->input_readable

Informs the term that the input handle may be readable. Attempts to read more
bytes of input. May result in C<on_key> or C<on_mouse> events.

=cut

=head2 $term->input_wait( $timeout )

Block until some input is available, and process it. Returns after one round
of input has been processed. May result in C<on_key> or C<on_mouse> events. If
C<$timeout> is defined, it will wait a period of time no longer than this time
before returning, even if no input events were received.

=cut

=head2 $timeout = $term->check_timeout

Returns a number in seconds to represent when the next timeout should occur on
the terminal, or C<undef> if nothing is waiting. May invoke expired timeouts,
and cause a C<on_key> event to occur.

=cut

=head1 TODO

=over 4

=item *

Track cursor position, and optimise (or eliminate entirely) C<goto> calls.

=back

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
