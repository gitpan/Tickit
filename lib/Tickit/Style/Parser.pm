#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2013 -- leonerd@leonerd.org.uk

package Tickit::Style::Parser;

use strict;
use warnings;

use base qw( Parser::MGC );

use Struct::Dumb;

# Identifiers can include hypens
use constant pattern_ident => qr/[A-Z0-9_-]+/i;

sub parse
{
   my $self = shift;
   $self->sequence_of( \&parse_def );
}

struct Definition => [qw( type class tags style )];

sub parse_def
{
   my $self = shift;

   my $type = $self->token_ident;
   $self->commit;

   my $class;
   if( $self->maybe_expect( '.' ) ) {
      $class = $self->token_ident;
   }

   my %tags;
   while( $self->maybe_expect( ':' ) ) {
      $tags{$self->token_ident}++;
   }

   my %style;
   $self->scope_of(
      '{',
      sub { $self->sequence_of( sub {
         my $delete = $self->maybe_expect( '!' );
         my $key = $self->token_ident;
         $self->commit;

         $key =~ s/-/_/g;

         if( $delete ) {
            $style{$key} = undef;
         }
         else {
            $self->expect( ':' );
            my $value = $self->any_of(
               $self->can( "token_int" ),
               $self->can( "token_string" ),
               \&token_boolean,
            );
            $style{$key} = $value;
         }

         $self->expect( ';' );
      } ) },
      '}'
   );

   return Definition( $type, $class, \%tags, \%style );
}

sub token_boolean
{
   my $self = shift;
   return $self->token_kw(qw( true false )) eq "true";
}

0x55AA;
