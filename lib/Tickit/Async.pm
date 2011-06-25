#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2011 -- leonerd@leonerd.org.uk

package Tickit::Async;

use strict;
use warnings;
use base qw( Tickit );

our $VERSION = '0.07';

=head1 NAME

C<Tickit::Async> - use C<Tickit> with C<IO::Async>

=head1 SYNOPSIS

 use IO::Async;
 use Tickit::Async;

 my $tickit = Tickit::Async->new;

 # Create some widgets
 # ...

 $tickit->set_root_widget( $rootwidget );

 my $loop = IO::Async::Loop->new;
 $loop->add( $tickit );

 $tickit->run;

=head1 DESCRIPTION

This class allows a L<Tickit> user interface to run alongside other
L<IO::Async>-driven code, using C<IO::Async> as a source of IO events.

=cut

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
