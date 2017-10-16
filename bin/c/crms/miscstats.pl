#!/usr/bin/perl

my $DLXSROOT;
BEGIN
{
  $DLXSROOT = $ENV{'DLXSROOT'};
  unshift (@INC, $DLXSROOT . '/cgi/c/crms/');
}

use strict;
use CRMS;
use Getopt::Long qw(:config no_ignore_case bundling);
use Encode;

my $usage = <<END;
USAGE: $0 [-hpqtv] [-m MAIL_ADDR [-m MAIL_ADDR2...]] [-x SYS]

Reports on volumes that are no longer ic/bib in the rights database
and, optionally, delete them from the system.

-h         Print this help message.
-m ADDR    Mail the report to ADDR. May be repeated for multiple addresses.
-p         Run in production.
-q         Do not emit report (ignored if -m is used).
-t         Run against the training site.
-v         Emit debugging information.
-x SYS     Set SYS as the system to execute.
END


my $delete;
my $help;
my $instance;
my @mails;
my $production;
my $quiet;
my $training;
my $verbose;
my $sys;

Getopt::Long::Configure ('bundling');
die 'Terminating' unless GetOptions(
           'h|?'  => \$help,
           'm:s@' => \@mails,
           'p'    => \$production,
           'q'    => \$quiet,
           't'    => \$training,
           'v+'   => \$verbose,
           'x:s'  => \$sys);
$instance = 'production' if $production;
$instance = 'crms-training' if $training;
die "$usage\n\n" if $help;

my $crms = CRMS->new(
    logFile  =>   "$DLXSROOT/prep/c/crms/miscstats_hist.txt",
    sys      =>   $sys,
    verbose  =>   $verbose,
    root     =>   $DLXSROOT,
    instance =>   $instance
);

my $report = $crms->StartHTML('CRMS Miscellaneous Stats');
my $sql = 'SELECT a.id,b.max FROM users a INNER JOIN' .
          ' (SELECT user,MAX(time) AS max FROM historicalreviews GROUP BY user) b' .
          ' ON a.id=b.user WHERE a.reviewer=1 AND a.expert=0' .
          ' AND DATE(b.max)<DATE_SUB(DATE(NOW()), INTERVAL 1 MONTH)' .
          ' AND a.id LIKE "%@%"' .
          ' ORDER BY b.max ASC';
my $ref = $crms->SelectAll($sql);
if (scalar @{$ref} > 0)
{
  $report .= "<h2>Inactive Reviewers</h2>\n";
  $report .= "<table><tr><th>User</th><th>Last Review</th></tr>\n";
  foreach my $row (@{$ref})
  {
    my $src = $row->[0];
    my $cnt = $row->[1];
    $report .= "<tr><td>$src</td><td>$cnt</td></tr>\n";
  }
  $report .= "</table>\n";
}

### Total unique volumes exported
$sql = 'SELECT COUNT(DISTINCT id) FROM exportdata WHERE exported=1';
my $uniq = $crms->SimpleSqlGet($sql);
$report .= "<h2>Total Unique Volumes Exported: $uniq</h2>\n";
$sql = 'SELECT COUNT(id) FROM exportdata WHERE exported=1';
my $uniq = $crms->SimpleSqlGet($sql);
$report .= "<h2>Total Volumes Exported: $uniq</h2>\n";
$sql = 'SELECT src,COUNT(id) FROM exportdata WHERE src NOT LIKE "HTS%" AND exported=1 GROUP BY src ORDER BY count(id) DESC';
my $ref = $crms->SelectAll($sql);
$report .= "<table><tr><th>Source</th><th>Volumes</th></tr>\n";
foreach my $row (@{$ref})
{
  my $src = $row->[0];
  my $cnt = $row->[1];
  $report .= "<tr><td>$src</td><td>$cnt</td></tr>\n";
}
$sql = 'SELECT COUNT(id) FROM exportdata WHERE src LIKE "HTS%"';
my $cnt = $crms->SimpleSqlGet($sql);
if ($cnt)
{
  $report .= "<tr><td>Jira</td><td>$cnt</td></tr>\n";
}
$report .= "</table>\n";
if (0)
{
  $sql = 'SELECT COUNT(id) FROM candidates';
  $uniq = $crms->SimpleSqlGet($sql);
  $report .= "<h2>Total Volumes Still in Candidates: $uniq</h2>\n";
}
if (0)
{
  ### Total unique titles exported (guesstimate)
  $sql = "SELECT COUNT(DISTINCT b.sysid) FROM exportdata e INNER JOIN bibdata b ON e.id=b.id";
  $uniq = $crms->SimpleSqlGet($sql);
  $report .= "<h2>Total Unique Titles Exported (slight guesstimate): $uniq</h2>\n";
}
if (0)
{
  $report .= "<h2>Candidates by Namespace</h2>\n";
  $report .= "<table><tr><th>Namespace</th><th>Count</th>";
  my @nss = $crms->Namespaces();
  foreach my $ns (@nss)
  {
    my $cnt = $crms->SimpleSqlGet('SELECT COUNT(*) FROM candidates WHERE id LIKE "'. $ns . '%"');
    next if $cnt == 0;
    $report .= "  <tr><td>$ns</td><td>$cnt</td></tr>\n";
  }
  $report .= "</table>\n";
}
$report .= "<h2>New Reviewer Progress</h2>\n";
$report .= N00bReport();

### Breakdown of time for each category of und
$report .= "<h2>Average Review Time for <code>und</code> Categories</h2>\n";
$report .= "<h4>including outliers of more than 5 minutes</h4>\n";
$report .= "<table><tr><th>Category</th><th>Seconds</th></tr>\n";
$sql = 'SELECT category,SUM(COALESCE(TIME_TO_SEC(duration),0))/COUNT(category) s' .
       ' FROM historicalreviews WHERE legacy!=1 AND attr=5 AND user!="autocrms"' .
       ' AND category IN (SELECT name FROM categories WHERE interface=1)' .
       ' GROUP BY category ORDER BY s DESC';
my $ref = $crms->SelectAll($sql);
foreach my $row (@{$ref})
{
  my $cat = $row->[0];
  my $dur = $row->[1];
  $report .= sprintf "<tr><td>%s</td><td>%0.2f</td></tr>\n", $cat, $dur if $dur > 0.0;
}
$report .= "</table>\n";

### CRMS World only: breakdown of time for country of origin
if (0)
{
  $report .= "<h2>Average Review Time by Country of Origin</h2>\n";
  $report .= "<h4>including outliers of more than 5 minutes</h4>\n";
  $report .= "<table><tr><th>Category</th><th>Seconds</th></tr>\n";
  my $data = CreateCountryReviewTimeData(10);
  foreach my $row (split "\n", $data)
  {
    my ($cat,$dur) = split "\t", $row;
    $report .= sprintf "<tr><td>%s</td><td>%0.2f</td></tr>\n", $cat, $dur;# if $dur > 0.0;
  }
  $report .= "</table>\n";
}

# Breakdown of time reviewing
my @ys = @{$crms->GetAllExportYears()};
foreach my $y (reverse @ys)
{
  $report .= "<h2>$y Reviews by Duration</h2>\n";
  my @yms = $crms->GetAllMonthsInYear($y);
  unshift @yms, 'Total';
  $report .= "<table><tr><th>Duration</th>";
  $report .= '<th>' . $crms->YearMonthToEnglish($_) . '</th>' for @yms;
  $report .= "</tr>\n";
  #print "$sql\n";
  my @mins = (1,2,3,4,5,10,30,60,120,240,480,960);
  for (my $i = 0; $i < scalar @mins; $i++)
  {
    my $t1 = ($i > 0)? $mins[$i-1]:0;
    my $pt1 = $t1;
    my $t2 = $mins[$i];
    my $pt2 = $t2;
    my $op = ($i == 0)? 'up to':'to';
    $op = 'above' if $i == scalar @mins - 1;
    my $units1 = 'minute';
    my $units2 = 'minute';
    if ($t1 && $t1 >= 60) {$pt1 /= 60;$units1 = 'hour'};
    if ($t2 && $t2 >= 60) {$pt2 /= 60;$units2 = 'hour'};
    $units1 = $crms->Pluralize($units1,$pt1);
    $units2 = $crms->Pluralize($units2,$pt2);
    $report .= sprintf("<tr><td>%s%s$op $pt2 $units2</td>",
      ($pt1 && $i < scalar @mins - 1)?"$pt1 ":'',
      ($pt1 && $i < scalar @mins - 1)?"$units1 ":'');
    foreach my $ym (@yms)
    {
      $ym = $y if $ym eq 'Total';
      my $sql = "SELECT COUNT(*) FROM historicalreviews WHERE legacy!=1 AND user!='autocrms' AND time LIKE '$ym%'";
      #print "$sql\n";
      my $of = $crms->SimpleSqlGet($sql);
      $sql = sprintf('SELECT COUNT(*) FROM historicalreviews WHERE legacy!=1' .
                     " AND user!='autocrms' AND time LIKE '$ym%'" .
                     ' AND TIME_TO_SEC(duration) < %d AND TIME_TO_SEC(duration) >= %d',
                     $t2*60, $t1*60);
      #print "$sql\n";
      my $n = $crms->SimpleSqlGet($sql);
      my $pct = 0.0;
      eval {$pct = 100.0*$n/$of;};
      $report .= sprintf("<td>$n (%0.2f%%)</td>", $pct);
    }
    $report .= "</tr>\n";
  }
  $report .= "</table>\n";
}
if (0)
{
  $report .= "<h2>Note Category Prevalence by Reviewer</h2>\n";
  my %cats;
  $sql = 'SELECT name FROM categories WHERE restricted IS NULL AND interface=1';
  $ref = $crms->SelectAll($sql);
  $cats{$_->[0]} = 1 for (@{$ref});
  $sql = 'SELECT id FROM users WHERE reviewer+advanced>0 AND expert+admin+superadmin=0';
  $ref = $crms->SelectAll($sql);
  $report .= '<table><tr><th>User (validation)<th>' . join "</th><th>", keys %cats;
  $report .= "</th></tr>\n";
  foreach my $row (@{$ref})
  {
    my $user = $row->[0];
    $sql = 'SELECT COUNT(*) FROM historicalreviews WHERE user=? AND category IS NOT NULL';
    my $total = $crms->SimpleSqlGet($sql, $user);
    next if $total == 0;
    $sql = 'SELECT SUM(total_correct)/SUM(total_reviews)*100.0 FROM userstats WHERE user=?';
    $report .= sprintf "<tr><th>$user (%.1f%%)</th>", $crms->SimpleSqlGet($sql, $user);
    foreach my $cat (sort keys %cats)
    {
      $sql = 'SELECT COUNT(*) FROM historicalreviews WHERE user=? AND category=?';
      my $n = $crms->SimpleSqlGet($sql, $user, $cat);
      $report .= sprintf "<td>%.1f%%</td>", 100.0 * $n / $total;
    }
    $report .= "</tr>\n";
  }
  $report .= "</table>\n";
}
$report .= "</body></html>\n";

if (@mails)
{
  my $bytes = encode('utf8', $report);
  my $to = join ',', @mails;
  use Mail::Sendmail;
  my %mail = ('from'         => 'crms-mailbot@umich.edu',
              'to'           => $to,
              'subject'      => $crms->SubjectLine('Miscellaneous Stats'),
              'content-type' => 'text/html; charset="UTF-8"',
              'body'         => $bytes
              );
  sendmail(%mail) || $crms->SetError("Error: $Mail::Sendmail::error\n");
}
else
{
  print "$report\n" unless $quiet;
}

sub CreateCountryReviewTimeData
{
  my $limit = shift;

  my $data = '';
  my $sql = 'SELECT COALESCE(b.country,"Undetermined"),'.
            'SUM(COALESCE(TIME_TO_SEC(h.duration),0))/COUNT(b.country) s'.
            ' FROM bibdata b INNER JOIN historicalreviews h ON b.id=h.id'.
            ' WHERE legacy!=1 AND user!="autocrms"'.
            ' GROUP BY COALESCE(b.country,"Undetermined") ORDER BY s DESC';
  $sql .= ' LIMIT ' . $limit if $limit;
  my $ref = $crms->SelectAll($sql);
  foreach my $row (@{$ref})
  {
    my $cat = $row->[0];
    my $dur = $row->[1];
    next if $dur <= 0;
    $data .= "$cat\t$dur\n";
  }
  return $data;
}

sub N00bReport
{
  my $report = "<table style='text-align:left;'>\n";
  my $sql = 'SELECT id,name FROM users WHERE id LIKE "%@%" AND reviewer=1 AND advanced=0 AND expert=0' .
            ' AND id IN (SELECT DISTINCT user FROM historicalreviews) ORDER BY name';
  my $ref = $crms->SelectAll($sql);
  my $now = $crms->SimpleSqlGet('SELECT CURDATE()');
  foreach my $row (@{$ref})
  {
    my $user = $row->[0];
    my $name = $row->[1];
    $report .= "<tr><th colspan='2'>$name</th></tr>\n";
    my $start = $crms->SimpleSqlGet('SELECT DATE_SUB(CURDATE(), INTERVAL 8 WEEK)');
    while ($start lt $now)
    {
      my $end = $crms->SimpleSqlGet('SELECT DATE_ADD(?, INTERVAL 6 DAY)', $start);
      my $sql = 'SELECT COUNT(id) FROM historicalreviews WHERE user=? AND DATE(time)>=? AND DATE(time)<=?';
      my $total = $crms->SimpleSqlGet($sql, $user, $start, $end);
      $report .= "<tr><td>$start</td><td>$total reviews";
      if ($total > 0)
      {
        my $sql = 'SELECT COUNT(id) FROM historicalreviews WHERE user=? AND DATE(time)>=? AND DATE(time)<=? AND validated=0';
        my $valid = $crms->SimpleSqlGet($sql, $user, $start, $end);
        my $pct = sprintf ' (%.1f%%) ', 100.0 * $valid / $total;
        $pct = ' ' unless $valid > 0;
        $report .= ", $valid" . $pct . 'invalidated';
      }
      $report .= "</td></tr>\n";
      $start = $crms->SimpleSqlGet('SELECT DATE_ADD(?, INTERVAL 7 DAY)', $start);
    }
  }
  $report .= '</table>';
}
