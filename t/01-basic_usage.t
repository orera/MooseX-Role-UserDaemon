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
  with qw(MooseX::Role::UserDaemon);

  sub main {
    my $run = 1;
    local $SIG{'INT'} = local $SIG{'TERM'} = sub { $run = 0; };
    local $SIG{'HUP'} = 'IGNORE';

    while ($run) { sleep 1; }
    return '0 but true';
  }

  1;
}

{
  local $ENV{'HOME'} = File::Temp::tempdir;
  chdir $ENV{'HOME'};

  # Check for valid methods
  my @subs = qw(
    start       stop               status
    restart     reload             run
    _lock       _unlock            _is_running
    _write_pid  _read_pid          _delete_pid
    _daemonize  _lockfile_is_valid
  );

  my $app = App->new;
  isa_ok( $app, 'App' );
  can_ok( $app, @subs );

  # Test public methods
  my @modes = qw(
    status  start   start  status restart stop
    status  restart stop   stop   run     status
    reload  stop start KILL status
  );

  my %mode_prints = (
    run   => [ qr{^Starting\.\.\.}, ],
    start => [
      qr{^Starting\.\.\.}, qr{^Running with PID:\s\d+},
      qr{^Starting\.\.\.}
    ],
    stop => [
      qr{^Stopping PID:\s\d+},
      qr{^Stopping PID:\s\d+},
      qr{Process not running, nothing to stop\.},
      qr{^Stopping PID:\s\d+},
    ],
    status => [
      qr{^Not running.},
      qr{^Running with PID:\s\d+},
      qr{^Not running.},
      qr{^Running with PID:\s\d+},
      qr{^Not running.},
    ],
    reload  => [ qr{^PID: \d+, was signaled to reload\.}, ],
    restart => [
      qr{^Stopping\sPID:\s\d+\.\.\.\nStarting\.\.\.},
      qr{Process not running, nothing to stop.\nStarting\.\.\.},
    ],
    KILL => [ qr{^Stopping PID:\s\d+}, ],
  );

  foreach my $mode (@modes) {
    sleep 1;    # Ugly but necessary, forking and locking take time.

    # variable to be used to capture data sent to STDOUT by public methods.
    my $stdout;
    my $stdout_re = shift @{ $mode_prints{$mode} };

    # Redirect STDOUT to variable.
    open my $stdout_fh, '>', \$stdout;
    select($stdout_fh);

    # Return values
    my $mode_rc = $app->$mode;
    ok( $mode_rc, "$mode() return value is true" );
    cmp_ok( $mode_rc, '==', '0', "$mode() return value is 0" );

    # Standard out
    like( $stdout, $stdout_re, "$mode() STDOUT matched $stdout_re" );

    close $stdout_fh;
  }

  # Back to regular STDOUT
  select(STDOUT);
}

done_testing;
