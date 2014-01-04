#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2012 -- leonerd@leonerd.org.uk

package Tickit::WidgetRole::Penable;

use strict;
use warnings;
use base qw( Tickit::WidgetRole );

our $VERSION = '0.41';

use Carp;

=head1 NAME

C<Tickit::WidgetRole::Penable> - implement widgets with setable pens

=head1 DESCRIPTION

Mixing this parametric role into a L<Tickit::Widget> subclass adds behaviour
to implement a custom pen. The mixing widget will automatically subscribe to
the pen for updates by its C<add_on_changed> method. The mixing widget class
still responsible for implementing the C<on_pen_changed> method.

=cut

=head1 METHODS

The following methods are provided parametrically on the caller package when
the module is imported by

 use Tickit::WidgetRole::Penable name => NAME, default => DEFAULT

The parameters are

=over 4

=item name => STRING

Required. The name to use for C<NAME> in the following generated methods, and
used as the C<$id> identifier to the C<add_on_changed> method.

=item default => HASH

Optional. A HASH reference containing the default attributes this pen should
have on initialisation.

=back

=cut

sub export_subs_for
{
   my $class = shift;
   shift;
   my %args = @_;

   my $name = $args{name} or croak "Require a Penable name";

   my $default = Tickit::Pen->new;
   $default->chattrs( {%{ $args{default} }} ) if $args{default};

   my $attr = "${name}_pen";

   return {
      "${name}_pen" => sub {
         my $self = shift;
         return $self->{$attr};
      },
      "_init_${name}_pen" => sub {
         my $self = shift;
         $self->${\"set_${name}_pen"}( $default->clone );
      },
      "set_${name}_pen" => sub {
         my $self = shift;
         my ( $newpen ) = @_;

         return if $self->{$attr} and $self->{$attr} == $newpen;

         $self->{$attr}->remove_on_changed( $self ) if $self->{$attr};
         $self->{$attr} = $newpen;
         $newpen->add_on_changed( $self, $name );
      },
   }
}

=head2 $pen = $widget->NAME_pen

Returns the L<Tickit::Pen> instance.

=cut

=head2 $widget->set_NAME_pen( $pen )

Sets a new pen instance.

=cut

=head2 $widget->_init_NAME_pen

Sets the initial default value of the pen, by calling C<set_NAME_pen>.

=cut

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
