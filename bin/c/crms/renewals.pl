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
use Utilities;
use Encode;

my $usage = <<'END';
USAGE: $0 [-hnpqv] [-m USER [-m USER...]]

Produces CSV file ofr HTID-renewal ID for Zephir download.

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
    logFile => $DLXSROOT . '/prep/c/crms/renewals_log.txt',
    sys     => 'crms',
    verbose => $verbose,
    root    => $DLXSROOT,
    dev     => $DLPS_DEV
);

my $outfile = $crms->get('root'). $crms->get('dataDir'). '/CRMSRenewals.tsv';
my $msg = $crms->StartHTML();
$msg .= <<'END';
<h2>CRMS-US</h2>
<p>Exported __N__ Stanford renewal records (__OUTFILE__) to
<a href="https://www.hathitrust.org/files/CRMSRenewals.csv">HathiTrust</a>.
</p>
END

my $n = CheckStanford();
$msg =~ s/__N__/$n/g;
$msg =~ s/__OUTFILE__/$outfile/g;
my $subject = $crms->SubjectLine('Stanford Renewal Report');
my $to = join ',', @mails;
if ($noop || scalar @mails == 0)
{
  print "No-op or no mails set; not sending e-mail to $to\n" if $verbose;
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
                'subject'      => $subject,
                'content-type' => 'text/html; charset="UTF-8"',
                'body'         => $bytes
                );
    sendmail(%mail) || $crms->SetError("Error: $Mail::Sendmail::error\n");
  }
}

$msg .= "<p>Warning: $_</p>\n" for @{$crms->GetErrors()};
$msg .= '</body></html>';

sub CheckStanford
{
  open my $out, '>:encoding(UTF-8)', $outfile;
  my $sql = 'SELECT DISTINCT id FROM historicalreviews'.
            ' WHERE renNum IS NOT NULL AND renNum!=""'.
            ' ORDER BY id ASC';
  my $ref = $crms->SelectAll($sql);
  my $n = 0;
  my $of = scalar @{$ref};
  foreach my $row (@{$ref})
  {
    my $id = $row->[0];
    my %values = ();
    my $val;
    $sql = 'SELECT user,time,renNum,expert FROM historicalreviews WHERE id=?'.
           ' AND renNum IS NOT NULL AND renNum!=""'.
           ' ORDER BY time DESC';
    my $ref2 = $crms->SelectAll($sql, $id);
    foreach my $row2 (@{$ref2})
    {
      my $u = $row2->[0];
      my $t = $row2->[1];
      my $r = $row2->[2];
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
      print $out "$id\t$val\n";
      $n++;
    }
  }
  close $out;
  return $n;
}

