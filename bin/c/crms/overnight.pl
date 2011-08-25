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
USAGE: overnight.pl [-cehmpqt]

Processes reviews, exports determinations, updates candidates,
updates the queue, and recalculates user stats.

-c       Do not update candidates.
-e       Do not process statuses or export determinations.
-h       Print this help message.
-m       Do not recalculate monthly stats.
-p       Run in production.
-q       Do not update queue.
-t       Run in training.
END


my %opts;
getopts('cehmpqt', \%opts);
my $skipCandidates = $opts{'c'};
my $skipExport = $opts{'e'};
my $help = $opts{'h'};
my $skipMonthly = $opts{'m'};
my $production = $opts{'p'};
my $skipQueue = $opts{'q'};
my $training = $opts{'t'};
die $usage if $help;
$DLPS_DEV = undef if $production;

my $crms = CRMS->new(
    logFile      =>   "$DLXSROOT/prep/c/crms/update_log.txt",
    configFile   =>   "$DLXSROOT/bin/c/crms/crms.cfg",
    verbose      =>   0,
    root         =>   $DLXSROOT,
    dev          =>   ($training)? 'crmstest':$DLPS_DEV
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

