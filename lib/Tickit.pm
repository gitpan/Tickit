#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2009-2014 -- leonerd@leonerd.org.uk

package Tickit;

use strict;
use warnings;

BEGIN {
   our $VERSION = '0.49';
}

use Carp;

use IO::Handle;

use Scalar::Util qw( weaken );
use Time::HiRes qw( time );

BEGIN {
   require XSLoader;
   XSLoader::load( __PACKAGE__, our $VERSION );
}

use Tickit::Term qw( TERM_MOUSEMODE_DRAG );
use Tickit::Window;

use Tickit::Debug;

use Struct::Dumb;
struct TimeQueue => [qw( time code )];

=head1 NAME

C<Tickit> - Terminal Interface Construction KIT

=head1 SYNOPSIS

 use Tickit;
 use Tickit::Widget::Box;
 use Tickit::Widget::Static;

 my $box = Tickit::Widget::Box->new(
    h_border => 4,
    v_border => 2,
    bg       => "green",
    child    => Tickit::Widget::Static->new(
       text     => "Hello, world!",
       bg       => "black",
       align    => "centre",
       valign   => "middle",
    ),
 );

 Tickit->new( root => $box )->run;

=head1 DESCRIPTION

C<Tickit> is a high-level toolkit for creating full-screen terminal-based
interactive programs. It allows programs to be written in an abstracted way,
working with a tree of widget objects, to represent the layout of the
interface and implement its behaviours.

Its supported terminal features includes a rich set of rendering attributes
(bold, underline, italic, 256-colours, etc), support for mouse including wheel
and position events above the 224th column and arbitrary modified key input
via F<libtermkey> (all of these will require a supporting terminal as well).
It also supports having multiple instances and non-blocking or asynchronous
control.

At the current version, this is a Perl distribution which contains and XS and
C implementation of the lower levels (L<Tickit::Term> and L<Tickit::Pen>), and
implements the higher levels (L<Tickit::Window> and L<Tickit::Widget>) in pure
perl. The XS parts are supported by F<libtickit>, either from the installed
library, or using a bundled copy compiled at build time. It is intended that
eventually the Window layer will be rewritten in XS and C instead.

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

=item root => Tickit::Widget

If defined, sets the root widget using C<set_root_widget> to the one
specified.

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

   my $self = bless {
      todo_queue => [],
      timer_queue => [],
      redraw_queue => [],
   }, $class;

   unless( $term ) {
      my $writer = $self->_make_writer( $out );

      $term = Tickit::Term->find_for_term(
         writer        => $writer,
         input_handle  => $in,
         output_handle => $out,
         UTF8          => $args{UTF8},
      );
   }

   $self->{term} = $term;
   $self->{term_in}  = $in;
   $self->{term_out} = $out;

   my $rootwin = $self->{rootwin} = Tickit::Window->new( $self, $term->lines, $term->cols );

   $self->bind_key( 'C-c' => $self->can( "stop" ) );

   $term->set_output_buffer( 2**16 ); # 64KiB

   weaken( my $weakself = $self );

   $term->bind_event( resize => sub {
      $weakself or return;
      my ( $term, $ev, $args ) = @_;
      Tickit::Debug->log( Ir => "Resize to $args->{cols}x$args->{lines}" ) if DEBUG;
      $weakself->rootwin->resize( $args->{lines}, $args->{cols} );
   } );

   $term->bind_event( key => sub {
      $weakself or return;
      my ( $term, $ev, $args ) = @_;
      Tickit::Debug->log( Ik => "Key event %s %s (mod=%d)", @{$args}{qw( type str mod )} ) if DEBUG;
      $weakself->on_key( $args );
   } );

   $term->bind_event( mouse => sub {
      $weakself or return;
      my ( $term, $ev, $args ) = @_;
      Tickit::Debug->log( Im => "Mouse event %s => %s @%d,%d (mod=%d)", @{$args}{qw( type button col line mod )} ) if DEBUG;
      $weakself->on_mouse( $args );
   } );

   $self->set_root_widget( $args{root} ) if defined $args{root};

   return $self;
}

=head1 METHODS

=cut

sub _make_writer
{
   my $self = shift;
   my ( $out ) = @_;

   $out->autoflush( 1 );

   return $out;
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

=head2 $tickit->timer( $mode, $amount, $code )

Runs the given CODE reference at some fixed point in time in the future.
C<$mode> must be either the string C<at>, or C<after>; and specifies that
C<$amount> gives either the absolute epoch time, or the delay relative to now,
respectively. Fractions are supported to a resolution of microseconds.

 $tickit->timer( at => $epoch, $code )

 $tickit->timer( after => $delay, $code )

=cut

sub timer
{
   my $self = shift;
   my ( $mode, $amount, $code ) = @_;

   my $at;
   if( $mode eq "at" ) {
      $at = $amount;
   }
   elsif( $mode eq "after" ) {
      $at = time + $amount;
   }
   else {
      croak "Mode should be 'at' or 'after'";
   }

   # TODO: bin-search insert position then splice
   @{ $self->{timer_queue} } = sort { $a->time <=> $b->time } @{ $self->{timer_queue} }, TimeQueue( $at => $code );
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

sub lines { shift->term->lines }
sub cols  { shift->term->cols  }

sub _SIGWINCH
{
   my $self = shift;

   $self->term->refresh_size;
}

sub on_key
{
   my $self = shift;
   my ( $args ) = @_;

   my $str = $args->{str};

   $self->rootwin->_handle_key( $args ) and return;

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
bound to the C<stop> method.

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
   my ( $args ) = @_;

   my $type = $args->{type};
   if( $type eq "press" ) {
      # Save the mouse press location in case of drag
      $self->{mouse_last_press} = [ $args->{button}, $args->{line}, $args->{col} ];
   }
   elsif( $type eq "drag" and !$self->{mouse_dragging} ) {
      my $start_args = { %$args,
         type => "drag_start",
         line => $self->{mouse_last_press}[1],
         col  => $self->{mouse_last_press}[2],
      };

      my $win = $self->rootwin->_handle_mouse( $start_args );
      $self->{drag_source_window} = $win;

      $self->{mouse_dragging} = 1;
   }
   elsif( $type eq "release" and $self->{mouse_dragging} ) {
      my $drop_args = { %$args,
         type => "drag_drop",
      };

      $self->rootwin->_handle_mouse( $drop_args );

      if( my $win = $self->{drag_source_window} ) {
         $win->_handle_mouse( { %$args,
            type => "drag_stop",
            line => $args->{line} - $win->abs_top,
            col  => $args->{col}  - $win->abs_left,
         } );
      }

      $self->{mouse_dragging} = 0;
   }

   my $win = $self->rootwin->_handle_mouse( $args );

   my $srcwin;
   if( $type eq "drag" and
       $srcwin = $self->{drag_source_window} and
       !$win || ( $win && $win != $srcwin ) ) {
      $srcwin->_handle_mouse( { %$args,
         type => "drag_outside",
         line => $args->{line} - $srcwin->abs_top,
         col  => $args->{col}  - $srcwin->abs_left,
      } );
   }
}

=head2 $tickit->rootwin

Returns the root L<Tickit::Window>.

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

=head2 $tickit->setup_term

Set up the screen and generally prepare to start running

=cut

sub setup_term
{
   my $self = shift;

   my $term = $self->term;

   $term->await_started( 0.100 ); # 100 msec

   $term->setctl_int( altscreen => 1 );
   $term->setctl_int( cursorvis => 0 );
   $term->setctl_int( mouse     => TERM_MOUSEMODE_DRAG );
   $term->clear;

   if( my $widget = $self->{root_widget} ) {
      $widget->set_window( $self->rootwin );
   }

   $term->flush;
}

=head2 $tickit->teardown_term

Shut down the screen after running

=cut

sub teardown_term
{
   my $self = shift;

   if( my $widget = $self->{root_widget} ) {
      $widget->set_window( undef );
   }

   my $term = $self->term;
   $term->setctl_int( altscreen => 0 );
   $term->setctl_int( cursorvis => 1 );
   $term->setctl_int( mouse     => 0 );

   $term->flush;
}

=head2 $tickit->tick

Run a single round of IO events. Does not call C<setup_term> or
C<teardown_term>.

=cut

sub _tick
{
   my $self = shift;

   my $timer_queue = $self->{timer_queue};

   my $timeout;
   if( @$timer_queue ) {
      $timeout = $self->{timer_queue}[0]->time - time;
   }

   $self->{term}->input_wait( $timeout );

   my $now = time;
   while( @$timer_queue and $timer_queue->[0]->time <= $now ) {
      shift( @$timer_queue )->code->();
   }

   $self->_flush_later if @{ $self->{todo_queue} };
}

sub tick
{
   my $self = shift;

   my $old_DIE = $SIG{__DIE__};
   local $SIG{__DIE__} = sub {
      local $SIG{__DIE__} = $old_DIE;

      die @_ if $^S;

      $self->teardown_term;
      die @_;
   };

   $self->_tick;
}

=head2 $tickit->run

Calls the C<setup_term> method, then processes IO events until stopped, by the
C<stop> method, C<SIGINT>, C<SIGTERM> or the C<Ctrl-C> key. Then runs the
C<teardown_term> method, and returns.

=cut

sub run
{
   my $self = shift;

   $self->setup_term;

   $SIG{INT} = $SIG{TERM} = sub {
      my $signal = shift;

      # Disable the handler so a second signal will be fatal
      undef $SIG{$signal};
      $SIG{$signal} = sub {
         die "Aborting Tickit on double SIGINT\n";
      };

      $self->stop;
   };

   $SIG{WINCH} = sub {
      $self->later( sub { $self->_SIGWINCH } )
   };

   my $old_DIE = $SIG{__DIE__};
   local $SIG{__DIE__} = sub {
      local $SIG{__DIE__} = $old_DIE;

      die @_ if $^S;

      $self->teardown_term;
      die @_;
   };

   $self->_flush_later if @{ $self->{todo_queue} };

   local $self->{keep_running} = 1;
   $self->_tick while( $self->{keep_running} );

   $self->teardown_term;
}

=head2 $tickit->stop

Causes a currently-running C<run> method to stop processing events and return.

=cut

sub stop
{
   my $self = shift;
   $self->{keep_running} = 0;
}

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
