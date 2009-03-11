#!/l/local/bin/perl

my $DLXSROOT;
my $DLPS_DEV;
BEGIN 
{ 
    $DLXSROOT = $ENV{'DLXSROOT'}; 
    $DLPS_DEV = $ENV{'DLPS_DEV'}; 
    unshift ( @INC, $DLXSROOT . "/cgi/c/crms/" );
}

use strict;
use CRMS;
use Getopt::Std;
use LWP::UserAgent;

my %opts;
getopts('vhu:', \%opts);

my $help     = $opts{'h'};
my $verbose  = $opts{'v'};
my $update   = $opts{'u'};

if ( $help ) 
{ 
    die "USAGE: $0 [-u update_time (2007-09-13 09:30:26)] " .
        "\n\t[-h (this help message)] " .
        "\n\t[-v (verbose)]\n"; 
}

my $crms = CRMS->new(
    logFile      =>   "$DLXSROOT/prep/c/crms/export_log.txt",
    configFile   =>   'crms.cfg',
    verbose      =>   $verbose,
    root         =>   $DLXSROOT,
    dev          =>   $DLPS_DEV,
);

## get new items and load the queue table
my $rc = $crms->ClearQueueAndExport();

print $rc . "\n";
