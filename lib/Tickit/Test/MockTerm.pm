package Tickit::Test::MockTerm;

use strict;
use warnings;

our $VERSION = '0.09';

sub new
{
   my $class = shift;
   my %args = @_;

   my $self = bless {
      lines => $args{lines} || 25,
      cols  => $args{cols}  || 80,
   }, $class;

   $self->clear;

   # Clear the method log
   $self->methodlog;

   return $self;
}

sub configure
{
   my $self = shift;
   my %args = @_;

   $self->{on_resize} = delete $args{on_resize} if exists $args{on_resize};
   $self->{on_key}    = delete $args{on_key}    if exists $args{on_key};
   $self->{on_mouse}  = delete $args{on_mouse}  if exists $args{on_mouse};
}

sub is_changed
{
   my $self = shift;
   return $self->{changed};
}

sub get_display
{
   my $self = shift;

   return map { $self->{display}[$_] } 0 .. $#{ $self->{display} };
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

   # Extend the buffer
   substr( $self->{display}[$_], $self->cols, 0 ) = " " x ( $newcols - $newcols ) for 0 .. $self->lines-1;
   $self->{display}[$_] = " " x $newcols for $self->lines .. $newlines-1;

   $self->{lines} = $newlines;
   $self->{cols}  = $newcols;
}

sub set_size
{
   # ignore
}

sub lines { $_[0]->{lines} }
sub cols  { $_[0]->{cols} }

sub clear
{
   my $self = shift;

   $self->_push_methodlog( clear => @_ );

   $self->{display}[$_] = " " x $self->cols for 0 .. $self->lines-1;

   $self->{changed}++;
}

sub erasech
{
   my $self = shift;
   my ( $count, $moveend ) = @_;

   $self->_push_methodlog( erasech => $count, $moveend || 0 );

   substr( $self->{display}[$self->{line}], $self->{col}, $count ) = " " x $count;
   $self->{col} += $count if $moveend;

   $self->{changed}++;
}

sub insertch
{
   my $self = shift;
   my ( $count ) = @_;

   $self->_push_methodlog( insertch => $count );

   substr( $self->{display}[$self->{line}], $self->{col} + $count ) =
      substr( $self->{display}[$self->{line}], $self->{col}, $self->cols - $self->{col} - $count );

   substr( $self->{display}[$self->{line}], $self->{col}, $count ) = " " x $count;

   $self->{changed}++;
}

sub deletech
{
   my $self = shift;
   my ( $count ) = @_;

   $self->_push_methodlog( deletech => $count );

   substr( $self->{display}[$self->{line}], $self->{col}, $self->cols - $self->{col} - $count ) =
      substr( $self->{display}[$self->{line}], $self->{col} + $count );

   substr( $self->{display}[$self->{line}], $self->cols - $count, $count ) = " " x $count;

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

   substr( $self->{display}[$self->{line}], $self->{col}, length $text ) = $text;

   $self->{col} += length $text;
   $self->{changed}++;
}

# Tickit::Term::scrollrect is implemented using _scroll_lines or
# goto/insertch/deletech. Either way, we can use it here
require Tickit::Term;
*scrollrect = \&Tickit::Term::scrollrect;

sub _scroll_lines
{
   my $self = shift;
   my ( $top, $bottom, $downward ) = @_;

   # Logic is simpler if $bottom is the first line -beyond- the scroll region
   $bottom++;

   my $display = $self->{display};

   if( $downward > 0 ) {
      splice @$display, $top, $downward, ();
      splice @$display, $bottom - $downward, 0, ( " " x $self->cols ) x $downward;
   }
   elsif( $downward < 0 ) {
      my $upward = -$downward;

      splice @$display, $bottom - $upward, $upward, ();
      splice @$display, $top, 0, ( " " x $self->cols ) x $upward;
   }

   $self->_push_methodlog( scrollrect => $top, 0, $bottom - $top, $self->cols, $downward, 0 );

   $self->{changed}++;

   return 1;
}

# For testing purposes we'll store this in a hash instead
sub chpen
{
   my $self = shift;
   my %attrs = @_;

   $self->_push_methodlog( chpen => \%attrs );
}

sub setpen
{
   my $self = shift;
   my %attrs = @_;
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
