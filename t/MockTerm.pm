package t::MockTerm;

use strict;
use warnings;

use base qw( IO::Async::Stream );

use Data::Dump qw( pp );

# Some handy testing functions
use Exporter 'import';
our @EXPORT = qw(
   PAD
   BLANK
   BLANKS
   DEFAULTPEN

   CLEAR
   GOTO
   ERASECH
   INSERTCH
   DELETECH
   PRINT
   SETPEN
   SETBG
);

use Tickit::Pen;

my $LINES = 25;
my $COLS  = 80;

sub PAD { sprintf "% -*s", $COLS, shift }
sub BLANK { PAD("") }
sub BLANKS { (BLANK) x shift }

use constant DEFAULTPEN => map { $_ => undef } @Tickit::Pen::ALL_ATTRS;

sub CLEAR    { [ clear => ] }
sub GOTO     { [ goto => $_[0], $_[1] ] }
sub ERASECH  { [ erasech => $_[0], $_[1] || 0 ] }
sub INSERTCH { [ insertch => $_[0] ] }
sub DELETECH { [ deletech => $_[0] ] }
sub PRINT    { [ print => $_[0] ] }
sub SETPEN   { [ chpen => { DEFAULTPEN, @_ } ] }
sub SETBG    { [ chpen => { bg => $_[0] } ] }

my $ON_RESIZE;
my $ON_KEY;

sub new
{
   my $class = shift;
   my $self = $class->SUPER::new( @_ );

   $self->clear;

   # Clear the method log
   $self->methodlog;

   return $self;
}

sub configure
{
   my $self = shift;
   my %args = @_;

   $ON_RESIZE = delete $args{on_resize} if exists $args{on_resize};
   $ON_KEY    = delete $args{on_key}    if exists $args{on_key};

   $self->SUPER::configure( %args );
}

sub is_changed
{
   my $self = shift;
   return $self->{changed};
}

sub get_display
{
   my $self = shift;

   return map { $self->{lines}[$_] } 0 .. $#{ $self->{lines} };
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
         printf "# %s(%s)\n", uc $l->[0], join( ", ", map pp($_), @{$l}[1..$#$l] );
      }
   }
}

sub resize
{
   my $self = shift;
   my ( $newlines, $newcols ) = @_;

   # Extend the buffer
   substr( $self->{lines}[$_], $COLS, 0 ) = " " x ( $newcols - $newcols ) for 0 .. $LINES-1;
   $self->{lines}[$_] = " " x $newcols for $LINES .. $newlines-1;

   $LINES = $newlines;
   $COLS = $newcols;

   $ON_RESIZE->( $self );
}

sub presskey
{
   my $self = shift;
   my ( $type, $str ) = @_;

   # TODO: See if we'll ever need to fake a Term::TermKey::Key event object
   $ON_KEY->( $self, $type, $str, undef );
}

sub lines { $LINES }
sub cols  { $COLS }

sub clear
{
   my $self = shift;

   $self->_push_methodlog( clear => @_ );

   $self->{lines}[$_] = " " x $self->cols for 0 .. $self->lines-1;

   $self->{changed}++;
}

sub erasech
{
   my $self = shift;
   my ( $count, $moveend ) = @_;

   $self->_push_methodlog( erasech => $count, $moveend || 0 );

   substr( $self->{lines}[$self->{line}], $self->{col}, $count ) = " " x $count;
   $self->{col} += $count if $moveend;

   $self->{changed}++;
}

sub insertch
{
   my $self = shift;
   my ( $count ) = @_;

   $self->_push_methodlog( insertch => $count );

   substr( $self->{lines}[$self->{line}], $self->{col} + $count ) =
      substr( $self->{lines}[$self->{line}], $self->{col}, $self->cols - $self->{col} - $count );

   substr( $self->{lines}[$self->{line}], $self->{col}, $count ) = " " x $count;

   $self->{changed}++;
}

sub deletech
{
   my $self = shift;
   my ( $count ) = @_;

   $self->_push_methodlog( deletech => $count );

   substr( $self->{lines}[$self->{line}], $self->{col}, $self->cols - $self->{col} - $count ) =
      substr( $self->{lines}[$self->{line}], $self->{col} + $count );

   substr( $self->{lines}[$self->{line}], $self->cols - $count, $count ) = " " x $count;

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

   substr( $self->{lines}[$self->{line}], $self->{col}, length $text ) = $text;

   $self->{col} += length $text;
   $self->{changed}++;
}

sub scroll
{
   my $self = shift;
   my ( $top, $bottom, $downward ) = @_;

   $self->_push_methodlog( scroll => @_ );

   $self->{changed}++;
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

0x55AA;
