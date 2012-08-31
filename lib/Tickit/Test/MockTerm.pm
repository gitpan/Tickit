package Tickit::Test::MockTerm;

use strict;
use warnings;

our $VERSION = '0.20';

sub new
{
   my $class = shift;
   my %args = @_;

   my $self = bless {
      lines => $args{lines} || 25,
      cols  => $args{cols}  || 80,
      pen   => { map { $_ => undef } @Tickit::Pen::ALL_ATTRS },
   }, $class;

   $self->set_on_resize( $args{on_resize} ) if $args{on_resize};

   $self->clear;

   # Clear the method log
   $self->methodlog;

   return $self;
}

# Ignore output buffering
sub set_output_buffer { }
sub flush { }

sub set_on_resize
{
   my $self = shift;
   ( $self->{on_resize} ) = @_;
}

sub set_on_key
{
   my $self = shift;
   ( $self->{on_key} ) = @_;
}

sub set_on_mouse
{
   my $self = shift;
   ( $self->{on_mouse} ) = @_;
}

sub is_changed
{
   my $self = shift;
   return $self->{changed};
}

sub get_display_text
{
   my $self = shift;
   my ( $line, $col, $width ) = @_;

   return join "", map { $_->[0] } @{ $self->{cells}[$line] }[$col .. $col + $width - 1];
}

sub get_display_pen
{
   my $self = shift;
   my ( $line, $col ) = @_;

   my $cell = $self->{cells}[$line][$col];
   my %pen = @{$cell}[1..$#$cell];
   defined $pen{$_} or delete $pen{$_} for keys %pen;
   return \%pen;
}

sub get_position
{
   my $self = shift;

   return ( $self->{line}, $self->{col} );
}

sub _push_methodlog
{
   my $self = shift;
   push @{ $self->{methodlog} }, [ @_ ];
}

sub methodlog
{
   my $self = shift;

   $self->showlog if $ENV{DEBUG_MOCKTERM_LOG};

   my @log = @{ $self->{methodlog} ||= [] };
   undef @{ $self->{methodlog} };
   $self->{changed} = 0;

   return @log;
}

sub showlog
{
   my $self = shift;

   foreach my $l ( @{ $self->{methodlog} } ) {
      if( $l->[0] eq "chpen" ) {
         my $pen = $l->[1];
         printf "# SETPEN(%s)\n", join( ", ", map { defined $pen->{$_} ? "$_ => $pen->{$_}" : () } sort keys %$pen );
      }
      else {
         printf "# %s(%s)\n", uc $l->[0], join( ", ", @{$l}[1..$#$l] );
      }
   }
}

sub resize
{
   my $self = shift;
   my ( $newlines, $newcols ) = @_;

   if( $newlines > $self->{lines} ) {
      $self->_clearcells( $_, 0, $newcols ) for $self->{lines} .. $newlines - 1;
   }

   if( $newcols > $self->{cols} ) {
      $self->_clearcells( $_, $self->{cols}, $newcols - $self->{cols} ) for 0 .. $self->{lines} - 1;
   }

   # TODO: handle shrinking

   if( $newlines != $self->{lines} or $newcols != $self->{cols} ) {
      $self->{lines} = $newlines;
      $self->{cols}  = $newcols;

      $self->{on_resize}->( $self, $newlines, $newcols ) if $self->{on_resize};
   }
}

sub set_size
{
   # ignore
}

sub lines { $_[0]->{lines} }
sub cols  { $_[0]->{cols} }

sub _clearcells
{
   my $self = shift;
   my ( $line, $col, $count ) = @_;

   local $_;
   $self->{cells}[$line][$_] = [ " ", %{ $self->{pen} } ] for $col .. $col+$count-1;
}

sub _clearline
{
   my $self = shift;
   my ( $line ) = @_;
   $self->_clearcells( $line, 0, $self->cols );
}

sub clear
{
   my $self = shift;

   $self->_push_methodlog( clear => @_ );

   local $_;
   $self->_clearline( $_ ) for 0 .. $self->lines-1;

   $self->{changed}++;
}

sub erasech
{
   my $self = shift;
   my ( $count, $moveend ) = @_;

   $self->_push_methodlog( erasech => $count, $moveend || 0 );

   $self->_clearcells( $self->{line}, $self->{col}, $count );
   $self->{col} += $count if $moveend;

   $self->{changed}++;
}

sub goto
{
   my $self = shift;
   ( $self->{line}, $self->{col} ) = @_;

   $self->_push_methodlog( goto => @_ );

   $self->{changed}++;
}

sub print
{
   my $self = shift;
   my ( $text ) = @_;

   $self->_push_methodlog( print => @_ );

   # TODO: This will only handle ASCII
   foreach my $char ( split //, $text ) {
      $self->{cells}[$self->{line}][$self->{col}] = [ $char, %{ $self->{pen} } ];
      $self->{col}++;
   }

   $self->{changed}++;
}

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
         $rightward > 0 ? $self->_insertch(  $rightward )
                        : $self->_deletech( -$rightward );
      }
      return 1;
   }

   return 0;
}

sub _scroll_lines
{
   my $self = shift;
   my ( $top, $bottom, $downward ) = @_;

   # Logic is simpler if $bottom is the first line -beyond- the scroll region
   $bottom++;

   $self->_push_methodlog( scrollrect => $top, 0, $bottom - $top, $self->cols, $downward, 0 );

   my $cells = $self->{cells};

   if( $downward > 0 ) {
      splice @$cells, $top, $downward, ();

      splice @$cells, $bottom - $downward, 0, ( undef ) x $downward;
      $self->_clearline( $_ ) for $bottom - $downward .. $bottom - 1;
   }
   elsif( $downward < 0 ) {
      my $upward = -$downward;

      splice @$cells, $bottom - $upward, $upward, ();

      splice @$cells, $top, 0, ( undef ) x $upward;
      $self->_clearline( $_ ) for $top .. $top + $upward - 1;
   }

   $self->{changed}++;

   return 1;
}

sub _insertch
{
   my $self = shift;
   my ( $count ) = @_;

   $self->_push_methodlog( insertch => $count );

   splice @{ $self->{cells}[$self->{line}] }, $self->{col}, 0, (undef) x $count;
   $self->_clearcells( $self->{line}, $self->{col}, $count );

   splice @{ $self->{cells}[$self->{line}] }, $self->cols; # truncate

   $self->{changed}++;
}

sub _deletech
{
   my $self = shift;
   my ( $count ) = @_;

   $self->_push_methodlog( deletech => $count );

   splice @{ $self->{cells}[$self->{line}] }, $self->{col}, $count, ();

   $self->_clearcells( $self->{line}, $self->cols - $count, $count );

   $self->{changed}++;
}

# For testing purposes we'll store this in a hash instead
sub chpen
{
   my $self = shift;
   my %attrs = ( @_ == 1 ) ? shift->getattrs : @_;

   $self->{pen}{$_} = $attrs{$_} for keys %attrs;

   $self->_push_methodlog( chpen => \%attrs );
}

sub setpen
{
   my $self = shift;
   my %attrs = ( @_ == 1 ) ? shift->getattrs : @_;
   $self->chpen( map { $_ => $attrs{$_} } @Tickit::Pen::ALL_ATTRS );
}

sub mode_altscreen
{
   # ignore
}

sub mode_cursorvis
{
   my $self = shift;
   ( $self->{cursorvis} ) = @_;
}

sub mode_mouse
{
   # ignore
}

0x55AA;
