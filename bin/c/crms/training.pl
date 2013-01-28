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

my $usage = <<END;
USAGE: $0 [-hntv5] [-x SYS] count

Populates the training database with examples (correct, single reviews) from production.

-h       Print this help message.
-n       Do not submit SQL.
-t       Run in training (dev otherwise).
-v       Be verbose.
-x SYS   Set SYS as the system to execute.
-5       Do only status 5 reviews.
END

my $help;
my $noop;
my $training;
my $verbose;
my $sys;
my $five;

Getopt::Long::Configure ('bundling');
Getopt::Long::Configure ('bundling');
die 'Terminating' unless GetOptions(
           'h'    => \$help,
           'n'    => \$noop,
           't'    => \$training,
           'v'    => \$verbose,
           'x:s'  => \$sys,
           '5'    => \$five);
           

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
    logFile      =>   "$DLXSROOT/prep/c/crms/duplicates_hist.txt",
    sys          =>   $sys,
    verbose      =>   $verbose,
    root         =>   $DLXSROOT,
    dev          =>   ($training)? 'crmstest':$DLPS_DEV
);



### Get a list of ids from the training DB already seen,
### and populate the 'seen' hash with them.
my %seen;
my $sql = '(select distinct id from reviews) union distinct (select distinct id from historicalreviews)';
my $ref = $crms2->GetDb()->selectall_arrayref($sql);
$seen{$_->[0]} = 1 for @{$ref};
my $n = 0;

my $fivesql = ($five)? ' AND status=5':'';
$sql = 'SELECT id,user,time,gid,status FROM historicalreviews WHERE ' .
       'user IN (SELECT id FROM users WHERE advanced=1 AND extadmin+expert+admin+superadmin=0) AND ' . 
       "validated=1 $fivesql ORDER BY time DESC";
if ($verbose)
{
  print "$sql\n";
  print "<!DOCTYPE html PUBLIC '-//W3C//DTD XHTML 1.0 Transitional//EN' 'http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd'>\n" .
        '<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en"><head>' .
        "<meta http-equiv='Content-Type' content='text/html; charset=utf-8'/>\n" .
        "<title>Duplicate volumes with differing rights</title></head><body>\n" .
        "<table border='1'>\n" .
        '<tr><th>ID</th><th>Title</th><th>Author</th><th>PubDate</th><th>Review&nbsp;Date</th><th>Status</th>' .
        '<th>User</th><th>Attr</th><th>Reason</th><th>Ren&nbsp;Date</th><th>Ren&nbsp;Num</th><th>Category</th>' .
        '<th>Note</th><th>Validated</th><th>Importing</th></tr>' .
        "\n";
}
$ref = $crms->GetDb()->selectall_arrayref($sql);

my $s4 = 0;
my $s5 = 0;
my @sqls = ();
foreach my $row (@{$ref})
{
  my $id     = $row->[0];
  last if $n >= $count;
  if ($seen{$id})
  {
    print "Skipping $id, it has been seen\n" if $verbose;
    next;
  }
  $seen{$id} = 1;
  my $user   = $row->[1];
  my $time   = $row->[2];
  my $gid    = $row->[3];
  my $status = $row->[4];
  # Do not do nonmatching 'crms' status 4s.
  my $expr   = $crms->SimpleSqlGet("SELECT reason FROM exportdata WHERE gid='$gid'");
  next if $expr eq 'crms';
  $sql = "SELECT MAX(swiss) FROM historicalreviews WHERE id='$id'";
  next if 0 < $crms->SimpleSqlGet($sql);
  $sql = "SELECT reason FROM exportdata WHERE gid=$gid";
  my $expreason = $crms->SimpleSqlGet($sql);
  next if $expreason eq 'crms';
  next if $crms2->SimpleSqlGet("SELECT COUNT(*) FROM queue WHERE id='$id'");
  if ($verbose)
  {
    my %vals = (0=>'x',1=>'+',2=>'-');
    $sql = 'SELECT h.user,DATE(h.time),h.attr,h.reason,h.renDate,h.renNum,h.category,h.note,h.validated,h.status,b.author,b.title,YEAR(b.pub_date) ' .
           "FROM historicalreviews h INNER JOIN bibdata b ON h.id=b.id WHERE h.gid=$gid";
    my $ref = $crms->GetDb()->selectall_arrayref($sql);
    foreach my $row (@{$ref})
    {
      my $user2 = $row->[0];
      my $time = $row->[1];
      my $attr = $crms->TranslateAttr($row->[2]);
      my $reason = $crms->TranslateReason($row->[3]);
      my $renDate = $row->[4];
      my $renNum = $row->[5];
      my $category = $row->[6];
      my $note = $row->[7];
      my $validated = $vals{$row->[8]};
      my $status = $row->[9];
      my $author = $row->[10];
      my $title = $row->[11];
      my $pubDate = $row->[12];
      $renDate = ' ' unless $renDate;
      $renNum = ' ' unless $renNum;
      $category = ' ' unless $category;
      $note = ' ' unless $note;
      $note =~ s/\s|\n/ /gs;
      my $importing = ($user eq $user2)? '&#x2713;':'';
      print "<tr><td>$id</td><td>$title</td><td>$author</td><td>$pubDate</td><td>$time</td><td>$status</td>" .
            "<td>$user2</td><td>$attr</td><td>$reason</td><td>$renDate</td><td>$renNum</td><td>$category</td>" .
            "<td>$note</td><td>$validated</td><td>$importing</td></tr>\n";
    }
  }
  $s4++ if $status == 4;
  $s5++ if $status == 5;
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
  $crms->UpdateMetadata($id, 'bibdata', 1);
  $n++;
}
print "</table></body></html>\n" if $verbose;
print "Warning: $_\n" for @{$crms->GetErrors()};

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

