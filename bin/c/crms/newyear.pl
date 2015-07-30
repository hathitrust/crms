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
USAGE: $0 [-hipv] [-e VOL_ID [-e VOL_ID2...]]
       [-s VOL_ID [-s VOL_ID2...]] [-x SYS] [-y YEAR]

Reports on determinations that may now, as of the new year, have had the copyright
expire.

-e VOL_ID  Exclude VOL_ID from being considered.
-h         Print this help message.
-i         Insert priority 3 re-reviews in the queue for volumes identified.
-p         Run in production.
-s VOL_ID  Report only for HT volume VOL_ID. May be repeated for multiple volumes.
-v         Emit debugging information.
-x SYS     Set SYS as the system to execute.
-y YEAR    Use this year instead of the current one (-i option is disabled).
END

my @excludes;
my $help;
my $insert;
my $production;
my @singles;
my $verbose;
my $sys;
my $year;

Getopt::Long::Configure ('bundling');
die 'Terminating' unless GetOptions(
           'e:s@' => \@excludes,
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

$year = $crms->GetTheYear() unless $year;
my $t1 = $year - 51;
my $t2 = $year - 71;
my $sql = 'SELECT id,gid FROM exportdata ' .
          ' WHERE (attr="pdus" OR (attr="ic" AND reason="add") OR attr="icus")' .
          ' AND exported=1 AND src="candidates"';
if (scalar @singles)
{
  $sql .= sprintf(" AND id IN ('%s')", join "','", @singles);
}
if (scalar @excludes)
{
  $sql .= sprintf(" AND NOT id IN ('%s')", join "','", @excludes);
}
$sql .= ' ORDER BY time DESC';
my $ref = $crms->SelectAll($sql);
my %seen;
my $i = 0;
my $change = 0;
foreach my $row (@{$ref})
{
  my $id = $row->[0];
  next if $seen{$id};
  my $rq = $crms->RightsQuery($id, 1);
  my ($acurr,$rcurr,$src,$usr,$time,$note) = @{$rq->[0]};
  $i++;
  my $gid = $row->[1];
  #print "$i: $id\n";
  $seen{$id} = 1;
  my $pub = $crms->GetPubDate($id);
  if ($pub + 140 < $year && $pub > 0)
  {
    print "$id: pub date $pub\n" if $verbose > 1;
    $change++;
    next;
  }
  $sql = 'SELECT renDate,renNum,category,note FROM historicalreviews WHERE gid=?' .
         ' AND validated=1 AND renDate IS NOT NULL';
  #print "$sql\n";
  my $ref2 = $crms->SelectAll($sql, $gid);
  my $same = 1;
  my $n = scalar @{$ref2};
  next unless $n > 0;
  my %predictions;
  my $pa;
  my $pr;
  my $renDate;
  foreach my $row2 (@{$ref2})
  {
    my %dates = ();
    $renDate = $row2->[0];
    $dates{$renDate} = 1;
    my $renNum = $row2->[1];
    my $cat = $row2->[2];
    my $note = $row2->[3];
    my @matches = $note =~ /(?<!\d)1\d\d\d(?![\d\-])/g;
    foreach my $match (@matches)
    {
      #print "Match on '$match'\n" if $verbose > 2;
      $dates{$match} = 1 if length $match and $match < $year;
    }
    foreach $renDate (sort keys %dates)
    {
      my $last = $crms->PredictLastCopyrightYear($id, $renDate, $renNum,
                                                 $crms->TolerantCompare($cat, 'Crown Copyright'));
      print "$id: last copyright year '$last' from '$renDate', '$renNum'\n" if $verbose > 1;
      my $rid = $crms->PredictRights($id, $renDate, $renNum, $crms->TolerantCompare($cat, 'Crown Copyright'));
      $pa = $crms->TranslateAttr($crms->SimpleSqlGet("SELECT attr FROM rights WHERE id=$rid"));
      $pr = $crms->TranslateReason($crms->SimpleSqlGet("SELECT reason FROM rights WHERE id=$rid"));
      print "$id: ($renDate) predicted $pa/$pr (curr $acurr/$rcurr)\n" if $verbose > 1;
      $predictions{$pa} = 1;
      last if $pa =~ 'ic';
    }
  }
  if (scalar keys %predictions && !defined $predictions{'ic'} &&
      !defined $predictions{'icus'} && (defined $predictions{'pd'} ||
      defined $predictions{'pdus'}))
  {
    next if defined $predictions{'pdus'} and $acurr eq 'pdus';
    next if defined $predictions{'pd'} and $acurr eq 'pd';
    my $msg = sprintf "%-24s ($renDate) predicted %s (currently $acurr/$rcurr)",
                      $id, join ', ', sort keys %predictions if $verbose;
    print colored($msg, ($renDate > $t2)? 'red':'black'), "\n";
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

print "Warning: $_\n" for @{$crms->GetErrors()};

