#!/usr/bin/perl
BEGIN 
{
  unshift(@INC, $ENV{'SDRROOT'}. '/crms/cgi');
}

use strict;
use warnings;
use CRMS;
use Getopt::Long;
use Utilities;

my $usage = <<END;
USAGE: $0 [-hnpv] [-m USER [-m USER...]]

Sends weekly or biweekly activity reports to HathiTrust administrators.

-h       Print this help message.
-m MAIL  Send report to MAIL. May be repeated for multiple recipients.
-n       No-op; do not send e-mail at all.
-p       Run in production.
-v       Be verbose.
END

my $help;
my $instance;
my @mails;
my $noop;
my $production;
my $verbose = 0;

Getopt::Long::Configure ('bundling');
die 'Terminating' unless GetOptions('h|?'  => \$help,
           'm:s@' => \@mails,
           'n'    => \$noop,
           'p'    => \$production,
           'v+'   => \$verbose);
$instance = 'production' if $production;
print "Verbosity $verbose\n" if $verbose;
die "$usage\n\n" if $help;

my $crms = CRMS->new(
    sys      => 'crmsworld',
    verbose  => $verbose,
    instance => $instance
);
my $crmsUS = CRMS->new(
    sys      => 'crms',
    verbose  => $verbose,
    instance => $instance
);

printf "CRMS-World DB: %s\n", $crms->DbInfo() if $verbose;
printf "CRMS-US DB: %s\n", $crmsUS->DbInfo() if $verbose;

my $dWorld = $crms->SimpleSqlGet('SELECT COUNT(*) FROM exportdata');
my $dWorld2 = $crms->SimpleSqlGet('SELECT COUNT(*) FROM exportdata WHERE time>DATE_SUB(NOW(),INTERVAL 2 WEEK)');
my $pdWorld = $crms->SimpleSqlGet('SELECT COUNT(*) FROM exportdata WHERE attr="pd" OR attr="pdus"');
my $pdWorld2 = $crms->SimpleSqlGet('SELECT COUNT(*) FROM exportdata WHERE (attr="pd" OR attr="pdus") AND time>DATE_SUB(NOW(),INTERVAL 2 WEEK)');
my $pdWorldPct = sprintf('%.1f', ($dWorld > 0)? $pdWorld/$dWorld*100.0 : 0.0);
my $pdWorld2Pct = sprintf('%.1f', ($dWorld2 > 0)? $pdWorld2/$dWorld2*100.0 : 0.0);
my $pdicusWorld = $crms->SimpleSqlGet('SELECT COUNT(*) FROM exportdata WHERE attr="pd" OR attr="icus"');
my $pdicusWorld2 = $crms->SimpleSqlGet('SELECT COUNT(*) FROM exportdata WHERE (attr="pd" OR attr="icus") AND time>DATE_SUB(NOW(),INTERVAL 2 WEEK)');
my $pdicusWorldPct = sprintf('%.1f', ($dWorld > 0)? $pdicusWorld/$dWorld*100.0 : 0.0);
my $pdicusWorld2Pct = sprintf('%.1f', ($dWorld2 > 0)?$pdicusWorld2/$dWorld2*100.0 : 0.0);
$pdicusWorld = commify($pdicusWorld);
$pdicusWorld2 = commify($pdicusWorld2);
my $sql = 'SELECT FORMAT(SUM(COALESCE(TIME_TO_SEC(duration),0)/3600.0),1) from historicalreviews'.
          ' WHERE TIME_TO_SEC(duration)<=3600';
my $timeWorld = $crms->SimpleSqlGet($sql);
my $timeWorld2 = $crms->SimpleSqlGet($sql. ' AND time>DATE_SUB(NOW(),INTERVAL 2 WEEK)') || 0;

my $dUS = $crmsUS->SimpleSqlGet('SELECT COUNT(*) FROM exportdata');
my $dUS2 = $crmsUS->SimpleSqlGet('SELECT COUNT(*) FROM exportdata WHERE time>DATE_SUB(NOW(),INTERVAL 2 WEEK)');
my $pdUS = $crmsUS->SimpleSqlGet('SELECT COUNT(*) FROM exportdata WHERE attr="pd" OR attr="pdus"');
my $pdUS2 = $crmsUS->SimpleSqlGet('SELECT COUNT(*) FROM exportdata WHERE (attr="pd" OR attr="pdus") AND time>DATE_SUB(NOW(),INTERVAL 2 WEEK)');
my $pdUSPct = sprintf('%.1f', ($dUS > 0)? $pdUS/$dUS*100.0 : 0.0);
my $pdUS2Pct = sprintf('%.1f', ($dUS2 > 0)? $pdUS2/$dUS2*100.0 : 0.0);
my $timeUS = $crmsUS->SimpleSqlGet($sql);
my $timeUS2 = $crmsUS->SimpleSqlGet($sql. ' AND time>DATE_SUB(NOW(),INTERVAL 2 WEEK)') || 0;

$dWorld = commify($dWorld);
$dWorld2 = commify($dWorld2);
$pdWorld = commify($pdWorld);
$pdWorld2 = commify($pdWorld2);
$dUS = commify($dUS);
$dUS2 = commify($dUS2);
$pdUS = commify($pdUS);
$pdUS2 = commify($pdUS2);
my %pdinus;
$sql = 'SELECT DISTINCT(CONCAT(attr,"/",reason)) FROM exportdata WHERE attr="pd" OR attr="pdus"';
map {$pdinus{$_->[0]}=1;} @{$crmsUS->SelectAll($sql)};
map {$pdinus{$_->[0]}=1;} @{$crms->SelectAll($sql)};
my %pdoutus;
$sql = 'SELECT DISTINCT(CONCAT(attr,"/",reason)) FROM exportdata WHERE attr="pd" OR attr="icus"';
map {$pdoutus{$_->[0]}=1;} @{$crmsUS->SelectAll($sql)};
map {$pdoutus{$_->[0]}=1;} @{$crms->SelectAll($sql)};
my $pdinus = join ', ', sort keys %pdinus;
my $pdoutus = join ', ', sort keys %pdoutus;

my $candWorld = commify($crms->SimpleSqlGet('SELECT COUNT(*) FROM candidates'));
my $candUS = commify($crmsUS->SimpleSqlGet('SELECT COUNT(*) FROM candidates'));

my $now = $crms->SimpleSqlGet('SELECT NOW()');
my $then = $crms->SimpleSqlGet('SELECT DATE_SUB(NOW(),INTERVAL 2 WEEK)');
my $rnote = sprintf('<span style="font-size:.9em;">Report for %s to %s</span>',
                    $crms->FormatDate($then), $crms->FormatDate($now));
my $msg = $crms->StartHTML();
$msg .= <<END;
<h2>CRMS-World</h2>
<table style="border:1px solid #000000;border-collapse:collapse;">
  <tr style="text-align:center;">
    <th style="background-color:#000000;color:#FFFFFF;padding:4px 20px 2px 6px;"></th>
    <th style="background-color:#000000;color:#FFFFFF;padding:4px 20px 2px 6px;">All Time</th>
    <th style="background-color:#000000;color:#FFFFFF;padding:4px 20px 2px 6px;">Last Two Weeks</th>
  </tr>
  <tr style="text-align:center;">
    <th style="background-color:#000000;color:#FFFFFF;padding:4px 20px 2px 6px;text-align:right;">Total Determinations</th>
    <td style="padding:4px 20px 2px 6px;text-align:left;">$dWorld</th>
    <td style="padding:4px 20px 2px 6px;text-align:left;">$dWorld2</th>
  </tr>
  <tr style="text-align:center;">
    <th style="background-color:#000000;color:#FFFFFF;padding:4px 20px 2px 6px;text-align:right;">PD in U.S.</th>
    <td style="padding:4px 20px 2px 6px;text-align:left;">$pdWorld ($pdWorldPct\%)</th>
    <td style="padding:4px 20px 2px 6px;text-align:left;">$pdWorld2 ($pdWorld2Pct\%)</th>
  </tr>
  <tr style="text-align:center;">
    <th style="background-color:#000000;color:#FFFFFF;padding:4px 20px 2px 6px;text-align:right;">PD outside U.S.</th>
    <td style="padding:4px 20px 2px 6px;text-align:left;">$pdicusWorld ($pdicusWorldPct\%)</th>
    <td style="padding:4px 20px 2px 6px;text-align:left;">$pdicusWorld2 ($pdicusWorld2Pct\%)</th>
  </tr>
  <tr style="text-align:center;">
    <th style="background-color:#000000;color:#FFFFFF;padding:4px 20px 2px 6px;text-align:right;">Time</th>
    <td style="padding:4px 20px 2px 6px;text-align:left;">$timeWorld hours</th>
    <td style="padding:4px 20px 2px 6px;text-align:left;">$timeWorld2 hours</th>
  </tr>
  <tr style="text-align:center;">
    <th style="background-color:#000000;color:#FFFFFF;padding:4px 20px 2px 6px;text-align:right;">Remaining Candidates</th>
    <td colspan="2" style="padding:4px 20px 2px 6px;text-align:center;">$candWorld</th>
  </tr>
</table>
<h2>CRMS-US</h2>
<table style="border:1px solid #000000;border-collapse:collapse;">
  <tr style="text-align:center;">
    <th style="background-color:#000000;color:#FFFFFF;padding:4px 20px 2px 6px;"></th>
    <th style="background-color:#000000;color:#FFFFFF;padding:4px 20px 2px 6px;">All Time</th>
    <th style="background-color:#000000;color:#FFFFFF;padding:4px 20px 2px 6px;">Last Two Weeks</th>
  </tr>
  <tr style="text-align:center;">
    <th style="background-color:#000000;color:#FFFFFF;padding:4px 20px 2px 6px;text-align:right;">Total Determinations</th>
    <td style="padding:4px 20px 2px 6px;text-align:left;">$dUS</th>
    <td style="padding:4px 20px 2px 6px;text-align:left;">$dUS2</th>
  </tr>
  <tr style="text-align:center;">
    <th style="background-color:#000000;color:#FFFFFF;padding:4px 20px 2px 6px;text-align:right;">PD in U.S.</th>
    <td style="padding:4px 20px 2px 6px;text-align:left;">$pdUS ($pdUSPct\%)</th>
    <td style="padding:4px 20px 2px 6px;text-align:left;">$pdUS2 ($pdUS2Pct\%)</th>
  </tr>
  <tr style="text-align:center;">
    <th style="background-color:#000000;color:#FFFFFF;padding:4px 20px 2px 6px;text-align:right;">Time</th>
    <td style="padding:4px 20px 2px 6px;text-align:left;">$timeUS hours</th>
    <td style="padding:4px 20px 2px 6px;text-align:left;">$timeUS2 hours</th>
  </tr>
  <tr style="text-align:center;">
    <th style="background-color:#000000;color:#FFFFFF;padding:4px 20px 2px 6px;text-align:right;">Remaining Candidates</th>
    <td colspan="2" style="padding:4px 20px 2px 6px;text-align:center;">$candUS</th>
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
    use Encode;
    use Mail::Sendmail;
    my $bytes = encode('utf8', $msg);
    my %mail = ('from'         => 'crms-mailbot@umich.edu',
                'to'           => $to,
                'subject'      => 'CRMS Determinations Report',
                'content-type' => 'text/html; charset="UTF-8"',
                'body'         => $bytes
                );
    sendmail(%mail) || $crms->SetError("Error: $Mail::Sendmail::error\n");
  }
}
print "Warning: $_\n" for @{$crms->GetErrors()};

sub commify
{
  my $input = shift;
  my $input2 = reverse $input;
  $input2 =~ s<(\d\d\d)(?=\d)(?!\d*\.)><$1,>g;
  #print "$input -> $input2\n";
  return reverse $input2;
}
