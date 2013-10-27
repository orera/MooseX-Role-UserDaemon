use 5.014;
use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
  NAME          => 'MooseX::UserDaemon',
  AUTHOR        => q{Tore Andersson <tore.andersson@gmail.com>},
  VERSION_FROM  => 'lib/MooseX/UserDaemon.pm',
  ABSTRACT_FROM => 'lib/MooseX/UserDaemon.pm',
  ( $ExtUtils::MakeMaker::VERSION >= 6.3002
    ? ( 'LICENSE' => 'perl' )
    : () ),
  PL_FILES  => {},
  PREREQ_PM => {
    'Test::More'           => 0,
    'Moose::Role'          => 0,
    'English'              => 0,
    'Fcntl'                => 0,
    'File::Basename'       => 0,
    'File::Path'           => 0,
    'POSIX'                => 0,
    'namespace::autoclean' => 0,
  },
  dist  => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
  clean => { FILES    => 'MooseX-UserDaemon-*' },
);
