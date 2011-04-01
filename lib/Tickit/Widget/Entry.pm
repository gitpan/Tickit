#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2011 -- leonerd@leonerd.org.uk

package Tickit::Widget::Entry;

use strict;
use warnings;
use base qw( Tickit::Widget );

our $VERSION = '0.03';

use Text::CharWidth qw( mbswidth );

# Positions in this code can get complicated. The following conventions apply:
#   $pos_ch  = a position in CHaracters within a Unicode string (length, substr,..)
#   $pos_co  = a position in screen COlumns counted from the start of the string
#   $pos_x   = a position in screen columns from the start of the window ($win->goto)

=head1 NAME

C<Tickit::Widget::Entry> - a widget for entering text

=head1 SYNOPSIS

 use Tickit;
 use Tickit::Widget::Entry;
 use IO::Async::Loop;
 
 my $loop = IO::Async::Loop->new;
 
 my $tickit = Tickit->new;
 $loop->add( $tickit );
 
 my $entry = Tickit::Widget::Entry->new(
    on_enter => sub {
       my ( $self, $line ) = @_;

       # process $line somehow

       $self->set_text( "" );
    },
 );
 
 $tickit->set_root_widget( $entry );
 
 $tickit->run;

=head1 DESCRIPTION

This class provides a widget which allows the user to enter a line of text.

=cut

=head1 KEYBINDINGS

The following keys are bound by default

=over 2

=item * Ctrl-K

Delete the entire line

=item * Ctrl-U

Delete to the start of the line

=item * Ctrl-W

Delete one word backwards

=item * Backspace

Delete one character backwards

=item * Delete

Delete one character forwards

=item * Ctrl-Delete

Delete one word forwards

=item * End

Move the cursor to the end of the input line

=item * Enter

Accept a line of input by running the C<on_enter> action

=item * Home

Move the cursor to the beginning of the input line

=item * Left

Move the cursor one character left

=item * Ctrl-Left or Alt-B

Move the cursor one word left

=item * Right

Move the cursor one character right

=item * Ctrl-Right or Alt-F

Move the cursor one word right

=back

=cut

=head1 CONSTRUCTOR

=cut

=head2 $entry = Tickit::Widget::Entry->new( %args )

Constructs a new C<Tickit::Widget::Entry> object.

=cut

sub new
{
   my $class = shift;
   my %params = @_;

   my $self = $class->SUPER::new( %params );

   $self->{text} = defined $params{text} ? $params{text} : "";
   $self->{pos_ch} = defined $params{position} ? $params{position} : 0;

   my $textlen = length $self->{text};
   $self->{pos_ch} = $textlen if $self->{pos_ch} > $textlen;

   $self->{keybindings} = {
      'C-k' => "key_delete_line",
      'C-u' => "key_backward_delete_line",
      'C-w' => "key_backward_delete_word",

      'M-b' => "key_backward_word",
      'M-f' => "key_forward_word",

      'Backspace' => "key_backward_delete_char",
      'Delete'    => "key_forward_delete_char",
      'C-Delete'  => "key_forward_delete_word",
      'End'       => "key_end_of_line",
      'Enter'     => "key_enter_line",
      'Home'      => "key_beginning_of_line",
      'Left'      => "key_backward_char",
      'C-Left'    => "key_backward_word",
      'Right'     => "key_forward_char",
      'C-Right'   => "key_forward_word",
   };

   $self->set_on_enter( $params{on_enter} ) if defined $params{on_enter};

   return $self;
}

sub lines { 1 }
sub cols  { 1 }

sub char2col
{
   my $self = shift;
   my ( $ch ) = @_;

   return mbswidth( substr $self->{text}, 0, $ch );
}

sub render
{
   my $self = shift;

   my $win = $self->window or return;

   $win->goto( 0, 0 );

   my $text = $self->{text};
   $win->print( $text );

   $win->erasech( $win->cols - length $text );

   $self->reposition_cursor;
}

sub reposition_cursor
{
   my $self = shift;

   my $win = $self->window or return;

   $win->focus( 0, $self->char2col( $self->{pos_ch} ) );
}

sub on_key
{
   my $self = shift;
   my ( $type, $str, $key ) = @_;

   if( $type eq "key" and my $code = $self->{keybindings}{$str} ) {
      return $self->$code( $str, $key );
   }
   if( $type eq "text" ) {
      $self->on_text( $str );
      return 1;
   }

   return 0;
}

sub on_text
{
   my $self = shift;
   my ( $text ) = @_;

   $self->text_insert( $text, $self->{pos_ch} );
}

=head1 ACCESSORS

=cut

=head2 $on_enter = $entry->on_enter

=cut

sub on_enter
{
   my $self = shift;
   return $self->{on_enter};
}

=head2 $entry->set_on_enter( $on_enter )

Return or set the CODE reference to be called when the C<key_enter_line>
action is invoked; usually bound to the C<Enter> key.

 $on_enter->( $entry, $line )

=cut

sub set_on_enter
{
   my $self = shift;
   ( $self->{on_enter} ) = @_;
}

=head2 $offset = $entry->position

Returns the current entry position, in terms of characters within the text.

=cut

sub position
{
   my $self = shift;
   return $self->{pos_ch};
}

=head2 $entry->set_position( $position )

Set the text entry position, moving the cursor

=cut

sub set_position
{
   my $self = shift;
   my ( $pos_ch ) = @_;

   $pos_ch = 0 if $pos_ch < 0;
   $pos_ch = length $self->{text} if $pos_ch > length $self->{text};

   $self->{pos_ch} = $pos_ch;

   $self->reposition_cursor;

   if( my $win = $self->window ) {
      $win->restore;
   }
}

=head1 METHODS

=cut

=head2 $entry->bind_keys( $keystr => $value, ... )

Associate methods or CODE references with keypresses. On receipt of a the key
the method or CODE reference will be invoked, being passed the stringified key
representation and the underlying C<Term::TermKey::Key> structure.

 $ret = $entry->method( $keystr, $key )
 $ret = $coderef->( $entry, $keystr, $key )

This method takes a hash of keystring/value pairs. Binding a value of C<undef>
will remove it.

=cut

sub bind_keys
{
   my $self = shift;
   while( @_ ) {
      my $str   = shift;
      my $value = shift;

      if( defined $value ) {
         $self->{keybindings}{$str} = $value;
      }
      else {
         delete $self->{keybindings}{$str};
      }
   }
}

=head1 TEXT MODEL METHODS

These methods operate on the text input buffer directly, updating the stored
text and changing the rendered display to reflect the changes. They can be
used by a program to directly manipulate the text.

=cut

=head2 $text = $entry->text

Returns the currently entered text.

=cut

sub text
{
   my $self = shift;
   return $self->{text};
}

=head2 $entry->set_text( $text )

Replace the text in the entry box. This completely redraws the widget's
window. It is largely provided for initialisation; for normal edits (such as
from keybindings), it is preferrable to use C<text_insert>, C<text_delete> or
C<text_splice>.

=cut

sub set_text
{
   my $self = shift;
   my ( $text ) = @_;

   $self->{text} = $text;
   $self->{pos_ch} = length $text if $self->{pos_ch} > length $text;

   $self->redraw;
}

=head2 $entry->text_insert( $text, $pos_ch )

Insert the given text at the given character position.

=cut

sub text_insert
{
   my $self = shift;
   my ( $text, $pos_ch ) = @_;

   $self->text_splice( $pos_ch, 0, $text );
}

=head2 $entry->text_delete( $pos_ch, $len_ch )

Delete the given section of text.

=cut

sub text_delete
{
   my $self = shift;
   my ( $pos_ch, $len_ch ) = @_;

   $self->text_splice( $pos_ch, $len_ch, "" );
}

=head2 $entry->text_splice( $pos_ch, $len_ch, $text )

Replace the given section of text with the given replacement.

=cut

sub text_splice
{
   my $self = shift;
   my ( $pos_ch, $len_ch, $text ) = @_;

   my $win = $self->window;

   my $textlen_co = mbswidth $text;
   my $textlen_ch = length($text);

   my $deletedlen_co = $len_ch ? mbswidth( substr $self->{text}, $pos_ch, $len_ch ) : 0;

   my $delta_ch = $textlen_ch - $len_ch;
   my $delta_co = $textlen_co - $deletedlen_co;

   if( $pos_ch != $self->{pos_ch} ) {
      $win->goto( 0, $self->char2col( $pos_ch ) );
   }

   if( $delta_co > 0 ) {
      $win->insertch( $delta_co ) if $pos_ch < length $self->{text};
   }
   elsif( $delta_co < 0 ) {
      $win->deletech( -$delta_co );
   }

   $win->print( $text ) if $textlen_ch;
   substr( $self->{text}, $pos_ch, $len_ch ) = $text;

   if( $self->{pos_ch} >= $pos_ch + $len_ch ) {
      # Cursor after splice; move to suit
      $self->{pos_ch} += $delta_ch;
   }
   elsif( $self->{pos_ch} > $pos_ch ) {
      # Cursor within splice; move to start
      $self->{pos_ch} = $pos_ch;
   }
   # else { ignore }

   $self->reposition_cursor;

   if( $pos_ch + $textlen_ch != $self->{pos_ch} ) {
      $win->restore;
   }
}

=head2 $pos = $entry->find_bow_forward( $initial, $else )

Search forward in the string, returning the character position of the next
beginning of word from the initial position. If none is found, returns
C<$else>.

=cut

sub find_bow_forward
{
   my $self = shift;
   my ( $pos, $else ) = @_;

   my $posttext = substr( $self->text, $pos );

   return $posttext =~ m/(?<=\s)\S/ ? $pos + $-[0] : $else;
}

=head2 $pos = $entry->find_eow_forward( $initial )

Search forward in the string, returning the character position of the next
end of word from the initial position. If none is found, returns the length of
the string.

=cut

sub find_eow_forward
{
   my $self = shift;
   my ( $pos ) = @_;

   my $posttext = substr( $self->text, $pos );

   $posttext =~ m/(?<=\S)\s|$/;
   return $pos + $-[0];
}

=head2 $pos = $entry->find_bow_backward( $initial )

Search backward in the string, returning the character position of the
previous beginning of word from the initial position. If none is found,
returns 0.

=cut

sub find_bow_backward
{
   my $self = shift;
   my ( $pos ) = @_;

   my $pretext = substr( $self->text, 0, $pos );

   return $pretext =~ m/.*\s(?=\S)/ ? $+[0] : 0;
}

=head2 $pos = $entry->find_eow_backward( $initial )

Search backward in the string, returning the character position of the
previous end of word from the initial position. If none is found, returns
C<undef>.

=cut

sub find_eow_backward
{
   my $self = shift;
   my ( $pos ) = @_;

   my $pretext = substr( $self->text, 0, $pos + 1 ); # +1 to allow if cursor is on the space

   return $pretext =~ m/.*\S(?=\s)/ ? $+[0] : undef;
}

## Key binding methods

sub key_backward_char
{
   my $self = shift;

   if( $self->{pos_ch} > 0 ) {
      $self->set_position( $self->{pos_ch} - 1 );
   }
}

sub key_backward_delete_char
{
   my $self = shift;

   if( $self->{pos_ch} > 0 ) {
      $self->text_delete( $self->{pos_ch} - 1, 1 );
   }
}

sub key_backward_delete_line
{
   my $self = shift;

   $self->text_delete( 0, $self->{pos_ch} );
}

sub key_backward_delete_word
{
   my $self = shift;

   my $bow = $self->find_bow_backward( $self->{pos_ch} );
   $self->text_delete( $bow, $self->{pos_ch} - $bow );
}

sub key_backward_word
{
   my $self = shift;

   if( $self->{pos_ch} > 0 ) {
      $self->set_position( $self->find_bow_backward( $self->{pos_ch} ) );
   }
}

sub key_beginning_of_line
{
   my $self = shift;

   $self->set_position( 0 );
}

sub key_delete_line
{
   my $self = shift;

   $self->text_delete( 0, length $self->text );
}

sub key_end_of_line
{
   my $self = shift;

   $self->set_position( length $self->{text} );
}

sub key_enter_line
{
   my $self = shift;

   my $text = $self->text;
   return unless length $text;

   my $on_enter = $self->{on_enter} or return;
   $on_enter->( $self, $text );
}

sub key_forward_char
{
   my $self = shift;

   if( $self->{pos_ch} < length $self->{text} ) {
      $self->set_position( $self->{pos_ch} + 1 );
   }
}

# Renamed from readline's "delete-char" because this one doesn't have the EOF
# behaviour if input line is empty
sub key_forward_delete_char
{
   my $self = shift;

   if( $self->{pos_ch} < length $self->{text} ) {
      $self->text_delete( $self->{pos_ch}, 1 );
   }
}

sub key_forward_delete_word
{
   my $self = shift;

   my $bow = $self->find_bow_forward( $self->{pos_ch}, length $self->text );
   $self->text_delete( $self->{pos_ch}, $bow - $self->{pos_ch} );
}

sub key_forward_word
{
   my $self = shift;

   my $bow = $self->find_bow_forward( $self->{pos_ch}, length $self->text );
   $self->set_position( $bow );
}

=head1 TODO

=over 4

=item * Plugin ability

Try to find a nice way to allow loaded plugins, possibly per-instance if not
just globally or per-class. See how many of these TODO items can be done using
plugins.

=item * Sideways scrolling

Scroll text left or right to fit the cursor within the visible range. Display
"more" markers at either end as appropriate.

=item * More readline behaviours

Insert/overwrite. History. Isearch. History replay. Transpose. Transcase. Yank
ring. Numeric prefixes.

=item * Visual selection behaviour

Shift-movement, or vim-style.

=item * Mouse support

Click to position cursor. Drag to start a selection.

=back

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
