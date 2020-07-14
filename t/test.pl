#!/usr/bin/perl -w

use strict;
use Test::Harness;
use Term::ANSIColor qw(:constants);
$Term::ANSIColor::AUTORESET = 1;

# Colorization is for Mac Docker app which makes it difficult to distinguish
# test runs in the logs.
my @colors = qw(BLACK RED GREEN YELLOW BLUE MAGENTA CYAN WHITE
                BRIGHT_BLACK BRIGHT_RED BRIGHT_GREEN BRIGHT_YELLOW
                BRIGHT_BLUE BRIGHT_MAGENTA BRIGHT_CYAN BRIGHT_WHITE);
my $col1 = splice(@colors, rand @colors, 1);
my $col2 = splice(@colors, rand @colors, 1);
foreach my $i (0 .. 9)
{
  print Term::ANSIColor::colored('====', $col1);
  print Term::ANSIColor::colored('====', $col2);
}
print "\n";


my @test_files = ('crms/t/bin.t',
                  '/crms/t/CRMS.t',
                  '/crms/t/Metadata.t',
                  '/crms/t/Project.t',
                  );
runtests map {$ENV{'SDRROOT'}. $_} @test_files;

foreach my $i (0 .. 9)
{
  print Term::ANSIColor::colored('====', $col1);
  print Term::ANSIColor::colored('====', $col2);
}
print "\n";
