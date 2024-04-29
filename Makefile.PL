use strict;
use warnings;
use ExtUtils::MakeMaker;

my ($mm) = $ExtUtils::MakeMaker::VERSION =~ /^([^_]+)/;

WriteMakefile(
  NAME         => 'CRMS',
  VERSION_FROM => 'lib/CRMS/Version.pm',
  test => {RECURSIVE_TEST_FILES => 1}
);
