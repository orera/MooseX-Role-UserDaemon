#!perl

use 5.014;
use inc::Module::Install;

name 'MooseX-Role-UserDaemon';
all_from 'lib/MooseX/Role/UserDaemon.pm';
license 'perl';

requires 'Moose::Role';
requires 'autodie';
requires 'English';
requires 'Fcntl';
requires 'File::Basename';
requires 'File::HomeDir';
requires 'File::Path';
requires 'POSIX';
requires 'namespace::autoclean';

test_requires 'English';
test_requires 'File::Path';
test_requires 'File::Temp';
test_requires 'Readonly';
test_requires 'Test::More';
test_requires 'Test::Most';
test_requires 'Test::Output';

WriteAll;
