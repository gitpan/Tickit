#!/usr/bin/perl

use strict;
use warnings;

use Test::More;

use Tickit::Test;

my $rootwin = mk_window;

{
   my @mouse_events;
   $rootwin->set_on_mouse( sub {
      push @mouse_events, [ @_[1..4] ];
      return 1;
   } );

   sub mouse_events
   {
      my @ret = @mouse_events;
      undef @mouse_events;
      return \@ret;
   }
}

# press
pressmouse( press => 1, 2, 5 );

is_deeply( mouse_events,
           [ [ press => 1, 2, 5 ] ],
           'mouse_events after press' );

# drag
pressmouse( drag => 1, 3, 5 );

is_deeply( mouse_events,
           [ [ drag_start => 1, 2, 5 ],
             [ drag       => 1, 3, 5 ] ],
           'mouse_events after drag contains drag_start' );

# release
pressmouse( release => 1, 3, 5 );

is_deeply( mouse_events,
           [ [ drag_drop => 1, 3, 5 ],
             [ release   => 1, 3, 5 ] ],
           'mouse_events after release contains drag_drop' );

done_testing;
