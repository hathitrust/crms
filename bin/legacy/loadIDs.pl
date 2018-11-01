#!/usr/bin/perl

BEGIN 
{ 
  unshift(@INC, $ENV{'SDRROOT'}. '/crms/cgi');
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
my $instance;
my $noop       = $opts{'n'};
my $production = $opts{'p'};
my $user       = $opts{'u'};
my $verbose    = $opts{'v'};
my $sys        = $opts{'x'};

if ($help || scalar @ARGV != 1 || !$user || !$ok)
{
  die $usage;
}
$instance = 'production' if $production;
my $file = $ARGV[0];

my $crms = CRMS->new(
    sys      => $sys,
    verbose  => $verbose,
    instance => $instance
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
    sys      =>   $sys,
    verbose  =>   $verbose,
    instance =>   $instance
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
    GiveItemsInQueuePriority($crms, $id, $now, 0, 1, 'rereport');
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
  SubmitActiveReview($crms, $id, $user, $time, $attr, $reason, $noop);
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

sub GiveItemsInQueuePriority
{
  my $crms     = shift;
  my $id       = lc shift;
  my $time     = shift;
  my $status   = shift;
  my $priority = shift;
  my $source   = shift;

  my $record = $crms->GetMetadata($id);
  my $errs = $crms->GetViolations($id, $record);
  if (scalar @{$errs})
  {
    $crms->SetError(sprintf "$id: %s", join ';', @{$errs});
    return 0;
  }
  my $sql = 'SELECT COUNT(*) FROM queue WHERE id=?';
  my $count = $crms->SimpleSqlGet($sql, $id);
  if ($count == 1)
  {
    $sql = 'UPDATE queue SET priority=1 WHERE id=?';
    $crms->PrepareSubmitSql($sql, $id);
  }
  else
  {
    $sql = 'INSERT INTO queue (id,time,status,priority,src) VALUES (?,?,?,?,?)';
    $crms->PrepareSubmitSql($sql, $id, $time, $status, $priority, $source);
    $crms->UpdateMetadata($id, 1, $record);
    # Accumulate counts for items added at the 'same time'.
    # Otherwise queuerecord will have a zillion kabillion single-item entries when importing
    # e.g. 2007 reviews for reprocessing.
    # We see if there is another ADMINSCRIPT entry for the current time; if so increment.
    # If not, add a new one.
    $sql = 'SELECT itemcount FROM queuerecord WHERE time=? AND src="ADMINSCRIPT" LIMIT 1';
    my $itemcount = $crms->SimpleSqlGet($sql, $time);
    if ($itemcount)
    {
      $itemcount++;
      $sql = 'UPDATE queuerecord SET itemcount=? WHERE time=? AND src="ADMINSCRIPT"';
    }
    else
    {
      $itemcount = 1;
      $sql = 'INSERT INTO queuerecord (itemcount,time,src) values (?,?,"ADMINSCRIPT")';
    }
    $crms->PrepareSubmitSql($sql, $itemcount, $time);
  }
  return 1;
}

## ----------------------------------------------------------------------------
##  Function:   submit a new active review  (single pd review from rights DB)
##  Parameters: Lots of them -- last one does the sanity checks but no db updates
##  Return:     1 || 0
## ----------------------------------------------------------------------------
sub SubmitActiveReview
{
  my $crms = shift;
  my ($id, $user, $date, $attr, $reason, $noop) = @_;

  ## change attr and reason back to numbers
  $attr = $crms->TranslateAttr($attr);
  if (!$attr) { $crms->SetError("bad attr: $attr"); return 0; }
  $reason = $crms->TranslateReason($reason);
  if (!$reason) { $crms->SetError("bad reason: $reason"); return 0; }
  if (!$crms->ValidateAttrReasonCombo($attr, $reason)) { $crms->SetError("bad attr/reason $attr/$reason"); return 0; }
  if (!$crms->CheckReviewer($user, 0))                 { $crms->SetError("reviewer ($user) check failed"); return 0; }
  if (!$noop)
  {
    ## all good, INSERT
    my $sql = 'REPLACE INTO reviews (id,user,time,attr,reason,legacy)' .
              ' VALUES(?,?,?,?,?,1)';
    $crms->PrepareSubmitSql($sql, $id, $user, $date, $attr, $reason);
    $sql = 'UPDATE queue SET pending_status=1,priority=1 WHERE id=?';
    $crms->PrepareSubmitSql($sql, $id);
    #Now load this info into the bibdata table.
    $crms->UpdateMetadata($id, 1);
  }
  return 1;
}
