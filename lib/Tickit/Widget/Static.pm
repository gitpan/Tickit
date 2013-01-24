#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2009-2012 -- leonerd@leonerd.org.uk

package Tickit::Widget::Static;

use strict;
use warnings;
use base qw( Tickit::Widget );

use Tickit::WidgetRole::Alignable name => 'align',  dir => 'h';
use Tickit::WidgetRole::Alignable name => 'valign', dir => 'v';

our $VERSION = '0.26';

use List::Util qw( max );
use Tickit::Utils qw( textwidth substrwidth );

=head1 NAME

C<Tickit::Widget::Static> - a widget displaying static text

=head1 SYNOPSIS

 use Tickit;
 use Tickit::Widget::Static;
 
 my $hello = Tickit::Widget::Static->new(
    text   => "Hello, world",
    align  => "centre",
    valign => "middle",
 );
 
 Tickit->new( root => $hello )->run;

=head1 DESCRIPTION

This class provides a widget which displays a single piece of static text. The
text may contain more than one line, separated by linefeed (C<\n>) characters.
No other control sequences are allowed in the string.

=cut

=head1 CONSTRUCTOR

=cut

=head2 $static = Tickit::Widget::Static->new( %args )

Constructs a new C<Tickit::Widget::Static> object.

Takes the following named arguments in addition to those taken by the base
L<Tickit::Widget> constructor:

=over 8

=item text => STRING

The text to display

=item align => FLOAT|STRING

Optional. Defaults to C<0.0> if unspecified.

=item valign => FLOAT|STRING

Optional. Defaults to C<0.0> if unspecified.

=back

For more details see the accessors below.

=cut

sub new
{
   my $class = shift;
   my %args = @_;

   my $self = $class->SUPER::new( %args );

   $self->set_text( $args{text} );
   $self->set_align( $args{align} || 0 );
   $self->set_valign( $args{valign} || 0 );

   return $self;
}

=head1 ACCESSORS

=cut

sub lines
{
   my $self = shift;
   return scalar @{ $self->{lines} };
}

sub cols
{
   my $self = shift;
   return max map { textwidth $_ } @{ $self->{lines} }
}

=head2 $text = $static->text

=cut

sub text
{
   my $self = shift;
   return join "\n", @{ $self->{lines} };
}

=head2 $static->set_text( $text )

Accessor for C<text> property; the actual text on display in the widget

=cut

sub set_text
{
   my $self = shift;
   my ( $text ) = @_;
   my @lines = split m/\n/, $text;
   # split on empty string returns empty list
   @lines = ( "" ) if !@lines;
   $self->{lines} = \@lines;
   $self->resized;
   $self->redraw;
}

=head2 $align = $static->align

=head2 $static->set_align( $align )

Accessor for horizontal alignment value.

Gives a value in the range from C<0.0> to C<1.0> to align the text display
within the window. If the window is larger than the width of the text, it will
be aligned according to this value; with C<0.0> on the left, C<1.0> on the
right, and other values inbetween.

See also L<Tickit::WidgetRole::Alignable>.

=cut

use constant CLEAR_BEFORE_RENDER => 0;

sub render
{
   my $self = shift;
   my %args = @_;

   my $win = $self->window;
   $win->is_visible or return;
   my $rect = $args{rect};

   my $cols = $win->cols;

   my ( $above, $lines ) = $self->_valign_allocation( $self->lines, $win->lines );

   $win->goto( $_, 0 ), $win->erasech( $cols ) for $rect->top .. $above - 1;

   foreach my $line ( 0 .. $lines - 1 ) {
      my $text = $self->{lines}[$line];

      my ( $left, $textwidth, $right ) = $self->_align_allocation( textwidth( $text ), $cols );

      $win->goto( $above + $line, 0 );
      $win->erasech( $left, 1 ) if $left;
      $win->print( substrwidth $text, 0, $textwidth );
      $win->erasech( $right ) if $right;
   }

   $win->goto( $_, 0 ), $win->erasech( $cols ) for $above + $lines .. $rect->bottom - 1;
}

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
