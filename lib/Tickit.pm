#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2009-2011 -- leonerd@leonerd.org.uk

package Tickit;

use strict;
use warnings;
use base qw( IO::Async::Notifier );

our $VERSION = '0.07';

use IO::Async::Loop;
use IO::Async::Signal;
use IO::Async::Stream;

use Term::Size;
use Term::TermKey::Async qw( FORMAT_ALTISMETA FLAG_UTF8 );

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

   my $self = $class->SUPER::new( %args );

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
   $self->add_child( $tka );

   $spacesym = $tka->keyname2sym( "Space" );

   unless( $term ) {
      my $writer = IO::Async::Stream->new(
         write_handle => $out,
         autoflush => 1,
      );

      $term = Tickit::Term->find_for_term(
         writer => $writer,
         ( $tka->get_flags & FLAG_UTF8 ) ? ( encoding => "UTF-8" ) : (),
      );

      $self->add_child( $writer );
   }

   $self->{term} = $term;
   $self->{term_out} = $out;

   $self->_recache_size;

   $self->add_child( IO::Async::Signal->new( 
      name => "WINCH",
      on_receipt => $self->_capture_weakself( sub {
         my $self = shift or return;

         $self->_recache_size;
         $self->rootwin->resize( $self->lines, $self->cols );
      } ),
   ) );

   $self->{rootwin} = Tickit::RootWindow->new( $self, $self->lines, $self->cols );

   $self->bind_key( 'C-c' => $self->_capture_weakself( sub {
      my $self = shift;
      $self->get_loop->loop_stop;
   } ) );

   return $self;
}

=head1 METHODS

=cut

sub _add_to_loop
{
   my $self = shift;
   $self->SUPER::_add_to_loop( @_ );

   if( $self->{todo_later} ) {
      $self->get_loop->later( $_ ) for @{ $self->{todo_later} };
      delete $self->{todo_later};
   }
}

=head2 $tickit->later( $code )

Runs the given CODE reference at some time soon in the future. It will not be
invoked yet, but will be invoked at some point before the next round of input
events are processed.

=cut

sub later
{
   my $self = shift;
   my ( $code ) = @_;

   if( my $loop = $self->get_loop ) {
      $loop->later( $code );
   }
   else {
      push @{ $self->{todo_later} }, $code;
   }
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
   $self->term->set_size( $self->{cols}, $self->{lines} );
}

sub lines { shift->{lines} }
sub cols  { shift->{cols}  }

sub on_key
{
   my $self = shift;
   my ( $type, $str, $key ) = @_;

   $self->rootwin->_handle_key( $type, $str, $key ) and return;

   if( exists $self->{key_binds}{$str} ) {
      $self->{key_binds}{$str}->( $str ) and return;
   }
}

=head2 $tickit->bind_key( $key, $code )

Installs a callback to invoke if the given key is pressed, overwriting any
previous callback for the same key. The code block is invoked as

 $code->( $key )

If C<$code> is missing or C<undef>, any existing callback is removed.

As a convenience for the common application use case, the C<Ctrl-C> key is
bound to a callback that calls the C<loop_stop> method on the underlying
C<IO::Async::Loop> object the C<Tickit> is a member of. This usually has the
effect of cleanly stopping the application.

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

   $SIG{INT} = $SIG{TERM} = sub { $self->get_loop->loop_stop };

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

A shortcut to the common usage pattern, combining the C<start> method with
C<loop_forever> on the containing C<IO::Async::Loop> object. If the C<Tickit>
object does not yet have a containing Loop, then one will be constructed using
the C<IO::Async::Loop> magic constructor.

=cut

sub run
{
   my $self = shift;

   my $loop = $self->get_loop || do {
      my $newloop = IO::Async::Loop->new;
      $newloop->add( $self );
      $newloop;
   };

   $self->start;

   my $old_DIE = $SIG{__DIE__};
   local $SIG{__DIE__} = sub {
      local $SIG{__DIE__} = $old_DIE;

      die @_ if $^S;

      $self->stop;
      die @_;
   };

   $loop->loop_forever;
   $self->stop;
}

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
