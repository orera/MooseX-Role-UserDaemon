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
  with qw(MooseX::Getopt);

  sub main {
    my $run = 1;
    my $x   = 10;

    local $SIG{'INT'} = local $SIG{'TERM'} = sub { $run = 0; };
    local $SIG{'HUP'} = 'IGNORE';

    while ($run) { sleep 1; $x-- }

    return '0 but true';
  }

  1;
}

{    # Invalid commands
  local $ENV{'HOME'} = File::Temp::tempdir;
  chdir $ENV{'HOME'};

  my @expected_output
    = ( qr/^Not running/, qr/^Process not running/, qr/^usage/, qr/^usage/ );

  foreach my $command (qw(status stop invalid_mode main)) {

    # Start with a fresh @ARGV
    @ARGV = ();

    # Populate with a command
    push @ARGV, $command;

    # Create application object
    my $app = App->new_with_options;

    # Keep data sendt to stdout here.
    my $stdout;

    # Redirect STDOUT to variable.
    open my $stdout_fh, '>', \$stdout;
    select($stdout_fh);

    # Return values
    my $mode_rc = $app->run;

    # Standard out contain the expected output
    like(
      $stdout,
      shift @expected_output,
      "standard out is correct for command: $command"
    );

    close $stdout_fh;

    # Back to regular STDOUT
    select(STDOUT);
  }
}

{    # Minimal app
  package TimeoutApp;

  use Moose;
  with qw(MooseX::Role::UserDaemon);

  sub main {
    local $SIG{'TERM'} = local $SIG{'INT'} = local $SIG{'HUP'} = 'IGNORE';
    my $x = 5;
    while ($x) { sleep 1; $x--; }
    return '0 but true';
  }

  1;
}

{
  local $ENV{'HOME'} = File::Temp::tempdir;
  chdir $ENV{'HOME'};

  @ARGV = ();

  my $app = TimeoutApp->new({timeout => 3});
  
  ok($app->run, 'TimeoutApp starts ok');
  sleep 1;
  ok(-e $app->lockfile, 'TimeoutApp has created a lockfile');
  ok(-e $app->pidfile, 'TimeoutApp has created a pidfile');
  
  ok(!$app->stop, 'TimeoutApp timeout while trying to stop, returning false');
}

{    # Minimal app
  package ForegroundApp;

  use Moose;
  with qw(MooseX::Role::UserDaemon);

  sub main { return '0 but true'; }

  1;
}

{
  local $ENV{'HOME'} = File::Temp::tempdir;
  chdir $ENV{'HOME'};

  @ARGV = ();

  my $app = ForegroundApp->new({ foreground => 1, });

  # Test return value of main, in forground mode we should return not exit
  is( $app->main, '0 but true', 'ForegroundApp returns zero but true' );

  # Here we can also test stop for failure
  # lock so that the app appears to be running
  ok( $app->_lock, '_lock OK' );
  
  # Call stop without having written a pidfile
  #ok( !$app->stop,    'stop return false' );
  ok( !$app->restart, 'restart return false' );
  ok( $app->_unlock,  '_unlock OK' );
}


done_testing;

__END__
