#!/usr/bin/perl

use strict;
use warnings;
BEGIN { unshift(@INC, $ENV{'SDRROOT'}. '/crms/cgi'); }

use CRMS;
use Getopt::Long;
#use Utilities;
#use Encode;

my $usage = <<END;
USAGE: $0 [-hlptv] [-m USER [-m USER...]]

Call imgsrv to cache page images for volumes in the queue.

-h       Print this help message.
-p       Run in production.
-t       Run in training.
-v       Be verbose.
END

my $help;
my $instance;
my $production;
my $training;
my $verbose = 0;

Getopt::Long::Configure ('bundling');
die 'Terminating' unless Getopt::Long::GetOptions(
           'h|?' => \$help,
           'p'   => \$production,
           't'   => \$training,
           'v+'  => \$verbose);
$instance = 'production' if $production;
$instance = 'crms-training' if $training;
if ($help) { print $usage. "\n"; exit(0); }

print "Verbosity $verbose\n" if $verbose;

my $binary = $ENV{'SDRROOT'}. '/imgsrv/scripts/cache_frontmatter.pl';
die "Can't find $binary, aborting\n" unless -f $binary;

my $crms = CRMS->new(
    verbose  => $verbose,
    instance => $instance
);

my $sql = 'SELECT id FROM queue ORDER BY id';
my $ref = $crms->SelectAll($sql);
foreach my $row (@$ref)
{
  my $id = $row->[0];
  my $cmd = $binary. ' '. $id;
  print "$cmd\n" if $verbose;
  `$cmd`;
}

print "Warning: $_\n" for @{$crms->GetErrors()};
