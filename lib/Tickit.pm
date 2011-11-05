#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2009-2011 -- leonerd@leonerd.org.uk

package Tickit;

use strict;
use warnings;

our $VERSION = '0.12';

use IO::Handle;
use Term::Size;
use Term::TermKey qw( FORMAT_ALTISMETA FLAG_UTF8 FLAG_RAW FLAG_EINTR RES_KEY RES_AGAIN );
use constant FLAGS_UTF8_RAW => FLAG_UTF8|FLAG_RAW;

use Tickit::Term;
use Tickit::RootWindow;

=head1 NAME

C<Tickit> - Terminal Interface Construction KIT

=head1 SYNOPSIS

 use Tickit;

 my $tickit = Tickit->new;

 # Create some widgets
 # ...

 $tickit->set_root_widget( $rootwidget );

 $tickit->run;

=head1 DESCRIPTION

=cut

=head1 CONSTRUCTOR

=cut

=head2 $tickit = Tickit->new( %args )

Constructs a new C<Tickit> framework container object.

Takes the following named arguments at construction time:

=over 8

=item term_in => IO

IO handle for terminal input. Will default to C<STDIN>.

=item term_out => IO

IO handle for terminal output. Will default to C<STDOUT>.

=item UTF8 => BOOL

If defined, overrides locale detection to enable or disable UTF-8 mode. If not
defined then this will be detected from the locale by using Perl's
C<${^UTF8LOCALE}> variable.

=back

=cut

sub new
{
   my $class = shift;
   my %args = @_;

   # Test code also accepts 'term' argument but we won't document that for now

   my $in  = delete $args{term_in}  || \*STDIN;
   my $out = delete $args{term_out} || \*STDOUT;

   my $term = delete $args{term};

   my $is_utf8 = defined $args{UTF8} ? $args{UTF8} : ${^UTF8LOCALE};

   my $self = bless {
      UTF8 => $is_utf8,
   }, $class;

   my $termkey = $self->_make_termkey( $in );

   $termkey->set_flags( ( $termkey->get_flags & ~FLAGS_UTF8_RAW ) |
                        ( $is_utf8 ? FLAG_UTF8 : FLAG_RAW ) );

   unless( $term ) {
      my $writer = $self->_make_writer( $out );

      $term = Tickit::Term->find_for_term(
         writer => $writer,
         $is_utf8 ? ( encoding => "UTF-8" ) : (),
      );
   }

   $self->{term} = $term;
   $self->{term_in}  = $in;
   $self->{term_out} = $out;
   $self->{termkey} = $termkey;

   $self->_recache_size;
   $term->set_size( $self->lines, $self->cols );

   $self->{rootwin} = Tickit::RootWindow->new( $self, $self->lines, $self->cols );

   $self->bind_key( 'C-c' => $self->can( "_STOP" ) );

   return $self;
}

=head1 METHODS

=cut

sub _make_termkey
{
   my $self = shift;
   my ( $in ) = @_;

   return Term::TermKey->new( $in, FLAG_EINTR );
}

sub _make_writer
{
   my $self = shift;
   my ( $out ) = @_;

   $out->autoflush( 1 );

   return $out;
}

=head2 $tickit->is_utf8

Returns true if running in UTF-8 mode; returned keypress events and displayed
text will be Unicode aware. If false, then keypresses and displayed text will
work in legacy 8-bit mode.

=cut

sub is_utf8
{
   my $self = shift;
   return $self->{UTF8};
}

=head2 $tickit->later( $code )

Runs the given CODE reference at some time soon in the future. It will not be
invoked yet, but will be invoked at some point before the next round of input
events are processed.

=cut

sub _flush_later
{
   my $self = shift;

   my $queue = $self->{todo_queue};
   ( shift @$queue )->() while @$queue;
}

sub later
{
   my $self = shift;
   my ( $code ) = @_;

   push @{ $self->{todo_queue} }, $code;
}

=head2 $term = $tickit->term

Returns the underlying L<Tickit::Term> object.

=cut

sub term
{
   my $self = shift;
   return $self->{term};
}

=head2 $cols = $tickit->cols

=head2 $lines = $tickit->lines

Query the current size of the terminal. Will be cached and updated on receipt
of C<SIGWINCH> signals.

=cut

sub _recache_size
{
   my $self = shift;
   ( $self->{cols}, $self->{lines} ) = Term::Size::chars $self->{term_out};
}

sub lines { shift->{lines} }
sub cols  { shift->{cols}  }

sub _SIGWINCH
{
   my $self = shift;

   $self->_recache_size;
   $self->term->set_size( $self->lines, $self->cols );
   $self->rootwin->resize( $self->lines, $self->cols );
}

sub _KEY
{
   my $self = shift;
   my ( $tk, $key ) = @_;

   my $spacesym = $self->{spacesym} ||= $tk->keyname2sym( "Space" );

   # libtermkey represents unmodified Space as a keysym, whereas we'd
   # prefer to treat it as plain text
   if( $key->type_is_unicode and !$key->modifiers ) {
      $self->on_key( text => $key->utf8, $key );
   }
   elsif( $key->type_is_keysym  and !$key->modifiers and $key->sym == $spacesym ) {
      $self->on_key( text => " ", $key );
   }
   elsif( $key->type_is_mouse ) {
      my ( $ev, $button, $line, $col ) = $tk->interpret_mouse( $key );
      my $evname = (qw( * press drag release ))[$ev];
      $self->on_mouse( $evname, $button, $line - 1, $col - 1 );
   }
   else {
      $self->on_key( key => $tk->format_key( $key, FORMAT_ALTISMETA ), $key );
   }
}

sub on_key
{
   my $self = shift;
   my ( $type, $str, $key ) = @_;

   $self->rootwin->_handle_key( $type, $str, $key ) and return;

   if( exists $self->{key_binds}{$str} ) {
      $self->{key_binds}{$str}->( $self, $str ) and return;
   }
}

=head2 $tickit->bind_key( $key, $code )

Installs a callback to invoke if the given key is pressed, overwriting any
previous callback for the same key. The code block is invoked as

 $code->( $tickit, $key )

If C<$code> is missing or C<undef>, any existing callback is removed.

As a convenience for the common application use case, the C<Ctrl-C> key is
bound to the C<_STOP> method.

To remove this binding, simply bind another callback, or remove the binding
entirely by setting C<undef>.

=cut

sub bind_key
{
   my $self = shift;
   my ( $key, $code ) = @_;

   if( $code ) {
      $self->{key_binds}{$key} = $code;
   }
   else {
      delete $self->{key_binds}{$key};
   }
}

sub on_mouse
{
   my $self = shift;
   my ( $ev, $button, $line, $col ) = @_;

   $self->rootwin->_handle_mouse( $ev, $button, $line, $col ) and return;
}

=head2 $tickit->rootwin

Returns the L<Tickit::RootWindow>.

=cut

sub rootwin
{
   my $self = shift;
   return $self->{rootwin};
}

=head2 $tickit->set_root_widget( $widget )

Sets the root widget for the application's display. This must be a subclass of
L<Tickit::Widget>.

=cut

sub set_root_widget
{
   my $self = shift;
   ( $self->{root_widget} ) = @_;
}

=head2 $tickit->start

Set up the screen and generally prepare to start running

=cut

sub start
{
   my $self = shift;

   my $term = $self->term;
   $term->mode_altscreen( 1 );
   $term->mode_cursorvis( 0 );
   $term->mode_mouse( 1 );
   $term->clear;

   if( my $widget = $self->{root_widget} ) {
      $widget->set_window( $self->rootwin );
   }
}

=head2 $tickit->stop

Shut down the screen after running

=cut

sub stop
{
   my $self = shift;

   if( my $widget = $self->{root_widget} ) {
      $widget->set_window( undef );
   }

   my $term = $self->term;
   $term->mode_altscreen( 0 );
   $term->mode_cursorvis( 1 );
   $term->mode_mouse( 0 );
}

=head2 $tickit->run

Calls the C<start> method, then processes IO events until stopped, by the
C<_STOP> method, C<SIGINT>, C<SIGTERM> or the C<Ctrl-C> key. Then runs the
C<stop> method, and returns.

=cut

sub _STOP
{
   my $self = shift;
   $self->{keep_running} = 0;
}

sub run
{
   my $self = shift;

   $self->start;

   $SIG{INT} = $SIG{TERM} = sub { $self->_STOP };

   $SIG{WINCH} = sub { 
      $self->later( sub { $self->_SIGWINCH } )
   };

   my $old_DIE = $SIG{__DIE__};
   local $SIG{__DIE__} = sub {
      local $SIG{__DIE__} = $old_DIE;

      die @_ if $^S;

      $self->stop;
      die @_;
   };

   my $fileno_in = $self->{term_in}->fileno;
   my $termkey = $self->{termkey};
   my $queue   = $self->{todo_queue};

   $self->_flush_later if @$queue;

   my $key_pending = 0;

   local $self->{keep_running} = 1;
   while( $self->{keep_running} ) {
      if( $termkey->waitkey( my $key ) == RES_KEY ) {
         $self->_KEY( $termkey, $key );
      }

      $self->_flush_later if @$queue;
   }

   $self->stop;
}

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
