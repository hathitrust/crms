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

my $usage = <<END;
USAGE: $0 [-hnpvx:] -u USER TSV_FILE

Imports reviews for a rereview project from TSV_FILE.

-h       Print this help message.
-n       Do not update the database.
-p       Run in production.
-u USER  Add reviews by this user ID.
-v       Be verbose.
-x SYS   Set SYS as the system to execute.

The TSV_FILE has one record per line (spacing added for clarity):

volume id sans mdp <tab> attr <tab> reason <tab> original review date
39015028120130     <tab>  ic  <tab> ren    <tab> 2007-10-03 12:20:49
END

my %opts;
my $ok = getopts('hnpu:vx:', \%opts);

my $help       = $opts{'h'};
my $noop       = $opts{'n'};
my $production = $opts{'p'};
my $user       = $opts{'u'};
my $verbose    = $opts{'v'};
my $sys        = $opts{'x'};

if ($help || scalar @ARGV != 1 || !$user || !$ok)
{
  die $usage;
}
$DLPS_DEV = undef if $production;
my $file = $ARGV[0];

my $crms = CRMS->new(
    logFile => "$DLXSROOT/prep/c/crms/log_IDs.txt",
    sys     => $sys,
    verbose => $verbose,
    root    => $DLXSROOT,
    dev     => $DLPS_DEV
);

open my $fh, $file or die "failed to open $file: $@ \n";

my $cnt = 0;
my $linen = 1;
my %ids=();
my $sql = "SELECT count(*) FROM users WHERE id='$user'";
my $cnt = $crms->SimpleSqlGet($sql);
if (!$cnt)
{
  $sql = "INSERT INTO users (name,type,id) VALUES ('Rereport User',1,'$user')";
  print "$sql\n" if $verbose;
  $crms->PrepareSubmitSql($sql);
}
my %yms;
my %counts = ('date' => 0, 'not us' => 0, 'not bk' => 0, 'already' => 0, 'err' => 0,
              'gov' => 0, 'pd/ren' => 0, 'pd/ncn' => 0);
foreach my $line ( <$fh> )
{
  chomp $line;
  next if $line =~ m/^\s*$/;
  my ($id,$attr,$reason,$time) = split(m/\t/, $line, 4);
  $id = 'mdp.' . $id;
  if ($attr eq 'pd' && ($reason eq 'ncn' || $reason eq 'ren'))
  {
    my ($y,$m,$blah) = split '-', $time;
    my $sql = "SELECT COUNT(*) FROM reviews WHERE id='$id' AND user='$user'";
    if ($crms->SimpleSqlGet($sql))
    {
      print "$id has already been rereviewed\n" if $verbose;
      $counts{'already'}++;
      next;
    }
    $sql = "SELECT COUNT(*) FROM historicalreviews WHERE id='$id' AND user LIKE 'rereport%'";
    if ($crms->SimpleSqlGet($sql))
    {
      print "$id has already been rereviewed (historical)\n" if $verbose;
      $counts{'already'}++;
      next;
    }
    $sql = "SELECT COUNT(*) FROM queue WHERE id='$id' AND priority=1";
    if ($crms->SimpleSqlGet($sql))
    {
      print "$id is already in the queue for rereview\n" if $verbose;
      $counts{'already'}++;
      next;
    }
    # Filter out gov docs
    #print "$id\n";
    my $record =  $crms->GetMetadata($id);
    if (!$record)
    {
      $counts{'err'}++;
      print "Can't get metadata for $id; skipping.\n";
      next;
    }
    my $pub = $crms->GetRecordPubDate($id, $record);
  
    if ( ( $pub lt '1923' ) || ( $pub gt '1963' ) )
    {
      $counts{'date'}++;
      print "Skipping item from $pub $id\n";
      next;
    }
    if ($crms->IsGovDoc($id, $record))
    {
      $counts{'gov'}++;
      print "Skipping gov't doc $id\n";
      next;
    }
    if ( $crms->IsForeignPub($id, $record) )
    {
      $counts{'not us'}++;
      print "Skipping non-us doc $id\n";
      next;
    }
    if ( ! $crms->IsFormatBK($id, $record) )
    {
      $counts{'not bk'}++;
      print "Skipping non-us doc $id\n";
      next;
    }
    $yms{"$y-$m"} = 0 unless $yms{"$y-$m"};
    $yms{"$y-$m"}++;
    $ids{$id} = join '__', ($attr,$reason,$time);
  }
  $linen++;
}
close $fh;
$crms = CRMS->new(
    logFile  =>   "$DLXSROOT/prep/c/crms/log_IDs.txt",
    sys      =>   $sys,
    verbose  =>   $verbose,
    root     =>   $DLXSROOT,
    dev      =>   $DLPS_DEV
);
$sql = "SELECT COUNT(*) FROM queue WHERE priority=1";
my $already = $crms->SimpleSqlGet($sql);
my $cnt = 0;
my $now = $crms->GetTodaysDate();
foreach my $id (keys %ids)
{
  my ($attr,$reason,$time) = split '__', $ids{$id};
  printf "%d) updating $id ($attr/$reason) $time\n", $cnt+1 if $verbose;
  if (!$noop)
  {
    $crms->GiveItemsInQueuePriority($id, $now, 0, 1, 'rereport');
    my $r = $crms->GetErrors();
    if (scalar @{$r})
    {
      $counts{'err'}++;
      printf "Error: %s\n", join("; ", @{$r});
    }
    $crms->ClearErrors();
    next if scalar @{$r};
    $counts{"$attr/$reason"}++;
  }
  $crms->SubmitActiveReview($id, $user, $time, $attr, $reason, $noop);
  my $r = $crms->GetErrors();
  printf "Error: %s\n", join("; ", @{$r}) if scalar @{$r};
  $crms->ClearErrors();
  next if scalar @{$r};
  $cnt++;
}
foreach my $ym (sort keys %yms)
{
  printf "$ym: %s volumes\n", $yms{$ym};
}
print "Added $cnt items\n";
foreach my $reason (sort keys %counts)
{
  printf "$reason: %s volumes\n", $counts{$reason};
}

