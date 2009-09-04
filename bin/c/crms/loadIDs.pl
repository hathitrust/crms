#!/l/local/bin/perl

my $DLXSROOT;
my $DLPS_DEV;
BEGIN 
{ 
    $DLXSROOT = $ENV{'DLXSROOT'}; 
    $DLPS_DEV = $ENV{'DLPS_DEV'}; 
    unshift ( @INC, $ENV{'DLXSROOT'} . "/cgi/c/crms/" );
}

use strict;
use CRMS;
use Getopt::Std;
use LWP::UserAgent;

my %opts;
getopts('f:hv', \%opts);

my $file       = $opts{'f'};
my $help       = $opts{'h'};
my $verbose    = $opts{'v'};


if ( $help || ! $file ) { die "USAGE: $0 -f csv_file [-v] [-h]\n\n"; }

print("DLXSROOT: $DLXSROOT DLPS_DEV: $DLPS_DEV\n");

my $crms = CRMS->new(
    logFile      =>   "$DLXSROOT/prep/c/crms/log_IDs.txt",
    configFile   =>   'crms.cfg',
    verbose      =>   $verbose,
    root         =>   $DLXSROOT,
    dev          =>   $DLPS_DEV,
);

open my $fh, $file or die "failed to open $file: $@ \n";

# This is for re-reviewing pd determinations from 2007. Ignores non-pd entries.
# If item is already in queue table it will get priority set to 1,
# otherwise an insert will be done in the queue table with prority set to 1.
## This is the format for file; one record per line:
##  barcode sans mdp <tab> rights <tab> reason <tab> original review date:
## 	39015028120130<tab>ic<tab>ren<tab>2007-10-03 12:20:49
my $cnt = 0;
my $linen = 1;
my $now = $crms->GetTodaysDate();
foreach my $line ( <$fh> )
{
  chomp $line;
  my ($id,$rights,$reason,$date) = split(m/\t/, $line, 4);
  $id = 'mdp.' . $id;
  if ($rights ne 'pd')
  {
    print "$linen) ignoring $id ($rights/$reason)\n" if $verbose;
  }
  else
  {
    print "$linen) updating $id ($rights/$reason)\n" if $verbose;
    $crms->GiveItemsInQueuePriority($id, $now, 0, 1);
    $cnt++;
  }
  $linen++;
}
print "Updated $cnt items\n" if $verbose;
close $fh;

