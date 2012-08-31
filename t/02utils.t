#!/usr/bin/perl

use strict;

# These tests depend on a locale that knows about Unicode
BEGIN {
   use POSIX qw( setlocale LC_CTYPE );

   my $CAN_UNICODE = 0;

   foreach (qw( en_US.UTF-8 en_GB.UTF-8 )) {
      setlocale LC_CTYPE, $_ and $CAN_UNICODE = 1 and last;
   }

   require constant;
   import constant CAN_UNICODE => $CAN_UNICODE;
}

use Test::More tests => 35;

# An invalid UTF-8 string
my $BAD_UTF8 = do { no utf8; "foo\xA9bar" };

my $CJK_UTF8 = do { use utf8; "(ノಠ益ಠ)ノ彡┻━┻" };

use Tickit::Utils qw(
   textwidth
   chars2cols
   cols2chars
   substrwidth
   align
);

is( textwidth( "" ),            0, 'textwidth empty' );
is( textwidth( "ABC" ),         3, 'textwidth ASCII' );
SKIP: {
   skip "No Unicode", 6 unless CAN_UNICODE;

   is( textwidth( "cafe\x{301}" ), 4, 'textwidth combining' );

   is( textwidth( "caf\x{fffd}" ), 4, 'U+FFFD counts as width 1' );

   is( textwidth( $BAD_UTF8 ), 7, 'Invalid UTF-8 counts as width 1' );

   is( textwidth( $CJK_UTF8 ), 15, 'CKJ UTF-8 counts as width 15');

   is( textwidth( "\x1b" ), undef, 'C0 control is invalid for textwidth' );
   is( textwidth( "\x9b" ), undef, 'C1 control is invalid for textwidth' );
}

is_deeply( [ chars2cols "ABC", 0, 1, 3, 4 ],
           [ 0, 1, 3, 3 ],
           'chars2cols ASCII' );
SKIP: {
   skip "No Unicode", 5 unless CAN_UNICODE;

   is_deeply( [ chars2cols "cafe\x{301}", 3, 4, 5, 6 ],
              [ 3, 3, 4, 4 ],
              'chars2cols combining' );

   is_deeply( [ chars2cols "caf\x{fffd}", 3, 4, 5 ],
              [ 3, 4, 4 ],
              'U+FFFD counts as width 1 for chars2cols' );

   is_deeply( [ chars2cols $BAD_UTF8, 3, 5, 7 ],
              [ 3, 5, 7 ],
              'Invalid UTF-8 counts as width 1 for chars2cols' );

   is( chars2cols( "\x1b", 1 ), undef, 'C0 control is invalid for chars2cols' );
   is( chars2cols( "\x9b", 1 ), undef, 'C1 control is invalid for chars2cols' );
}

is( scalar chars2cols( "ABC", 2 ), 2, 'scalar chars2cols' );
is( scalar chars2cols( "ABC", 3 ), 3, 'scalar chars2cols EOS' );
is( scalar chars2cols( "ABC", 4 ), 3, 'scalar chars2cols past EOS' );

is_deeply( [ cols2chars "ABC", 0, 1, 3, 4 ],
           [ 0, 1, 3, 3 ],
           'cols2chars ASCII' );
SKIP: {
   skip "No Unicode", 5 unless CAN_UNICODE;

   is_deeply( [ cols2chars "cafe\x{301}", 3, 4, 5 ],
              [ 3, 5, 5 ],
              'cols2chars combining' );

   is_deeply( [ cols2chars "caf\x{fffd}", 3, 4, 5 ],
              [ 3, 4, 4 ],
              'U+FFFD counts as width 1 for cols2chars' );

   is_deeply( [ cols2chars $BAD_UTF8, 3, 5, 7 ],
              [ 3, 5, 7 ],
              'Invalid UTF-8 counts as width 1 for cols2chars' );

   is( cols2chars( "\x1b", 1 ), undef, 'C0 control is invalid for cols2chars' );
   is( cols2chars( "\x9b", 1 ), undef, 'C1 control is invalid for cols2chars' );
}

is( scalar cols2chars( "ABC", 2 ), 2, 'scalar cols2chars' );
is( scalar cols2chars( "ABC", 3 ), 3, 'scalar cols2chars EOS' );
is( scalar cols2chars( "ABC", 4 ), 3, 'scalar cols2chars past EOS' );

is( substrwidth( "ABC", 0, 1 ), "A", 'substrwidth ASCII' );
is( substrwidth( "ABC", 2 ),    "C", 'substrwidth ASCII trail' );
SKIP: {
   skip "No Unicode", 2 unless CAN_UNICODE;

   is( substrwidth( "cafe\x{301} table", 0, 4 ), "cafe\x{301}", 'substrwidth combining within' );
   is( substrwidth( "cafe\x{301} table", 5, 5 ), "table", 'substrwidth combining after' );
}

is_deeply( [ align 10, 30, 0.0 ], [  0, 10, 20 ], 'align 10 in 30 by 0.0' );
is_deeply( [ align 10, 30, 0.5 ], [ 10, 10, 10 ], 'align 10 in 30 by 0.5' );
is_deeply( [ align 10, 30, 1.0 ], [ 20, 10,  0 ], 'align 10 in 30 by 1.0' );

is_deeply( [ align 30, 30, 0.0 ], [  0, 30,  0 ], 'align 30 in 30 by 0.0' );
is_deeply( [ align 40, 30, 0.0 ], [  0, 30,  0 ], 'align 40 in 30 by 0.0' );
