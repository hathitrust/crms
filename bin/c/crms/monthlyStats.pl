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


my $crms = CRMS->new(
    logFile      =>   "$DLXSROOT/prep/c/crms/log_monthlyStats.txt",
    configFile   =>   "$DLXSROOT/bin/c/crms/crms.cfg",
    verbose      =>   0,
    root         =>   $DLXSROOT,
    dev          =>   $DLPS_DEV,
);

$crms->UpdateStats();
my $r = $crms->GetErrors();
foreach my $err (@{$r})
{
  print "Error: $err\n";
}
