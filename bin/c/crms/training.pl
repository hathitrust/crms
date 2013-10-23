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
USAGE: $0 [-hnrtv] [-e FILE] [-o FILE] [-x SYS] count

Populates the training database with examples (correct, single reviews) from production.

-e FILE  Write an Excel spreadsheet with information on the volumes to be added.
-h       Print this help message.
-n       Do not submit SQL.
-o       Write a tab-delimited file with information on the volumes to be added.
-r       Randomize sample from production.
-t       Run in training (dev otherwise).
-v       Be verbose.
-x SYS   Set SYS as the system to execute.
END

my $excel;
my $help;
my $noop;
my $random;
my $out;
my $training;
my $verbose;
my $sys;

Getopt::Long::Configure ('bundling');
Getopt::Long::Configure ('bundling');
die 'Terminating' unless GetOptions(
           'e:s'  => \$excel,
           'h'    => \$help,
           'n'    => \$noop,
           'o:s'  => \$out,
           'r'    => \$random,
           't'    => \$training,
           'v'    => \$verbose,
           'x:s'  => \$sys);
           

die "$usage\n\n" if $help;
die "You need a volume count.\n" unless 1 == scalar @ARGV;
my $count = $ARGV[0];
die "Count format should be numeric\n" if $count !~ m/\d+/;

my $crms = CRMS->new(
    logFile      =>   "$DLXSROOT/prep/c/crms/training_hist.txt",
    sys          =>   $sys,
    verbose      =>   $verbose,
    root         =>   $DLXSROOT,
    dev          =>   undef
);

# Connect to training database.
my $crms2 = CRMS->new(
    logFile      =>   "$DLXSROOT/prep/c/crms/training_hist2.txt",
    sys          =>   $sys,
    verbose      =>   $verbose,
    root         =>   $DLXSROOT,
    dev          =>   ($training)? 'crmstest':$DLPS_DEV
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
my $sql = '(SELECT DISTINCT id FROM reviews) UNION DISTINCT (SELECT DISTINCT id FROM historicalreviews)' .
          ' UNION DISTINCT (SELECT id FROM queue)';
my $ref = $crms2->GetDb()->selectall_arrayref($sql);
#$seen{$_->[0]} = 1 for @{$ref};
my $n = 0;

my $orderby = ($random)? 'RAND()':'time DESC';
$sql = 'SELECT id,user,time,gid,status FROM historicalreviews WHERE' .
       ' user IN (SELECT id FROM users WHERE advanced=1 AND extadmin+expert+admin+superadmin=0) AND' . 
       ' validated=1 AND (status=4 OR status=5) ORDER BY ' . $orderby;
$ref = $crms->GetDb()->selectall_arrayref($sql);
print "$sql\n" if $verbose;
my $s4 = 0;
my $s5 = 0;
my @sqls = ();
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
  my $expr = $crms->SimpleSqlGet('SELECT reason FROM exportdata WHERE gid=?', $gid);
  next if $expr eq 'crms';
  $sql = 'SELECT MAX(swiss) FROM historicalreviews WHERE id=?';
  next if 0 < $crms->SimpleSqlGet($sql, $id);
  $sql = 'SELECT reason FROM exportdata WHERE gid=?';
  my $expreason = $crms->SimpleSqlGet($sql, $gid);
  next if $expreason eq 'crms';
  my $record = $crms->GetMetadata($id);
  $sql = "SELECT attr,reason,renDate,renNum,category,note,duration FROM historicalreviews WHERE id='$id' AND user='$user' AND time='$time'";
  my $ref2 = $crms->GetDb()->selectall_arrayref($sql);
  $row = $ref2->[0];
  my $attr = $row->[0];
  my $reason = $row->[1];
  my $renDate = $row->[2];
  my $renNum = $row->[3];
  my $category = $row->[4];
  my $note = $row->[5];
  my $duration = $row->[6];
  $renDate = (defined $renDate)? "'$renDate'":'NULL';
  $renNum = (defined $renNum)? "'$renNum'":'NULL';
  $category = (defined $category)? "'$category'":'NULL';
  $note = (defined $note)? $crms->GetDb()->quote($note):'NULL';
  push @sqls, "INSERT INTO queue (id,time,pending_status) VALUES ('$id','$time',1)";
  push @sqls, 'INSERT INTO reviews (id,user,time,attr,reason,renDate,renNum,category,note,duration) ' .
              "VALUES ('$id','$user','$time',$attr,$reason,$renDate,$renNum,$category,$note,'$duration')";
  $crms2->UpdateMetadata($id, 1) unless $noop;
  if (defined $excel || defined $out)
  {
    my $author = $crms->GetRecordAuthor($id, $record);
    my $title = $crms->GetRecordTitle($id, $record);
    next if $seenAuthors{$author};
    next if $seenTitles{$title};
    $seenAuthors{$author} = 1;
    $seenTitles{$title} = 1;
    my $date = $crms->GetRecordPubDate($id, $record);
    my $country = $crms->GetRecordPubCountry($id, $record);
    my $rights = $crms->TranslateAttr($attr) . '/' . $crms->TranslateReason($reason);
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
}
print "Warning: $_\n" for @{$crms->GetErrors()};
$workbook->close() if $workbook;
close $fh if defined $out;
$crms = $crms2;
foreach $sql (@sqls)
{
  print "$sql\n" if $verbose;
  $crms->PrepareSubmitSql($sql) unless $noop;
}

$sql = "INSERT INTO queuerecord (itemcount,source) VALUES ($n,'training.pl')";
print "$sql\n" if $verbose;
$crms->PrepareSubmitSql($sql) unless $noop;
print "Added $n: $s4 status 4 and $s5 status 5\n";
print "Warning: $_\n" for @{$crms->GetErrors()};

