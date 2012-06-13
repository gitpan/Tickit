#!/usr/bin/perl

use strict;

use Test::More tests => 37;
use Test::Identity;
use Test::Refcount;

use Tickit::Pen;

my $pen = Tickit::Pen->new;

my $changed = 0;
my $changed_pen;
my $changed_id;

isa_ok( $pen, "Tickit::Pen", '$pen isa Tickit::Pen' );

my $id = [];
is_oneref( $id, 'Pen $id has refcount 1 before ->add_on_changed' );

my $observer = bless {}, "PenObserver";
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

$pen = Tickit::Pen->new( fg => 1, bg => 2 );

is_deeply( { $pen->getattrs }, { fg => 1, bg => 2 }, '$pen initial attrs' );

is( $pen->getattr( 'fg' ), 1, '$pen fg initially 1' );

my $bluepen = Tickit::Pen->new( fg => 4 );

{
   my $copy = $bluepen->clone;
   $copy->add_on_changed( $observer );
   $changed = 0;

   is_deeply( { $copy->copy_from( $pen )->getattrs },
              { fg => 1, bg => 2 },
              'pen ->copy_from overwrites attributes' );

   is( $changed, 1, '$changed 1 after copy ->copy_from' );
   identical( $changed_pen, $copy, '$changed_pen after copy ->copy_from' );
}

{
   my $copy = $bluepen->clone;
   $copy->add_on_changed( $observer );
   $changed = 0;

   is_deeply( { $copy->default_from( $pen )->getattrs },
              { fg => 4, bg => 2 },
              'pen ->default_from does not overwrite attributes' );

   is( $changed, 1, '$changed 1 after copy ->default_from' );
   identical( $changed_pen, $copy, '$changed_pen after copy ->default_from' );
}

package PenObserver;

sub on_pen_changed
{
   my $self = shift;
   ( $changed_pen, $changed_id ) = @_;
   $changed++;
}
