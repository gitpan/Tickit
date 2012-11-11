#!/usr/bin/perl

use strict;

use Test::More tests => 21;
use Test::Refcount;

my $widget = TestWidget->new;
my $container = TestContainer->new;

my $changed = 0;

ok( defined $container, 'defined $container' );

is_oneref( $widget, '$widget has refcount 1 initially' );
is_oneref( $container, '$container has refcount 1 initially' );

is( scalar $container->children, 0, 'scalar $container->children is 0' );
is_deeply( [ $container->children ], [], '$container->children empty' );

my @args;
$container->foreach_child( sub { push @args, [ @_ ] } );

is_deeply( \@args, [], '$container->foreach_child pushes nothing' );

$container->add( $widget, foo => "bar" );

is_refcount( $widget, 2, '$widget has refcount 2 after add' );
is_oneref( $container, '$container has refcount 1 after add' );

is( $widget->parent, $container, '$widget->parent is container' );

is_deeply( { $container->child_opts( $widget ) }, { foo => "bar" }, 'child_opts by reference' );

is_deeply( { $container->child_opts( 0 ) },       { foo => "bar" }, 'child_opts by index' );

is( $changed, 1, '$changed is 1' );

$container->set_child_opts( $widget, foo => "splot" );

is_deeply( { $container->child_opts( $widget ) }, { foo => "splot" }, 'child_opts after change' );

is( $changed, 2, '$changed is 2' );

is( scalar $container->children, 1, 'scalar $container->children is 1' );
is_deeply( [ $container->children ], [ $widget ], '$container->children contains widget' );

undef @args;
$container->foreach_child( sub {
   my ( $child, %opts ) = @_;
   push @args, [ $child, \%opts ];
} );

is_deeply( \@args,
   [ [ $widget, { foo => "splot" } ] ],
   '$container->foreach_child pushes one child' );

$container->remove( $widget );

is( scalar $container->children, 0, 'scalar $container->children is 0' );
is_deeply( [ $container->children ], [], '$container->children empty' );

is( $widget->parent, undef, '$widget->parent is undef' );

is( $changed, 3, '$changed is 3' );

package TestWidget;

use base qw( Tickit::Widget );

use constant CLEAR_BEFORE_RENDER => 0;
sub render {}

sub lines { 1 }
sub cols  { 5 }

package TestContainer;

use base qw( Tickit::ContainerWidget );

use constant CLEAR_BEFORE_RENDER => 0;
sub render {}

sub lines { 2 }
sub cols  { 10 }

sub children_changed { $changed++ }
