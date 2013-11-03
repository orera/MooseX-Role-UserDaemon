package MooseX::UserDaemon 0.05;

use 5.014;
use Moose::Role;
use autodie;
use English qw(-no_match_vars);
use Fcntl qw(:flock);
use File::Basename qw();
use File::HomeDir qw();
use File::Path qw(make_path);
use POSIX qw();
use namespace::autoclean;

{
  requires 'main';

  has '_name' => (
    is      => 'ro',
    isa     => 'Str',
    default => sub {
      my $name = File::Basename::fileparse $PROGRAM_NAME;
      return $name;
    },
  );

  has '_valid_commands' => (
    is      => 'ro',
    isa     => 'RegexpRef',
    default => sub {qr/status|start|stop|reload|restart/xms},
  );

  has 'foreground' => (
    is      => 'ro',
    isa     => 'Int',
    default => 0,
    documentation =>
      'Run the app in the foreground, instead of daemonizing it.',
  );

  has 'basedir' => (
    is            => 'ro',
    isa           => 'Str',
    lazy_build    => 1,
    documentation => 'Use custom base directory.',
  );

  has 'lockfile' => (
    is            => 'rw',
    isa           => 'Str',
    lazy_build    => 1,
    documentation => 'Use custom lockfile.',
  );

  has 'pidfile' => (
    is            => 'rw',
    isa           => 'Str',
    lazy_build    => 1,
    documentation => 'Use custom pidfile.',
  );

  has '_lock_fh' => (
    is      => 'rw',
    isa     => 'Maybe[FileHandle]',
    clearer => 'clear_lock_fh',
  );

  sub _build_basedir {
    my ($self) = @_;
    return join q{/.}, File::HomeDir->my_home, lc $self->_name;
  }

  sub _build_lockfile {
    my ($self) = @_;
    return join q{/}, $self->basedir, 'lock';
  }

  sub _build_pidfile {
    my ($self) = @_;
    return join q{/}, $self->basedir, 'pid';
  }

  # Write PID file if supplied
  around 'main' => sub {
    my ( $orig, $self ) = @_;

    return if !$self->pidfile;

    return 5 if !$self->_write_pid;

    $self->$orig;

    return 6 if !$self->_delete_pid;
  };

  # Write lock file if supplied
  around 'main' => sub {
    my ( $orig, $self ) = @_;

    return if !$self->lockfile;

    return 4 if !$self->_lock;

    $self->$orig;

    return 7 if !$self->_unlock;
  };

  sub _lock {
    my ($self) = @_;

    die 'Must specify a path to be used as a lock file.'
      if !$self->lockfile;

    die 'A lockfile already exists but it is not an empty writable file'
      if -e $self->lockfile    # If it exists it:
      && (
      !-f $self->lockfile       # must be a regular file
      || !-z $self->lockfile    # have a size of zero
      || !-w $self->lockfile    # and be writeable
      );

    # create the entire path, and remove the innermost directory
    make_path( $self->lockfile ) && rmdir $self->lockfile
      if !-e $self->lockfile;

    # Finally open the file and place a lock on it
    open my $LOCK_FH, '>>', $self->lockfile;
    flock $LOCK_FH, LOCK_EX | LOCK_NB
      or return;

    # Maintain the lock troughout the runtime of the app. Store the FH.
    $self->_lock_fh($LOCK_FH);

    return 1;
  }

  sub _unlock {
    my ($self) = @_;

    die 'Trying to unlock a non-existing lockfile filehandle'
      if !$self->_lock_fh;

    close $self->_lock_fh or do {
      warn 'Failed to close lockfile filehandle: ' . $ERRNO;
      return;
    };

    # Clear the lock filehandle
    $self->clear_lock_fh;

    # And lastly unlink the lockfile.
    return unlink $self->lockfile;
  }

  sub _write_pid {
    my ($self) = @_;

    die 'Must specify a path to be used as a pidfile.'
      if !$self->pidfile;

    die 'A pidfile already exist, but is not a regular writable file'
      if -e $self->pidfile && ( !-f $self->pidfile || !-w $self->pidfile );

    # create the entire path, and remove the innermost directory
    make_path( $self->pidfile ) && rmdir $self->pidfile
      if !-e $self->pidfile;

    # write the actual file
    {
      local $OUTPUT_AUTOFLUSH = 1;
      open my $PID_FH, '>', $self->pidfile;
      print {$PID_FH} $PID;
      close $PID_FH;
    }

    return 1;
  }

  sub _read_pid {
    my ($self) = @_;

    # Return undef if no pidfile.
    return
      if !$self->pidfile || !-e $self->pidfile;

    die 'pidfile is not a regular file or is not readable'
      if !-f $self->pidfile || !-r $self->pidfile;

    open my $PID_FH, '<', $self->pidfile;
    my $DAEMON_PID = do { local $INPUT_RECORD_SEPARATOR = undef; <$PID_FH> };
    close $PID_FH;

    return $DAEMON_PID;
  }

  sub _delete_pid {
    my ($self) = @_;

    # Return undef if no pidfile.
    return
      if !$self->pidfile || !-e $self->pidfile;

    return unlink $self->pidfile;
  }

  sub _daemonize {
    my ($self) = @_;

    # Redirect STD* to /dev/null
    open STDIN,  '<',  '/dev/null';
    open STDOUT, '>>', '/dev/null';
    open STDERR, '>>', '/dev/null';

    # Fork once
    defined( my $pid1 = fork ) or die "Can’t fork: $ERRNO";
    exit if $pid1;    # Parent exit

    # Fork twice
    defined( my $pid2 = fork ) or die "Can’t fork: $ERRNO";
    exit if $pid2;    # Parent exit

    # Become session leader
    POSIX::setsid
      or die "Unable to to become session leader: $ERRNO";

    # Return success!
    return 1;
  }

  sub _is_running {
    my ($self) = @_;

    # return false if lockfile is not in use
    return if !$self->lockfile || !-e $self->lockfile;

    return if $self->_lock && $self->_unlock;    # Not running
    return 1;                                    # running
  }

  sub status {
    my ($self) = @_;

    $self->_is_running
      ? say 'Running with PID: ' . $self->_read_pid
      : say 'Not running.';

    return '0 but true';
  }

  sub start {
    my ($self) = @_;

    return $self->status if $self->_is_running;

    say 'Starting...';

    # Do the fork, unless foreground mode is enabled
    return 3 if !$self->foreground && !$self->_daemonize;

    # Return output of main
    return $self->main;
  }

  sub stop {
    my ($self) = @_;

    if ( !$self->_is_running ) {
      say 'Process not running, nothing to stop.';
      return '0 but true';
    }

    if ( !$self->pidfile || !-e $self->pidfile ) {
      say 'No pidfile, not able to identify process';
      return '0 but true';
    }

    my $PID = $self->_read_pid;

    say "Stopping PID: $PID";
    kill 0, $PID and kill 'INT', $PID or do {
      warn 'Not able to issue kill signal.';
      return 8;
    };

    # Not dead yet?
    sleep 1 while $self->_is_running;

    return '0 but true';
  }

  sub restart {
    my ($self) = @_;

    # Stop the app.
    $self->stop;

    # Start a new
    return $self->start;
  }

  sub reload {
    my ($self) = @_;

    if ( $self->_is_running ) {
      my $pid = $self->_read_pid;

      my $rc = kill 'HUP', $pid;
      $rc
        ? say "PID: $pid, was signaled to reload"
        : say "Failed to signal PID: $pid";

      return '0 but true';
    }

    say 'No process to signal';
    return '0 but true';
  }

  sub run {
    my ($self) = @_;

    # Get run mode.
    my $command;
    $command = $self->can('extra_argv')
      ? shift $self->extra_argv    # If MooseX::Getopt is in use.
      : shift @ARGV;               # Else get it from @ARGV

    # Default to start.
    $command = 'start' if !$command;

    # Validate that mode is valid/approved
    if ( $command !~ $self->_valid_commands ) {
      say "Invalid command: $command";
      return 9;
    }

    # Create base dir if none exists.
    return 1 if !-e $self->basedir && !make_path( $self->basedir );

    # Change to running dir, fail if base dir is not a directory
    return 2 if !-d $self->basedir || !chdir $self->basedir;

    # Run!
    return $self->$command;
  }

  no Moose::Role;
}
1;
__END__

=pod

=head1 NAME

MooseX::UserDaemon - A moose role ment to simplify writing of user level perl daemons.

=head1 VERSION

Version 0.05

=head1 SYNOPSIS

In your module:

    package YourApp;
    use Moose;
    with 'MooseX::UserDaemon';

    # MooseX::UserDaemon requires the consuming class to implement main()
    sub main {
      while (1) {
        ...
      }
      
      return '0 but true'; # Return '0 but true' on success.
    }

In your script:

    use YourApp;
    my $app = YourApp->new;

    exit $app->run unless caller 0;

On the commanline:

	Start your app
	$ myapp.pl start
		Starting...

	Check your status
	$ myapp.pl status
		Running with PID: ...

	Stop your app
	$ myapp.pl stop
		Stopping PID: ...

Or preferably in combination with MooseX::SimpleConfig and/or MooseX::Getopt:

In your module:
    package YourApp;
    use Moose;

    # Enable use of config file
    with 'MooseX::SimpleConfig';

    # Enable use of commandline parameters
    with 'MooseX::Getopt';

    with 'MooseX::UserDaemon';

    # '+configfile' Only required if using MooseX::SimpleConfig
    has '+configfile' => (
      is            => 'ro',
      isa           => 'Str',
      default       => $ENV{'HOME'} . '/.yourapp/yourapp.conf',
      documentation => 'Use custom configfile.',
    );

    sub main {
      while (1) {
        ...
      }
    }

In your script:

    use YourApp;
    my $app = YourApp->new_with_options;

    exit $app->run unless caller 0;

On the commanline:

	Start your app
	$ myapp.pl start
		Starting...

	Check your status
	$ myapp.pl status
		Running with PID: ...

	Stop your app
	$ myapp.pl stop
		Stopping PID: ...

=head1 DESCRIPTION

	This module aims to simplify the process of writing user level daemons, that runs from the users home directory.
	This module should NOT under any circumstance be used to implement system level daemons.

	It implements (by default):
	Daemonization / forking, running your script in the background detached from the terminal.
	Lockfile functionality to ensure only one running instance at any given time.
	Pidfile functionality to allow you find the process id of any running instace.
	Facilities to issue start/stop/restart/reload and status commands to your daemon while running.
	
	It plays nice with MooseX::Getopt and MooseX::SimpleConfig.

=head1 SUBROUTINES/METHODS

=head2 run

	Runs the command issued to the script, defaults to 'start' if no command is given.
	By default the valid commands are:
	status
	start
	stop
	restart
	reload

  New commands can be added by the consuming class, it which case the attribute '_valid_commands' needs to be updated for 'run()' to allow the command to be executed.
	'_valid_commands' is a RegexpRef and the default value is: qr/status|start|stop|reload|restart/

=head2 status

	Checks if the app is running or not and prints to STDOUT.

=head2 start

	start() call 'main()' after checking that it is not running and after forking (unless foreground mode is enabled).

=head2 stop

	stop issues a 'INT' signal to the PID listed in the pidfile.
	It is up to the author to trap this signal and end the application in an orderly fashion.

=head2 restart

	restart simply call 'stop()', wait for the app to stop and call 'start()'.

=head2 reload

	Reload issues a "HUP" signal to the PID listed in the pidfile.
	It is up to the author to trap this signal and do the appropriate thing, usualy to reload the configuration file.

=head1 AUTHOR

Tore Andersson, C<< <tore.andersson at gmail.com> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-moosex-userdaemon at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=MooseX-DaemonControl>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc MooseX::UserDaemon

You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=MooseX-UserDaemon>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/MooseX-UserDaemon>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/MooseX-UserDaemon>

=item * Search CPAN

L<http://search.cpan.org/dist/MooseX-UserDaemon/>

=back

=head1 ACKNOWLEDGEMENTS

=head1 LICENSE AND COPYRIGHT

Copyright 2013 Tore Andersson.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.

=cut
