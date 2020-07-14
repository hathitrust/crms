#!/usr/bin/perl

use strict;
use warnings;
use Test::More;

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
done_testing();

