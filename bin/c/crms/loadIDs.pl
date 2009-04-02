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
getopts('f:hva', \%opts);

my $help       = $opts{'h'};
my $verbose    = $opts{'v'};
my $file       = $opts{'f'};


if ( $help || ! $file ) { die "USAGE: $0 -f csv_file [-v] [-h]  \n\n"; }


my $crms = CRMS->new(
    logFile      =>   "$DLXSROOT/prep/c/crms/log_IDs.txt",
    configFile   =>   'crms.cfg',
    verbose      =>   $verbose,
    root         =>   $DLXSROOT,
    dev          =>   $DLPS_DEV,
);

open my $fh, $file or die "failed t_histo open $file: $@ \n";

#If item is already in queue table it will get priority set to 1,
#otherwise an isert will be done in the queue table with prority set to 1

## This is the format for file
## 0  Barcode


foreach my $line ( <$fh> )
{
    chomp $line;
    my $id     = $line;


    if ( $verbose )
    { 
        print qq{$id } . "\n"; 
    }

    $crms->GiveItemsInQueuePriority( $id, $crms->GetTodaysDate(), 0, 1 );

}

close $fh;


