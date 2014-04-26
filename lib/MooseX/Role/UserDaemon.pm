package MooseX::Role::UserDaemon;

# ABSTRACT: Simplify writing of user space daemons

use 5.014;
use Moose::Role;
use autodie;
use English qw(-no_match_vars);
use Fcntl qw(:flock);
use File::Basename ();
use File::HomeDir  ();
use File::Spec     ();
use File::Path     ();
use POSIX          ();
use namespace::autoclean;

BEGIN {
  # VERSION
}

{
  requires 'main';

  has '_name' => (
    is      => 'ro',
    isa     => 'Str',
    lazy    => 1,
    default => sub {    # The program name should not be to exotic.

      # Aviod modifying $PORGRAM_NAME directly
      my $program_name = $PROGRAM_NAME;

      # First replace unexpected chars with _ to pass unit tests (t/..);
      $program_name =~ s/[^\w.,_ -]+/_/g;

      # Then capture to pass taintmode.
      ($program_name) = $program_name =~ /\A([\w.,_ -]+)\z/
        or die 'program name contain invalid characters.';

      return File::Basename::fileparse $program_name;
    },
  );

  has '_valid_commands' => (
    is       => 'ro',
    isa      => 'RegexpRef',
    lazy     => 1,
    default  => sub {qr/\A(status|start|stop|reload|restart)\z/},
    init_arg => undef,
  );

  has 'timeout' => (
    is      => 'ro',
    isa     => 'Int',
    lazy    => 1,
    default => 5,
    documentation =>
      '--timeout=n, default = 5, time in seconds to wait for the daemon to exit.',
  );

  has 'foreground' => (
    is      => 'ro',
    isa     => 'Int',
    lazy    => 1,
    default => 0,
    documentation =>
      '--foreground=1 will run the app in the foreground instead of daemonizing it.',
  );

  has 'basedir' => (
    is            => 'ro',
    isa           => 'Str',
    lazy_build    => 1,
    documentation => '--basedir="/custom/path", Use custom base directory.',
  );

  has 'lockfile' => (
    is            => 'ro',
    isa           => 'Str',
    lazy_build    => 1,
    documentation => '--basedir=/path/to/file, Use custom lockfile.',
  );

  has 'pidfile' => (
    is            => 'ro',
    isa           => 'Str',
    lazy_build    => 1,
    documentation => '--pidfile=/path/to/file, Use custom pidfile.',
  );

  has '_lock_fh' => (
    is       => 'rw',
    isa      => 'Maybe[FileHandle]',
    init_arg => undef,
    clearer  => 'clear_lock_fh',
  );

  sub _build_basedir {
    my ($self) = @_;
    return File::Spec->catdir( File::HomeDir->my_home,
      lc( q{.} . $self->_name ) );
  }

  sub _build_lockfile {
    my ($self) = @_;
    return File::Spec->catdir( $self->basedir, 'lock' );
  }

  sub _build_pidfile {
    my ($self) = @_;
    return File::Spec->catdir( $self->basedir, 'pid' );
  }

  # Write PID file if supplied
  around 'main' => sub {
    my ( $orig, $self ) = @_;

    # Abort if no pidfile has been specified
    return if !$self->pidfile;

    # Failed to write pid
    return 0 if !$self->_write_pid;

    my $rc = $self->$orig;

    # Failed to remove pidfile after execution
    return 0 if !$self->_delete_pid;

    return $rc;
  };

  # Write lock file if supplied
  around 'main' => sub {
    my ( $orig, $self ) = @_;

    # Abort if no lockfile has been specified
    return if !$self->lockfile;

    # Failed to establish a lock
    return 0 if !$self->_lock;

    # run main
    my $rc = $self->$orig;

    # Failed to remove lock
    return 0 if !$self->_unlock;

    return $rc;
  };

  sub _init_fh {
    my ( $self, $mode, $filename ) = @_;

    # Create leading directories if missing.
    if ( !-e $filename ) {
      File::Path::make_path($filename);
      rmdir $filename;
    }

    # Open filehandle
    open my ($filehandle), $mode, $filename;
    return $filehandle;
  }

  sub _lockfile_is_valid {
    my ($self) = @_;

    if ( !-f $self->lockfile ) {
      warn 'lockfile is not a regular file.';
      return;
    }

    if ( !-z $self->lockfile ) {
      warn 'lockfile is not a empty file.';
      return;
    }

    if ( !-w $self->lockfile ) {
      warn 'lockfile is not writeable by the current process.';
      return;
    }

    return 1;
  }

  sub _lock {
    my ($self) = @_;

    die 'Must specify a path to be used as a lockfile.'
      if !$self->lockfile;

    die 'A lockfile already exists but it is not an empty writable file.'
      if -e $self->lockfile && !$self->_lockfile_is_valid;

    # Finally open the file and place a lock on it
    my $lock_fh = $self->_init_fh( '>>', $self->lockfile );
    flock $lock_fh, LOCK_EX | LOCK_NB or return;

    # Maintain the lock troughout the runtime of the app. Store the FH.
    $self->_lock_fh($lock_fh);

    return 1;
  }

  sub _unlock {
    my ($self) = @_;

    die 'Trying to unlock a non-existing lockfile filehandle.'
      if !$self->_lock_fh;

    my $close_rc = close $self->_lock_fh;

    if ( !$close_rc ) {
      warn "Failed to close lockfile filehandle: $ERRNO";
    }
    else {
      $self->clear_lock_fh;
    }

    return $close_rc;
  }

  sub _pidfile_is_valid {
    my ($self) = @_;

    if ( !-f $self->pidfile ) {
      warn 'pidfile is not a file';
      return;
    }

    if ( !-r $self->pidfile ) {
      warn 'pidfile is not readable';
      return;
    }

    if ( !-w $self->pidfile ) {
      warn 'pidfile is not writeable';
      return;
    }

    return 1;
  }

  sub _write_pid {
    my ($self) = @_;

    die 'Must specify a path to be used as a pidfile.'
      if !$self->pidfile;

    die 'A pidfile already exist, but is not a regular writable file.'
      if -e $self->pidfile && !$self->_pidfile_is_valid;

    # write the actual file
    {
      ## no critic (ProhibitLocalVars)
      local $OUTPUT_AUTOFLUSH = 1;

      ## use critic
      my $pid_fh = $self->_init_fh( '>', $self->pidfile );
      print {$pid_fh} $PID;
      close $pid_fh;
    }

    return 1;
  }

  sub _read_pid {
    my ($self) = @_;

    die 'Must specify a path to be used as a pidfile.'
      if !$self->pidfile;

    die 'A pidfile already exist, but is not a regular file.'
      if -e $self->pidfile && !$self->_pidfile_is_valid;

    open my $pid_fh, '<', $self->pidfile;
    my $daemon_pid = do { local $INPUT_RECORD_SEPARATOR = undef; <$pid_fh> };
    ($daemon_pid) = $daemon_pid =~ /\A(\d+)\z/
      or die 'pidfile contained something other than digits.';
    close $pid_fh;

    return $daemon_pid;
  }

  sub _delete_pid {
    my ($self) = @_;

    die 'Must specify a path to be used as a pidfile.'
      if !$self->pidfile;

    die 'pidfile does not exist'
      if !-e $self->pidfile;

    die 'pidfile is not a regular file'
      if !-f $self->pidfile;

    die 'pidfile is not writable'
      if !-w $self->pidfile;

    return unlink $self->pidfile;
  }

  # Check if exists a locked version of the lockfile already
  sub _is_running {
    my ($self) = @_;

    # return false if lockfile is not in use
    return if !$self->lockfile || !-e $self->lockfile;

    if ( $self->_lock ) {    # Not running
      $self->_unlock;
      return;
    }

    return 1;                # running
  }

  sub _daemonize {
    my ($self) = @_;

    # Fork once
    defined( my $pid1 = fork ) or die "Can’t fork: $ERRNO";
    return '0 but true' if $pid1;    # Original parent exit

    # Become session leader
    POSIX::setsid
      or die "Unable to to become session leader: $ERRNO";

    # Fork twice
    defined( my $pid2 = fork ) or die "Can’t fork: $ERRNO";
    exit if $pid2;                   # Intermediate parent exit

    # Redirect STD* to /dev/null
    open STDIN,  '<',  File::Spec->devnull;
    open STDOUT, '>>', File::Spec->devnull;
    open STDERR, '>>', File::Spec->devnull;

    # Child returns false.
    return;
  }

  sub status {
    my ($self) = @_;

    say $self->_is_running
      ? 'Running with PID: ' . $self->_read_pid
      : 'Not running.';

    return '0 but true';
  }

  sub start {
    my ($self) = @_;

    return $self->status if $self->_is_running;

    say 'Starting...';

    # Return with output of main if foreground mode is enabled
    return $self->main
      if $self->foreground;

    # Else Daemonize
    my $daemonize_rc = $self->_daemonize;

    # Original parent returns
    return $daemonize_rc if defined $daemonize_rc;

    # Child will run main and exit when running as daemon
    exit $self->main;
  }

  sub stop {
    my ($self) = @_;

    if ( !$self->_is_running ) {
      say 'Process not running, nothing to stop.';
      return '0 but true';
    }

    if ( !$self->pidfile || !-e $self->pidfile ) {
      say 'No pidfile, not able to identify process.';
      return 0;    # Return 0 to please both unit tests and exit
    }

    # Get process id
    my $pid = $self->_read_pid;

    eval { kill 'TERM', $pid };
    if ($EVAL_ERROR) {
      warn 'Not able to issue kill signal.';
      return 0;
    }
    else {
      say "Stopping PID: $pid...";
    }

    eval {
      local $SIG{'ALRM'} = sub { die "Timed out waiting for exit\n"; };

      my $lockfile_fh = $self->_init_fh( '+<', $self->lockfile );
      if ( !flock( $lockfile_fh, LOCK_EX | LOCK_NB ) ) {

        #say "Lockfile still blocked, waiting\n";
        alarm $self->timeout;
        flock( $lockfile_fh, LOCK_EX );
        alarm 0;
      }
      close $lockfile_fh;
    };
    return $EVAL_ERROR
      ? 0
      : '0 but true';
  }

  sub restart {
    my ($self) = @_;

    # Start a new if stop is successful
    return $self->start if $self->stop;

    # Stop failed:
    say 'Failed to stop process, restart aborted.';

    # Return 0 to please both unit tests and exit
    return 0;
  }

  sub reload {
    my ($self) = @_;

    # Unable to signal process if no pidfile
    return 0 if !$self->pidfile || $self->_is_running;

    # Get the process id
    my $pid = $self->_read_pid;

    # Signal the process
    eval { kill 'HUP', $pid };
    if ($EVAL_ERROR) {
      say "Failed to signal PID: $pid";
      return 0;    # Return 0 to please both unit tests and exit
    }

    say "PID: $pid, was signaled to reload";
    return '0 but true';
  }

  sub run {
    my ($self) = @_;

    # Get the command to run.
    my $command
      = $self->can('extra_argv') && ref( $self->extra_argv ) eq 'ARRAY'
      ? shift $self->extra_argv    # If MooseX::Getopt is in use.
      : shift @ARGV;               # Else get it from @ARGV

    # Default to start.
    $command ||= 'start';

    # Validate that mode is valid/approved
    ($command) = $command =~ $self->_valid_commands or do {
      say $self->can('usage')
        && ref( $self->usage )
        && $self->usage->can('text')
        ? $self->usage->text              # If MooseX::Getopt is in use
        : 'The command is not valid.';    # else default to a simple message
      return 0;
    };

    # Create base dir if none exists.
    if ( !-e $self->basedir && !File::Path::make_path( $self->basedir ) ) {
      say 'Failed to create basedir.';
      return 0;
    }

    # Change to running dir, fail if base dir is not a directory
    if ( !-d $self->basedir || !chdir $self->basedir ) {
      say 'Failed to enter basedir.';
      return 0;
    }

    # Run!
    return $self->$command;
  }
}

no Moose::Role;
1;

__END__

=pod

=encoding UTF-8

=head1 NAME

MooseX::Role::UserDaemon - Simplify writing of user space daemons

=head1 VERSION

version 0.05

=head1 SYNOPSIS

In your module:

  package YourApp;
  use Moose;
  with qw(MooseX::Role::UserDaemon);

  # MooseX::Role::UserDaemon requires the consuming class to implement main()
  sub main {
    my ($self) = @_;

    # It is the responsibility of the consuming class to capture INT signals
    # to allow for graceful shutdown of the app.
    # In addition the HUP signal should be caught and used for config reload.
    my $run = 1;
    local $SIG{'INT'} = sub { $run = 0; };

    FOREVER_LOOP:
    while ($run) {
      ...
    }

    # It is recomended that main() return '0 but true' on success.
    # the return value of main is feed directly to exit()
    return '0 but true';
  }

In your script:

  use YourApp;
  my $app = YourApp->new;

  exit $app->run unless caller 0;

On the commanline:

  Start your app
  $ yourapp.pl start
    Starting...

  Check your status
  $ yourapp.pl status
    Running with PID: ...

  Stop your app
  $ yourapp.pl stop
    Stopping PID: ...

Or preferably in combination with MooseX::SimpleConfig and/or MooseX::Getopt
In your module:

  package YourApp;
  use Moose;

  # Enable use of configfile and commandline parameters as well
  with qw(MooseX::Role::UserDaemon MooseX::SimpleConfig MooseX::Getopt);

  # '+configfile' Only required when using MooseX::SimpleConfig
  has '+configfile' => (
    is      => 'ro',
    isa     => 'Str',
    default => sub {
      File::Spec->catdir( File::HomeDir->my_home, '.yourapp',
        'yourapp.conf' );
    },
    documentation => 'Use custom configfile.',   # Getopt use this description
  );

  # MooseX::Role::UserDaemon requires the consuming class to implement main()
  sub main {
    my ($self) = @_;

    # the user have to implement capturing signals and exiting.
    my $run = 1;
    local $SIG{'INT'} = sub { $run = 0; };

    FOREVER_LOOP:
    while ($run) {
      sleep 1;
    }
      
    # It is recomended that main() return '0 but true' on success.
    # the return value of main is feed directly to exit()
    return '0 but true';
  }

In your script:

  use YourApp;

  # use new_with_options when using Getopt/SimpleConfig
  my $app = YourApp->new_with_options;

  exit $app->run unless caller 0;

On the commanline:

  Start your app
  $ yourapp.pl start
    Starting...

  Check your status
  $ yourapp.pl status
    Running with PID: ...

  Stop your app
  $ yourapp.pl stop
    Stopping PID: ...

=head1 DESCRIPTION

This module aims to simplify implementation of daemons and apps ment to be run
for normal users. Not system wide services or servers.

B<< This module is not suited for implementing daemons running as root
or other system users. >>

When using this role your script will by default:

1. Create a hidden folder in the users home directory with the same
name as the script itself. So YourApp.pl will create a directory ~/.yourapp.pl

2. C<< chdir >> to this directory.

3. Daemonize by double forking.

4. Create a lockfile named lock and place a C<< flock >> on the file.
This lock  will be in place until the app shuts down.

5. Create a pidfile named pid.

6. run the C<< main() >> subroutine.

Five commands are implemented by default: status, start, stop, restart,
reload.

=head2 start (default)

Will launch the application according to the description above.

=head2 stop

Will read the pid from the pidfile and issue a C<< INT >> signal.

=head2 restart

Restart is the same as running stop then start again.

=head2 reload

Will read the pid from the pidfile and issue a C<< HUP >> signal.

=head2 status

Will read the pid from the pidfile and print to STDOUT.

=head1 ATTRIBUTES

=head2 _name

String. Defaults to script name, is used for setting a application folder name.

=head2 _valid_commands

Regexp. Default is C<< qr/status|start|stop|reload|restart/xms >>. Whitelist 
methods which can be called from the command line.

=head2 timeout

Integer. Default is 5. How much time in seconds it's expected to take after
shutting down the app by sending a C<< INT >> singal. This is used by
C<< stop >> to avoid waiting forever for the app to shut down.

=head2 foreground

Integer. Default is 0. If set to 1 the app will not daemonize/fork or redirect
STD* to /dev/null.

=head2 basedir

String. Default to an application folder in the users home directory. The app
will C<< chdir >> to this location during startup. This is where we will place 
lockfile, pidfile and other application files.

=head2 lockfile

String. Default to /basedir/lockfile

=head2 _lockfile_fh

Filehandle. Used for holding the lockfile filehandle while the app is running.

=head2 pidfile

String. Default to /basedir/pid

=head1 METHODS

=head2 run

C<< run() >> will determine which command was issued to the script,
defaults to I<< start >> if no command is given. By default the valid
commands are: status, start, stop, restart, reload

New commands can be added by the consuming class, it which case the
attribute C<< _valid_commands >> needs to be updated for C<< run() >>
to allow the command to be executed. C<< _valid_commands >> is a
RegexpRef and the default value is:
C<< qr/status|start|stop|reload|restart/ >>

You can set your own C<< _valid_commands >> in the consuming class, to allow 
for custom commands like this:

  has '+_valid_commands' => (
    default => sub {
      return qr/status|start|stop|restart|custom_command/xms
    },
  );

=head2 status

Checks if the app is running, print status to STDOUT.

=head2 start

C<< start() >> call C<< main() >> after checking that it is not running
and after forking (unless foreground mode is enabled).

=head2 stop

C<< stop() >> issues a C<< INT >> signal to the PID listed in the pidfile. It
is up to the author to trap this signal and end the application in an
orderly fashion.

=head2 restart

C<< restart() >> simply call C<< stop() >>, wait for the app to stop
and call C<< start() >>.

=head2 reload

C<< reload() >> issues a C<< HUP >> signal to the PID listed in the pidfile.
It is up to the author to trap this signal and do the appropriate
thing, usualy to reload configuration files.

=for Pod::Coverage LOCK_EX

=for Pod::Coverage LOCK_NB

=head1 AUTHOR

Tore Andersson <tore.andersson@gmail.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2014 by Tore Andersson.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
