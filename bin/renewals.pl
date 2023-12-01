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
use JSON::XS;
use Term::ANSIColor qw(:constants);

use CRMS;
use CRMS::Cron;
use Utilities;

$Term::ANSIColor::AUTORESET = 1;

my $usage = <<END;
USAGE: $0 [-hnpqv] [-m MAIL [-m MAIL...]]

Produces TSV file of HTID and renewal ID for Zephir download at
https://www.hathitrust.org/files/CRMSRenewals.tsv

Data hosted on macc-ht-web-000 etc at config->hathitrust_files_directory

For each distinct HTID in historical reviews with one or more renewal IDs,
gets all validated reviews with renewal IDs.
If there is an expert review, that renewal ID is written and no further
reviews are checked.
Otherwise, the value written is the unique renewal ID agreed on by all reviews.
If there is more than one distinct renewal ID then no value is written.

-h       Print this help message.
-m MAIL  Send note to MAIL. May be repeated for multiple recipients.
-n       No-op; do not send e-mail at all.
-p       Run in production.
-v       Emit verbose debugging information. May be repeated.
END

my $help;
my $instance;
my $nomail;
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
if ($help) { print $usage. "\n"; exit(0); }
print "Verbosity $verbose\n" if $verbose;

my $crms = CRMS->new(
    verbose  => $verbose,
    instance => $instance
);
my $cron = CRMS::Cron->new(crms => $crms);

my $outfile = $crms->FSPath('prep', 'CRMSRenewals.tsv');
my $msg = $crms->StartHTML();
$msg .= <<'END';
<h2>CRMS US Monographs</h2>
<p>Exported __N__ Stanford renewal records (__OUTFILE__) to
<a href="https://www.hathitrust.org/files/CRMSRenewals.tsv">HathiTrust</a>.
</p>
END

my $n = CheckStanford();
$msg =~ s/__N__/$n/g;
$msg =~ s/__OUTFILE__/$outfile/g;

if ($noop) {
  print "Noop set: not moving file to new location.\n";
  $msg .= '<strong>Noop set: not moving file to new location.</strong>';
}
else {
  eval {
    $crms->MoveToHathitrustFiles($outfile);
  };
  if ($@) {
    $msg .= '<strong>Error moving TSV file: $@</strong>';
  }
}
$msg .= "<p>Warning: $_</p>\n" for @{$crms->GetErrors()};
$msg .= '</body></html>';

my $subject = $crms->SubjectLine('Stanford Renewal Report');
my $recipients = $cron->recipients(@mails);
my $to = join ',', @$recipients;
if ($noop || scalar @$recipients == 0)
{
  print "No-op or no mails set; not sending e-mail to {$to}\n" if $verbose;
  print "$msg\n";
}
else
{
  if (scalar @$recipients)
  {
    use Encode;
    use Mail::Sendmail;
    my $bytes = encode('utf8', $msg);
    my %mail = ('from'         => $crms->GetSystemVar('sender_email'),
                'to'           => $to,
                'subject'      => $subject,
                'content-type' => 'text/html; charset="UTF-8"',
                'body'         => $bytes
                );
    sendmail(%mail) || $crms->SetError("Error: $Mail::Sendmail::error\n");
  }
}

# Returns number of lines written.
sub CheckStanford
{
  my $jsonxs = JSON::XS->new->utf8->canonical(1)->pretty(0);
  open my $out, '>:encoding(UTF-8)', $outfile;
  my $sql = 'SELECT NOW()';
  my $now = $crms->SimpleSqlGet($sql);
  print $out "$now\n";
  $sql = 'SELECT DISTINCT r.id FROM historicalreviews r'.
         ' INNER JOIN exportdata e ON r.gid=e.gid'.
         ' INNER JOIN projects p ON e.project=p.id'.
         ' WHERE r.data IS NOT NULL AND r.validated!=0 AND p.name="Core"'.
         ' ORDER BY r.id ASC';
  my $ref = $crms->SelectAll($sql);
  my $n = 0;
  foreach my $row (@{$ref})
  {
    my $id = $row->[0];
    my $ref = $crms->RightsQuery($id)->[-1];
    my $rights = $ref->[0]. '/'. $ref->[1];
    if ($rights =~ m/^pd/ && $rights ne 'pdus/gfv')
    {
      #print RED "$id: skipping because rights are $rights\n" if $verbose;
      print "$id ($rights)\n" if $verbose;
      next;
    }
    my %values = ();
    my $val;
    $sql = 'SELECT r.user,r.time,d.data,r.expert FROM historicalreviews r'.
           ' INNER JOIN exportdata e ON r.gid=e.gid'.
           ' INNER JOIN projects p ON e.project=p.id'.
           ' INNER JOIN reviewdata d ON r.data=d.id'.
           ' WHERE r.id=? AND r.data IS NOT NULL AND r.validated!=0 AND p.name="Core"'.
           ' ORDER BY r.time DESC';
    #print "$sql\n" if $verbose;
    my $ref2 = $crms->SelectAll($sql, $id);
    foreach my $row2 (@{$ref2})
    {
      my $u = $row2->[0];
      my $t = $row2->[1];
      my $data = $row2->[2];
      $data = $jsonxs->decode($data);
      my $r = $data->{'renNum'};
      next unless $r;
      my $e = $row2->[3];
      if ($e)
      {
        $val = $r;
        last;
      }
      $values{$r} = 1;
    }
    if (!defined $val)
    {
      my @k = keys %values;
      $val = $k[0] if scalar @k == 1;
    }
    if (defined $val)
    {
      my $date = $crms->GetRenDate($val) || '';
      print $out "$id\t$val\t$date\n";
      $n++;
    }
  }
  close $out;
  return $n;
}

