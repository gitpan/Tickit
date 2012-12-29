#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2011-2012 -- leonerd@leonerd.org.uk

package Tickit::Utils;

use strict;
use warnings;

our $VERSION = '0.25';

use Exporter 'import';
our @EXPORT_OK = qw(
   string_count
   string_countmore

   textwidth

   chars2cols
   cols2chars

   substrwidth

   align

   bound
);

# XS code comes from Tickit itself
require Tickit;

=head1 NAME

C<Tickit::Utils> - utility functions for C<Tickit>

=head1 DESCRIPTION

This module provides a number of utility functions used across C<Tickit>.

=cut

=head1 FUNCTIONS

=head2 $bytes = string_count( $str, $pos, $limit )

Given a string in C<$str> and a L<Tickit::StringPos> instance in C<$pos>,
updates the counters in C<$pos> by counting the string, and returns the number
of bytes consumed. If C<$limit> is given, then it will count no further than
any of the limits given.

=head2 $bytes = string_countmore( $str, $pos, $limit, $start )

Similar to C<string_count> but will not zero the counters before it begins.
Counters in C<$pos> will still be incremented. If C<$start> is provided it
gives the byte offset within C<$str> to begin counting from. This is more
efficient than applying C<substr> on the input string to create the starting
point.

=head2 $cols = textwidth( $str )

Returns the number of screen columns consumed by the given (Unicode) string.

=cut

# Provided by XS

=head2 @cols = chars2cols( $text, @chars )

Given a list of increasing character positions, returns a list of column
widths of those characters. In scalar context returns the first columns width.

=cut

# Provided by XS

=head2 @chars = cols2chars( $text, @cols )

Given a list of increasing column widths, returns a list of character
positions at those widths. In scalar context returns the first character
position.

=cut

# Provided by XS

=head2 $substr = substrwidth $text, $startcol

=head2 $substr = substrwidth $text, $startcol, $widthcols

=head2 $substr = substrwidth $text, $startcol, $widthcols, $replacement

Similar to C<substr>, but counts start offset and length in screen columns
instead of characters

=cut

sub substrwidth
{
   if( @_ > 2 ) {
      my ( $start, $end ) = cols2chars( $_[0], $_[1], $_[1]+$_[2] );
      if( @_ > 3 ) {
         return substr( $_[0], $start, $end-$start, $_[3] );
      }
      else {
         return substr( $_[0], $start, $end-$start );
      }
   }
   else {
      my $start = cols2chars( $_[0], $_[1] );
      return substr( $_[0], $start );
   }
}

=head2 ( $before, $alloc, $after ) = align( $value, $total, $alignment )

Returns a list of three integers created by aligning the C<$value> to a
position within the C<$total> according to C<$alignment>. The sum of the three
returned values will always add to total.

If the value is not larger than the total then the returned allocation will be
the entire value, and the remaining space will be divided between before and
after according to the given fractional alignment, with more of the remainder
being allocated to the C<$after> position in proportion to the alignment.

If the value is larger than the total, then the total is returned as the
allocation and the before and after positions will both be given zero.

=cut

sub align
{
   my ( $value, $total, $alignment ) = @_;

   return ( 0, $total, 0 ) if $value >= $total;

   my $spare = $total - $value;
   my $before = int( $spare * $alignment );

   return ( $before, $value, $spare - $before );
}

=head2 $val = bound( $min, $val, $max )

Returns the value of C<$val> bounded by the given minimum and maximum. Either
limit may be left undefined, causing no limit of that kind to be applied.

=cut

sub bound
{
   my ( $min, $val, $max ) = @_;
   $val = $min if defined $min and $val < $min;
   $val = $max if defined $max and $val > $max;
   return $val;
}

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
