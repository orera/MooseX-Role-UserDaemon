#!perl

use 5.014;
use strict;
use warnings;
use autodie;
use Data::Dumper qw(Dumper);
use English qw(-no_match_vars);
use File::Temp qw();
use Test::More;
use Test::Output;

BEGIN { use_ok('MooseX::Role::UserDaemon'); }

{    # Minimal app

  package App;

  use Moose;
  with 'MooseX::Role::UserDaemon';

  my $run = 1;
  local $SIG{'INT'} = sub { $run = 0; };

  sub main {
    while ($run) {
      sleep 1;
    }
    exit;
  }
}

{
  my $app = App->new;
  isa_ok( $app, 'App' );

  # Check for valid methods
  my @subs = qw(
    start       stop      status
    restart     reload    run
    _lock       _unlock   _is_running
    _write_pid  _read_pid _delete_pid
    _daemonize
  );
  can_ok( $app, @subs );

  local $ENV{'HOME'} = File::Temp::tempdir;

  # Test _private methods

  # Lockfile test
  ok( !-e $app->lockfile, 'lockfile does not exists' );
  ok( !$app->_is_running, '_is_running() return false' );
  ok( $app->_lock,        '_lock() return success' );
  ok( -e $app->lockfile,  'lockfile exists' );
  ok( $app->_is_running,  '_is_running() return success' );
  ok( $app->_unlock,      '_unlock() return success' );
  ok( !-e $app->lockfile, 'lockfile does not exists' );

  # Pidfile test
  ok( !-e $app->pidfile, 'pidfile does not exists' );
  ok( $app->_write_pid,  '_write_pid() return success' );
  ok( -e $app->pidfile,  'pidfile exists' );
  cmp_ok( $app->_read_pid, '==', $PID, '_read_pid() match current PID' );
  ok( $app->_delete_pid, '_delete_pid() return success' );
  ok( !-e $app->pidfile, 'pidfile does not exist' );

  # Test public methods
  my @modes = qw(status start status restart stop status restart stop stop);

  my %mode_prints = (
    start => [ qr{^Starting\.\.\.}, ],
    stop  => [
      qr{^Stopping PID:\s\d+},
      qr{^Stopping PID:\s\d+},
      qr{Process not running, nothing to stop\.},
    ],
    status =>
      [ qr{^Not running.}, qr{^Running with PID:\s\d+}, qr{^Not running.}, ],
    restart => [
      qr{^Stopping\sPID:\s\d+\nStarting\.\.\.},
      qr{Process not running, nothing to stop.\nStarting\.\.\.},
    ],
  );

  # variable to be used to capture data sent to STDOUT by public methods.
  my $stdout;

  foreach my $mode (@modes) {
    sleep 1;    # Ugly but necessary, forking and locking take time.

    # Redirect STDOUT to variable.
    open my $stdout_fh, '>', \$stdout;
    select($stdout_fh);

    my $regexp = shift @{ $mode_prints{$mode} };

    # Return values
    my $mode_rc = $app->$mode;
    cmp_ok( $mode_rc, '==', '0', "$mode() return value is 0" );
    ok( $mode_rc, "$mode() return value is also true" );

    # Standard out
    like( $stdout, $regexp, "$mode() STDOUT matched $regexp" );

    close $stdout_fh;
  }

  # Back to regular STDOUT
  select(STDOUT);
}

done_testing;
