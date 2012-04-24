#!/usr/bin/perl

my $DLXSROOT;
my $DLPS_DEV;

BEGIN 
{ 
  $DLXSROOT = $ENV{'DLXSROOT'}; 
  $DLPS_DEV = $ENV{'DLPS_DEV'}; 
  unshift (@INC, $DLXSROOT . '/cgi/c/crms/');
}

use strict;
use CRMS;
use Getopt::Std;

my $usage = <<END;
USAGE: $0 [-cehmpqt] [-x SYS] [start_date [end_date]]

Processes reviews, exports determinations, updates candidates,
updates the queue, and recalculates user stats.

If the start or end dates are specified, only loads candidates
with latest rights DB timestamp between them.

-c       Do not update candidates.
-e       Do not process statuses or export determinations.
-h       Print this help message.
-m       Do not recalculate monthly stats.
-n       Do not check no-meta filtered volumes
-p       Run in production.
-q       Do not update queue.
-t       Run in training.
-x SYS   Set SYS as the system to execute.
END


my %opts;
getopts('cehmnpqtx:', \%opts);
my $skipCandidates = $opts{'c'};
my $skipExport = $opts{'e'};
my $help = $opts{'h'};
my $skipMonthly = $opts{'m'};
my $skipNoMeta = $opts{'n'};
my $production = $opts{'p'};
my $skipQueue = $opts{'q'};
my $training = $opts{'t'};
my $sys = $opts{'x'};
die $usage if $help;
$DLPS_DEV = undef if $production;

my $start = undef;
my $end = undef;
if (scalar @ARGV)
{
  $start = $ARGV[0];
  die "Bad date format ($start); should be in the form e.g. 2010-08-29" unless $start =~ m/^\d\d\d\d-\d\d-\d\d$/;
  $start .= ' 00:00:00';
  if (scalar @ARGV > 1)
  {
    $end = $ARGV[1];
    die "Bad date format ($end); should be in the form e.g. 2010-08-29" unless $end =~ m/^\d\d\d\d-\d\d-\d\d$/;
    $end .= ' 23:59:59'
  }
}

my $crms = CRMS->new(
    logFile    =>   "$DLXSROOT/prep/c/crms/update_log.txt",
    sys        =>   $sys,
    verbose    =>   0,
    root       =>   $DLXSROOT,
    dev        =>   ($training)? 'crmstest':$DLPS_DEV
);
$crms->set('ping','yes');
if ($skipExport) { ReportMsg("-e flag set; skipping queue processing and export."); }
else
{
  ReportMsg("Starting to process the statuses.");
  $crms->ProcessReviews();
  ReportMsg("DONE processing the statuses.");
  ReportMsg("Starting to create export for the rights db. You should receive a separate email when this completes.");
  my $rc = $crms->ClearQueueAndExport();
  ReportMsg("$rc\nDONE exporting.");
}

if ($skipCandidates) { ReportMsg("-c flag set; skipping candidates load."); }
else
{
  ReportMsg("Starting to load new volumes into candidates.");
  my $status = $crms->LoadNewItemsInCandidates($skipNoMeta, $start, $end);
  ReportMsg("DONE loading new volumes into candidates.");
}

if ($skipQueue) { ReportMsg("-q flag set; skipping queue load."); }
else
{
  ReportMsg("Starting to load new volumes into queue.");
  $crms->LoadNewItems();
  ReportMsg("DONE loading new volumes into queue.");
}

if ($skipMonthly) { ReportMsg("-m flag set; skipping monthly stats."); }
else
{
  ReportMsg("Starting to update monthly stats.");
  $crms->UpdateStats();
  ReportMsg("DONE updating monthly stats.");
}

my $r = $crms->GetErrors();
printf "There were %d errors%s\n", scalar @{$r}, (scalar @{$r})? ':':'.';
print "$_\n" for @{$r};

ReportMsg("All DONE with nightly script.");


sub ReportMsg
{
  my $msg = shift;
  
  my $newtime = scalar (localtime(time()));
  print "$newtime: $msg\n";
}

