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

my %opts;
getopts('hnpu:v', \%opts);

my $help       = $opts{'h'};
my $noop       = $opts{'n'};
my $production = $opts{'p'};
my $user       = $opts{'u'};
my $verbose    = $opts{'v'};

if ( $help || scalar @ARGV != 1 || !$user)
{
  die "USAGE: $0 [-h] [-n] [-p] [-v] -u rereport_user tsv_file\n\n";
}
my $file = $ARGV[0];

#print("DLXSROOT: $DLXSROOT DLPS_DEV: $DLPS_DEV\n");

my $crms = CRMS->new(
    logFile      =>   "$DLXSROOT/prep/c/crms/log_IDs.txt",
    configFile   =>   'crms.cfg',
    verbose      =>   $verbose,
    root         =>   $DLXSROOT,
    dev          =>   !$production,
);


open my $fh, $file or die "failed to open $file: $@ \n";

#Ignore ic/ren determinations (4805) and ic/cdpp (255); all pd/cdpp
#(166) will need to be re-reviewed)
#Moses will queue up a sample set of 240* pd/ncn (out of a total 2446)
#determinations as initial reviews) in Dev - queueing for reviewing
#will be random but roughly 2 not reviewed for every one already
#reviewed once (there are still questions on how this will work). 
#When ready put them in the queue in production, let EA staff review;
#Anne & Greg review and calculate error rates and determine next steps-
#COMPLETE BY 9/30/09
#*60 june, 60 aug, 60 oct, 60 dec

# This is for re-reviewing pd determinations from 2007. Ignores non-pd entries.
# If item is already in queue table it will get priority set to 1,
# otherwise an insert will be done in the queue table with prority set to 1.
## This is the format for file; one record per line:
##  barcode sans mdp <tab> attr <tab> reason <tab> original review date:
## 	39015028120130<tab>ic<tab>ren<tab>2007-10-03 12:20:49
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
    my $sql = "SELECT COUNT(id) FROM historicalreviews WHERE id='$id' AND user='rereport01'";
    my $count = $crms->SimpleSqlGet($sql);
    if ($count)
    {
      $counts{'not bk'}++;
      print "Skipping non-us doc $id\n";
      next;
    }
    else
    {
      $yms{"$y-$m"} = 0 unless $yms{"$y-$m"};
      $yms{"$y-$m"}++;
    }
    # Filter out gov docs
    #print "$id\n";
    my $record =  $crms->GetRecordMetadata($id);
    if (!$record)
    {
      $counts{'err'}++;
      print "Can't get metadata for $id; skipping.\n";
      next;
    }
    my $pub = $crms->GetPublDate( $id, $record );
  
    if ( ( $pub lt '1923' ) || ( $pub gt '1963' ) )
    {
      $counts{'date'}++;
      print "Skipping item from $pub $id\n";
      next;
    }
    if ($crms->IsGovDoc( $id, $record ))
    {
      $counts{'gov'}++;
      print "Skipping gov't doc $id\n";
      next;
    }
    if ( !$crms->IsUSPub( $id, $record ) )
    {
      $counts{'not us'}++;
      print "Skipping non-us doc $id\n";
      next;
    }
    if ( ! $crms->IsFormatBK( $id, $record ) )
    {
      $counts{'not bk'}++;
      print "Skipping non-us doc $id\n";
      next;
    }
    #next if $id eq 'mdp.39015001540890';
    $ids{$id} = join '__', ($attr,$reason,$time);
  }
  $linen++;
}
close $fh;
$crms->ClearErrors();
#$crms = CRMS->new(
#    logFile      =>   "$DLXSROOT/prep/c/crms/log_IDs.txt",
#    configFile   =>   'crms.cfg',
#    verbose      =>   $verbose,
#    root         =>   $DLXSROOT,
#    dev          =>   !$production,
#);
$sql = "SELECT COUNT(*) FROM queue WHERE priority=1";
my $already = $crms->SimpleSqlGet($sql);
my $cnt = 0;
my $now = $crms->GetTodaysDate();
foreach my $id (keys %ids)
{
  #last if 1000 == $cnt + $already;
  $sql = "SELECT COUNT(*) FROM queue WHERE id='$id' AND priority=1";
  if ($crms->SimpleSqlGet($sql))
  {
    print "$id is already in the queue for rereview\n" if $verbose;
    $counts{'already'}++;
    next;
  }
  $sql = "SELECT COUNT(*) FROM reviews WHERE id='$id' AND user='$user'";
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

