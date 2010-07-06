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
USAGE: $0 [-hp]

Clears and recalculates user stats.

-h       Print this help message.
-p       Run in production.
END

my %opts;
getopts('hp', \%opts);
my $help = $opts{'h'};
my $dev = $DLPS_DEV;
$dev = undef if $opts{'p'};

die $usage if $help;

my $crms = CRMS->new(
    logFile      =>   "$DLXSROOT/prep/c/crms/log_monthlyStats.txt",
    configFile   =>   "$DLXSROOT/bin/c/crms/crms.cfg",
    verbose      =>   0,
    root         =>   $DLXSROOT,
    dev          =>   $dev
);

$crms->UpdateStats();
my $r = $crms->GetErrors();
foreach my $err (@{$r})
{
  print "Error: $err\n";
}
