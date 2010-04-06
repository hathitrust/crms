#!/l/local/bin/perl

# This script can be run from crontab; it 

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
getopts('hnpt:v', \%opts);

my $help       = $opts{'h'};
my $noop       = $opts{'n'};
my $production = $opts{'p'};
my $time       = $opts{'t'};
my $verbose    = $opts{'v'};

$time = 10800 unless $time;

if ($help)
{
  die "USAGE: $0 [-h] [-n] [-p] [-t secs_to_run] [-v]\n\n";
}

my $file = $ARGV[0];

my $crms = CRMS->new(
    logFile      =>   "$DLXSROOT/prep/c/crms/und_hist.txt",
    configFile   =>   "$DLXSROOT/bin/c/crms/crms.cfg",
    verbose      =>   $verbose,
    root         =>   $DLXSROOT,
    dev          =>   !$production
);
my $done = 0;
my $of = 0;
$SIG{ALRM} = sub { print "Signal received!\n" if $verbose; $done = 1;};
my %und = ();
my %times = ();
alarm($time);
my $sql = 'SELECT id,time FROM candidates WHERE checked=0';
my $ref = $crms->get('dbh')->selectall_arrayref($sql);
foreach my $row ( @{$ref} )
{
  last if $done;
  my $id = $row->[0];
  my $time = $row->[1];
  $of++;
  print "Checking $id\n" if $verbose;
  my $record = $crms->GetRecordMetadata($id);
  if ($record)
  {
    my $lang = $crms->GetPubLanguage($id, $record);
    if ($lang && 'eng' ne $lang && '###' ne $lang && '|||' ne $lang && 'zxx' ne $lang && 'mul' ne $lang && 'sgn' ne $lang && 'und' ne $lang)
    {
      $und{$id} = 'language';
      $times{$id} = $time;
      next;
    }
    elsif ($crms->IsThesis($id, $record))
    {
      $und{$id} = 'dissertation';
      $times{$id} = $time;
      next;
    }
    elsif ($crms->IsTranslation($id, $record))
    {
      $und{$id} = 'translation';
      $times{$id} = $time;
      next;
    }
    elsif ($crms->IsForeignPub($id, $record))
    {
      $und{$id} = 'foreign';
      $times{$id} = $time;
      next;
    }
    $sql = "UPDATE candidates SET checked=1 WHERE id='$id'";
    $crms->PrepareSubmitSql($sql) unless $noop;
  }
}

my $n = scalar keys %und;
my %counts = ('language' => 0, 'dissertation' => 0, 'translation' => 0, 'foreign' => 0);
foreach my $id (keys %und)
{
  my $src = $und{$id};
  my $time = $times{$id};
  $counts{$src}++;
  print "$id ($src)\n";
  my $sql = "REPLACE INTO und (id,src,time) VALUES ('$id','$src','$time')";
  $crms->PrepareSubmitSql($sql) unless $noop;
  $sql = "DELETE FROM candidates WHERE id='$id'";
  $crms->PrepareSubmitSql($sql) unless $noop;
}
my $pct = 0.0;
eval { $pct = 100.0 * $n / $of; };
printf "Removed $n of $of (%0.2f%%)\n", $pct;
foreach my $src (sort keys %counts)
{
  printf "$src: %d\n", $counts{$src};
}

my $r = $crms->GetErrors();
foreach my $w (@{$r})
{
  print "Warning: $w\n";
}

