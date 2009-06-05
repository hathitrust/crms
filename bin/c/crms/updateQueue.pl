#!/l/local/bin/perl

my $DLXSROOT;
my $DLPS_DEV;

BEGIN
{
    unshift( @INC, '/l1/dev/blancoj/cgi/c/crms' );
}



BEGIN 
{ 
    $DLXSROOT = $ENV{'DLXSROOT'}; 
    $DLPS_DEV = $ENV{'DLPS_DEV'}; 
}

use strict;
use CRMS;
use Getopt::Std;
use LWP::UserAgent;


sub ReportMsg
{
  my ( $msg ) = @_;

  my $newtime = scalar (localtime(time()));

  $msg = qq{$newtime : $msg};
  print "$msg","\n";

}


my $crms = CRMS->new(
    logFile      =>   "$DLXSROOT/prep/c/crms/update_log.txt",
    configFile   =>   "$DLXSROOT/bin/c/crms/crms.cfg",
    verbose      =>   0,
    root         =>   $DLXSROOT,
    dev          =>   $DLPS_DEV,
);

my $msg = qq{Starting to Process the statuses. \n};
&ReportMsg ( $msg );

#Set the statuses as needed.
$crms->ProcessReviews ( );

$msg = qq{DONE Processing the statuses. \n};
&ReportMsg ( $msg );

my $msg = qq{Starting to create export for the rights db.  You should receive a separate email when this completes. \n};
&ReportMsg ( $msg );
## get new items and load the queue table
my $rc = $crms->ClearQueueAndExport();
my $msg = qq{DONE Exporting. Starting to Load New volumes into candidates.\n};
&ReportMsg ( $msg );

## get new items and load the queue table
my $status = $crms->LoadNewItemsInCandidates ();

my $msg = qq{DONE Loading new volumes into candidates.\n};
&ReportMsg ( $msg );


if ( $status )
{
   my $msg = qq{Starting to Load new itmes into queue.\n};
   &ReportMsg ( $msg );

   $crms->LoadNewItems ();

   my $msg = qq{DONE loading new volumes into queue.\n};
   &ReportMsg ( $msg );

}
my $msg = qq{All DONE with nightly script.\n};
&ReportMsg ( $msg );



