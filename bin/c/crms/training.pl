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

my $usage = <<END;
USAGE: $0 [-hntv5] start_date [end_date]

Populates the training database with examples (correct, single reviews) from production.

-h       Print this help message.
-n       Do not submit SQL.
-t       Run in training (dev otherwise).
-v       Be verbose.
-5       Do only status 5 reviews.
END

my %opts;
getopts('hntv5', \%opts);

my $help       = $opts{'h'};
my $noop       = $opts{'n'};
my $training   = $opts{'t'};
my $verbose    = $opts{'v'};
my $five       = $opts{'5'};

die "$usage\n\n" if $help;
die "You need a start date and optional end date.\n" unless 0 < scalar @ARGV;
my $start = $ARGV[0];
my $end   = $ARGV[1] or '';
die "Start date format should be YYYY-MM-DD\n" if $start !~ m/\d\d\d\d-\d\d-\d\d/;
die "End date format should be YYYY-MM-DD\n" if $end and $end !~ m/\d\d\d\d-\d\d-\d\d/;
if ($end && $start > $end)
{
  my $tmp = $start;
  $start = $end;
  $end = $tmp;
}
$start .= ' 00:00:00' if $start;
$end   .= ' 23:59:59' if $end;

my $crms = CRMS->new(
    logFile      =>   "$DLXSROOT/prep/c/crms/training_hist.txt",
    configFile   =>   "$DLXSROOT/bin/c/crms/crms.cfg",
    verbose      =>   $verbose,
    root         =>   $DLXSROOT,
    dev          =>   undef
);

my $endsql = ($end)? "AND time<='$end'":'';
my $fivesql = ($five)? ' AND status=5':'';

my $n = 0;
my $sql = 'SELECT id,user,time,gid,status FROM historicalreviews WHERE ' .
          'user IN (SELECT id FROM users WHERE advanced=1 AND extadmin+expert+admin+superadmin=0) AND ' . 
          "validated=1 AND time>='$start' $endsql $fivesql ORDER BY id ASC, time ASC";
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
my $ref = $crms->get('dbh')->selectall_arrayref($sql);
my %seen;
my $s4 = 0;
my $s5 = 0;
my @sqls = ();
foreach my $row (@{$ref})
{
  my $id     = $row->[0];
  next if $seen{$id};
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
  if ($verbose)
  {
    my %vals = (0=>'x',1=>'+',2=>'-');
    $sql = 'SELECT h.user,DATE(h.time),h.attr,h.reason,h.renDate,h.renNum,h.category,h.note,h.validated,h.status,b.author,b.title,YEAR(b.pub_date) ' .
           "FROM historicalreviews h INNER JOIN bibdata b ON h.id=b.id WHERE h.gid=$gid";
    my $ref = $crms->get('dbh')->selectall_arrayref($sql);
    foreach my $row (@{$ref})
    {
      my $user2 = $row->[0];
      my $time = $row->[1];
      my $attr = $crms->GetRightsName($row->[2]);
      my $reason = $crms->GetReasonName($row->[3]);
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
  my $ref2 = $crms->get('dbh')->selectall_arrayref($sql);
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
  $note = (defined $note)? $crms->get('dbh')->quote($note):'NULL';
  push @sqls, "INSERT INTO queue (id,time,pending_status) VALUES ('$id','$start',1)";
  push @sqls, 'INSERT INTO reviews (id,user,time,attr,reason,renDate,renNum,category,note,duration) ' .
              "VALUES ('$id','$user','$time',$attr,$reason,$renDate,$renNum,$category,$note,'$duration')";
  $n++;
}
print "</table></body></html>\n" if $verbose;
print "Warning: $_\n" for @{$crms->GetErrors()};

# Connect to training database.
$crms = CRMS->new(
    logFile      =>   "$DLXSROOT/prep/c/crms/duplicates_hist.txt",
    configFile   =>   "$DLXSROOT/bin/c/crms/crms.cfg",
    verbose      =>   $verbose,
    root         =>   $DLXSROOT,
    dev          =>   ($training)? 'crmstest':$DLPS_DEV
);

foreach $sql (@sqls)
{
  print "$sql\n" if $verbose;
  $crms->PrepareSubmitSql($sql) unless $noop;
}

$sql = "SELECT id FROM queue WHERE id NOT IN (SELECT id FROM bibdata)";
my $ref = $crms->get('dbh')->selectall_arrayref($sql);
foreach my $row (@{$ref})
{
  my $id = $row->[0];
  my $record = $crms->GetMetadata($id);
  $crms->UpdateTitle($id, undef, $record);
  $crms->UpdateAuthor($id, undef, $record);
  $crms->UpdatePubDate($id, undef, $record);
  $crms->BarcodeToId($id);
}
print "Added $n: $s4 status 4 and $s5 status 5\n";
print "Warning: $_\n" for @{$crms->GetErrors()};

