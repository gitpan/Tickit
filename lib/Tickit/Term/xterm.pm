package Tickit::Term::xterm;

use strict;
use warnings;
use base qw( Tickit::Term );

our $VERSION = '0.15';

sub _colspec_to_sgr
{
   my $self = shift;
   my ( $spec, $is_bg ) = @_;

   return ( $is_bg ? 48 : 38 ), 5, $spec if $spec >= 16 and $spec < 256;

   return $self->SUPER::_colspec_to_sgr( @_ );
}

0x55AA;
