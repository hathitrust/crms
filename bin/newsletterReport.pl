#!/usr/bin/perl

my ($root);
BEGIN 
{ 
  $root = $ENV{'SDRROOT'};
  $root = $ENV{'DLXSROOT'} unless $root and -d $root;
  unshift(@INC, $root. '/crms/cgi');
  unshift(@INC, $root. '/cgi/c/crms');
}

use strict;
use warnings;
use CRMS;
use Getopt::Long;
use Utilities;

my $usage = <<END;
USAGE: $0 [-hnpv] [-m USER [-m USER...]]

Sends monthly determination	stats for HathiTrust newsletter.

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
# Get first day of last month, in sql and English formats.
my $lastfirst = $crms->SimpleSqlGet('SELECT DATE_SUB(DATE_SUB(CURDATE(),INTERVAL (DAY(CURDATE())-1) DAY), INTERVAL 1 MONTH)');
# Get last day of last month for the overall numbers.
my $lastlast = $crms->SimpleSqlGet('SELECT DATE_SUB(CURDATE(),INTERVAL (DAY(CURDATE())) DAY)');
my $my = $crms->SimpleSqlGet('SELECT DATE_FORMAT(?,"%Y-%m")', $lastfirst);
my $myEng = $crms->SimpleSqlGet('SELECT DATE_FORMAT(?,"%M, %Y")', $lastfirst);
my $dWorld = $crms->SimpleSqlGet('SELECT COUNT(*) FROM exportdata WHERE DATE(time)<=?', $lastlast);
my $dWorldM = $crms->SimpleSqlGet("SELECT COUNT(*) FROM exportdata WHERE DATE(time) LIKE '$my%'");
my $pdWorld = $crms->SimpleSqlGet('SELECT COUNT(*) FROM exportdata WHERE DATE(time)<=? AND (attr="pd" OR attr="pdus")', $lastlast);
my $pdWorldM = $crms->SimpleSqlGet("SELECT COUNT(*) FROM exportdata WHERE DATE(time) LIKE '$my%' AND (attr='pd' OR attr='pdus')");
my $dUS = $crmsUS->SimpleSqlGet('SELECT COUNT(*) FROM exportdata WHERE DATE(time)<=?', $lastlast);
my $dUSM = $crmsUS->SimpleSqlGet("SELECT COUNT(*) FROM exportdata WHERE DATE(time) LIKE '$my%'");
my $pdUS = $crmsUS->SimpleSqlGet('SELECT COUNT(*) FROM exportdata WHERE DATE(time)<=? AND (attr="pd" OR attr="pdus")', $lastlast);
my $pdUSM = $crmsUS->SimpleSqlGet("SELECT COUNT(*) FROM exportdata WHERE DATE(time) LIKE '$my%' AND (attr='pd' OR attr='pdus')");

my $pdWorldPct = sprintf '%.1f%%', 100.0 * $pdWorld / $dWorld;
my $pdWorldMPct = sprintf '%.1f%%', 100.0 * $pdWorldM / $dWorldM;
my $pdUSPct = sprintf '%.1f%%', 100.0 * $pdUS / $dUS;
my $pdUSMPct = sprintf '%.1f%%', 100.0 * $pdUSM / $dUSM;

$dWorld = commify($dWorld);
$dWorldM = commify($dWorldM);
$pdWorld = commify($pdWorld);
$pdWorldM = commify($pdWorldM);
$dUS = commify($dUS);
$dUSM = commify($dUSM);
$pdUS = commify($pdUS);
$pdUSM = commify($pdUSM);

my $msg = $crms->StartHTML();
$msg .= <<END;
<table style="border:1px solid #000000;border-collapse:collapse;">
  <tr style="text-align:center;">
    <th style="background-color:#000000;color:#FFFFFF;padding:4px 20px 2px 6px;"></th>
    <th colspan="2" style="background-color:#000000;color:#FFFFFF;padding:4px 6px 2px 6px;">$myEng</th>
    <th colspan="2" style="background-color:#000000;color:#FFFFFF;padding:4px 6px 2px 6px;">Overall</th>
  </tr>
  <tr style="text-align:center;">
    <th style="background-color:#000000;color:#FFFFFF;padding:4px 6px 2px 6px;"></th>
    <th style="background-color:#000000;color:#FFFFFF;padding:4px 6px 2px 6px;text-align:center;">Public Domain Determinations</th>
    <th style="background-color:#000000;color:#FFFFFF;padding:4px 6px 2px 6px;text-align:center;">All Determinations</th>
    <th style="background-color:#000000;color:#FFFFFF;padding:4px 6px 2px 6px;text-align:center;">Public Domain Determinations</th>
    <th style="background-color:#000000;color:#FFFFFF;padding:4px 6px 2px 6px;text-align:center;">All Determinations</th>
  </tr>
  <tr style="text-align:center;">
    <th style="background-color:#000000;color:#FFFFFF;padding:4px 20px 2px 6px;text-align:left;">CRMS-US</th>
    <td style="padding:4px 6px 2px 6px;text-align:center;">$pdUSM ($pdUSMPct)</th>
    <td style="padding:4px 6px 2px 6px;text-align:center;">$dUSM</th>
    <td style="padding:4px 6px 2px 6px;text-align:center;">$pdUS ($pdUSPct)</th>
    <td style="padding:4px 6px 2px 6px;text-align:center;">$dUS</th>
  </tr>
  <tr style="text-align:center;">
    <th style="background-color:#000000;color:#FFFFFF;padding:4px 20px 2px 6px;text-align:left;">CRMS-World</th>
    <td style="padding:4px 6px 2px 6px;text-align:center;">$pdWorldM ($pdWorldMPct)</th>
    <td style="padding:4px 6px 2px 6px;text-align:center;">$dWorldM</th>
    <td style="padding:4px 6px 2px 6px;text-align:center;">$pdWorld ($pdWorldPct)</th>
    <td style="padding:4px 6px 2px 6px;text-align:center;">$dWorld</th>
  </tr>
</table>
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
                'subject'      => 'CRMS Newsletter Report for '. $myEng,
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
