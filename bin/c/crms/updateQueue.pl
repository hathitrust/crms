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
use LWP::UserAgent;

my $usage = <<END;
USAGE: $0 [-chq]

Processes reviews, exports determinations, updates candidates, and updates the queue.

-c       Do not update candidates.
-h       Print this help message.
-q       Do not update queue.
END

sub ReportMsg
{
  my $msg = shift;
  my $newtime = scalar (localtime(time()));
  print "$newtime: $msg\n";
}

my %opts;
getopts('chq', \%opts);
my $skipCandidates = $opts{'c'};
my $help = $opts{'h'};
my $skipQueue = $opts{'q'};

die $usage if $help;

my $crms = CRMS->new(
    logFile      =>   "$DLXSROOT/prep/c/crms/update_log.txt",
    configFile   =>   "$DLXSROOT/bin/c/crms/crms.cfg",
    verbose      =>   0,
    root         =>   $DLXSROOT,
    dev          =>   $DLPS_DEV,
);

ReportMsg("Starting to Process the statuses.\n");
$crms->ProcessReviews();
ReportMsg("DONE Processing the statuses.\n");

ReportMsg("Starting to create export for the rights db. You should receive a separate email when this completes.\n");
## get new items and load the queue table
my $rc = $crms->ClearQueueAndExport();
#only run this on dlps11
#it will process all files in the rights_dir of the form *.rights and move them to the
#/l1/prep/c/crms/archive
my $host = `hostname`;
if ( $host =~ m,dlps11\..*, )
{
  ReportMsg("Calling Jessica's script to populate the rights db.\n");
  my $out = `/l/local/bin/perl /l1/bin/g/groove/populate_rights_data.pl --rights_dir=/l1/prep/c/crms --archive=/l1/prep/c/crms/archive/`;
  ReportMsg("DONE calling Jessica's script to populate the rights db. This is the output:\n $out\n");
}

my $status = 1;
# The testsuite can safely skip this often time-consuming project.
if ($skipCandidates) { ReportMsg("-c flag set; skipping candidates load."); }
else
{
  ReportMsg("Starting to Load New volumes into candidates.\n");
  ## get new items and load the queue table
  $status = $crms->LoadNewItemsInCandidates();
  ReportMsg("DONE Loading new volumes into candidates.\n");
}

if ($skipQueue) { ReportMsg("-q flag set; skipping queue load."); }
elsif ($status)
{
   ReportMsg("Starting to Load new items into queue.\n");
   $crms->LoadNewItems();
   ReportMsg("DONE loading new volumes into queue.\n");
}
ReportMsg("All DONE with nightly script.\n");
