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

my $crms = CRMS->new(
    logFile      =>   "$DLXSROOT/prep/c/crms/log_load_hist.txt",
    configFile   =>   'crms.cfg',
    verbose      =>   0,
    root         =>   $DLXSROOT,
    dev          =>   $DLPS_DEV,
);

#Call script to unlock items after one hour of being locked.
# every 1000 is one minute so 60,000 is one hour.
my $sql  = qq{ SELECT id, user  FROM timer where current_timestamp - start_time >= 60000};

my $ref  = $crms->GetDb()->selectall_arrayref( $sql );

my @return;
foreach my $r ( @{$ref} ) 
{ 
  my $id         = $r->[0];
  my $userid     = $r->[1];

  $crms->UnlockItemEvenIfNotLocked ( $id, $userid );

}

