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
use Encode;

my $usage = <<'END';
USAGE: $0 [-hlptv] [-m USER [-m USER...]]

Sends weekly activity reports.

-h       Print this help message.
-l       Send to the MCommunity list for each CRMS system.
-m MAIL  Also send report to MAIL. May be repeated for multiple recipients.
-p       Run in production.
-t       Run in training.
-v       Be verbose.
END

my $help;
my $instance;
my $lists;
my @mails;
my $production;
my $training;
my $sys;
my $verbose = 0;

Getopt::Long::Configure ('bundling');
die 'Terminating' unless GetOptions('h|?'  => \$help,
           'l'    => \$lists,
           'm:s@' => \@mails,
           'p'    => \$production,
           't'    => \$training,
           'v+'   => \$verbose);
$instance = 'production' if $production;
$instance = 'crms-training' if $training;
print "Verbosity $verbose\n" if $verbose;
die "$usage\n\n" if $help;

my %systems;
my %mails;
my $crms = CRMS->new(
    sys      => 'crmsworld',
    verbose  => $verbose,
    instance => $instance
);
#$systems{$crms->System()} = $crms;
$crms = CRMS->new(
    sys      => 'crms',
    verbose  => $verbose,
    instance => $instance
);
$systems{$crms->System()} = $crms;
$mails{$_} = 1 for @mails;
my $msg = $crms->StartHTML();
my $sql = 'SELECT NOW()';
my $now = $crms->SimpleSqlGet($sql);
$sql = 'SELECT DATE_SUB(?, INTERVAL 1 WEEK)';
my $startThis = $crms->SimpleSqlGet($sql, $now);
$sql = 'SELECT DATE_SUB(?, INTERVAL 2 WEEK)';
my $startLast = $crms->SimpleSqlGet($sql, $now);
foreach my $system (sort keys %systems)
{
  $crms = $systems{$system};
  $msg .= <<'END';
  <h2>__SYSTEM__</h2>
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
  printf "%s: %s\n", $crms->System(), Utilities::StringifySql($sql, $startThis, $now) if $verbose>1;
  my $thisn = $crms->SimpleSqlGet($sql, $startThis, $now);
  my $lastn = $crms->SimpleSqlGet($sql, $startLast, $startThis);
  $sql = 'SELECT COUNT(*) FROM reviews WHERE time>=? AND time<?';
  printf "%s: %s\n", $crms->System(), Utilities::StringifySql($sql, $startThis, $now) if $verbose>1;
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
  $msg =~ s/__SYSTEM__/$system/;
  $msg =~ s/__TOTAL_THIS_WEEK__/$thisn/g;
  $msg =~ s/__TOTAL_LAST_WEEK__/$lastn/g;
  $mails{$crms->GetSystemVar('mailingList')} = 1 if $lists;
}

$msg .= sprintf('<span style="font-size:.9em;">Report for week %s to %s, compared to week %s to %s</span>',
                $crms->FormatDate($startThis), $crms->FormatDate($now),
                $crms->FormatDate($startLast), $crms->FormatDate($startThis));
$msg .= '</body></html>';

@mails = keys %mails;
if (scalar @mails)
{
  my $subj = $crms->SubjectLine('Wednesday Data Report');
  @mails = map { ($_ =~ m/@/)? $_:($_ . '@umich.edu'); } @mails;
  my $to = join ',', @mails;
  print "Sending to $to\n" if $verbose;
  use Encode;
  use Mail::Sendmail;
  my $bytes = encode('utf8', $msg);
  my %mail = ('from'         => 'crms-mailbot@umich.edu',
              'to'           => $to,
              'subject'      => $subj,
              'content-type' => 'text/html; charset="UTF-8"',
              'body'         => $bytes
              );
  sendmail(%mail) || $crms->SetError("Error: $Mail::Sendmail::error\n");
}
print "Warning: $_\n" for @{$crms->GetErrors()};
