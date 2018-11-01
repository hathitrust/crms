#!/usr/bin/perl

BEGIN 
{ 
  unshift(@INC, $ENV{'SDRROOT'}. '/crms/cgi');
}

use strict;
use warnings;
use CRMS;
use Getopt::Long qw(:config no_ignore_case bundling);
use Encode;

my $usage = <<END;
USAGE: $0 [-hpqtv] [-m MAIL [-m MAIL...]] [-x SYS]

Reports on user progress, patron requests, and past month's invalidations
and swiss reviews.

-h         Print this help message.
-m MAIL    Mail the report to MAIL. May be repeated for multiple addresses.
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
    sys      =>   $sys,
    verbose  =>   $verbose,
    instance =>   $instance
);

my $report = $crms->StartHTML('CRMS User Progress Report');
my $sql = 'SELECT a.id,b.max FROM users a INNER JOIN'.
          ' (SELECT user,MAX(time) AS max FROM historicalreviews GROUP BY user) b'.
          ' ON a.id=b.user WHERE a.reviewer=1 AND a.expert=0'.
          ' AND DATE(b.max)<DATE_SUB(DATE(NOW()), INTERVAL 2 WEEK)'.
          ' AND a.id LIKE "%@%"'.
          ' ORDER BY b.max ASC';
my $ref = $crms->SelectAll($sql);
if (scalar @{$ref} > 0)
{
  $report .= '<h2>Inactive Reviewers</h2>'. "\n";
  $report .= '<table style="border:1px solid #000000;border-collapse:collapse;">';
  $report .= '  <tr><th style="background-color:#000000;color:#FFFFFF;padding:4px 20px 2px 6px;">User</th>'. "\n".
             '      <th style="background-color:#000000;color:#FFFFFF;padding:4px 20px 2px 6px;">Last Review</th></tr>'. "\n";
  foreach my $row (@{$ref})
  {
    $report .= '<tr style="border:1px solid #000000">'.
               '<td style="border:1px solid #000000;padding:4px 20px 2px 6px;">'. $row->[0]. '</td>'. "\n".
               '<td style="border:1px solid #000000;padding:4px 20px 2px 6px;">'. $row->[1]. '</td></tr>'. "\n";
  }
  $report .= '</table>'. "\n";
}


$report .= "<h2>Reviewer Progress</h2>\n";
$report .= '<table style="border:1px solid #000000;border-collapse:collapse;">'. "\n";
$sql = 'SELECT u.id,u.name FROM users u INNER JOIN projectusers pu'.
       ' ON u.id=pu.user WHERE u.id LIKE "%@%" AND u.reviewer=1'.
       ' AND u.advanced=0 AND u.expert=0'.
       ' AND id IN (SELECT DISTINCT user FROM historicalreviews)'.
       ' ORDER BY pu.project,u.name';
my %seen;
$ref = $crms->SelectAll($sql);
my $now = $crms->SimpleSqlGet('SELECT CURDATE()');
foreach my $row (@{$ref})
{
  my $user = $row->[0];
  next if $seen{$user};
  $seen{$user} = 1;
  my $name = $row->[1];
  my $projs = $crms->GetUserProjects($user);
  my $projnames = join ', ', map {$_->{'name'}} @{$projs};
  $report .= '<tr style="border:1px solid #000000;"><th colspan="2">'.
             $user. " ($name: <i>$projnames</i>)". '</th></tr>'. "\n";
  my $start = $crms->SimpleSqlGet('SELECT DATE_SUB(CURDATE(), INTERVAL 8 WEEK)');
  while ($start lt $now)
  {
    my $end = $crms->SimpleSqlGet('SELECT DATE_ADD(?, INTERVAL 6 DAY)', $start);
    $sql = 'SELECT COUNT(id) FROM historicalreviews WHERE user=?'.
           ' AND DATE(time)>=? AND DATE(time)<=?';
    my $total = $crms->SimpleSqlGet($sql, $user, $start, $end);
    $report .= "<tr><td>$start</td><td>$total reviews";
    if ($total > 0)
    {
      $sql = 'SELECT COUNT(id) FROM historicalreviews WHERE user=?'.
             ' AND DATE(time)>=? AND DATE(time)<=? AND validated=0';
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

$sql = 'SELECT id,ticket,time,status FROM queue'.
       ' WHERE ticket IS NOT NULL ORDER BY ticket';
$ref = $crms->SelectAll($sql);
if (scalar @{$ref})
{
  $report .= "<h2>Patron Requests</h2>\n";
  $report .= '<table style="border:1px solid #000000;border-collapse:collapse;">'. "\n";
  $report .= '  <tr><th style="background-color:#000000;color:#FFFFFF;padding:4px 20px 2px 6px;">ID</th>'. "\n".
             '      <th style="background-color:#000000;color:#FFFFFF;padding:4px 20px 2px 6px;">Ticket</th>'. "\n".
             '      <th style="background-color:#000000;color:#FFFFFF;padding:4px 20px 2px 6px;">Date Added</th>'. "\n".
             '      <th style="background-color:#000000;color:#FFFFFF;padding:4px 20px 2px 6px;">Status</th></tr>'. "\n";
	foreach my $row (@{$ref})
	{
    $report .= '<tr style="border:1px solid #000000">'.
               '<th style="border:1px solid #000000;padding:4px 20px 2px 6px;">'. $row->[0]. '</th>'.
               '<td style="border:1px solid #000000;padding:4px 20px 2px 6px;">'. $row->[1]. '</td>'.
               '<td style="border:1px solid #000000;padding:4px 20px 2px 6px;">'. $row->[2]. '</td>'.
               '<td style="border:1px solid #000000;padding:4px 20px 2px 6px;">'. $row->[3]. '</td></tr>'. "\n";
  }
  $report .= '</table>';
}

my %stats;
$report .= "<h2>Invalidations and Swisses by Note Category (past month)</h2>\n";
$report .= '<table style="border:1px solid #000000;border-collapse:collapse;">'. "\n";
$sql = 'SELECT COALESCE(r.category,"") AS cat,p.name,'.
       'SUM(IF(r.validated=0,1,0)),SUM(IF(r.swiss=1,1,0))'.
       ' FROM historicalreviews r INNER JOIN exportdata e ON r.gid=e.gid'.
       ' INNER JOIN projects p ON e.project=p.id'.
       ' WHERE DATE(r.time)>=DATE_SUB(DATE(NOW()), INTERVAL 1 MONTH)'.
       ' AND r.user!="autocrms" GROUP BY cat,p.id ORDER BY cat,p.id;';
$ref = $crms->SelectAll($sql);
$report .= '  <tr><th style="background-color:#000000;color:#FFFFFF;padding:4px 20px 2px 6px;">Category</th>'. "\n".
           '      <th style="background-color:#000000;color:#FFFFFF;padding:4px 20px 2px 6px;">Project</th>'. "\n".
           '      <th style="background-color:#000000;color:#FFFFFF;padding:4px 20px 2px 6px;">Invalid</th>'. "\n".
           '      <th style="background-color:#000000;color:#FFFFFF;padding:4px 20px 2px 6px;">Swiss</th></tr>'. "\n";
foreach my $row (@{$ref})
{
	$report .= '<tr style="border:1px solid #000000;padding:4px 20px 2px 6px;">'.
						 '<th style="border:1px solid #000000;padding:4px 20px 2px 6px;">'. ($row->[0] || '<none>'). '</th>'.
						 '<td style="border:1px solid #000000;padding:4px 20px 2px 6px;">'. $row->[1]. '</td>'.
						 '<td style="border:1px solid #000000;padding:4px 20px 2px 6px;">'. $row->[2]. '</td>'.
						 '<td style="border:1px solid #000000;padding:4px 20px 2px 6px;">'. $row->[3]. '</td></tr>'. "\n";
}
$report .= '</table>';

$report .= "</body></html>\n";


if (@mails)
{
  @mails = map { ($_ =~ m/@/)? $_:($_ . '@umich.edu'); } @mails;
  my $bytes = encode('utf8', $report);
  my $to = join ',', @mails;
  use Mail::Sendmail;
  my %mail = ('from'         => 'crms-mailbot@umich.edu',
              'to'           => $to,
              'subject'      => $crms->SubjectLine('User Progress'),
              'content-type' => 'text/html; charset="UTF-8"',
              'body'         => $bytes
              );
  sendmail(%mail) || $crms->SetError("Error: $Mail::Sendmail::error\n");
}
else
{
  print "$report\n" unless $quiet;
}

