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
USAGE: $0 [-achinpuv] [-s VOL_ID [-s VOL_ID2...]]
          [-x SYS] [start_date [end_date]]

Reports on volumes that are no longer eligible for candidacy in the rights database
and removes them from the system.

-a         Report on all volumes, ignoring date range.
-c         Run against candidates.
-f         Run against single volume ids in a text file.
-h         Print this help message.
-i         Run the candidates population logic over volumes in the rights database
           for the date range given (if any).
-j         Only consider ic and op volumes in rights_current when the -i flag is set.
-n         No-op; reports what would be done but do not modify the database.
-p         Run in production.
-s VOL_ID  Report only for HT volume VOL_ID. May be repeated for multiple volumes.
-u         Run against the und table, unfiltering where necessary.
-v         Emit debugging information.
-x SYS     Set SYS as the system to execute.
END

my $all;
my $candidates;
my $file;
my $help;
my $init;
my $iconly;
my $noop;
my $production;
my @singles;
my $und;
my $verbose;
my $sys;

Getopt::Long::Configure ('bundling');
die 'Terminating' unless GetOptions(
           'a'    => \$all,
           'c'    => \$candidates,
           'f:s'  => \$file,
           'h|?'  => \$help,
           'i'    => \$init,
           'j'    => \$iconly,
           'n'    => \$noop,
           'p'    => \$production,
           's:s@' => \@singles,
           'u'    => \$und,
           'v+'   => \$verbose,
           'x:s'  => \$sys);
$DLPS_DEV = undef if $production;
die "$usage\n\n" if $help;

my $crms = CRMS->new(
    logFile      =>   $DLXSROOT . '/prep/c/crms/candidatespurge_hist.txt',
    sys          =>   $sys,
    verbose      =>   $verbose,
    root         =>   $DLXSROOT,
    dev          =>   $DLPS_DEV
);

if ($file)
{
  if (open(my $fh, '<:encoding(UTF-8)', $file))
  {
    while (my $row = <$fh>)
    {
      chomp $row;
      push @singles, $row;
    }
    close($fh);
  }
}
print "Verbosity $verbose\n" if $verbose;
my $dbh = $crms->GetDb();
my $start = $crms->SimpleSqlGet('SELECT DATE(NOW())');
my $end = $start;
if (scalar @ARGV)
{
  $start = $ARGV[0];
  die "Bad date format ($start); should be in the form e.g. 2010-08-29" unless $start =~ m/^\d\d\d\d-\d\d-\d\d$/;
  if (scalar @ARGV > 1)
  {
    $end = $ARGV[1];
    die "Bad date format ($end); should be in the form e.g. 2010-08-29" unless $end =~ m/^\d\d\d\d-\d\d-\d\d$/;
  }
}

my $before = $crms->GetCandidatesSize();
if ($candidates)
{
  print "Checking candidates...\n";
  CheckTable('candidates', $all, $start, $end, \@singles);
}
if ($und)
{
  print "Checking und...\n";
  CheckTable('und', $all, $start, $end, \@singles);
}
if ($init)
{
  print "Checking rights DB...\n";
  Init($all, $start, $end, \@singles);
}
if (!$noop)
{
  my $after = $crms->GetCandidatesSize();
  printf "Change to candidates: %d\n", $after-$before;
  my $sql = 'INSERT INTO candidatesrecord (addedamount) VALUES (?)';
  $crms->PrepareSubmitSql($sql, $after-$before);
}

sub CheckTable
{
  my $table   = shift;
  my $all     = shift;
  my $start   = shift;
  my $end     = shift;
  my $singles = shift;
  
  my $sql = 'SELECT id FROM ' . $table;
  my @restrict = ();
  push @restrict, 'src!="gov"' if $table eq 'und';
  push @restrict, "(time>'$start 00:00:00' AND time<='$end 23:59:59')" unless $all;
  $sql .= ' WHERE ' . join ' AND ', @restrict if scalar @restrict;
  $sql .= ' ORDER BY time ASC';
  my @singles = @{$singles};
  if (@singles && scalar @singles)
  {
    $sql = sprintf("SELECT id FROM $table WHERE id in ('%s') ORDER BY id", join "','", @singles);
  }
  print "$sql\n" if $verbose > 0;
  my $ref = $dbh->selectall_arrayref($sql);
  foreach my $row (@{$ref})
  {
    my $id = $row->[0];
    print "$id\n" if $verbose > 1;
    $crms->CheckAndLoadItemIntoCandidates($id, $noop, 1);
  }
}

sub Init
{
  my $all     = shift;
  my $start   = shift;
  my $end     = shift;
  my $singles = shift;

  if (defined $singles && scalar @{$singles})
  {
    foreach my $id (@{$singles})
    {
      my ($n,$i) = split m/\./, $id;
      $crms->CheckAndLoadItemIntoCandidates($id, $noop);
    }
  }
  else
  {
    my $sql = 'SELECT namespace,id,DATE(time) FROM rights_current';
    my @restrict = ();
    push @restrict, "(time>'$start 00:00:00' AND time<='$end 23:59:59')" unless $all;
    push @restrict, '((attr=2 AND reason=1) OR (attr=3 AND reason=10))' if $iconly;
    $sql .= ' WHERE ' . join ' AND ', @restrict if scalar @restrict;
    $sql .= ' ORDER BY time ASC';
    my $ref = $crms->GetSdrDb()->selectall_arrayref($sql);
    my $of = scalar @{$ref};
    print "$sql: $of results\n" if $verbose > 0;
    my $lastWhen = '';
    for (my $i = 0; $i < $of; $i++)
    {
      my $row = $ref->[$i];
      my $id = $row->[0] . '.' . $row->[1];
      my $when = $row->[2];
      print "$when\n" if $verbose && $lastWhen ne $when;
      $lastWhen = $when;
      print "$id ($i/$of)\n" if $verbose > 1;
      $crms->CheckAndLoadItemIntoCandidates($id, $noop);
    }
  }
}

print "Warning: $_\n" for @{$crms->GetErrors()};
