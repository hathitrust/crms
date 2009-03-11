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

my $help       = $opts{'h'};
my $verbose    = $opts{'v'};
my $file       = $opts{'f'};

if ( $help || ! $file ) { die "USAGE: $0 -f csv_file [-v] [-h] \n\n"; }


my $crms = CRMS->new(
    logFile      =>   "$DLXSROOT/prep/c/crms/log_load_hist.txt",
    configFile   =>   'crms.cfg',
    verbose      =>   $verbose,
    root         =>   $DLXSROOT,
    dev          =>   $DLPS_DEV,
);

open my $fh, $file or die "failed t_histo open $file: $@ \n";

## 0  Barcode
## 1  Author
## 2  Title
## 3  Year
## 4  Original Copyright date, if different
## 5  Attribute
## 6  Reason
## 7  Copyright renewal date?
## 8  Copyright renewal number?
## 9  Date of check
## 10 Checker
## 11 Notes
## 12 akz comments

foreach my $line ( <$fh> )
{
    chomp $line;
    my @parts     = split("\t", $line);
    my $id        = "mdp." . $parts[0];
    my $year      = $parts[3];
    my $cDate     = $parts[4];
    my $attr      = $parts[5];
    my $reason    = $parts[6];
    my $renDate   = $parts[7];
    my $renNum    = $parts[8];
    my $date      = $parts[9];
    my $user      = $parts[10];
    my $note      = $parts[11];
    my $eNote     = $parts[12];

    if ( scalar @parts > 13 ) { die "ERROR:$line \n"; }

    if ( $verbose )
    { 
        print qq{$id, $user, $attr, $reason, $cDate, $renNum, $renDate, $note, $eNote} . "\n"; 
    }
    my $rc = $crms->SubmitHistReview( $id, $user, $date, $attr, $reason, $cDate, $renNum, $renDate, $note, $eNote);

    if ( ! $rc ) 
    {
        my $errors = $crms->GetErrors();
        foreach ( @{$errors} ) { print "$_ \n"; }
        die "failed \n\n"; 
    }
}

close $fh;


