#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2009-2011 -- leonerd@leonerd.org.uk

package Tickit::Widget::Static;

use strict;
use warnings;
use base qw( Tickit::OneLineWidget );

our $VERSION = '0.15_001';

use Tickit::Utils qw( textwidth substrwidth ); # 'align'

=head1 NAME

C<Tickit::Widget::Static> - a widget displaying static text

=head1 SYNOPSIS

 use Tickit;
 use Tickit::Widget::Static;
 
 my $tickit = Tickit->new;
 
 my $hello = Tickit::Widget::Static->new(
    text   => "Hello, world",
    align  => "centre",
    valign => "middle",
 );
 
 $tickit->set_root_widget( $hello );
 
 $tickit->run;

=head1 DESCRIPTION

This class provides a widget which displays a single piece of static text.

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

   return $self;
}

=head1 ACCESSORS

=cut

sub cols
{
   my $self = shift;
   return textwidth( $self->{text} );
}

=head2 $text = $static->text

=cut

sub text
{
   my $self = shift;
   return $self->{text};
}

=head2 $static->set_text( $text )

Accessor for C<text> property; the actual text on display in the widget

=cut

sub set_text
{
   my $self = shift;
   ( $self->{text} ) = @_;
   $self->resized;
}

=head2 $align = $static->align

=cut

sub align
{
   my $self = shift;
   return $self->{align};
}

=head2 $static->set_align( $align )

Accessor for horizontal alignment value.

Gives a value in the range from C<0.0> to C<1.0> to align the text display
within the window. If the window is larger than the width of the text, it will
be aligned according to this value; with C<0.0> on the left, C<1.0> on the
right, and other values inbetween.

The symbolic values C<left>, C<centre> and C<right> can be supplied instead of
C<0.0>, C<0.5> and C<1.0> respectively.

=cut

sub set_align
{
   my $self = shift;
   my ( $align ) = @_;

   # Convert symbolics
   $align = 0.0 if $align eq "left";
   $align = 0.5 if $align eq "centre";
   $align = 1.0 if $align eq "right";

   $self->{align} = $align;

   $self->redraw;
}

use constant CLEAR_BEFORE_RENDER => 0;

sub render_line
{
   my $self = shift;
   my $window = $self->window;

   my $text = $self->{text};
   my ( $left, $textwidth, $right ) = 
      Tickit::Utils::align( textwidth( $text ), $window->cols, $self->{align} );

   $window->erasech( $left, 1 ) if $left;
   $window->print( substrwidth $text, 0, $textwidth );
   $window->erasech( $right ) if $right;
}

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
