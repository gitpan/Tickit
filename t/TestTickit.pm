package t::TestTickit;

use strict;
use Exporter 'import';

our @EXPORT = qw(
   mk_term_and_window
   flush_tickit
);

use IO::Async::Test;
use IO::Async::Loop;

use t::MockTerm;
use Tickit;

sub mk_term_and_window
{
   my $loop = IO::Async::Loop->new();
   testing_loop( $loop );

   my $term = t::MockTerm->new;

   my $tickit = t::TestTickit->new(
      term => $term
   );

   $loop->add( $tickit );

   my $win = $tickit->rootwin;

   $tickit->start;

   # Clear the method log from ->start
   $term->methodlog;

   return ( $term, $win );
}

## Actual object implementation

use base qw( Tickit );

my @later;
sub later { push @later, $_[1] }

sub flush_tickit
{
   while( @later ) {
      my @queue = @later; @later = ();
      $_->() for @queue;
   }
}

0x55AA;
