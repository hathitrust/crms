#!/usr/bin/perl

use strict;
use warnings;
use utf8;

BEGIN {
  die "SDRROOT environment variable not set" unless defined $ENV{'SDRROOT'};
  use lib $ENV{'SDRROOT'} . '/crms/cgi';
}

use CRMS;
use Getopt::Long;
use Utilities;

my $usage = <<END;
USAGE: $0 [-hnpv] [-m MAIL [-m MAIL...]] [-y YEAR]

Sends biweekly activity reports to HathiTrust administrators.

-h       Print this help message.
-m MAIL  Send report to MAIL. May be repeated for multiple recipients.
-n       No-op; do not send e-mail at all.
-p       Run in production.
-v       Emit verbose debugging information. May be repeated.
-y YEAR  Run report against entire year YEAR.
END

my $help;
my $instance;
my @mails;
my $noop;
my $production;
my $verbose = 0;
my $year;

Getopt::Long::Configure ('bundling');
die 'Terminating' unless GetOptions('h|?'  => \$help,
           'm:s@' => \@mails,
           'n'    => \$noop,
           'p'    => \$production,
           'v+'   => \$verbose,
           'y:s'    => \$year);
$instance = 'production' if $production;
if ($help) { print $usage. "\n"; exit(0); }
print "Verbosity $verbose\n" if $verbose;

my $crms = CRMS->new(
    verbose  => $verbose,
    instance => $instance
);

my ($start, $period);
if ($year)
{
  $start = $year. '-01-01';
  $period = 'Year';
}
else
{
  $start = $crms->SimpleSqlGet('SELECT DATE_SUB(NOW(),INTERVAL 2 WEEK)');
  $period = 'Two Weeks';
}

printf "DB: %s\n", $crms->DbInfo() if $verbose;

my $d = $crms->SimpleSqlGet('SELECT COUNT(*) FROM exportdata');
my $d2 = $crms->SimpleSqlGet('SELECT COUNT(*) FROM exportdata WHERE time>?', $start);
my $pd = $crms->SimpleSqlGet('SELECT COUNT(*) FROM exportdata WHERE attr="pd" OR attr="pdus"');
my $pd2 = $crms->SimpleSqlGet('SELECT COUNT(*) FROM exportdata WHERE (attr="pd" OR attr="pdus") AND time>?', $start);
my $pdPct = sprintf('%.1f', ($d > 0)? $pd/$d*100.0 : 0.0);
my $pd2Pct = sprintf('%.1f', ($d2 > 0)? $pd2/$d2*100.0 : 0.0);
my $pdicus = $crms->SimpleSqlGet('SELECT COUNT(*) FROM exportdata WHERE attr="pd" OR attr="icus"');
my $pdicus2 = $crms->SimpleSqlGet('SELECT COUNT(*) FROM exportdata WHERE (attr="pd" OR attr="icus") AND time>?', $start);
my $pdicusPct = sprintf('%.1f', ($d > 0)? $pdicus/$d*100.0 : 0.0);
my $pdicus2Pct = sprintf('%.1f', ($d2 > 0)?$pdicus2/$d2*100.0 : 0.0);
$pdicus = $crms->Commify($pdicus);
$pdicus2 = $crms->Commify($pdicus2);
my $sql = 'SELECT FORMAT(SUM(COALESCE(TIME_TO_SEC(duration),0)/3600.0),1) from historicalreviews'.
          ' WHERE TIME_TO_SEC(duration)<=3600';
my $time = $crms->SimpleSqlGet($sql);
my $time2 = $crms->SimpleSqlGet($sql. ' AND time>?', $start) || 0;

$d = $crms->Commify($d);
$d2 = $crms->Commify($d2);
$pd = $crms->Commify($pd);
$pd2 = $crms->Commify($pd2);

my %pdinus;
$sql = 'SELECT DISTINCT(CONCAT(attr,"/",reason)) FROM exportdata WHERE attr="pd" OR attr="pdus"';
map {$pdinus{$_->[0]}=1;} @{$crms->SelectAll($sql)};
my %pdoutus;
$sql = 'SELECT DISTINCT(CONCAT(attr,"/",reason)) FROM exportdata WHERE attr="pd" OR attr="icus"';
map {$pdoutus{$_->[0]}=1;} @{$crms->SelectAll($sql)};
my $pdinus = join ', ', sort keys %pdinus;
my $pdoutus = join ', ', sort keys %pdoutus;

my $cand = $crms->Commify($crms->SimpleSqlGet('SELECT COUNT(*) FROM candidates'));

my $now = ($year)? "$year-12-31" : $crms->SimpleSqlGet('SELECT NOW()');
my $rnote = sprintf('<span style="font-size:.9em;">Report for %s to %s</span>',
                    $crms->FormatDate($start),
                    #$start,
                    $crms->FormatDate($now));
my $msg = $crms->StartHTML();
$msg .= <<END;
<table style="border:1px solid #000000;border-collapse:collapse;">
  <tr style="text-align:center;">
    <th style="background-color:#000000;color:#FFFFFF;padding:4px 20px 2px 6px;"></th>
    <th style="background-color:#000000;color:#FFFFFF;padding:4px 20px 2px 6px;">All Time</th>
    <th style="background-color:#000000;color:#FFFFFF;padding:4px 20px 2px 6px;">Last __PERIOD__</th>
  </tr>
  <tr style="text-align:center;">
    <th style="background-color:#000000;color:#FFFFFF;padding:4px 20px 2px 6px;text-align:right;">Total Determinations</th>
    <td style="padding:4px 20px 2px 6px;text-align:left;">$d</th>
    <td style="padding:4px 20px 2px 6px;text-align:left;">$d2</th>
  </tr>
  <tr style="text-align:center;">
    <th style="background-color:#000000;color:#FFFFFF;padding:4px 20px 2px 6px;text-align:right;">PD in U.S.</th>
    <td style="padding:4px 20px 2px 6px;text-align:left;">$pd ($pdPct\%)</th>
    <td style="padding:4px 20px 2px 6px;text-align:left;">$pd2 ($pd2Pct\%)</th>
  </tr>
  <tr style="text-align:center;">
    <th style="background-color:#000000;color:#FFFFFF;padding:4px 20px 2px 6px;text-align:right;">PD outside U.S.</th>
    <td style="padding:4px 20px 2px 6px;text-align:left;">$pdicus ($pdicusPct\%)</th>
    <td style="padding:4px 20px 2px 6px;text-align:left;">$pdicus2 ($pdicus2Pct\%)</th>
  </tr>
  <tr style="text-align:center;">
    <th style="background-color:#000000;color:#FFFFFF;padding:4px 20px 2px 6px;text-align:right;">Time</th>
    <td style="padding:4px 20px 2px 6px;text-align:left;">$time hours</th>
    <td style="padding:4px 20px 2px 6px;text-align:left;">$time2 hours</th>
  </tr>
  <tr style="text-align:center;">
    <th style="background-color:#000000;color:#FFFFFF;padding:4px 20px 2px 6px;text-align:right;">Remaining Candidates</th>
    <td colspan="2" style="padding:4px 20px 2px 6px;text-align:center;">$cand</th>
  </tr>
</table>
<br/>
<h4>Time Spent does not include "outliers" over an hour</h4>
<h4>PD in U.S. codes: {$pdinus}</h4>
<h4>PD outside U.S. codes: {$pdoutus}</h4>
$rnote
</body>
</html>
END

$msg =~ s/__PERIOD__/$period/g;
@mails = map { ($_ =~ m/@/)? $_:($_ . '@umich.edu'); } @mails;
my $to = join ',', @mails;
if ($noop)
{
  print "No-op set; not sending e-mail to $to\n" if $verbose;
}
else
{
  if (scalar @mails)
  {
    my $subj = 'CRMS Determinations Report';
    $subj .= ' – Yearly' if $year;
    use Encode;
    use Mail::Sendmail;
    my $bytes = encode('utf8', $msg);
    my %mail = ('from'         => $crms->GetSystemVar('sender_email'),
                'to'           => $to,
                'subject'      => $subj,
                'content-type' => 'text/html; charset="UTF-8"',
                'body'         => $bytes
                );
    sendmail(%mail) || $crms->SetError("Error: $Mail::Sendmail::error\n");
  }
}
print "Warning: $_\n" for @{$crms->GetErrors()};


