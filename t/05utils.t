#!/usr/bin/perl

use strict;

use Test::More tests => 16;

use Tickit::Utils qw(
   textwidth
   chars2cols
   cols2chars
   substrwidth
   align
);

is( textwidth( "" ),            0, 'textwidth empty' );
is( textwidth( "ABC" ),         3, 'textwidth ASCII' );
is( textwidth( "cafe\x{301}" ), 4, 'textwidth combining' );

is_deeply( [ chars2cols "ABC", 0, 1, 3 ],
           [ 0, 1, 3 ],
           'chars2cols ASCII' );
is_deeply( [ chars2cols "cafe\x{301}", 3, 4, 5 ],
           [ 3, 4, 4 ],
           'chars2cols combining' );

is_deeply( [ cols2chars "ABC", 0, 1, 3 ],
           [ 0, 1, 3 ],
           'cols2chars ASCII' );
is_deeply( [ cols2chars "cafe\x{301}", 3, 4 ],
           [ 3, 5 ],
           'cols2chars combining' );

is( substrwidth( "ABC", 0, 1 ), "A", 'substrwidth ASCII' );
is( substrwidth( "ABC", 2 ),    "C", 'substrwidth ASCII trail' );
is( substrwidth( "cafe\x{301} table", 0, 4 ), "cafe\x{301}", 'substrwidth combining within' );
is( substrwidth( "cafe\x{301} table", 5, 5 ), "table", 'substrwidth combining after' );

is_deeply( [ align 10, 30, 0.0 ], [  0, 10, 20 ], 'align 10 in 30 by 0.0' );
is_deeply( [ align 10, 30, 0.5 ], [ 10, 10, 10 ], 'align 10 in 30 by 0.5' );
is_deeply( [ align 10, 30, 1.0 ], [ 20, 10,  0 ], 'align 10 in 30 by 1.0' );

is_deeply( [ align 30, 30, 0.0 ], [  0, 30,  0 ], 'align 30 in 30 by 0.0' );
is_deeply( [ align 40, 30, 0.0 ], [  0, 30,  0 ], 'align 40 in 30 by 0.0' );
