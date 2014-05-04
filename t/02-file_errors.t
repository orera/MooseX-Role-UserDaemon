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



  # unlink $app->lockfile
    # if -e $app->lockfile;

  # ok( !-e $app->lockfile, 'No lockfile exist before first lock' );

  # my $lock_rc = $app->_lock;
  # ok( -e $app->lockfile, 'Lockfile exist after locking' );
  # ok( $lock_rc,          '_lock returned true on successful lock' );
  # ok( $app->_unlock,     'unlock return true' );
  # ok( -e $app->lockfile, 'Lockfile remains after unlocking' );
  # ok( $app->_lock, 'Locking works when lockfile existed but was not locked' );
  # ok( $app->_unlock, 'unlock return true' );

  # unlink
    # $app->lockfile;    # Remove lockfile so not to cause truble later in test.

  # make_path( $app->lockfile );

  # # Lockfile is a directory
  # foreach my $sub (qw(_lock _unlock)) {
    # dies_ok { $app->$sub } "$sub die when lockfile is a directory";
  # }

  # rmdir $app->lockfile;
  # open my $lockfile_fh, '>', $app->lockfile;
  # print {$lockfile_fh} 'some content';
  # close $lockfile_fh;

  # # Lockfile contains data
  # foreach my $sub (qw(_lock _unlock)) {
    # dies_ok { $app->$sub } "$sub die when lockfile contain data";
  # }

  # # Empty the file
  # open $lockfile_fh, '>', $app->lockfile;
  # close $lockfile_fh;

  # chmod $ro_mode, $app->lockfile;

  # # Lockfile contains data
  # foreach my $sub (qw(_lock _unlock)) {
    # next if $UID == 0;
    # dies_ok { $app->$sub } "$sub die when lockfile is not writeable";
  # }

  # chmod $rw_mode, $app->lockfile;
  # unlink $app->lockfile;

  # # No filehandle for the lockfile exists
  # dies_ok { $app->_unlock } '_unlock die the filehandle does not exist';
}

# {
  # #
  # # Missing lockfile tests
  # #

  # local $ENV{'HOME'} = File::Temp::tempdir;
  # chdir $ENV{'HOME'};

  # my $app = App->new( { lockfile => '' } );
  # isa_ok( $app, 'App' );

  # # Missing lockfile
  # foreach my $sub (qw(_lock _unlock)) {
    # dies_ok { $app->$sub } "$sub die when no lockfile";
  # }

  # ok( !$app->_is_running, 'is_running return false when not using lockfile' );
  # ok( $app->stop,         'stop return true when not using lockfile' );
# }



# {
  # #
  # # Missing pidfile tests
  # #

  # local $ENV{'HOME'} = File::Temp::tempdir;
  # chdir $ENV{'HOME'};

  # my $app = App->new( { pidfile => '' } );
  # isa_ok( $app, 'App' );

  # # PID file not specified
  # foreach my $operation (qw(_write_pid _read_pid _delete_pid)) {
    # dies_ok { $app->$operation } "$operation die when pidfile is unspecified";
  # }
# }

# {
  # #
  # # Pidfile tests
  # #

  # local $ENV{'HOME'} = File::Temp::tempdir;
  # chdir $ENV{'HOME'};

  # my $app = App->new;
  # isa_ok( $app, 'App' );

  # ok( !-e $app->pidfile, 'No PID file' );

  # my $write_pid_rc = $app->_write_pid;
  # ok( -e $app->pidfile, 'PID file exist' );
  # ok( $write_pid_rc,    '_write_pid returned true on success' );
  # ok( $app->_write_pid, '_write_pid return true when file already exists' );

  # $app->_delete_pid;
  # ok( !-e $app->pidfile, 'PID file have been removed' );

  # # PID file is not a file
  # make_path( $app->pidfile );

  # foreach my $operation (qw(_write_pid _read_pid _delete_pid)) {
    # dies_ok { $app->$operation } "$operation die when pidfile is a directory";
  # }

  # rmdir $app->pidfile;

  # # PID file is not writeable
  # $app->_write_pid;

  # foreach my $operation (qw(_write_pid _delete_pid)) {
    # next if $UID == 0;
    # chmod $ro_mode, $app->pidfile;
    # dies_ok { $app->$operation }
    # "$operation die when pidfile is not writable";
  # }

  # if ( $UID != 0 ) {

    # # PID file is not readable
    # chmod $no_mode, $app->pidfile;
    # dies_ok { $app->_read_pid } '_read_pid die when pidfile is not readable';
  # }

  # chmod $rw_mode, $app->pidfile;
  # unlink $app->pidfile;

  # # PID file have been removed unexpectedly
  # foreach my $operation (qw(_read_pid _delete_pid)) {
    # dies_ok { $app->$operation } "$operation die when pidfile does not exist";
  # }
# }

done_testing;

__END__
