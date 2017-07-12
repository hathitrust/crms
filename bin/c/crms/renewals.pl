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
use Term::ANSIColor qw(:constants);
$Term::ANSIColor::AUTORESET = 1;

my $usage = <<END;
USAGE: $0 [-hnpqv] [-m USER [-m USER...]]

Produces TSV file of HTID-renewal ID for Zephir download at
prep/c/crms/CRMSRenewals.tsv

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
-q       Send only to addresses specified via the -m flag.
-v       Be verbose. May be repeated for increased verbosity.
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
<a href="https://www.hathitrust.org/files/CRMSRenewals.tsv">HathiTrust</a>.
</p>
END

my $n = CheckStanford();
$msg =~ s/__N__/$n/g;
$msg =~ s/__OUTFILE__/$outfile/g;
my $subject = $crms->SubjectLine('Stanford Renewal Report');
my $to = join ',', @mails;
if ($noop || scalar @mails == 0)
{
  print "No-op or no mails set; not sending e-mail to {$to}\n" if $verbose;
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

# Returns number of lines written.
sub CheckStanford
{
  open my $out, '>:encoding(UTF-8)', $outfile;
  my $sql = 'SELECT NOW()';
  my $now = $crms->SimpleSqlGet($sql);
  print $out "$now\n";
  $sql = 'SELECT DISTINCT id FROM historicalreviews'.
         ' WHERE renNum IS NOT NULL AND renNum!=""'.
         ' AND validated!=0 ORDER BY id ASC';
  my $ref = $crms->SelectAll($sql);
  my $n = 0;
  my $of = scalar @{$ref};
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
    $sql = 'SELECT user,time,renNum,expert FROM historicalreviews WHERE id=?'.
           ' AND renNum IS NOT NULL AND renNum!="" AND validated!=0'.
           ' ORDER BY time DESC';
    #print "$sql\n" if $verbose;
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
      my $date = $crms->GetRenDate($val) || '';
      print $out "$id\t$val\t$date\n";
      $n++;
    }
  }
  close $out;
  return $n;
}

