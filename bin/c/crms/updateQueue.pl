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
#to create a range of time to get from rights db
#my $start   = $opts{'u'};
#my $stop    = $opts{'s'};

my $start   = '2009-03-01 09:30:26';
my $stop    = '2009-03-07 09:30:26';

if ( $help ) 
{ 
    die "USAGE: $0 [-u start_time (2007-09-13 09:30:26) -u stop_time (2007-09-13 09:30:26)] " .
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

## get new items and load the queue table
$crms->LoadNewItems( $start, $stop );


