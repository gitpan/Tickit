#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use Test::Refcount;

my $widget = TestWidget->new;
my $container = TestContainer->new;

my $changed = 0;

ok( defined $container, 'defined $container' );

is_oneref( $widget, '$widget has refcount 1 initially' );
is_oneref( $container, '$container has refcount 1 initially' );

is( scalar $container->children, 0, 'scalar $container->children is 0' );
is_deeply( [ $container->children ], [], '$container->children empty' );

$container->add( $widget, foo => "bar" );

is_refcount( $widget, 2, '$widget has refcount 2 after add' );
is_oneref( $container, '$container has refcount 1 after add' );

is( $widget->parent, $container, '$widget->parent is container' );

is_deeply( { $container->child_opts( $widget ) }, { foo => "bar" }, 'child_opts in list context' );

is_deeply( scalar $container->child_opts( $widget ), { foo => "bar" }, 'child_opts in scalar context' );

is( $changed, 1, '$changed is 1' );

$container->set_child_opts( $widget, foo => "splot" );

is_deeply( { $container->child_opts( $widget ) }, { foo => "splot" }, 'child_opts after change' );

is( $changed, 2, '$changed is 2' );

is( scalar $container->children, 1, 'scalar $container->children is 1' );
is_deeply( [ $container->children ], [ $widget ], '$container->children contains widget' );

$container->remove( $widget );

is( scalar $container->children, 0, 'scalar $container->children is 0' );
is_deeply( [ $container->children ], [], '$container->children empty' );

is( $widget->parent, undef, '$widget->parent is undef' );

is( $changed, 3, '$changed is 3' );

done_testing;

package TestWidget;

use base qw( Tickit::Widget );

use constant CLEAR_BEFORE_RENDER => 0;
sub render {}

sub lines { 1 }
sub cols  { 5 }

package TestContainer;

use base qw( Tickit::ContainerWidget );

use constant CLEAR_BEFORE_RENDER => 0;

sub new
{
   my $class = shift;
   my $self = $class->SUPER::new( @_ );
   $self->{children} = [];
   return $self;
}

sub render {}

sub lines { 2 }
sub cols  { 10 }

sub children
{
   my $self = shift;
   return @{ $self->{children} }
}

sub add
{
   my $self = shift;
   my ( $child ) = @_;
   push @{ $self->{children} }, $child;
   $self->SUPER::add( @_ );
}

sub remove
{
   my $self = shift;
   my ( $child ) = @_;
   @{ $self->{children} } = grep { $_ != $child } @{ $self->{children} };
   $self->SUPER::remove( @_ );
}

sub children_changed { $changed++ }
