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
getopts('vhs:', \%opts);

my $help     = $opts{'h'};
my $verbose  = $opts{'v'};
my $sec      = $opts{'s'} || 86400;

if ( $help ) 
{ 
    die "USAGE: $0 [-s (sec. locked, default 86400)] " .
        "\n\t[-h (this help message)] " .
        "\n\t[-v (verbose)]\n"; 
}

my $crms = CRMS->new(
    logFile      =>   "$DLXSROOT/prep/c/crms/clearLocks_log.txt",
    configFile   =>   'crms.cfg',
    verbose      =>   $verbose,
    root         =>   $DLXSROOT,
    dev          =>   $DLPS_DEV,
);

$crms->RemoveOldLocks($sec);

