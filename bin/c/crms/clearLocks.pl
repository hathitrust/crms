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
use LWP::UserAgent;

my $usage = <<END;
USAGE: $0 [-hv] [-s SECS] [-x SYS]

Clear old locks.

-h        Print this help message.
-s SECS   Clear locks older than SECS seconds old.
-v        Emit debugging information.
-x SYS    Set SYS as the system to execute.
END

my %opts;
getopts('hs:vx:', \%opts);

my $help    = $opts{'h'};
my $sec     = $opts{'s'} || 86400;
my $verbose = $opts{'v'};
my $sys     = $opts{'x'};

if ($help)
{ 
  die "USAGE: $0 [-s (sec. locked, default 86400)] " .
      "\n\t[-h (this help message)] " .
      "\n\t[-v (verbose)]\n"; 
}

my $crms = CRMS->new(
    logFile => "$DLXSROOT/prep/c/crms/clearLocks_log.txt",
    sys     => $sys,
    verbose => $verbose,
    root    => $DLXSROOT,
    dev     => $DLPS_DEV,
);

$crms->RemoveOldLocks($sec);

