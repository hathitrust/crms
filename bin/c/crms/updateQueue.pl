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

my %opts;
getopts('vhu:', \%opts);

my $help     = $opts{'h'};
my $verbose  = $opts{'v'};

if ( $help ) 
{ 
    die "USAGE: $0 " .
        "\n\t[-h (this help message)] " .
        "\n\t[-v (verbose)]\n"; 
}

my $crms = CRMS->new(
    logFile      =>   "$DLXSROOT/prep/c/crms/update_log.txt",
    configFile   =>   'crms.cfg',
    verbose      =>   $verbose,
    root         =>   $DLXSROOT,
    dev          =>   $DLPS_DEV,
);

#Set the statuses as needed.
$crms->ProcessReviews ( );

## get new items and load the queue table
my $status = $crms->LoadNewItemsInCandidates ();

if ( $status )
{
   $crms->LoadNewItems ();
}



