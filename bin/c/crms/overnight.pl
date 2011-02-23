#!/l/local/bin/perl

my $DLXSROOT;
my $DLPS_DEV;

BEGIN 
{ 
  $DLXSROOT = $ENV{'DLXSROOT'}; 
  $DLPS_DEV = $ENV{'DLPS_DEV'}; 

  my $toinclude = qq{$DLXSROOT/cgi/c/crms};
  unshift( @INC, $toinclude );
}

use strict;
use CRMS;
use Getopt::Std;

my $usage = <<END;
USAGE: overnight.pl [-cehmq]

Processes reviews, exports determinations, updates candidates,
updates the queue, and recalculates user stats.

-c       Do not update candidates.
-e       Do not process statuses or export determinations.
-h       Print this help message.
-m       Do not recalculate monthly stats.
-q       Do not update queue.
END


my %opts;
getopts('cehmq', \%opts);
my $skipCandidates = $opts{'c'};
my $skipExport = $opts{'e'};
my $help = $opts{'h'};
my $skipMonthly = $opts{'m'};
my $skipQueue = $opts{'q'};
die $usage if $help;

my $crms = CRMS->new(
    logFile      =>   "$DLXSROOT/prep/c/crms/update_log.txt",
    configFile   =>   "$DLXSROOT/bin/c/crms/crms.cfg",
    verbose      =>   0,
    root         =>   $DLXSROOT,
    dev          =>   $DLPS_DEV,
);

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
  my $status = $crms->LoadNewItemsInCandidates();
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

