#!/usr/bin/perl

use strict;
use warnings;
BEGIN { unshift(@INC, $ENV{'SDRROOT'}. '/crms/cgi'); }

use CRMS;
use Getopt::Long qw(:config no_ignore_case bundling);
use Term::ANSIColor qw(:constants);
$Term::ANSIColor::AUTORESET = 1;

my $usage = <<END;
USAGE: $0 [-Ddhnqv] [-x SYS] [-p PROJ [-p PROJ2...]] COUNT

Populates the training database with examples (correct, single reviews)
from production so that the queue size is increased to COUNT.

-D       Delete all existing reviews and volumes in queue.
-d       Run in dev (training otherwise).
-h       Print this help message.
-n       Do not submit SQL.
-p PROJ  Only include reviews on the specified project PROJ. Defaults to 'Core'.
-q       Only bring in queue entries, do not import single review.
-v       Be verbose.
-x SYS   Set SYS as the system to execute.
END

my $del;
my $dev;
my $help;
my $instance;
my $noop;
my @projs;
my $queueOnly;
my $verbose;
my $sys;

Getopt::Long::Configure ('bundling');
die 'Terminating' unless GetOptions(
           'D'    => \$del,
           'd'    => \$dev,
           'h'    => \$help,
           'n'    => \$noop,
           'p:s@' => \@projs,
           'q'    => \$queueOnly,
           'v'    => \$verbose,
           'x:s'  => \$sys);

die "$usage\n\n" if $help;
die "You need a volume count.\n" unless 1 == scalar @ARGV;
my $count = $ARGV[0];
die "Count format should be numeric\n" if $count !~ m/^\d+$/;

my $crmsp = CRMS->new(
    sys          =>   $sys,
    verbose      =>   $verbose,
    instance     =>   'production'
);

# Connect to training database.
my $crmst = CRMS->new(
    sys      => $sys,
    verbose  => $verbose,,
    instance => ($dev)? undef:'crms-training'
);

$crmst->set('noop', 1) if $noop;
if ($verbose)
{
  my $dbinfo = $crmsp->DbInfo();
  print "Production instance: $dbinfo\n";
  $dbinfo = $crmst->DbInfo();
  print "Training instance: $dbinfo\n";
  
}
my %seen;
my %seenAuthorTitles;
my %seenSysids;
if ($del)
{
  print "Deleting reviews and emptying queue...\n" if $verbose;
  $crmst->PrepareSubmitSql('DELETE from queue');
  $crmst->PrepareSubmitSql('DELETE from reviews');
}
else
{
  ### Get a list of ids from the training DB already seen,
  ### and populate the 'seen' hash with them.
  my $sql = 'SELECT q.id,b.sysid,b.author,b.title FROM queue q'.
            ' INNER JOIN bibdata b ON q.id=b.id';
  my $ref = $crmst->SelectAll($sql);
  foreach my $row (@{$ref})
  {
    my $id = $row->[0];
    my $sysid = $row->[1];
    my $a = $row->[2] || '';
    my $t = $row->[3] || '';
    my $at = $a . $t;
    $at =~ s/[^A-Za-z0-9]//g;
    print "Updating seen filters for existing $id ($sysid) $at\n" if $verbose;
    $seen{$id} = 1;
    $seenSysids{$sysid} = 1;
    $seenAuthorTitles{$at} = 1 if length $at;
  }
}
my $n = 0;
my $usql = '(SELECT id FROM users WHERE reviewer=1 AND expert+admin=0)';
@projs = ('Core') unless scalar @projs;
my $projsql = sprintf 'p.name IN ("%s")', join '","', @projs;
my $sql = 'SELECT r.id,r.user,r.time,e.status,p.name FROM historicalreviews r'.
          ' INNER JOIN exportdata e ON r.gid=e.gid'.
          ' INNER JOIN projects p ON e.project=p.id'.
          ' WHERE r.user IN '. $usql.
          ' AND '. $projsql.
          ' AND e.ticket IS NULL'.
          ' AND r.validated=1 AND (e.status=4 OR e.status=5 OR e.status=7)'.
          ' ORDER BY r.time DESC';

my $ref = $crmsp->SelectAll($sql);
printf "$sql: %s results\n", (defined $ref)? scalar @$ref:'no' if $verbose;
my $s4 = 0;
my $s5 = 0;
my $s7 = 0;
$sql = 'SELECT COUNT(*) FROM queue q'.
       ' INNER JOIN projects p ON q.project=p.id'.
       ' AND '. $projsql;
print "$sql\n" if $verbose;
my $already = $crmst->SimpleSqlGet($sql);
$count -= $already;
print "Need $count volumes ($already already in queue)\n" if $verbose;
foreach my $row (@{$ref})
{
  my $id = $row->[0];
  last if $n >= $count;
  my $record = $crmsp->GetMetadata($id);
  next unless defined $record;
  my $sysid = $record->sysid;
  my $a = $record->author || '';
  my $t = $record->title || '';
  my $at = $a . $t;
  $at =~ s/[^A-Za-z0-9]//g;
  if ($seen{$id})
  {
    print RED "Skipping $id, it has been seen\n" if $verbose;
    next;
  }
  if ($seenSysids{$sysid})
  {
    print RED "Skipping $id, sysid has been seen ($sysid)\n" if $verbose;
    next;
  }
  if ($seenAuthorTitles{$t})
  {
    print RED "Skipping $id, author/title has been seen ($t)\n" if $verbose;
    next;
  }
  $seen{$id} = 1;
  $seenSysids{$sysid} = 1;
  $seenAuthorTitles{$at} = 1 if length $at;
  my $user   = $row->[1];
  my $time   = $row->[2];
  my $status = $row->[3];
  my $proj   = $row->[4];
  # Disallow swissed volumes.
  $sql = 'SELECT COUNT(*) FROM historicalreviews WHERE id=? AND swiss=1';
  if (0 < $crmsp->SimpleSqlGet($sql, $id))
  {
    print RED "Skipping swissed $id\n" if $verbose;
    next;
  }
  $sql = 'SELECT COALESCE(id,1) FROM projects WHERE name=?';
  my $projt = $crmst->SimpleSqlGet($sql, $proj);
  die "Can't get training instance project id for $proj\n" unless defined $projt;
  print GREEN "Add to queue: $id for project $proj\n" if $verbose;
  my $pending = ($queueOnly)? 0:1;
  $sql = 'INSERT INTO queue (id,time,pending_status,project) VALUES (?,?,?,?)';
  $crmst->PrepareSubmitSql($sql, $id, $time, $pending, $projt);
  if (!$queueOnly)
  {
    $sql = 'SELECT attr,reason,renDate,renNum,category,note'.
         ' FROM historicalreviews WHERE id=? AND user=? AND time=?';
    my $ref2 = $crmsp->SelectAll($sql, $id, $user, $time);
    $row = $ref2->[0];
    my $attr = $row->[0];
    my $reason = $row->[1];
    my $renDate = $row->[2];
    my $renNum = $row->[3];
    my $category = $row->[4];
    my $note = $row->[5];
    my $ta = $crmst->TranslateAttr($attr);
    my $tr = $crmst->TranslateReason($reason);
    print "  $user ($ta/$tr) status $status ($time)\n" if $verbose;
    $sql = 'INSERT INTO reviews (id,user,time,attr,reason,renDate,renNum,category,note)'.
           'VALUES (?,?,?,?,?,?,?,?,?)';
    $crmst->PrepareSubmitSql($sql, $id, $user, $time, $attr, $reason,
                            $renDate, $renNum, $category, $note);
  }
  $crmst->UpdateMetadata($id, 1, $record);
  $n++;
  $s4++ if $status == 4;
  $s5++ if $status == 5;
  $s7++ if $status == 7;
}

$sql = 'INSERT INTO queuerecord (itemcount,source) VALUES (?,"training.pl")';
$crmst->PrepareSubmitSql($sql, $n);
print "Added $n: $s4 status 4, $s5 status 5, $s7 status 7\n";
print "Warning: $_\n" for @{$crmsp->GetErrors()};
print "Warning: $_\n" for @{$crmst->GetErrors()};

