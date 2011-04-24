#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2009-2011 -- leonerd@leonerd.org.uk

package Tickit;

use strict;
use warnings;
use base qw( IO::Async::Notifier );

our $VERSION = '0.04';

use Tickit::Term;
use Tickit::RootWindow;

=head1 NAME

C<Tickit> - Terminal Interface Construction KIT

=head1 SYNOPSIS

 use Tickit;
 use IO::Async::Loop;

 my $loop = IO::Async::Loop->new;

 my $tickit = Tickit->new;
 $loop->add( $tickit );

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

=item term_out => IO

Passed to the L<Tickit::Term> constructor.

=back

=cut

sub new
{
   my $class = shift;
   my %args = @_;

   # Test code also accepts 'term' argument but we won't document that for now

   my $term = delete $args{term} || Tickit::Term->new(
      term_in  => delete $args{term_in},
      term_out => delete $args{term_out},
   );

   my $self = $class->SUPER::new( %args );

   $term->configure(
      on_key => $self->_replace_weakself( sub {
         my $self = shift or return;
         my ( $type, $str, $key ) = @_;

         return if $self->rootwin->_on_key( $type, $str, $key );

         $self->on_key( $type, $str, $key );
      } ),

      on_resize => $self->_capture_weakself( sub {
         my $self = shift or return;
         my $term = shift;
         $self->rootwin->resize( $term->lines, $term->cols );
      } ),
   );

   $self->{term} = $term;
   $self->add_child( $term );

   $self->{rootwin} = Tickit::RootWindow->new( $self );

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

sub on_key
{
   my $self = shift;
   my ( $type, $str, $key ) = @_;

   if( exists $self->{key_binds}{$str} ) {
      $self->{key_binds}{$str}->( $str );
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
   $term->on_write_ready; # TODO - consider a synchronous flush or similar
}

=head2 $tickit->run

A shortcut to the common usage pattern, combining the C<start> method with
C<loop_forever> on the containing C<IO::Async::Loop> object.

=cut

sub run
{
   my $self = shift;

   $self->start;
   $self->get_loop->loop_forever;
   $self->stop;
}

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
