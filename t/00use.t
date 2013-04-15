#!/usr/bin/perl

use strict;
use warnings;

use Test::More;

use_ok( 'Tickit' );

use_ok( 'Tickit::Term' );
use_ok( 'Tickit::Pen' );
use_ok( 'Tickit::Rect' );
use_ok( 'Tickit::RectSet' );
use_ok( 'Tickit::Utils' );
use_ok( 'Tickit::StringPos' );

use_ok( 'Tickit::Window' );

use_ok( 'Tickit::Widget' );
use_ok( 'Tickit::ContainerWidget' );

use_ok( 'Tickit::Widget::Static' );

use_ok( 'Tickit::Widget::Box' );
use_ok( 'Tickit::Widget::HBox' );
use_ok( 'Tickit::Widget::VBox' );

done_testing;
