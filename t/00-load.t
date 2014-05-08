#!perl -T

use Test::More;

BEGIN {
  use_ok('MooseX::Role::UserDaemon') || print "Bail out!\n";
}

diag(
  "Testing MooseX::Role::UserDaemon $MooseX::Role::UserDaemon::VERSION, Perl $], $^X"
);

done_testing;
