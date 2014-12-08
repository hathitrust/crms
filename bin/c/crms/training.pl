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
use Spreadsheet::WriteExcel;

my $usage = <<END;
USAGE: $0 [-dhnrv] [-e FILE] [-o FILE] [-x SYS]
          [-p PRI [-p PRI2...]] count

Populates the training database with examples (correct, single reviews) from production.

-a       Allow status 7 reviews from non-advanced reviewers.
-d       Run in dev (training otherwise).
-e FILE  Write an Excel spreadsheet with information on the volumes to be added.
-h       Print this help message.
-n       Do not submit SQL.
-o       Write a tab-delimited file with information on the volumes to be added.
-p PRI   Only include reviews of the specified priority PRI
-r       Randomize sample from production.
-v       Be verbose.
-x SYS   Set SYS as the system to execute.
END

my $noadvanced;
my $dev;
my $excel;
my $help;
my $noop;
my $out;
my @pris;
my $random;
my $verbose;
my $sys;

Getopt::Long::Configure ('bundling');
die 'Terminating' unless GetOptions(
           'a'    => \$noadvanced,
           'd'    => \$dev,
           'e:s'  => \$excel,
           'h'    => \$help,
           'n'    => \$noop,
           'o:s'  => \$out,
           'p:s@' => \@pris,
           'r'    => \$random,
           'v'    => \$verbose,
           'x:s'  => \$sys);
           

die "$usage\n\n" if $help;
die "You need a volume count.\n" unless 1 == scalar @ARGV;
my $count = $ARGV[0];
die "Count format should be numeric\n" if $count !~ m/\d+/;

my $crmsp = CRMS->new(
    logFile      =>   "$DLXSROOT/prep/c/crms/training_hist.txt",
    sys          =>   $sys,
    verbose      =>   $verbose,
    root         =>   $DLXSROOT,
    dev          =>   undef
);

# Connect to training database.
my $crmst = CRMS->new(
    logFile      =>   "$DLXSROOT/prep/c/crms/training_hist2.txt",
    sys          =>   $sys,
    verbose      =>   $verbose,
    root         =>   $DLXSROOT,
    dev          =>   ($dev)? $DLPS_DEV:'crms-training'
);


my $workbook;
my $worksheet;
my @cols = ('ID', 'Author', 'Title', 'Pub Date', 'Country', 'User', 'Date', 'Category', 'Rights');
if (defined $excel)
{
  $workbook = Spreadsheet::WriteExcel->new($excel);
  $worksheet = $workbook->add_worksheet();
  $worksheet->write_string(0, $_, $cols[$_]) for (0 .. scalar @cols);
}
my $fh;
if (defined $out)
{
  open $fh, '>', $out or die "Can't open output file\n";
  binmode($fh, ':utf8');
  print $fh join "\t", @cols;
}
### Get a list of ids from the training DB already seen,
### and populate the 'seen' hash with them.
my %seen;
my %seenAuthors;
my %seenTitles;
#my $sql = '(SELECT DISTINCT id FROM reviews) UNION DISTINCT (SELECT DISTINCT id FROM historicalreviews)' .
#          ' UNION DISTINCT (SELECT id FROM queue)';
#my $ref = $crmst->SelectAll($sql);
#$seen{$_->[0]} = 1 for @{$ref};
my $n = 0;
my $usql = sprintf '(SELECT id FROM users WHERE %s=1'.
                   ' AND extadmin+expert+admin+superadmin=0)',
                   ($noadvanced)?'reviewer':'advanced';
my $ssql = 'status=4 OR status=5';
$ssql .= ' OR status=7' if $noadvanced;
my $prisql = '';
$prisql = sprintf ' AND priority IN (%s)', join ',', @pris if scalar @pris;
my $orderby = ($random)? 'RAND()':'time DESC';
my $sql = 'SELECT id,user,time,gid,status FROM historicalreviews WHERE' .
          ' user IN '. $usql.
          ' AND validated=1 AND ('. $ssql. ')'.
          $prisql .  ' ORDER BY ' . $orderby;
my $ref = $crmsp->SelectAll($sql);
printf "$sql: %d results\n", scalar @$ref if $verbose;
my $s4 = 0;
my $s5 = 0;
my $s7 = 0;
foreach my $row (@{$ref})
{
  my $id = $row->[0];
  print "$id\n" if $verbose;
  last if $n >= $count;
  if ($seen{$id})
  {
    print "Skipping $id, it has been seen (n is $n)\n" if $verbose;
    next;
  }
  $seen{$id} = 1;
  my $user   = $row->[1];
  my $time   = $row->[2];
  my $gid    = $row->[3];
  my $status = $row->[4];
  # Do not do nonmatching 'crms' status 4s.
  my $expr = $crmsp->SimpleSqlGet('SELECT reason FROM exportdata WHERE gid=?', $gid);
  next if $expr eq 'crms';
  $sql = 'SELECT MAX(swiss) FROM historicalreviews WHERE id=?';
  next if 0 < $crmsp->SimpleSqlGet($sql, $id);
  $sql = 'SELECT reason FROM exportdata WHERE gid=?';
  my $expreason = $crmsp->SimpleSqlGet($sql, $gid);
  next if $expreason eq 'crms';
  my $record = $crmsp->GetMetadata($id);
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
  $sql = 'INSERT INTO queue (id,time,pending_status) VALUES (?,?,1)';
  $crmst->PrepareSubmitSql($sql, $id, $time) unless $noop;
  $sql = 'INSERT INTO reviews (id,user,time,attr,reason,renDate,renNum,category,note)'.
         'VALUES (?,?,?,?,?,?,?,?,?)';
  $crmst->PrepareSubmitSql($sql, $id, $user, $time, $attr, $reason,
                          $renDate, $renNum, $category, $note) unless $noop;
  $crmst->UpdateMetadata($id, 1) unless $noop;
  if (defined $excel || defined $out)
  {
    my $author = $crmst->GetRecordAuthor($id, $record);
    my $title = $crmst->GetRecordTitle($id, $record);
    next if $seenAuthors{$author};
    next if $seenTitles{$title};
    $seenAuthors{$author} = 1;
    $seenTitles{$title} = 1;
    my $date = $crmst->GetRecordPubDate($id, $record);
    my $country = $crmst->GetRecordPubCountry($id, $record);
    my $rights = $crmst->TranslateAttr($attr) . '/' . $crmst->TranslateReason($reason);
    $category = $row->[4];
    if (defined $out)
    {
      print $fh join "\t", ($id, $author, $title, $date, $country, $user, $time, $category, $rights);
    }
    if (defined $excel)
    {
      $worksheet->write_string($n+1, 0, $id);
      $worksheet->write_string($n+1, 1, $author);
      $worksheet->write_string($n+1, 2, $title);
      $worksheet->write_string($n+1, 3, $date);
      $worksheet->write_string($n+1, 4, $country);
      $worksheet->write_string($n+1, 5, $user);
      $worksheet->write_string($n+1, 6, $time);
      $worksheet->write_string($n+1, 7, $category);
      $worksheet->write_string($n+1, 8, $rights);
    }
  }
  $n++;
  $s4++ if $status == 4;
  $s5++ if $status == 5;
  $s7++ if $status == 7;
}
$workbook->close() if $workbook;
close $fh if defined $out;
$sql = 'INSERT INTO queuerecord (itemcount,source) VALUES (?,"training.pl")';
print "$sql\n" if $verbose;
$crmst->PrepareSubmitSql($sql, $n) unless $noop;
print "Added $n: $s4 status 4, $s5 status 5, $s7 status 7\n";
print "Warning: $_\n" for @{$crmsp->GetErrors()};
print "Warning: $_\n" for @{$crmst->GetErrors()};

