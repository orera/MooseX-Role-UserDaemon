#!perl

use 5.014;
use inc::Module::Install;

name 'MooseX-UserDaemon';
all_from 'lib/MooseX/UserDaemon.pm';
license 'perl';

requires 'Moose::Role'          => 0;
requires 'English'              => 0;
requires 'Fcntl'                => 0;
requires 'File::Basename'       => 0;
requires 'File::HomeDir'        => 0;
requires 'File::Path'           => 0;
requires 'POSIX'                => 0;
requires 'namespace::autoclean' => 0;

test_requires 'Test::More' => '0';
WriteAll;