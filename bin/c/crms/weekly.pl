#!/usr/bin/perl

# This script can be run from crontab

my $DLXSROOT;
my $DLPS_DEV;
BEGIN 
{ 
  $DLXSROOT = $ENV{'DLXSROOT'}; 
  $DLPS_DEV = $ENV{'DLPS_DEV'}; 
  unshift (@INC, $DLXSROOT . '/cgi/c/crms/');
}

use strict;
use warnings;
use CRMS;
use Getopt::Long;
use Mail::Sender;

my $usage = <<'END';
USAGE: $0 [-hnpqv] [-d DATE][-m USER [-m USER...]] [-x SYS]

Sends weekly activity reports to all active reviewers.

-d DATE  Use YYYY-MM-DD[ HH:MM:SS] as the current date.
-h       Print this help message.
-m MAIL  Also send report to MAIL. May be repeated for multiple recipients.
         Appends '@umich.edu' in e-mail if necessary.
-n       No-op; do not send e-mail at all.
-p       Run in production.
-q       Send only to addresses specified via the -m flag.
-v       Be verbose.
-x SYS   Set SYS as the system to execute.
END

my $date;
my $help;
my $nomail;
my @mails;
my $noop;
my $production;
my $quiet;
my $sys;
my $verbose = 0;

Getopt::Long::Configure ('bundling');
die 'Terminating' unless GetOptions('d:s' => \$date,
           'h|?'  => \$help,
           'm:s@' => \@mails,
           'n'    => \$noop,
           'p'    => \$production,
           'q'    => \$quiet,
           'v+'   => \$verbose,
           'x:s'  => \$sys);
$DLPS_DEV = undef if $production;
print "Verbosity $verbose\n" if $verbose;
die "$usage\n\n" if $help;

die "Bad date format ($date); should be in the form e.g. 2010-08-29"
  if defined $date and $date !~ m/^\d\d\d\d-\d\d-\d\d(\s+\d\d:\d\d:\d\d)?$/;
$date .= ' 00:00:00' if defined $date and $date !~ m/\d\d:\d\d:\d\d$/;

my $crms = CRMS->new(
    logFile => $DLXSROOT . '/prep/c/crms/weekly_hist.txt',
    sys     => $sys,
    verbose => $verbose,
    root    => $DLXSROOT,
    dev     => $DLPS_DEV
);

my $sender = new Mail::Sender { smtp => 'mail.umdl.umich.edu',
                                from => 'crms-mailbot@umich.edu',
                                on_errors => 'undef' }
or die "Error in mailing : $Mail::Sender::Error\n";
my $system = $crms->System();
my @recips;

my $msg = $crms->StartHTML();
$msg .= <<'END';
<h3>Total reviews this week: __TOTEL_THIS_WEEK__</h3>
<h3>Total reviews last week: __TOTEL_LAST_WEEK__</h3>
<h3>We did __PERCENT__ (__COUNT__) out of our weekly target of __TARGET__ determinations.</h3>
<table style="border:1px solid #000000;border-collapse:collapse;">
<tr><th style="background-color:#000000;color:#FFFFFF;padding:4px 20px 2px 6px;">Total by Institution</th>
    <th style="background-color:#000000;color:#FFFFFF;padding:4px 20px 2px 6px;">this week</th>
    <th style="background-color:#000000;color:#FFFFFF;padding:4px 20px 2px 6px;">last week</th>
</tr>
__TABLE__
</table>
<h4>keden-reviewer: __KEDEN_COUNT__</h4>
END
my $table = '';
my $sql = 'SELECT NOW()';
my $now = $crms->SimpleSqlGet($sql);
$now = $date if defined $date;
$sql = 'SELECT DATE_SUB(?, INTERVAL 1 WEEK)';
my $startThis = $crms->SimpleSqlGet($sql, $now);
$sql = 'SELECT DATE_SUB(?, INTERVAL 2 WEEK)';
my $startLast = $crms->SimpleSqlGet($sql, $now);

$sql = 'SELECT COUNT(*) FROM historicalreviews WHERE time>=? AND time<? AND user!="autocrms"';
my $thisn = $crms->SimpleSqlGet($sql, $startThis, $now);
my $lastn = $crms->SimpleSqlGet($sql, $startLast, $startThis);
$sql = 'SELECT COUNT(*) FROM reviews WHERE time>=? AND time<?';
$thisn += $crms->SimpleSqlGet($sql, $startThis, $now);
$lastn += $crms->SimpleSqlGet($sql, $startLast, $startThis);
$msg =~ s/__TOTEL_THIS_WEEK__/$thisn/;
$msg =~ s/__TOTEL_LAST_WEEK__/$lastn/;

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
  $thisn = $crms->SimpleSqlGet($sql, $id, $startThis, $now);
  $lastn = $crms->SimpleSqlGet($sql, $id, $startLast, $startThis);
  $sql = 'SELECT COUNT(*) FROM reviews r INNER JOIN users u ON r.user=u.id'.
         ' INNER JOIN institutions i ON u.institution=i.id'.
         ' WHERE i.id=? AND r.time>=? AND r.time<?'.
         ' AND u.reviewer+u.advanced+u.expert>0';
  $thisn += $crms->SimpleSqlGet($sql, $id, $startThis, $now);
  $lastn += $crms->SimpleSqlGet($sql, $id, $startLast, $startThis);
  $table .= "<tr><td style='border:1px solid #000000;'>$name</td>".
            "<td style='border:1px solid #000000;'>$thisn</td>".
            "<td style='border:1px solid #000000;'>$lastn</td></tr>\n";
}
$msg =~ s/__TABLE__/$table/;

$sql = 'SELECT COUNT(*) FROM historicalreviews WHERE time>=? AND time<? AND user="keden-reviewer"';
my $kn = $crms->SimpleSqlGet($sql, $startThis, $now);
$sql = 'SELECT COUNT(*) FROM reviews WHERE time>=? AND time<? AND user="keden-reviewer"';
$kn += $crms->SimpleSqlGet($sql, $startThis, $now);
$msg =~ s/__KEDEN_COUNT__/$kn/i;

$sql = 'SELECT COUNT(*) FROM exportdata WHERE src="candidates" AND time>=? AND time<?';
my $count = $crms->SimpleSqlGet($sql, $startThis, $now);
$sql = 'SELECT COUNT(*)/(DATEDIFF("2015-11-30 23:59:59", ?)/7) FROM candidates';
my $target = int $crms->SimpleSqlGet($sql, $now);
my $pct = sprintf('%.1f%%', 100.0 * $count / $target);
$msg =~ s/__PERCENT__/$pct/;
$msg =~ s/__COUNT__/$count/;
$msg =~ s/__TARGET__/$target/;

$msg .= sprintf('<span style="font-size:.9em;">Report for week %s to %s, compared to week %s to %s</span>',
                $crms->FormatDate($startThis), $crms->FormatDate($now),
                $crms->FormatDate($startLast), $crms->FormatDate($startThis));
$msg .= '</body></html>';
my $title = sprintf '%s %sWednesday Data Report',
                    $crms->System(),
                    ($DLPS_DEV)? 'Dev ':'';
my %recipients;
$recipients{$_}=1 for @mails;
if (!$quiet)
{
  $sql = 'SELECT id FROM users WHERE reviewer+advanced+expert>0'.
         ' AND NOT id LIKE "%-reviewer" AND NOT id LIKE "%-expert"';
  my $ref = $crms->SelectAll($sql);
  $recipients{$_->[0]}=1 for @{$ref};
}
@mails = ();
foreach my $user (sort keys %recipients)
{
  $user .= '@umich.edu' unless $user =~ m/@/;
  push @mails, $user;
}
my $to = join ',', @mails;

if ($noop)
{
  print "No-op set; not sending e-mail to $to\n" if $verbose;
}
else
{
  if (scalar @mails && !$noop)
  {
    $sender->OpenMultipart({
      to => $to,
      subject => $title,
      ctype => 'text/html',
      encoding => 'utf-8'
    }) or die $Mail::Sender::Error,"\n";
    $sender->Body();
    $sender->SendEnc($msg);
    $sender->Close();
  }
}
print "Warning: $_\n" for @{$crms->GetErrors()};
