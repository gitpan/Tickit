#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2011-2012 -- leonerd@leonerd.org.uk

package Tickit::Widget::Frame;

use strict;
use warnings;
use base qw( Tickit::SingleChildWidget );

use Tickit::WidgetRole::Alignable name => "title_align";
use Tickit::WidgetRole::Penable name => "frame";

our $VERSION = '0.24';

use Carp;

use Tickit::Pen;
use Tickit::Utils qw( textwidth substrwidth );

=head1 NAME

C<Tickit::Widget::Frame> - draw a frame around another widget

=head1 SYNOPSIS

 use Tickit;
 use Tickit::Widget::Frame;
 use Tickit::Widget::Static;
 
 my $tickit = Tickit->new;
 
 my $hello = Tickit::Widget::Static->new(
    text   => "Hello, world",
    align  => "centre",
    valign => "middle",
 );

 my $frame = Tickit::Widget::Frame->new;

 $frame->add( $hello );
 
 $tickit->set_root_widget( $frame );
 
 $tickit->run;

=head1 DESCRIPTION

This container widget draws a frame around a single child widget.

=cut

=head1 CONSTRUCTOR

=cut

=head2 $frame = Tickit::Widget::Frame->new( %args )

Constructs a new C<Tickit::Widget::Static> object.

Takes the following named arguments in addition to those taken by the base
L<Tickit::SingleChildWidget> constructor:

=over 8

=item style => STRING

Optional. Defaults to C<ascii> if unspecified.

=item title => STRING

Optional.

=item title_align => FLOAT|STRING

Optional. Defaults to C<0.0> if unspecified.

=back

For more details see the accessors below.

=cut

sub new
{
   my $class = shift;
   my %args = @_;

   my $self = $class->SUPER::new( %args );

   $self->set_style( $args{style} || "ascii" );
   $self->_init_frame_pen;
   $self->set_title( $args{title} ) if defined $args{title};
   $self->set_title_align( $args{title_align} || 0 );

   return $self;
}

=head1 ACCESSORS

=cut

sub lines
{
   my $self = shift;
   my $child = $self->child;
   return ( $child ? $child->lines : 0 ) + 2;
}

sub cols
{
   my $self = shift;
   my $child = $self->child;
   return ( $child ? $child->cols : 0 ) + 2;
}

use constant {
   TOP       => 0,
   BOTTOM    => 1,
   LEFT      => 2,
   RIGHT     => 3,
   CORNER_TL => 4,
   CORNER_TR => 5,
   CORNER_BL => 6,
   CORNER_BR => 7,
};

# Character numbers from
#   http://en.wikipedia.org/wiki/Box-drawing_characters

my %STYLES = ( #               TOP     BOTTOM  LEFT    RIGHT   TL      TR      BL      BR
   ascii         => [          '-',    '-',    '|',    '|',    '+',    '+',    '+',    '+' ],
   single        => [ map chr, 0x2500, 0x2500, 0x2502, 0x2502, 0x250C, 0x2510, 0x2514, 0x2518 ],
   double        => [ map chr, 0x2550, 0x2550, 0x2551, 0x2551, 0x2554, 0x2557, 0x255A, 0x255D ],
   thick         => [ map chr, 0x2501, 0x2501, 0x2503, 0x2503, 0x250F, 0x2513, 0x2517, 0x251B ],
   solid_inside  => [ map chr, 0x2584, 0x2580, 0x2590, 0x258C, 0x2597, 0x2596, 0x259D, 0x2598 ],
   solid_outside => [ map chr, 0x2580, 0x2584, 0x258C, 0x2590, 0x259B, 0x259C, 0x2599, 0x259F ],
);

=head2 $style = $frame->style

=cut

sub style
{
   my $self = shift;
   return $self->{style};
}

=head2 $frame->set_style( $style )

Accessor for the C<style> property, which controls the way the actual frame is
drawn around the inner widget. Must be one of the following names:

 ascii single double thick solid_inside solid_outside

The C<ascii> style is default, and uses only the C<-|+> ASCII characters.
Other styles use Unicode box-drawing characters. These may not be supported by
all terminals or fonts.

=cut

sub set_style
{
   my $self = shift;

   exists $STYLES{$_[0]} or croak "Cannot set Frame style to '$_[0]'";

   $self->{style} = $_[0];
   $self->redraw;
}

=head2 $frame_pen = $widget->frame_pen

Returns the current frame pen. Modifying an attribute of the returned object
results in the widget being redrawn if the widget has a window associated.

=cut

=head2 $widget->set_frame_pen( $pen )

Set a new C<Tickit::Pen> object. This is stored by reference; changes to the
pen will be reflected in the rendered look of the frame. The same pen may be
shared by more than one widget; updates will affect them all.

=cut

sub on_pen_changed
{
   my $self = shift;
   my ( $pen ) = @_;

   if( $self->window and $pen == $self->frame_pen ) {
      $self->redraw;
   }
   else {
      $self->SUPER::on_pen_changed( @_ );
   }
}

=head2 $title = $frame->title

=cut

sub title
{
   my $self = shift;
   return $self->{title};
}

=head2 $frame->title( $title )

Accessor for the C<title> property, a string written in the top of the
frame.

=cut

sub set_title
{
   my $self = shift;
   $self->{title} = $_[0];
   $self->redraw;
}

=head2 $title_align = $frame->title_align

=head2 $frame->set_title_align( $title_align )

Accessor for the C<title_align> property. Gives a vlaue in the range C<0.0> to
C<1.0> to align the title in the top of the frame.

See also L<Tickit::WidgetRole::Alignable>.

=cut

sub children_changed { shift->set_child_window }
sub reshape          { shift->set_child_window }

sub set_child_window
{
   my $self = shift;

   my $window = $self->window or return;
   my $child  = $self->child  or return;

   my $lines = $window->lines;
   my $cols  = $window->cols;

   if( $lines > 2 and $cols > 2 ) {
      if( my $childwin = $child->window ) {
         $childwin->change_geometry( 1, 1, $lines - 2, $cols - 2 );
      }
      else {
         my $childwin = $window->make_sub( 1, 1, $lines - 2, $cols - 2 );
         $child->set_window( $childwin );
      }
   }
   else {
      if( $child->window ) {
         $child->set_window( undef );
      }
   }
}

use constant CLEAR_BEFORE_RENDER => 0;

sub render
{
   my $self = shift;
   my %args = @_;

   my $win = $self->window or return;
   $win->is_visible or return;
   my $rect = $args{rect};

   my $cols  = $win->cols;
   my $lines = $win->lines;

   my $style = $STYLES{$self->{style}};

   my $framepen = $self->frame_pen;

   foreach my $line ( $rect->linerange ) {
      $win->goto( $line, 0 );

      if( $line == 0 ) {
         # Top line
         if( defined( my $title = $self->title ) ) {
            # At most we can fit $cols-4 columns of title
            my ( $left, $titlewidth, $right ) = $self->_title_align_allocation( textwidth( $title ), $cols - 4 );

            $win->print( $style->[CORNER_TL] . ( $style->[TOP] x $left ) . " ", $framepen );
            $win->print( $title, $framepen );
            $win->print( " " . ( $style->[TOP] x $right ) . $style->[CORNER_TR], $framepen ) if $cols > 1;
         }
         else {
            my $str = $style->[CORNER_TL];
            $str .= $style->[TOP] x ($cols - 2) if $cols > 2;
            $str .= $style->[CORNER_TR] if $cols > 1;

            $win->print( $str, $framepen );
         }
      }
      elsif( $line < $lines - 1 ) {
         # Middle line
         $win->print( $style->[LEFT], $framepen );

         next if $cols == 1;

         $win->goto( $line, $cols - 1 );
         $win->print( $style->[RIGHT], $framepen );
      }
      else {
         # Bottom line
         my $str = $style->[CORNER_BL];
         $str .= $style->[BOTTOM] x ($cols - 2) if $cols > 2;
         $str .= $style->[CORNER_BR] if $cols > 1;

         $win->print( $str, $framepen );
      }
   }
}

=head1 TODO

=over 4

=item *

Specific pen for title. Layered on top of frame pen.

=item *

Caption at the bottom of the frame as well. Identical to title.

=item *

Consider if it's useful to provide accessors to apply extra padding inside the
frame, surrounding the child window.

=back

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
