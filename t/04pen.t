#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use Test::Identity;
use Test::Refcount;

use Tickit::Pen;

# Immutable pens
{
   my $pen = Tickit::Pen::Immutable->new( fg => 3 );

   isa_ok( $pen, "Tickit::Pen", '$pen isa Tickit::Pen' );

   is( "$pen", "Tickit::Pen::Immutable={fg=3}", '"$pen"' );

   is_deeply( { $pen->getattrs }, { fg => 3 }, '$pen attrs' );

   ok( $pen->hasattr( 'fg' ), '$pen has fg' );
   is( $pen->getattr( 'fg' ), 3, '$pen fg' );

   ok( !$pen->hasattr( 'bg' ), '$pen has no bg' );
   is( $pen->getattr( 'bg' ), undef, '$pen bg undef' );
}

my $changed = 0;
my $changed_pen;
my $changed_id;
my $observer = bless {}, "PenObserver";

# Mutable pens
{
   my $pen = Tickit::Pen::Mutable->new;

   is( "$pen", "Tickit::Pen::Mutable={}", '"$pen" empty' );

   my $id = [];
   is_oneref( $id, 'Pen $id has refcount 1 before ->add_on_changed' );

   $pen->add_on_changed( $observer, $id );

   is_oneref( $observer, 'Pen observer does not increase refcount' );
   is_refcount( $id, 2, 'Pen $id has refcount 2 after ->add_on_changed' );

   is_deeply( { $pen->getattrs }, {}, '$pen initial attrs' );
   ok( !$pen->hasattr( 'fg' ), '$pen initially lacks fg' );
   is( $pen->getattr( 'fg' ), undef, '$pen fg initially undef' );

   is( $changed, 0, '$changed before chattr' );

   $pen->chattr( fg => 3 );

   is_deeply( { $pen->getattrs }, { fg => 3 }, '$pen attrs after chattr' );
   ok( $pen->hasattr( 'fg' ), '$pen now has fg' );
   is( $pen->getattr( 'fg' ), 3, '$pen fg after chattr' );

   is( "$pen", "Tickit::Pen::Mutable={fg=3}", '"$pen" after chattr' );

   is_deeply( { $pen->clone->getattrs }, { $pen->getattrs }, '$pen->clone attrs' );

   is( $changed, 1, '$changed after chattr' );
   identical( $changed_pen, $pen, '$changed_pen after chattr' );
   identical( $changed_id,  $id,  '$changed_id after chattr' );

   $pen->chattr( fg => "blue" );

   is_deeply( { $pen->getattrs }, { fg => 4 }, '$pen attrs fg named' );
   is( $pen->getattr( 'fg' ), 4, '$pen fg named' );

   is( $changed, 2, '$changed after chattr named' );

   $pen->chattr( fg => "hi-blue" );

   is_deeply( { $pen->getattrs }, { fg => 12 }, '$pen attrs fg named high-intensity' );
   is( $pen->getattr( 'fg' ), 12, '$pen fg named high-intensity' );

   is( $changed, 3, '$changed after chattr named high-intensity' );

   $pen->delattr( 'fg' );

   is_deeply( { $pen->getattrs }, {}, '$pen attrs after delattr' );
   is( $pen->getattr( 'fg' ), undef, '$pen fg after delattr' );

   is( $changed, 4, '$changed after delattr' );

   my %attrs = ( b => 1, na => 5 );

   $pen->chattrs( \%attrs );

   is( $changed, 5, '$changed after chattrs' );

   is_deeply( { $pen->getattrs }, { b => 1 }, '$pen attrs after chattrs' );
   is_deeply( \%attrs, { na => 5 }, '%attrs after chattrs' );

   $pen->remove_on_changed( $observer );

   undef $changed_id;
   is_oneref( $id, 'Pen $id has refcount 1 after ->remove_on_changed' );

   $pen->chattr( fg => "red" );

   is( $changed, 5, '$changed unchanged after remove+chattr' );
}

my $bluepen  = Tickit::Pen::Immutable->new( fg => 4 );
my $otherpen = Tickit::Pen::Immutable->new( fg => 1, bg => 2 );

{
   my $copy = $bluepen->clone;
   $copy->add_on_changed( $observer );
   $changed = 0;

   is_deeply( { $copy->copy_from( $otherpen )->getattrs },
              { fg => 1, bg => 2 },
              'pen ->copy_from overwrites attributes' );

   is( $changed, 1, '$changed 1 after copy ->copy_from' );
   identical( $changed_pen, $copy, '$changed_pen after copy ->copy_from' );
}

{
   my $copy = $bluepen->clone;
   $copy->add_on_changed( $observer );
   $changed = 0;

   is_deeply( { $copy->default_from( $otherpen )->getattrs },
              { fg => 4, bg => 2 },
              'pen ->default_from does not overwrite attributes' );

   is( $changed, 1, '$changed 1 after copy ->default_from' );
   identical( $changed_pen, $copy, '$changed_pen after copy ->default_from' );
}

my $norv_pen = Tickit::Pen->new( rv => 0 );
$norv_pen->default_from( Tickit::Pen->new( rv => 1 ) );
is_deeply( { $norv_pen->getattrs },
           { rv => '' },
           'pen ->default_from does not overwrite defined-but-false attributes' );

done_testing;

package PenObserver;

sub on_pen_changed
{
   my $self = shift;
   ( $changed_pen, $changed_id ) = @_;
   $changed++;
}
