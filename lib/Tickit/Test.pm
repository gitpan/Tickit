#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2011 -- leonerd@leonerd.org.uk

package Tickit::Test;

use strict;
use warnings;

our $VERSION = '0.07';

use Exporter 'import';

our @EXPORT = qw(
   mk_term
   mk_window
   mk_term_and_window
   flush_tickit

   resize_term

   presskey
   pressmouse

   is_termlog
   is_display
   is_cursorpos

   CLEAR
   GOTO
   ERASECH
   INSERTCH
   DELETECH
   SCROLLRECT
   PRINT
   SETPEN
   SETBG
);

use Tickit::Test::MockTerm;
use Tickit::Pen;
use Tickit;

use Test::More;

=head1 NAME

C<Tickit::Test> - unit testing for C<Tickit>-based code

=head1 SYNOPSIS

 use Test::More tests => 2;
 use Tickit::Test;

 use Tickit::Widget::Static;

 my $win = mk_window;

 my $widget = Tickit::Widget::Static->new( text => "Message" );

 $widget->set_window( $win );

 flush_tickit;

 is_termlog( [ SETPEN,
               CLEAR,
               GOTO(0,0),
               SETPEN,
               PRINT("Message"),
               SETBG(undef),
               ERASECH(73) ] );

 is_display( [ "Message" ] );

=head1 DESCRIPTION

This module helps write unit tests for L<Tickit>-based code, such as
L<Tickit::Widget> subclasses. Primarily, it provides a mock terminal
implementation, allowing the code under test to affect a virtual terminal,
whose state is inspectable by the unit test script.

This module is used by the C<Tickit> unit tests themselves, and provided as an
installable module, so that authors of widget subclasses can use it too.

=cut

=head1 FUNCTIONS

=cut

my $term;
my $tickit;

=head2 $term = mk_term

Constructs and returns the mock terminal to unit test with. This object will
be cached and returned if this function is called again. Most unit tests will
want a root window as well; for convenience see instead C<mk_term_and_window>.

The mock terminal usually starts with a size of 80 columns and 25 lines,
though can be overridden by passing named arguments.

 $term = mk_term lines => 30, cols => 100;

=cut

sub mk_term
{
   return $term ||= Tickit::Test::MockTerm->new( @_ );
}

=head2 $win = mk_window

Construct a root window using the mock terminal, to unit test with.

=cut

sub mk_window
{
   mk_term;

   $tickit = __PACKAGE__->new(
      term => $term
   );

   my $win = $tickit->rootwin;

   $tickit->start;

   # Clear the method log from ->start
   $term->methodlog;

   return $win;
}

=head2 ( $term, $win ) = mk_term_and_window

Constructs and returns the mock terminal and root window; equivalent to
calling each of C<mk_term> and C<mk_window> separately.

=cut

sub mk_term_and_window
{
   my $term = mk_term( @_ );
   my $win = mk_window;

   return ( $term, $win );
}

## Actual object implementation

use base qw( Tickit );

my @later;
sub later { push @later, $_[1] }

sub lines { return $term->lines }
sub cols  { return $term->cols  }

=head2 flush_tickit

Flushes any pending C<later> events in the testing C<Tickit> object. Because
the unit test script has no real event loop, this is required instead, to
flush any pending events.

=cut

sub flush_tickit
{
   while( @later ) {
      my @queue = @later; @later = ();
      $_->() for @queue;
   }
}

=head2 resize_term( $lines, $cols )

Resize the virtual testing terminal to the size given

=cut

sub resize_term
{
   my ( $lines, $cols ) = @_;
   $term->resize( $lines, $cols );

   # This is evil hackery
   $tickit->rootwin->resize( $tickit->lines, $tickit->cols );
}

=head2 presskey( $type, $str )

Fire a key event

=cut

sub presskey
{
   my ( $type, $str ) = @_;

   # TODO: See if we'll ever need to fake a Term::TermKey::Key event object
   $tickit->on_key( $type, $str, undef );
}

=head2 pressmouse( $ev, $button, $line, $col )

Fire a mouse button event

=cut

sub pressmouse
{
   my ( $ev, $button, $line, $col ) = @_;

   $tickit->on_mouse( $ev, $button, $line, $col );
}

=head1 TEST FUNCTIONS

The following functions can be used like C<Test::More> primatives, in unit
test scripts.

=cut

=head2 is_termlog( $log, $name )

Asserts that the mock terminal log contains exactly the given sequence of
methods. See also the helper functions below.

=cut

sub is_termlog
{
   my ( $log, $name ) = @_;

   is_deeply( [ $term->methodlog ],
              $log,
              $name );
}

=head2 is_display( $lines, $name )

Asserts that the mock terminal display is exactly that given in C<$lines>,
which must be an ARRAY reference of strings. These strings will be padded with
spaces out to the terminal width, and the array itself extended with blank
lines, so it is of the correct size.

The mock terminal display contains only the printed characters, it does not
consider formatting. For formatting-aware unit tests, use the C<is_termlog>
test.

=cut

sub is_display
{
   my ( $lines, $name ) = @_;

   my @lines = map { sprintf "% -*s", $term->cols, $_ } @$lines;
   push @lines, " " x $term->cols while @lines < $term->lines;

   is_deeply( [ $term->get_display ],
              \@lines,
              $name );
}

=head2 is_cursorpos( $line, $col, $name )

Asserts that the mock terminal cursor is at the given position.

=cut

sub is_cursorpos
{
   my ( $line, $col, $name ) = @_;

   is_deeply( [ $term->get_position ],
              [ $line, $col ],
              $name );
}

use constant DEFAULTPEN => map { $_ => undef } @Tickit::Pen::ALL_ATTRS;

=head1 METHOD LOG HELPER FUNCTIONS

The following functions can be used to help write the expected log for a call
to C<is_termlog>.

 CLEAR
 GOTO($line,$col)
 ERASECH($count,$move_to_end)
 INSERTCH($count)
 DELETECH($count)
 SCROLLRECT($top,$left,$lines,$cols,$downward,$rightward)
 PRINT($string)
 SETPEN(%attrs)
 SETBG($bg_attr)

=cut

sub CLEAR      { [ clear => ] }
sub GOTO       { [ goto => $_[0], $_[1] ] }
sub ERASECH    { [ erasech => $_[0], $_[1] || 0 ] }
sub INSERTCH   { [ insertch => $_[0] ] }
sub DELETECH   { [ deletech => $_[0] ] }
sub SCROLLRECT { [ scrollrect => @_[0..5] ] }
sub PRINT      { [ print => $_[0] ] }
sub SETPEN     { [ chpen => { DEFAULTPEN, @_ } ] }
sub SETBG      { [ chpen => { bg => $_[0] } ] }

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
