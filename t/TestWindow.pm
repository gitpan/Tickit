package t::TestWindow;

use strict;
use Exporter 'import';

our @EXPORT = qw(
   mk_term_and_window
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

   my $tickit = Tickit->new(
      term => $term
   );

   $loop->add( $tickit );

   my $win = $tickit->rootwin;

   $tickit->start;

   # Clear the method log from ->start
   $term->methodlog;

   return ( $term, $win );
}

0x55AA;
