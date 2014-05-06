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
    local $SIG{'INT'} = local $SIG{'TERM'} = sub { $run = 0; };
    local $SIG{'HUP'} = 'IGNORE';

    while ($run) { sleep 1; }
    return '0 but true';
  }

  1;
}

{    # no pidfile used
  local $ENV{'HOME'} = File::Temp::tempdir;
  chdir $ENV{'HOME'};

  my $app = App->new;

  push @ARGV, 'invalid_command';
  ok( !$app->run, 'run return false when command is invalid' );
  @ARGV = ();
}

# {    # pidfile removed
  # local $ENV{'HOME'} = File::Temp::tempdir;
  # chdir $ENV{'HOME'};

  # my $app = App->new;

  # # Set the lockfile so that is_running returns true
  # $app->_lock;

  # ok( !$app->stop,   'stop return false when there are no pidfile' );
  # ok( !$app->reload, 'reload return false when there are no pidfile' );

  # # pidfile corrupt
  # open my $pid_fh, '>', $app->pidfile;
  # print {$pid_fh} '1234567890';
  # close $pid_fh;

  # ok( !$app->stop,   'stop return false when pid is invalid' );
  # ok( !$app->reload, 'reload return false, when is invalid' );

  # $app->_unlock;
  # ok( !$app->reload, 'reload return false when there is no lockfile' );
# }

# {    # Invalid commands
  # local $ENV{'HOME'} = File::Temp::tempdir;
  # chdir $ENV{'HOME'};

  # my @expected_output
    # = ( qr/^Not running/, qr/^Process not running/, qr/^usage/, qr/^usage/ );

  # foreach my $command (qw(status stop invalid_mode main)) {

    # # Start with a fresh @ARGV
    # @ARGV = ();

    # # Populate with a command
    # push @ARGV, $command;

    # # Create application object
    # my $app = App->new_with_options;

    # # Keep data sendt to stdout here.
    # my $stdout;

    # # Redirect STDOUT to variable.
    # open my $stdout_fh, '>', \$stdout;
    # select($stdout_fh);

    # # Return values
    # my $mode_rc = $app->run;

    # # Standard out contain the expected output
    # like(
      # $stdout,
      # shift @expected_output,
      # "standard out is correct for command: $command"
    # );

    # close $stdout_fh;

    # # Back to regular STDOUT
    # select(STDOUT);
  # }
# }

# {    # Minimal app
  # package TimeoutApp;

  # use Moose;
  # with 'MooseX::Role::UserDaemon';

  # my $x = 5;
  # sub main {
    # local $SIG{'TERM'} = 'IGNORE';
    # while ($x) {
      # sleep 1;
      # say $x;
      # $x--;
    # }
    # return '0 but true';
  # }

  # 1;
# }

# {
  # local $ENV{'HOME'} = File::Temp::tempdir;
  # chdir $ENV{'HOME'};

  # @ARGV = ();

  # my $app = TimeoutApp->new({timeout => 3});
  
  # ok($app->run, 'TimeoutApp starts ok');
  # sleep 1;
  # ok(-e $app->lockfile, 'TimeoutApp has created a lockfile');
  # ok(-e $app->pidfile, 'TimeoutApp has created a pidfile');
  
  # ok(!$app->stop, 'TimeoutApp timeout while trying to stop, returning false');
# }

# {    # Minimal app
  # package ForegroundApp;

  # use Moose;
  # with 'MooseX::Role::UserDaemon';

  # sub main { '0 but true' }

  # 1;
# }

# {
  # local $ENV{'HOME'} = File::Temp::tempdir;
  # chdir $ENV{'HOME'};

  # @ARGV = ();

  # my $app = ForegroundApp->new({ foreground => 1, });

  # is($app->main, '0 but true', 'ForegroundApp returns zero but true');
# }


done_testing;

__END__
