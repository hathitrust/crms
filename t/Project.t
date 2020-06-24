#!/usr/bin/perl

use strict;
use warnings;
BEGIN { unshift(@INC, $ENV{'SDRROOT'}. '/crms/cgi'); }

use Test::More;

my $dir = $ENV{'SDRROOT'}. '/crms/cgi/Project';
opendir(DIR, $dir) or die "Can't open $dir\n";
my @files = readdir(DIR);
closedir(DIR);
foreach my $file (sort @files)
{
  next if $file =~ /^\.\.?$/;
  my $path = "$dir/$file";
  require_ok($path);
}

done_testing();
