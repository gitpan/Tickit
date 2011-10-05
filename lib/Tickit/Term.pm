#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2009-2011 -- leonerd@leonerd.org.uk

package Tickit::Term;

use strict;
use warnings;

our $VERSION = '0.11';

use Encode qw( find_encoding );
use Term::Terminfo;

use Tickit::Pen;

my $ESC = "\e";
my $CSI = "$ESC\[";

=head1 NAME

C<Tickit::Term> - terminal formatting abstraction

=head1 SYNOPSIS

=head1 DESCRIPTION

Provides terminal control primatives for L<Tickit>; a number of methods that
control the terminal by writing control strings. This object itself performs
no acutal IO work; it writes bytes to a delegated object given to the
constructor called the writer.

This object is not normally constructed directly by the containing
application; instead it is used indirectly by other parts of the C<Tickit>
distribution.

=cut

=head1 CONSTRUCTOR

=cut

=head2 $term = Tickit::Term->find_for_term( %params )

Attempts to load and construct a subclass determined by the current terminal
type (as given by C<$ENV{TERM}>). If this fails, returns a normal
C<Tickit::Term> instead.

=cut

sub find_for_term
{
   my $class = shift;

   if( defined( my $term = $ENV{TERM} ) ) {
      my $subclass = "${class}::$term";
      ( my $file = "$subclass.pm" ) =~ s{::}{/}g;

      my $self;
      eval { require $file and $self = $subclass->new( @_ ) } and
         return $self;
   }

   return $class->new( @_ );
}

=head2 $term = Tickit::Term->new( %params )

Constructs a new C<Tickit::Term> object.

Takes the following named arguments at construction time:

=over 8

=item encoding => STRING

Optional. If supplied, applies the named encoding to the Unicode string
supplied to the C<print> method.

=item writer => OBJECT

An object delegated to for sending strings of terminal control bytes to the
terminal itself. This object must support a single method, C<write>, taking
a string of bytes.

 $writer->write( $data )

Such an interface is supported by an C<IO::Handle> object.

=back

=cut

sub new
{
   my $class = shift;
   my %params = @_;

   my $encoding = delete $params{encoding};

   my $self = bless {
      writer => $params{writer},
   }, $class;

   my $ti = Term::Terminfo->new();

   # Precache some terminfo flags that we know won't change
   $self->{has_bce} = $ti->getflag( "bce" );

   if( defined $encoding ) {
      $self->{encoder} = find_encoding( $encoding );
   }

   $self->{pen} = {};

   # Almost certainly we'll start in a mode where the cursor is still visible
   $self->{mode_cursorvis} = 1;

   return $self;
}

sub write
{
   my $self = shift;
   $self->{writer}->write( @_ );
}

=head1 METHODS

=cut

sub set_size
{
   my $self = shift;
   ( $self->{lines}, $self->{cols} ) = @_;
}

sub lines { shift->{lines} }
sub cols  { shift->{cols}  }

=head2 $term->print( $text )

Print the given text to the terminal at the current cursor position

=cut

sub print
{
   my $self = shift;
   my ( $text ) = @_;

   $text = $self->{encoder}->encode( $text ) if $self->{encoder};

   $self->write( $text );
}

=head2 $term->goto( $line, $col )

Move the cursor to the given position on the screen. If only one parameter is
defined, does not alter the other. Both C<$line> and C<$col> are 0-based.

=cut

sub goto
{
   my $self = shift;
   my ( $line, $col ) = @_;

   if( defined $col and defined $line ) {
      $self->write( sprintf "${CSI}%d;%dH", $line+1, $col+1 );
   }
   elsif( defined $line ) {
      $self->write( sprintf "${CSI}%dH", $line+1 );
   }
   elsif( defined $col ) {
      $self->write( sprintf "${CSI}%dG", $col+1 );
   }
}

=head2 $term->move( $downward, $rightward )

Move the cursor relative to where it currently is.

=cut

sub move
{
   my $self = shift;
   my ( $downward, $rightward ) = @_;

   if( $downward and $downward > 0 ) {
      $self->write( sprintf "${CSI}%dB", $downward );
   }
   elsif( $downward and $downward < 0 ) {
      $self->write( sprintf "${CSI}%dA", -$downward );
   }

   if( $rightward and $rightward > 0 ) {
      $self->write( sprintf "${CSI}%dC", $rightward );
   }
   elsif( $rightward and $rightward < 0 ) {
      $self->write( sprintf "${CSI}%dD", -$rightward );
   }
}

=head2 $success = $term->scrollrect( $top, $left, $lines, $cols, $downward, $rightward )

Attempt to scroll the rectangle of the screen defined by the first four
parameters by an amount given by the latter two. Since most terminals cannot
perform arbitrary rectangle scrolling, this method returns a boolean to
indicate if it was successful. The caller should test this return value and
fall back to another drawing strategy if the attempt was unsuccessful.

The cursor may move as a result of calling this method; its location is
undefined if this method returns successful.

=cut

sub scrollrect
{
   my $self = shift;
   my ( $top, $left, $lines, $cols, $downward, $rightward ) = @_;

   return 1 if !$downward and !$rightward;

   if( $left == 0 and $cols == $self->cols and $rightward == 0 ) {
      $self->_scroll_lines( $top, $top + $lines - 1, $downward );
      return 1;
   }

   if( $left + $cols == $self->cols and $downward == 0 ) {
      foreach my $line ( $top .. $top + $lines - 1 ) {
         $self->goto( $line, $left );
         $rightward > 0 ? $self->insertch(  $rightward )
                        : $self->deletech( -$rightward );
      }
      return 1;
   }

   return 0;
}

sub _scroll_lines
{
   my $self = shift;
   my ( $from, $to, $by ) = @_;

   $self->write( sprintf "${CSI}%d;%dr", $from+1, $to+1 );

   if( $by > 0 ) {
      $self->goto( $to );
      $self->write( "\n" x $by );
   }
   else {
      $self->goto( $from );
      $self->write( "${ESC}M" x abs($by) ); # ESC M = Reverse Index
   }

   $self->write( "${CSI}r" );
}

sub _colspec_to_sgr
{
   my $self = shift;
   my ( $spec, $is_bg ) = @_;

   return $spec + ($is_bg?40:30) if $spec < 8;
   return +($spec-8) + ($is_bg?100:90) if $spec >= 8 and $spec < 16;

   # Defaults
   return $is_bg?49:39;
}

# Methods to make SGRs out of attribute values
sub _make_sgr_fg { defined $_[1] ? $_[0]->_colspec_to_sgr( $_[1], 0 ) : 39 }
sub _make_sgr_bg { defined $_[1] ? $_[0]->_colspec_to_sgr( $_[1], 1 ) : 49 }
sub _make_sgr_b      { $_[1] ? 1 : 22 }
sub _make_sgr_u      { $_[1] ? 4 : 24 }
sub _make_sgr_i      { $_[1] ? 3 : 23 }
sub _make_sgr_rv     { $_[1] ? 7 : 27 }
sub _make_sgr_strike { $_[1] ? 9 : 29 }
sub _make_sgr_af     { $_[1] ? $_[1]+10 : 10 }

=head2 $term->chpen( %attrs )

Changes the current pen attributes to those given. Any attribute whose value
is given as C<undef> is reset. Any attributes not named are unchanged.

For details of the supported pen attributes, see L<Tickit::Pen>.

=cut

sub chpen
{
   my $self = shift;
   my %new = @_;

   my $pen = $self->{pen};

   my @SGR;

   foreach my $attr (@Tickit::Pen::ALL_ATTRS) {
      next unless exists $new{$attr};

      my $val = $new{$attr};

      next if !defined $pen->{$attr} and !defined $val and exists $pen->{$attr};
      next if  defined $pen->{$attr} and  defined $val and $pen->{$attr} eq $val;

      $pen->{$attr} = $val;

      my $method = "_make_sgr_$attr";
      push @SGR, $self->$method( $val );
   }

   # Shortcut - if there's no pen attributes left, just send SGR reset. Fewer
   # bytes down possibly-slow terminal link that way.
   if( grep { $pen->{$_} } keys %$pen ) {
      $self->write( "${CSI}" . join( ";", @SGR ) . "m" ) if @SGR;
   }
   else {
      $self->write( "${CSI}m" );
   }
}

=head2 $term->setpen( %attrs )

Similar to C<chpen>, but completely defines the state of the terminal pen. Any
attribute not given will be reset to its default value.

=cut

sub setpen
{
   my $self = shift;
   my %new = @_;

   $self->chpen( map { $_ => $new{$_} } @Tickit::Pen::ALL_ATTRS );
}

=head2 $term->clear

Erase the entire screen

=cut

sub clear
{
   my $self = shift;
   $self->write( "${CSI}2J" );
}

=head2 $term->eraseinline

Clear the current line from the cursor onwards.

=cut

sub eraseinline
{
   my $self = shift;
   $self->write( "${CSI}K" );
}

=head2 $term->erasech( $count, $moveend )

Erase C<$count> characters forwards. If C<$moveend> is true, the cursor is
moved to the end of the erased region. If defined but false, the cursor will
remain where it is. If undefined, the terminal will perform whichever of these
behaviours is more efficient, and the cursor will end at some undefined
location.

Using C<$moveend> may be more efficient than separate C<erasech> and C<goto>
calls on terminals that do not have an erase function, as it will be
implemented by printing spaces. This removes the need for two cursor jumps.

=cut

sub erasech
{
   my $self = shift;
   my ( $count, $moveend ) = @_;

   # If we have a background colour and the term does not have background
   # colour erase, we'll need to print spaces to set the colour
   if( $self->{pen}{bg} and !$self->{has_bce} ) {
      $self->write( " " x $count );
      $self->write( sprintf "${CSI}%dD", $count ) if defined $moveend and !$moveend;
   }
   else {
      $self->write( sprintf "${CSI}%dX", $count );
      $self->write( sprintf "${CSI}%dC", $count ) if $moveend;
   }
}

=head2 $term->insertch( $count )

Insert C<$count> blank characters, shifting following text to the right.

=cut

sub insertch
{
   my $self = shift;
   my ( $count ) = @_;

   $self->write( sprintf "${CSI}%d@", $count );
}

=head2 $term->deletech( $count )

Delete the following C<$count> characters, shifting the remaining text to the
left. The terminal will fill the empty region with blanks.

=cut

sub deletech
{
   my $self = shift;
   my ( $count ) = @_;

   $self->write( sprintf "${CSI}%dP", $count );
}

=head2 $term->mode_altscreen( $on )

Set or clear the DEC Alternate Screen mode

=cut

sub mode_altscreen
{
   my $self = shift;
   my ( $on ) = @_;

   $self->write( $on ? "${CSI}?1049h" : "${CSI}?1049l" );
}

=head2 $term->mode_cursorvis( $on )

Set or clear the cursor visible mode

=cut

sub mode_cursorvis
{
   my $self = shift;
   my ( $on ) = @_;

   return if $self->{mode_cursorvis} == $on;
   $self->{mode_cursorvis} = $on;

   $self->write( $on ? "${CSI}?25h" : "${CSI}?25l" );
}

=head2 $term->mode_mouse( $on )

Set or clear the mouse tracking mode

=cut

sub mode_mouse
{
   my $self = shift;
   my ( $on ) = @_;

   $self->write( $on ? "${CSI}?1002h" : "${CSI}?1002l" );
}

=head1 TODO

=over 4

=item *

Track cursor position, and optimise (or eliminate entirely) C<goto> calls.

=back

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
