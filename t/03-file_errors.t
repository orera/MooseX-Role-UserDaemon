#!perl

use 5.014;
use strict;
use warnings;
use autodie;
use Data::Dumper qw(Dumper);
use English qw(-no_match_vars);
use File::Path qw(make_path);
use File::Temp qw();
use Readonly;
use Test::Most;
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

Readonly my $rw_mode => 0744;
Readonly my $ro_mode => 0444;
Readonly my $no_mode => 0000;

{
  #
  # Lockfile tests
  #

  my $app = App->new;
  isa_ok( $app, 'App' );

  local $ENV{'HOME'} = File::Temp::tempdir;
  chdir $ENV{'HOME'};

  unlink $app->lockfile
    if -e $app->lockfile;

  ok( !-e $app->lockfile, 'No lockfile exist before first lock' );
  $app->_lock;
  ok( -e $app->lockfile, 'Lockfile exist after locking' );
  $app->_unlock;
  ok( !-e $app->lockfile, 'Lockfile have been removed after unlocking' );

  my $original_lockfile = $app->lockfile;
  $app->lockfile('');

  # Missing lockfile
  foreach my $sub (qw(_lock _unlock)) {
    dies_ok { $app->$sub } "$sub die when no lockfile";
  }

  $app->lockfile($original_lockfile);
  make_path( $app->lockfile );

  # Lockfile is a directory
  foreach my $sub (qw(_lock _unlock)) {
    dies_ok { $app->$sub } "$sub die when lockfile is a directory";
  }

  rmdir $app->lockfile;
  open my $lockfile_fh, '>', $app->lockfile;
  print {$lockfile_fh} 'some content';
  close $lockfile_fh;

  # Lockfile contains data
  foreach my $sub (qw(_lock _unlock)) {
    dies_ok { $app->$sub } "$sub die when lockfile contain data";
  }

  # Empty the file
  open $lockfile_fh, '>', $app->lockfile;
  close $lockfile_fh;

  chmod $ro_mode, $app->lockfile;

  # Lockfile contains data
  foreach my $sub (qw(_lock _unlock)) {
    next if $UID == 0;
    dies_ok { $app->$sub } "$sub die when lockfile is not writeable";
  }

  chmod $rw_mode, $app->lockfile;
  unlink $app->lockfile;

  # No filehandle for the lockfile exists
  dies_ok { $app->_unlock } '_unlock die the filehandle does not exist';
}

{
  #
  # PID file tests
  #

  my $app = App->new;
  isa_ok( $app, 'App' );

  local $ENV{'HOME'} = File::Temp::tempdir;
  chdir $ENV{'HOME'};

  ok( !-e $app->pidfile, 'No PID file' );
  $app->_write_pid;
  ok( -e $app->pidfile, 'PID file exist' );
  $app->_delete_pid;
  ok( !-e $app->pidfile, 'PID file have been removed' );

  my $original_pidfile = $app->pidfile;
  $app->pidfile('');

  # PID file not specified
  foreach my $operation (qw(_write_pid _read_pid _delete_pid)) {
    dies_ok { $app->$operation } "$operation die when pidfile is unspecified";
  }

  $app->pidfile($original_pidfile);

  # PID file is not a file
  make_path( $app->pidfile );

  foreach my $operation (qw(_write_pid _read_pid _delete_pid)) {
    dies_ok { $app->$operation } "$operation die when pidfile is a directory";
  }

  rmdir $app->pidfile;

  # PID file is not writeable
  $app->_write_pid;

  foreach my $operation (qw(_write_pid _delete_pid)) {
    next if $UID == 0;
    chmod $ro_mode, $app->pidfile;
    dies_ok { $app->$operation }
    "$operation die when pidfile is not writable";
  }

  if ( $UID != 0 ) {

    # PID file is not readable
    chmod $no_mode, $app->pidfile;
    dies_ok { $app->_read_pid } '_read_pid die when pidfile is not readable';
  }

  chmod $rw_mode, $app->pidfile;
  unlink $app->pidfile;

  # PID file have been removed unexpectedly
  foreach my $operation (qw(_read_pid _delete_pid)) {
    dies_ok { $app->$operation } "$operation die when pidfile does not exist";
  }
}

done_testing;

__END__
