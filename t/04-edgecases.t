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
  with 'MooseX::Getopt';

  my $run = 1;
  local $SIG{'INT'} = sub { $run = 0; };

  sub main {
    while ($run) {
      sleep 1;
    }
    return '0 but true';
  }

  1;
}

{
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

done_testing;

__END__
