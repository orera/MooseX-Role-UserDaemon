#!perl -T

use Test::More tests => 1;

BEGIN {
    use_ok( 'MooseX::UserDaemon' ) || print "Bail out!\n";
}

diag( "Testing MooseX::UserDaemon $MooseX::UserDaemon::VERSION, Perl $], $^X" );
