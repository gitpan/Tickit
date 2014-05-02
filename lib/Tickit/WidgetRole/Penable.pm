#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2012 -- leonerd@leonerd.org.uk

package Tickit::WidgetRole::Penable;

use strict;
use warnings;
use base qw( Tickit::WidgetRole );

our $VERSION = '0.46';

use Carp;
croak "Tickit::WidgetRole::Penable is deprecated; use Tickit::Style instead";

=head1 NAME

C<Tickit::WidgetRole::Penable> - implement widgets with setable pens

=head1 DESCRIPTION

This code is entirely deprecated. Do not use it.

See instead the far more flexible L<Tickit::Style> to set a configurable pen.

=cut

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
