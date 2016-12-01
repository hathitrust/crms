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
use Utilities;

my $usage = <<'END';
USAGE: $0 [-hnpqv] [-m USER [-m USER...]]

Sends weekly activity reports to RCPC participants.

-h       Print this help message.
-m MAIL  Also send report to MAIL. May be repeated for multiple recipients.
-n       No-op; do not send e-mail at all.
-p       Run in production.
-q       Send only to addresses specified via the -m flag.
-v       Be verbose.
END

my $help;
my $nomail;
my @mails;
my $noop;
my $production;
my $quiet;
my $sys;
my $verbose = 0;

Getopt::Long::Configure ('bundling');
die 'Terminating' unless GetOptions('h|?'  => \$help,
           'm:s@' => \@mails,
           'n'    => \$noop,
           'p'    => \$production,
           'q'    => \$quiet,
           'v+'   => \$verbose);
$DLPS_DEV = undef if $production;
print "Verbosity $verbose\n" if $verbose;
die "$usage\n\n" if $help;

my $crms = CRMS->new(
    logFile => $DLXSROOT . '/prep/c/crms/weekly_hist.txt',
    sys     => 'crms',
    verbose => $verbose,
    root    => $DLXSROOT,
    dev     => $DLPS_DEV
);

my $sender = new Mail::Sender { smtp => 'mail.umdl.umich.edu',
                                from => 'crms-mailbot@umich.edu',
                                on_errors => 'undef' }
or die "Error in mailing : $Mail::Sender::Error\n";
my $system = $crms->System();

my $start = $crms->SimpleSqlGet('SELECT DATE_SUB(NOW(), INTERVAL 1 WEEK)');
my $startFmt = $crms->FormatDate($start);
my $totalTop = $crms->SimpleSqlGet('SELECT COUNT(*) FROM inserts WHERE iid=0');
my $weekTop = $crms->SimpleSqlGet('SELECT COUNT(*) FROM inserts WHERE iid=0 AND time>?', $start);
my $totalIns = $crms->SimpleSqlGet('SELECT COUNT(*) FROM inserts WHERE iid>0');
my $weekIns = $crms->SimpleSqlGet('SELECT COUNT(*) FROM inserts WHERE iid>0 AND time>?', $start);

my $msg = $crms->StartHTML();
$msg .= <<END;
<h2>Current RCPC Progress</h2>
<table style="border:1px solid #000000;border-collapse:collapse;">
  <tr style="text-align:center;">
    <th style="background-color:#000000;color:#FFFFFF;padding:4px 20px 2px 6px;"></th>
    <th style="background-color:#000000;color:#FFFFFF;padding:4px 20px 2px 6px;">Past Week</th>
    <th style="background-color:#000000;color:#FFFFFF;padding:4px 20px 2px 6px;">Total</th>
  </tr>
  <tr style="text-align:center;">
    <th style="background-color:#000000;color:#FFFFFF;padding:4px 20px 2px 6px;">Top-level Reviews</th>
    <td><span style="font-size:1.3em;color:#7F75BC;">$weekTop</span></td>
    <td><span style="font-size:1.3em;color:#7F75BC;">$totalTop</span></td>
  <tr>
  <tr style="text-align:center;">
    <th style="background-color:#000000;color:#FFFFFF;padding:4px 20px 2px 6px;">Inserts</th>
    <td><span style="font-size:1.3em;color:#7F75BC;">$weekIns</span></td>
    <td><span style="text-align:center;font-size:1.3em;color:#7F75BC;">$totalIns</span></td>
  <tr>
</table>
<br/><span style="text-align:center;font-size:1.1em;color:#7F75BC;">Past week includes all reviews after $startFmt</span>
</body>
</html>
END

push @mails, 'rcpc-copyright@umich.edu' unless $quiet;

my $to = join ',', @mails;
if ($noop)
{
  print "No-op set; not sending e-mail to $to\n" if $verbose;
}
else
{
  if (scalar @mails)
  {
    $sender->OpenMultipart({
      to => $to,
      subject => $crms->SubjectLine('RCPC Progress Report'),
      ctype => 'text/html',
      encoding => 'utf-8'
    }) or die $Mail::Sender::Error,"\n";
    $sender->Body();
    $sender->SendEnc($msg);
    $sender->Close();
  }
}
print "Warning: $_\n" for @{$crms->GetErrors()};
