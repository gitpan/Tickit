#!/usr/bin/perl

use Test::More tests => 15;

use_ok( 'Tickit' );
use_ok( 'Tickit::Async' );

use_ok( 'Tickit::Term' );
use_ok( 'Tickit::Pen' );
use_ok( 'Tickit::Utils' );

use_ok( 'Tickit::Window' );
use_ok( 'Tickit::RootWindow' );

use_ok( 'Tickit::Widget' );
use_ok( 'Tickit::ContainerWidget' );

use_ok( 'Tickit::Widget::Static' );
use_ok( 'Tickit::Widget::Entry' );

use_ok( 'Tickit::Widget::Box' );
use_ok( 'Tickit::Widget::HBox' );
use_ok( 'Tickit::Widget::VBox' );
use_ok( 'Tickit::Widget::Frame' );
