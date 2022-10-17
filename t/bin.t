#!/usr/bin/perl

# Make sure all Perl scripts can at least be invoked with the -h
# usage flag without error.

use strict;
use warnings;
use Test::More;

foreach my $bindir ($ENV{'SDRROOT'}. '/crms/bin', $ENV{'SDRROOT'}. '/crms/bib_rights') {
  my $bindir = $ENV{'SDRROOT'}. '/crms/bin';
  opendir(DIR, $bindir) or die "Can't open $bindir\n";
  my @files = readdir(DIR);
  closedir(DIR);
  foreach my $file (sort @files)
  {
    $file = $ENV{'SDRROOT'}. '/crms/bin/'. $file;
    next unless $file =~ m/\.pl$/;
    my $cmd = $file. ' -h >/dev/null 2>&1';
    ok(system($cmd) == 0, $cmd);
  }
}

done_testing();
