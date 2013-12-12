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
use Getopt::Long qw(:config no_ignore_case bundling);
use Encode;

my $usage = <<END;
USAGE: $0 [-hipv] [-s VOL_ID [-s VOL_ID2...]] [-x SYS] [-y YEAR]

Reports on determinations that may now, as of the new year, have had the copyright
expire. 

-h         Print this help message.
-i         Insert priority 3 re-reviews in the queue for volumes identified.
-p         Run in production.
-s VOL_ID  Report only for HT volume VOL_ID. May be repeated for multiple volumes.
-v         Emit debugging information.
-x SYS     Set SYS as the system to execute.
-y YEAR    Use this year instead of the current one (-i option is disabled).
END

my $help;
my $insert;
my $production;
my @singles;
my $verbose;
my $sys;
my $year;

Getopt::Long::Configure ('bundling');
die 'Terminating' unless GetOptions(
           'h|?'  => \$help,
           'i'    => \$insert,
           'p'    => \$production,
           's:s@' => \@singles,
           'v+'   => \$verbose,
           'x:s'  => \$sys,
           'y:s'  => \$year);
$DLPS_DEV = undef if $production;
die "$usage\n\n" if $help;

my $crms = CRMS->new(
    logFile      =>   $DLXSROOT . '/prep/c/crms/newyear_hist.txt',
    sys          =>   $sys,
    verbose      =>   $verbose,
    root         =>   $DLXSROOT,
    dev          =>   $DLPS_DEV
);

$insert = undef if $year;
print "Verbosity $verbose\n" if $verbose;

FindICtoPD();

sub FindICtoPD
{
  $year = $crms->GetTheYear() unless $year;
  my $t1 = $year - 51;
  my $t2 = $year - 71;
  my $sql = 'SELECT id,gid,attr,reason FROM exportdata WHERE (attr="pdus" OR (attr="ic" AND reason="add"))' .
            ' AND src!="inherited"';
  if (scalar @singles)
  {
    $sql .= sprintf(" AND id in ('%s')", join "','", @singles);
  }
  $sql .= ' ORDER BY time DESC';
  my $ref = $crms->GetDb()->selectall_arrayref($sql);
  my %seen;
  my $i = 0;
  my $change = 0;
  foreach my $row (@{$ref})
  {
    my $id = $row->[0];
    next if $seen{$id};
    #-next unless $id eq 'mdp.39015011941781';
    $i++;
    my $gid = $row->[1];
    my $a = $row->[2];
    my $r = $row->[3];
    #print "$i: $id\n";
    $seen{$id} = 1;
    $sql = "SELECT renDate,renNum,category FROM historicalreviews WHERE gid=$gid" .
           ' AND validated=1 AND renDate IS NOT NULL';
    #print "$sql\n";
    my $ref2 = $crms->GetDb()->selectall_arrayref($sql);
    my $same = 1;
    my $n = scalar @{$ref2};
    #print "Results: $n\n";
    foreach (0 ... $n-2)
    {
      $same = 0 unless $crms->TolerantCompare($ref2->[$_]->[0], $ref2->[$_+1]->[0]);
      #printf "$id: [$_] %s vs %s\n", $ref2->[$_]->[0], $ref2->[$_+1]->[0];
    }
    foreach (0 ... $n-2)
    {
      $same = 0 unless $crms->TolerantCompare($ref2->[$_]->[1], $ref2->[$_+1]->[1]);
      #printf "$id: [$_ a] %s vs %s\n", $ref2->[$_]->[1], $ref2->[$_+1]->[1];
    }
    if (!$same)
    {
      #print "Conflicting dates for $id ($gid)\n";
      next;
    }
    my $renDate = $ref2->[0]->[0];
    my $renNum = $ref2->[0]->[1];
    my $cat = $ref2->[0]->[2];
    next if $renDate != $t1 && $renDate != $t2;
    my $last = $crms->PredictLastCopyrightYear($id, $renDate, $renNum, $crms->TolerantCompare($cat, 'Crown Copyright'));
    #printf "PredictLastCopyrightYear($id, $renDate, %s, %s)\n", ($renNum)? '1':'undef', ($cat && $cat eq 'Crown Copyright')? '1':'undef';
    #print "$id: predicted $rid: $a2/$r2\n";
    if ($last < $year)
    {
      print "$id: $last ($renDate)\n" if $verbose;
      if ($insert)
      {
        # Returns a status code (0=Add, 1=Error, 2=Skip, 3=Modify) followed by optional text.
        my $res = $crms->AddItemToQueueOrSetItemActive($id, 3, 1, 'newyear', 'newyear');
        my $code = substr $res, 0, 1;
        my $msg = substr $res, 1;
        if ($code eq '1' || $code eq '2')
        {
          print "Result for $id: $code $msg\n";
        }
      }
      $change++;
    }
  }
  print "Suggested rereviews: $change of $i\n";
}

print "Warning: $_\n" for @{$crms->GetErrors()};

