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
use List::Util qw(shuffle);

my %opts;
getopts('hnu:v', \%opts);

my $help      = $opts{'h'};
my $noop      = $opts{'n'};
my $user      = $opts{'u'};
my $verbose   = $opts{'v'};

if ( $help || scalar @ARGV != 1 || !$user)
{
  die "USAGE: $0 [-h] [-n] [-v] -u rereport_user tsv_file\n\n";
}
my $file = $ARGV[0];

#print("DLXSROOT: $DLXSROOT DLPS_DEV: $DLPS_DEV\n");

my $crms = CRMS->new(
    logFile      =>   "$DLXSROOT/prep/c/crms/log_IDs.txt",
    configFile   =>   'crms.cfg',
    verbose      =>   $verbose,
    root         =>   $DLXSROOT,
    dev          =>   $DLPS_DEV,
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
my @May=();
my @Jun=();
my @Aug=();
my @Oct=();
my @Dec=();
my %bar2Data = ();
my $sql = "SELECT count(*) FROM users WHERE id='$user'";
my $cnt = $crms->SimpleSqlGet($sql);
if (!$cnt)
{
  $sql = "INSERT INTO users (name,type,id) VALUES ('Rereport User',1,'$user')";
  $crms->PrepareSubmitSql($sql);
}
foreach my $line ( <$fh> )
{
  chomp $line;
  next if $line eq '';
  my ($id,$attr,$reason,$time) = split(m/\t/, $line, 4);
  $id = 'mdp.' . $id;
  if ($attr ne 'pd' || $reason ne 'ncn')
  {
    #print "$linen) ignoring $id ($attr/$reason)\n" if $verbose;
  }
  else
  {
    my ($y,$m,$blah) = split '-', $time;
    if ($y eq '2007' && ($m eq '05' || $m eq '06' || $m eq '08' || $m eq '10' || $m eq '12'))
    {
      # Filter out gov docs
      my $record =  $crms->GetRecordMetadata($id);
      if ($crms->IsGovDoc( $id, $record )) { print "Skipping gov't doc $id $m/$y\n"; next; }
      $bar2Data{$id} = join '__', ($attr,$reason,$time);
      push @May, $id if $m eq '05';
      push @Jun, $id if $m eq '06';
      push @Aug, $id if $m eq '08';
      push @Oct, $id if $m eq '10';
      push @Dec, $id if $m eq '12';
    }
  }
  $linen++;
}
printf("May: %d Jun: %d Aug: %d Oct: %d Dec: %d\n", scalar @May, scalar @Jun, scalar @Aug, scalar @Oct, scalar @Dec);
@May = @May[(shuffle(0..$#May))[0..8]];
@Jun = @Jun[(shuffle(0..$#Jun))[0..50]];
@Aug = @Aug[(shuffle(0..$#Aug))[0..59]];
@Oct = @Oct[(shuffle(0..$#Oct))[0..59]];
@Dec = @Dec[(shuffle(0..$#Dec))[0..59]];
printf("May: %d Jun: %d Aug: %d Oct: %d Dec: %d\n", scalar @May, scalar @Jun, scalar @Aug, scalar @Oct, scalar @Dec);
my $cnt = 0;
my %seen = ();
my $now = $crms->GetTodaysDate();
foreach my $id ((@May,@Jun,@Aug,@Oct,@Dec))
{
  die "Duplicate barcode $id!" if exists($seen{$id});
  $seen{$id} = 1;
  my ($attr,$reason,$time) = split '__', $bar2Data{$id};
  printf "%d) updating $id ($attr/$reason) $time\n", $cnt+1 if $verbose;
  $crms->SubmitActiveReview($id, $user, $time, $attr, $reason, $noop);
  my $r = $crms->GetErrors();
  die 'Error: '.join(", ", @{$r}) if scalar @{$r};
  if (!$noop)
  {
    $crms->GiveItemsInQueuePriority($id, $now, 0, 1);
    $r = $crms->GetErrors();
    die 'Error: '.join(", ", @{$r}) if scalar @{$r};
  }
  $cnt++;
}
print "Processed $cnt items\n";
close $fh;

