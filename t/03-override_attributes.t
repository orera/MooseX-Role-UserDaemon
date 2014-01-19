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

  has '+_valid_commands' => ( default => sub {qr/custom_command/xms}, );

  sub custom_command {
    my ($self) = @_;
    return 1;
  }

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

  local $ENV{'HOME'} = File::Temp::tempdir;
  chdir $ENV{'HOME'};

  diag( $app->_valid_commands );
  is( $app->_valid_commands, '(?^umsx:custom_command)',
    '_valid_command have been successfully changed' );

  ok( $app->custom_command, 'custom command returns true' );
}

done_testing;

__END__
