package Tickit::Test::MockTerm;

use strict;
use warnings;
use feature qw( switch );
no if $] >= 5.017011, warnings => 'experimental::smartmatch';

our $VERSION = '0.45';

use base qw( Tickit::Term );

use Tickit::Utils qw( textwidth substrwidth );

sub new
{
   my $class = shift;
   my %args = @_;

   my $self = $class->_new_mocking( $args{lines} || 25, $args{cols} || 80 );

   $self->clear;

   # Clear the method log
   $self->get_methodlog;

   return $self;
}

# Ignore output buffering
sub set_output_buffer { }
sub flush { }

# We're already ready
sub await_started { }

sub get_display_text
{
   my $self = shift;
   my ( $line, $col, $width ) = @_;

   return join "", map { $_->[0] } @{ $self->cells->[$line] }[$col .. $col + $width - 1];
}

sub get_display_pen
{
   my $self = shift;
   my ( $line, $col ) = @_;

   my $cell = $self->cells->[$line][$col];
   my %pen = @{$cell}[1..$#$cell];
   defined $pen{$_} or delete $pen{$_} for keys %pen;
   return \%pen;
}

sub get_position
{
   my $self = shift;

   return ( $self->line, $self->col );
}

sub _push_methodlog
{
   my $self = shift;
   push @{ $self->methodlog }, [ @_ ];
}

sub get_methodlog
{
   my $self = shift;

   $self->showlog if $ENV{DEBUG_MOCKTERM_LOG};

   my @log = @{ $self->methodlog };
   undef @{ $self->methodlog };
   $self->_set_changed(0);

   return @log;
}

sub showlog
{
   my $self = shift;

   foreach my $l ( @{ $self->methodlog } ) {
      if( $l->[0] eq "setpen" ) {
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

   if( $newlines > $self->lines ) {
      $self->_clearcells( $_, 0, $newcols ) for $self->lines .. $newlines - 1;
   }

   if( $newcols > $self->cols ) {
      $self->_clearcells( $_, $self->cols, $newcols - $self->cols ) for 0 .. $self->lines - 1;
   }

   # TODO: handle shrinking

   if( $newlines != $self->lines or $newcols != $self->cols ) {
      $self->set_size( $newlines, $newcols );
   }
}

sub scrollrect
{
   my $self = shift;
   my ( $top, $left, $lines, $cols, $downward, $rightward ) = @_;

   return 1 if !$downward and !$rightward;

   if( $left == 0 and $cols == $self->cols and $rightward == 0 ) {
      $self->_push_methodlog( scrollrect => $top, $left, $lines, $cols, $downward, $rightward );

      my $bottom = $top + $lines;
      my $cells = $self->cells;

      if( $downward > 0 ) {
         splice @$cells, $top, $downward, ();
         splice @$cells, $bottom - $downward, 0, (undef) x $downward;

         $self->_clearcells( $_, 0, $self->cols ) for $bottom - $downward .. $bottom - 1;
      }
      elsif( $downward < 0 ) {
         my $upward = -$downward;

         splice @$cells, $bottom - $upward, $upward, ();
         splice @$cells, $top, 0, (undef) x $upward;

         $self->_clearcells( $_, 0, $self->cols ) for $top .. $top + $upward - 1;
      }

      $self->_set_changed(1);
      return 1;
   }

   my $right = $left + $cols;
   if( $right == $self->cols and $downward == 0 ) {
      $self->_push_methodlog( scrollrect => $top, $left, $lines, $cols, $downward, $rightward );

      foreach my $line ( $top .. $top + $lines - 1 ) {
         my $linecells = $self->cells->[$line];

         if( $rightward > 0 ) {
            splice @$linecells, $left, $rightward, ();
            splice @$linecells, $right - $rightward, 0, (undef) x $rightward;

            $self->_clearcells( $line, $self->cols - $rightward, $rightward );
         }
         else {
            my $leftward = -$rightward;

            splice @$linecells, $left, 0, (undef) x $leftward;
            splice @$linecells, $self->cols; # truncate

            $self->_clearcells( $line, $left, $leftward );
         }
      }
      $self->_set_changed(1);

      return 1;
   }

   return 0;
}

0x55AA;
