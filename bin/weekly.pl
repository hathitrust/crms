#!/usr/bin/perl

use strict;
use warnings;
use utf8;

BEGIN {
  die "SDRROOT environment variable not set" unless defined $ENV{'SDRROOT'};
  use lib $ENV{'SDRROOT'} . '/crms/cgi';
  use lib $ENV{'SDRROOT'} . '/crms/lib';
}

use Encode;
use Getopt::Long;
use Utilities;

use CRMS;
use CRMS::Cron;


my $usage = <<END;
USAGE: $0 [-hptv] [-m USER [-m USER...]]

Sends weekly activity report.

-h       Print this help message.
-m MAIL  Also send report to MAIL. May be repeated for multiple recipients.
-p       Run in production.
-q       Quiet: do not send any e-mail at all. For testing.
-t       Run in training.
-v       Emit verbose debugging information. May be repeated.
END

my $help;
my $instance;
my @mails;
my $production;
my $quiet;
my $training;
my $verbose = 0;

Getopt::Long::Configure ('bundling');
die 'Terminating' unless GetOptions('h|?'  => \$help,
           'm:s@' => \@mails,
           'p'    => \$production,
           'q'    => \$quiet,
           't'    => \$training,
           'v+'   => \$verbose);
$instance = 'production' if $production;
$instance = 'crms-training' if $training;
if ($help) { print $usage. "\n"; exit(0); }
print "Verbosity $verbose\n" if $verbose;

my $crms = CRMS->new(
    verbose  => $verbose,
    instance => $instance
);
my $cron = CRMS::Cron->new(crms => $crms);

my $msg = $crms->StartHTML();
my $sql = 'SELECT NOW()';
my $now = $crms->SimpleSqlGet($sql);
$sql = 'SELECT DATE_SUB(?, INTERVAL 1 WEEK)';
my $startThis = $crms->SimpleSqlGet($sql, $now);
$sql = 'SELECT DATE_SUB(?, INTERVAL 2 WEEK)';
my $startLast = $crms->SimpleSqlGet($sql, $now);

$msg .= <<'END';
<table style="border:1px solid #000000;border-collapse:collapse;">
  <tr><th style="background-color:#000000;color:#FFFFFF;padding:4px 20px 2px 6px;">Total by Institution</th>
      <th style="background-color:#000000;color:#FFFFFF;padding:4px 20px 2px 6px;">This week</th>
      <th style="background-color:#000000;color:#FFFFFF;padding:4px 20px 2px 6px;">Last week</th>
  </tr>
  __TABLE__
  <tr><th style="background-color:#000000;color:#FFFFFF;padding:4px 20px 2px 6px;">Total</th>
      <td style='border:1px solid #000000;'><strong>__TOTAL_THIS_WEEK__</strong></td>
      <td style='border:1px solid #000000;'><strong>__TOTAL_LAST_WEEK__</strong></td>
  </tr>
</table>
<br/>
END
my $table = '';
$sql = 'SELECT COUNT(*) FROM historicalreviews WHERE time>=? AND time<? AND user!="autocrms"';
printf "%s\n", Utilities::StringifySql($sql, $startThis, $now) if $verbose>1;
my $thisn = $crms->SimpleSqlGet($sql, $startThis, $now);
my $lastn = $crms->SimpleSqlGet($sql, $startLast, $startThis);
$sql = 'SELECT COUNT(*) FROM reviews WHERE time>=? AND time<?';
printf "%s\n", Utilities::StringifySql($sql, $startThis, $now) if $verbose>1;
$thisn += $crms->SimpleSqlGet($sql, $startThis, $now);
$lastn += $crms->SimpleSqlGet($sql, $startLast, $startThis);
$sql = 'SELECT id,shortname FROM institutions'.
       ' WHERE id IN (SELECT DISTINCT institution FROM users'.
       '  WHERE reviewer+advanced+expert>0)'.
       ' ORDER BY shortname ASC';
my $ref = $crms->SelectAll($sql);
foreach my $row (@{$ref})
{
  my $id = $row->[0];
  my $name = $row->[1];
  $sql = 'SELECT COUNT(*) FROM historicalreviews r INNER JOIN users u ON r.user=u.id'.
         ' INNER JOIN institutions i ON u.institution=i.id'.
         ' WHERE i.id=? AND r.time>=? AND r.time<?'.
         ' AND u.reviewer+u.advanced+u.expert>0';
  my $userThis = $crms->SimpleSqlGet($sql, $id, $startThis, $now);
  my $userLast = $crms->SimpleSqlGet($sql, $id, $startLast, $startThis);
  $sql = 'SELECT COUNT(*) FROM reviews r INNER JOIN users u ON r.user=u.id'.
         ' INNER JOIN institutions i ON u.institution=i.id'.
         ' WHERE i.id=? AND r.time>=? AND r.time<?'.
         ' AND u.reviewer+u.advanced+u.expert>0';
  $userThis += $crms->SimpleSqlGet($sql, $id, $startThis, $now);
  $userLast += $crms->SimpleSqlGet($sql, $id, $startLast, $startThis);
  $table .= "<tr><td style='border:1px solid #000000;'>$name</td>".
            "<td style='border:1px solid #000000;'>$userThis</td>".
            "<td style='border:1px solid #000000;'>$userLast</td></tr>\n";
}
$msg =~ s/__TABLE__/$table/;
$msg =~ s/__TOTAL_THIS_WEEK__/$thisn/g;
$msg =~ s/__TOTAL_LAST_WEEK__/$lastn/g;


$msg .= sprintf('<span style="font-size:.9em;">Report for week %s to %s, compared to week %s to %s</span>',
                $crms->FormatDate($startThis), $crms->FormatDate($now),
                $crms->FormatDate($startLast), $crms->FormatDate($startThis));
$msg .= '</body></html>';

my $recipients = $cron->recipients(@mails);
if (scalar @$recipients)
{
  my $subj = $crms->SubjectLine('Wednesday Data Report');
  my $to = join ',', @$recipients;
  print "Sending to $to\n" if $verbose;
  use Encode;
  use Mail::Sendmail;
  my $bytes = encode('utf8', $msg);
  my %mail = ('from'         => $crms->GetSystemVar('sender_email'),
              'to'           => $to,
              'subject'      => $subj,
              'content-type' => 'text/html; charset="UTF-8"',
              'body'         => $bytes
              );
  sendmail(%mail) || $crms->SetError("Error: $Mail::Sendmail::error\n") unless $quiet;
}
print "Warning: $_\n" for @{$crms->GetErrors()};
