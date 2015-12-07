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
use Term::ANSIColor qw(:constants colored);
$Term::ANSIColor::AUTORESET = 1;

my $usage = <<END;
USAGE: $0 [-hinpv] [-e VOL_ID [-e VOL_ID2...]]
       [-s VOL_ID [-s VOL_ID2...]] [-x SYS] [-y YEAR]

Reports on determinations that may now, as of the new year, have had the copyright
expire.

-e VOL_ID  Exclude VOL_ID from being considered.
-h         Print this help message.
-i         Report on ic to icus/gatt transitions instead.
-n         No-op. Makes no changes to the database.
-p         Run in production.
-s VOL_ID  Report only for HT volume VOL_ID. May be repeated for multiple volumes.
-v         Emit debugging information.
-x SYS     Set SYS as the system to execute.
-y YEAR    Use this year instead of the current one (implies -n).
END

my @excludes;
my $help;
my $icus;
my $noop;
my $production;
my @singles;
my $verbose;
my $sys;
my $year;

Getopt::Long::Configure('bundling');
die 'Terminating' unless GetOptions(
           'e:s@' => \@excludes,
           'h|?'  => \$help,
           'i'    => \$icus,
           'n'    => \$noop,
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

$noop = 1 if $year;
print "Verbosity $verbose\n" if $verbose;

$year = $crms->GetTheYear() unless $year;
my $t1 = $year - 51;
my $t2 = $year - 71;
my $attrsClause = '(attr="pdus" OR attr="ic" OR attr="icus")';
$attrsClause = '(attr="ic")' if $icus;
my $sql = 'SELECT id,gid,time,attr,reason FROM exportdata'.
          ' WHERE '. $attrsClause.
          ' AND exported=1 AND src="candidates" AND YEAR(DATE(time))<?'.
          ' AND id NOT IN (SELECT id FROM queue)';
if (scalar @singles)
{
  $sql .= sprintf(" AND id IN ('%s')", join "','", @singles);
}
if (scalar @excludes)
{
  $sql .= sprintf(" AND NOT id IN ('%s')", join "','", @excludes);
}
$sql .= ' ORDER BY time DESC';
my $ref = $crms->SelectAll($sql, $year);
my %seen;
my $i = 0;
my $change = 0;
foreach my $row (@{$ref})
{
  my $id = $row->[0];
  next if $seen{$id};
  my $record = $crms->GetMetadata($id);
  next unless defined $record;
  my $rq = $crms->RightsQuery($id, 1);
  my ($acurr,$rcurr,$src,$usr,$time,$note) = @{$rq->[0]};
  $i++;
  my $gid = $row->[1];
  my $time = $row->[2];
  $seen{$id} = 1;
  my $msg = '';
  my $pub = $record->copyrightDate($id, $record);
  next unless defined $pub;
  if ($pub + 140 < $year && $pub > 0)
  {
    print "$id: pub date $pub\n" if $verbose > 1;
    $change++;
    next;
  }
  $sql = 'SELECT renDate,renNum,category,note,user FROM historicalreviews WHERE gid=?' .
         ' AND validated=1 AND renDate IS NOT NULL';
  my $ref2 = $crms->SelectAll($sql, $gid);
  my $n = scalar @{$ref2};
  next unless $n > 0;
  my %predictions;
  my $pa;
  my $pr;
  my $renDate;
  my $crown = 0;
  foreach my $row2 (@{$ref2})
  {
    my $pub;
    my %dates = ();
    $renDate = $row2->[0];
    $dates{$renDate} = 1 if $renDate;
    my $renNum = $row2->[1];
    my $cat = $row2->[2];
    my $note = $row2->[3];
    my $user = $row2->[4];
    my @matches = $note =~ /(?<!\d)1\d\d\d(?![\d\-])/g;
    $crown = 1 if $crms->TolerantCompare($cat, 'Crown Copyright');
    foreach my $match (@matches)
    {
      print "Match on '$match'\n" if $verbose > 2;
      $dates{$match} = 1 if length $match and $match < $year;
    }
    printf "Dates %s\n", join ', ', sort keys %dates if $verbose > 2;
    foreach $renDate (sort keys %dates)
    {
      my $last = $crms->PredictLastCopyrightYear($id, $renDate, $renNum,
                                                 $crms->TolerantCompare($cat, 'Crown Copyright'),
                                                 $record);
      $msg .= "   last copyright year '$last' from '$renDate', '$renNum' ($user)\n";
      my $rid = $crms->PredictRights($id, $renDate, $renNum,
                                     $crms->TolerantCompare($cat, 'Crown Copyright'),
                                     $record, \$pub);
      ($pa, $pr) = $crms->TranslateAttrReasonFromCode($rid);
      $msg .= "   ADD $renDate predicted $pa/$pr (curr $acurr/$rcurr)\n";
      $predictions{$pa} = 1;
      print "Predict $pa from $renDate ($user)\n" if $verbose > 2;
      last if $pa eq 'ic';
      last if $pa eq $acurr;
    }
  }
  if (!$icus && scalar keys %predictions && !defined $predictions{'ic'} &&
      !defined $predictions{'icus'} && (defined $predictions{'pd'} ||
      defined $predictions{'pdus'})
      ||
      ($icus && scalar keys %predictions && !defined $predictions{'ic'} &&
      defined $predictions{'icus'} && !(defined $predictions{'pd'} ||
      defined $predictions{'pdus'})))
  {
    next if !$icus and $predictions{'pdus'} and $acurr =~ m/^pd/;
    next if !$icus and $predictions{'pd'} and $acurr eq 'pd';
    next if $icus and $predictions{'icus'} and $acurr eq 'icus';
    my $msg2 = sprintf "%-20s %s: %s (%s)", $id, $record->author, $record->title, $record->country;
    my $msg3 = sprintf "%-20s (gid $gid, ADD $renDate, pub $pub) predicted %s (curr $acurr/$rcurr) - $time",
                       '', join ', ', sort keys %predictions;
    my $t3 = ($record->country eq 'United Kingdom')? (($crown)? $t1:$t2):$t1;
    print colored($msg2, ($renDate > $t3)? 'red':'black'), "\n";
    print colored($msg3, ($renDate > $t3)? 'red':'black'), "\n";
    if ($renDate > $t3 || $verbose > 1)
    {
      print "$msg";
    }
    if (!$noop)
    {
      $crms->UpdateMetadata($id, 1, $record);
      # Returns a status code (0=Add, 1=Error, 2=Skip, 3=Modify) followed by optional text.
      my $res = $crms->AddItemToQueueOrSetItemActive($id, 3, 1, 'newyear', undef, undef, $record);
      my $code = substr $res, 0, 1;
      my $msg = substr $res, 1;
      if ($code eq '1' || $code eq '2')
      {
        print ($code == 1)? RED:GREEN "Result for $id: $code $msg\n";
      }
    }
    $change++;
  }
}
print "Suggested rereviews: $change of $i\n";

print "Warning: $_\n" for @{$crms->GetErrors()};

