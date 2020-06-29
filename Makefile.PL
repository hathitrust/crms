use strict;
use warnings;
use ExtUtils::MakeMaker;

my ($mm) = $ExtUtils::MakeMaker::VERSION =~ /^([^_]+)/;

WriteMakefile(
  NAME         => 'CRMS',
  VERSION_FROM => 'cgi/CRMS.pm',
  test => {TESTS => 't/*.t'}
);
