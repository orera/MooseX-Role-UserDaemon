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
  with qw(MooseX::Role::UserDaemon);

  sub main {
    my $run = 1;
    my $x   = 10;

    local $SIG{'INT'} = sub { $run = 0; };
    while ($run) { sleep 1; $x-- }

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

  local $ENV{'HOME'} = File::Temp::tempdir;
  chdir $ENV{'HOME'};

  my $app = App->new;
  isa_ok( $app, 'App' );

  # Lockfile test
  ok( !-e $app->lockfile, 'lockfile does not exists' );
  ok( !$app->_is_running, '_is_running() return false' );
  ok( $app->_lock,        '_lock() return success' );
  ok( -e $app->lockfile,  'lockfile exists' );
  ok( $app->_is_running,  '_is_running() return success' );
  ok( $app->_unlock,      '_unlock() return success' );
  ok( -e $app->lockfile, 'Lockfile remains after unlocking' );
  ok( $app->_lock, 'Locking works when lockfile existed but was not locked' );
  ok( $app->_unlock, 'unlock return true' );

  # Remove lockfile to reset the enviorment before continuing
  unlink $app->lockfile if -e $app->lockfile;
  
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

  # Set permissions to read only
  chmod $ro_mode, $app->lockfile;

  # Lockfile is not writable by the current process
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
  # Lockfile not used tests
  #

  local $ENV{'HOME'} = File::Temp::tempdir;
  chdir $ENV{'HOME'};

  my $app = App->new( { lockfile => '' } );
  isa_ok( $app, 'App' );

  # Missing lockfile
  foreach my $sub (qw(_lock _unlock)) {
    dies_ok { $app->$sub } "$sub die when no lockfile";
  }

  ok( $app->run,          'run return true when not using lockfile' );
  sleep 1;
  ok( !$app->_is_running, 'is_running return false when not using lockfile' );
  ok( $app->stop,         'stop return true when not using lockfile' );
}

{
  #
  # Pidfile tests
  #

  local $ENV{'HOME'} = File::Temp::tempdir;
  chdir $ENV{'HOME'};

  my $app = App->new;
  isa_ok( $app, 'App' );

  # Pidfile test
  ok( !-e $app->pidfile, 'pidfile does not exists' );
  ok( $app->_write_pid,  '_write_pid() return success' );
  ok( $app->_write_pid, '_write_pid return true when file already exists' );
  ok( -e $app->pidfile,  'pidfile exists' );
  cmp_ok( $app->_read_pid, '==', $PID, '_read_pid() match current PID' );
  ok( $app->_delete_pid, '_delete_pid() return success' );
  ok( !-e $app->pidfile, 'pidfile does not exist' );

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

{
  #
  # Missing pidfile tests
  #

  local $ENV{'HOME'} = File::Temp::tempdir;
  chdir $ENV{'HOME'};

  my $app = App->new( { pidfile => '' } );
  isa_ok( $app, 'App' );

  # PID file not specified
  foreach my $operation (qw(_write_pid _read_pid _delete_pid)) {
    dies_ok { $app->$operation } "$operation die when pidfile is unspecified";
  }
  
  ok( $app->run,          'run return true when not using pidfile' );
  sleep 1;
  ok( !$app->_is_running, 'is_running return false when not using lockfile' );
  ok( !$app->reload,      'reload return false, when there is no pidfile' );
  ok( $app->stop,         'stop return true when not using pidfile' );
}


done_testing;

__END__
