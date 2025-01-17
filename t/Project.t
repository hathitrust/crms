#!/usr/bin/perl

use strict;
use warnings;
BEGIN { unshift(@INC, $ENV{'SDRROOT'}. '/crms/cgi'); }

use Test::More;

use CRMS;

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

my $crms = CRMS->new;

my $project = Project->new(crms => $crms);
subtest '#queue_order' => sub {
  is($project->queue_order, undef, 'default project has no queue_order');
};

subtest '#PresentationOrder' => sub {
  is($project->PresentationOrder, undef, 'default project has no PresentationOrder');
};

done_testing();

