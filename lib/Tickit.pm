#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2009-2011 -- leonerd@leonerd.org.uk

package Tickit;

use strict;
use warnings;
use base qw( IO::Async::Notifier );

our $VERSION = '0.01';

use Tickit::Term;
use Tickit::RootWindow;

=head1 NAME

C<Tickit> - Terminal Interface Construction KIT

=head1 SYNOPSIS

 TODO

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

=head2 $tickit->start

Set up the screen and generally prepare to start running

=cut

sub start
{
   my $self = shift;

   my $term = $self->term;
   $term->mode_altscreen( 1 );
   $term->clear;
}

=head2 $tickit->stop

Shut down the screen after running

=cut

sub stop
{
   my $self = shift;

   my $term = $self->term;
   $term->mode_altscreen( 0 );
   $term->on_write_ready; # TODO - consider a synchronous flush or similar
}

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
