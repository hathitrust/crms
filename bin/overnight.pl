#!/usr/bin/perl

use strict;
use warnings;
BEGIN { unshift(@INC, $ENV{'SDRROOT'}. '/crms/cgi'); }

use CRMS;
use Getopt::Long qw(:config no_ignore_case bundling);
use Mail::Sendmail;
use Encode;

my $usage = <<END;
USAGE: $0 [-acCehlNpqtv] [-m MAIL [-m MAIL...]] [start_date [end_date]]

Processes reviews, exports determinations, updates candidates,
updates the queue, recalculates user stats, and clears stale locks.

If the start or end dates are specified, only loads candidates
with latest rights DB timestamp between them.

-a      Do not synchronize local attribute/reason tables with Rights Database.
-c      Do not update candidates.
-e      Do not process statuses or export determinations.
-h      Print this help message.
-l      Do not clear old locks.
-m MAIL Send report to MAIL. May be repeated for multiple recipients.
-N      Do not check no meta volumes in queue for priority restoration.
-p      Run in production.
-q      Do not update queue.
-s      Do not recalculate monthly stats.
-t      Run in training.
-v      Be verbose. May be repeated for increased verbosity.
END

my $instance;
my ($skipAttrReason, $skipCandidates, $skipExport, $help, $skipLocks,
    @mails, $skipQueueNoMeta, $production, $skipQueue, $skipStats, $training,
    $verbose);

Getopt::Long::Configure ('bundling');
die 'Terminating' unless GetOptions(
           'a'    => \$skipAttrReason,
           'c'    => \$skipCandidates,
           'e'    => \$skipExport,
           'h|?'  => \$help,
           'l'    => \$skipLocks,
           'm:s@' => \@mails,
           'N'    => \$skipQueueNoMeta,
           'p'    => \$production,
           'q'    => \$skipQueue,
           's'    => \$skipStats,
           't'    => \$training,
           'v+'   => \$verbose);

die $usage if $help;
$instance = 'production' if $production;
$instance = 'crms-training' if $training;

my $start = undef;
my $end = undef;
if (scalar @ARGV)
{
  $start = $ARGV[0];
  die "Bad date format ($start); should be in the form e.g. 2010-08-29" unless $start =~ m/^\d\d\d\d-\d\d-\d\d$/;
  $start .= ' 00:00:00';
  if (scalar @ARGV > 1)
  {
    $end = $ARGV[1];
    die "Bad date format ($end); should be in the form e.g. 2010-08-29" unless $end =~ m/^\d\d\d\d-\d\d-\d\d$/;
    $end .= ' 23:59:59'
  }
}

my $crms = CRMS->new(
    verbose  => 0,
    instance => $instance
);


my $subj = $crms->SubjectLine('Nightly Processing');
my $body = $crms->StartHTML($subj);
$crms->set('ping', 'yes');
$crms->set('messages', $body) if scalar @mails;
$crms->ReportMsg(sprintf "%s\n", $crms->DbInfo()) if $verbose;

if ($skipExport) { $crms->ReportMsg('-e flag set; skipping queue processing and export.', 1); }
else
{
  $crms->ReportMsg('Starting to process the statuses.', 1);
  $crms->ProcessReviews();
  $crms->ReportMsg('<b>Done</b> processing the statuses.', 1);
  $crms->ReportMsg('Starting to create export for the rights db. You should receive a separate email when this completes.', 1);
  my $rc = $crms->ClearQueueAndExport();
  $crms->ReportMsg($rc, 1);
  $crms->ReportMsg("<b>Done</b> exporting.", 1);
}
#if (!$crms->GetSystemVar('cri')) { $crms->ReportMsg('CRI system variable not set; skipping.', 1); }
#elsif ($skipCRI) { $crms->ReportMsg('-i flag set; skipping CRI processing.', 1); }
#else
#{
#  $crms->ReportMsg('Starting to process CRI.', 1);
#  use CRI;
#  my $cri = CRI->new('crms' => $crms);
#  $cri->ProcessCRI();
#  $crms->ReportMsg('DONE processing CRI.', 1);
#}

if ($skipCandidates) { $crms->ReportMsg("-c flag set; skipping candidates load.", 1); }
else
{
  $crms->ReportMsg('Starting to load new volumes into candidates.', 1);
  my $added = $crms->LoadNewItemsInCandidates($start, $end);
  $crms->ReportMsg("<b>Done</b> loading $added new volumes into candidates.", 1);
  $subj = $crms->SubjectLine("Candidates Load ($added new)");
}

if ($skipQueue) { $crms->ReportMsg('-q flag set; skipping queue load.', 1); }
else
{
  $crms->ReportMsg('Starting to load new volumes into queue.', 1);
  $crms->LoadQueue();
  $crms->ReportMsg('<b>Done</b> loading new volumes into queue.', 1);
}

if ($skipStats) { $crms->ReportMsg('-s flag set; skipping monthly stats.', 1); }
else
{
  $crms->ReportMsg('Starting to update monthly stats.', 1);
  $crms->UpdateUserStats();
  $crms->ReportMsg('<b>Done</b> updating monthly stats.', 1);
}

if ($skipLocks) { $crms->ReportMsg('-l flag set; skipping unlock.', 1); }
else
{
  $crms->ReportMsg('Starting to clear stale locks.', 1);
  $crms->RemoveOldLocks();
  $crms->ReportMsg('<b>Done</b> clearing stale locks.', 1);
}

if ($skipAttrReason) { $crms->ReportMsg('-a flag set; skipping attr/reason sync.', 1); }
else
{
  $crms->ReportMsg('Starting to synchronize attr/reason tables with Rights Database.', 1);
  $crms->AttrReasonSync();
  $crms->ReportMsg('<b>Done</b> synchronizing attr/reasons.', 1);
}

if ($skipQueueNoMeta) { $crms->ReportMsg('-N flag set; skipping queue no meta restoration.', 1); }
else
{
  $crms->ReportMsg('Starting to restore queue no meta volumes.', 1);
  $crms->UpdateQueueNoMeta();
  $crms->ReportMsg('<b>Done</b> restoring queue no meta volumes.', 1);
}

my $r = $crms->GetErrors();
$crms->ReportMsg(sprintf("There were %d errors%s", scalar @{$r}, (scalar @{$r})? ':':'.'));
$crms->ReportMsg("$_") for @{$r};

$crms->ReportMsg('All <b>done</b> with nightly script.', 1);
$body = $crms->get('messages');
$body .= "  </body>\n</html>\n";

#$crms->set('export_file', 'crms_2020-02-24_17_11_06.rights');
#$crms->set('export_path', '/htapps/moseshll.babel/crms/prep/crms_2020-02-24_17_11_06.rights');
EmailReport() if scalar @mails;

print "Warning: $_\n" for @{$crms->GetErrors()};



sub EmailReport
{
  my $file = $crms->get('export_file');
  my $path = $crms->get('export_path');
  @mails = map { ($_ =~ m/@/)? $_:($_ . '@umich.edu'); } @mails;
  my $to = join ',', @mails;
  my $contentType = 'text/html; charset="UTF-8"';
  my $message = $body;
  if ($file && $path)
  {
    my $boundary = "====" . time() . "====";
    $contentType = "multipart/mixed; boundary=\"$boundary\"";
    open (my $FH, '<', $path) or die "Cannot read $path: $!";
    binmode $FH; undef $/;
    my $enc = <$FH>;
    close $FH;
    $boundary = '--'.$boundary;
    $message = <<END_OF_BODY;
$boundary
Content-Type: text/html; charset="UTF-8"
Content-Transfer-Encoding: quoted-printable

$body
$boundary
Content-Type: text/plain; charset="UTF-8"; name="$file"
Content-Transfer-Encoding: base64
Content-Disposition: attachment; filename="$file"

$enc
$boundary--
END_OF_BODY
  }
  my $bytes = Encode::encode('utf8', $message);
  my %mail = ('from'         => 'crms-mailbot@umich.edu',
              'to'           => $to,
              'subject'      => $subj,
              'content-type' => $contentType,
              'body'         => $message
              );
  sendmail(%mail) || $crms->SetError("Error: $Mail::Sendmail::error\n");
}

