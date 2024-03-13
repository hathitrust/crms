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
use Excel::Writer::XLSX;
use Getopt::Long;

use CRMS;
use CRMS::Cron;

my $usage = <<END;
USAGE: $0 [-hnpv] [-m MAIL [-m MAIL2...]] [-x SYS]

Reports on volumes suspected to be eligible for Creative Commons license.

-h       Print this help message.
-m MAIL  Mail the report to MAIL. May be repeated for multiple addresses.
-n       No-op. Do not delete src='cc' entries in the und table.
-p       Run in production.
-v       Emit debugging information. May be repeated.
END

my $help;
my $instance;
my @mails;
my $noop;
my $production;
my $verbose;

Getopt::Long::Configure ('bundling');
die 'Terminating' unless GetOptions(
           'h|?' => \$help,
           'm:s@' => \@mails,
           'n' => \$noop,
           'p' => \$production,
           'v+' => \$verbose);
$instance = 'production' if $production;
if ($help) { print $usage. "\n"; exit(0); }
print "Verbosity $verbose\n" if $verbose;

my $crms = CRMS->new(
    verbose  => $verbose,
    instance => $instance
);
my $cron = CRMS::Cron->new('crms' => $crms);

$crms->set('noop', 1) if $noop;
my $sql = 'SELECT id FROM und WHERE src="cc"';
my $ref = $crms->SelectAll($sql);
my $txt = '';
$sql = 'SELECT DATE_FORMAT(NOW(), "%Y-%m")';
my $ym = $crms->SimpleSqlGet($sql);
my $subj = "Suspected CC Documents, $ym";
my $excelname = 'CCDocs_'. $ym. '.xlsx';
my $excelpath = $crms->FSPath('prep', $excelname);
my @cols = ('ID', 'Sys ID', 'Author', 'Title', 'Pub Date');
my $workbook  = Excel::Writer::XLSX->new($excelpath);
my $worksheet = $workbook->add_worksheet();
$worksheet->write_string(0, $_, $cols[$_]) for (0 .. scalar @cols - 1);
my $n = 0;
foreach my $row (@{$ref})
{
  my $id = $row->[0];
  my $record = $crms->GetMetadata($id);
  if (!defined $record)
  {
    $crms->Filter($id, 'no meta');
    next;
  }
  my $catLink = $crms->LinkToCatalogMARC($record->sysid);
  my $ptLink = 'https://babel.hathitrust.org/cgi/pt?debug=super;id=' . $id;
  my $au = $record->author || '';
  $au =~ s/&/&amp;/g;
  my $ti = $record->title || '';
  $ti =~ s/&/&amp;/g;
  my $pub = $record->publication_date->format || '';
  $n++;
  @cols = ($id, $record->sysid, $au, $ti, $pub);
  $worksheet->write_string($n, $_, $cols[$_]) for (0 .. scalar @cols - 1);
}
$workbook->close();
$subj .= " ($n)";
my $recipients = $cron->recipients(@mails);
if (scalar @$recipients)
{
  $subj = $crms->SubjectLine($subj);
  $txt = 'This is an automatically generated report on volumes suspected of being'.
         ' eligible for CC license based on a volume on the same record'. "\n\n";
  unless ($n > 0)
  {
    $txt .= 'There are no volumes in the report for this period.'. "\n";
  }
  my $bytes = encode('utf8', $txt);
  use MIME::Base64;
  use Mail::Sendmail;
  my $boundary = "====" . time() . "====";
  my %mail = ('from'         => $crms->GetSystemVar('sender_email'),
              'to'           => (join ',', @$recipients),
              'subject'      => $subj,
              'content-type' => "multipart/mixed; boundary=\"$boundary\""
              );
  open (my $fh, '<', $excelpath) or die "Cannot read $excelpath: $!";
  binmode $fh; undef $/;
  my $enc = encode_base64(<$fh>);
  close $fh;
  $boundary = '--'.$boundary;
  $mail{body} = <<END_OF_BODY;
$boundary
Content-Type: text/plain; charset="UTF-8"
Content-Transfer-Encoding: quoted-printable

$txt
$boundary
Content-Type: application/vnd.ms-excel; name="$excelname"
Content-Transfer-Encoding: base64
Content-Disposition: attachment; filename="$excelname"

$enc
$boundary--
END_OF_BODY

  sendmail(%mail) || $crms->SetError("Error: $Mail::Sendmail::error\n");
}
$crms->PrepareSubmitSql('DELETE FROM und WHERE src="cc"');
print "Warning: $_\n" for @{$crms->GetErrors()};
