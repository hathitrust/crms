#!/usr/bin/perl
BEGIN 
{
  unshift(@INC, $ENV{'SDRROOT'}. '/crms/cgi');
}

use strict;
use CRMS;
use Getopt::Long;
use Excel::Writer::XLSX;
use Encode;

my $usage = <<END;
USAGE: $0 [-hnpv] [-m MAIL_ADDR [-m MAIL_ADDR2...]]

Reports on suspected gov docs in the und table.

-h       Print this help message.
-m ADDR  Mail the report to ADDR. May be repeated for multiple addresses.
-n       No-op. Do not delete src='gov' entries in the und table.
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
print "Verbosity $verbose\n" if $verbose;
die "$usage\n\n" if $help;

my $crms = CRMS->new(
    verbose  => $verbose,
    instance => $instance
);

$crms->set('noop', 1) if $noop;
my $sql = 'SELECT id FROM und WHERE src="gov"';
my $ref = $crms->SelectAll($sql);
my $txt = '';
$sql = 'SELECT DATE_FORMAT(MAX(time), "%M %Y") FROM und WHERE src="gov"';
my $month = $crms->SimpleSqlGet($sql);
my $subj = "Suspected Gov Documents, $month";
$month =~ s/\s+/_/g;
my $excelname = 'GovDocs_'. $month. '.xlsx';
my $excelpath = $crms->FSPath('prep', $excelname);
my @cols= ('ID','Sys ID','Author','Title','Pub Date','Pub');
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
  # Check to make sure the record has not been updated in the meantime
  my $src = $crms->ShouldVolumeBeFiltered($id, $record);
  next unless defined $src;
  if ($src ne 'gov')
  {
    $crms->Filter($id, $src);
    next;
  }
  my $catLink = $crms->LinkToMirlynDetails($id);
  my $ptLink = 'https://babel.hathitrust.org/cgi/pt?debug=super;id=' . $id;
  my $au = $record->author || '';
  $au =~ s/&/&amp;/g;
  my $ti = $record->title || '';
  $ti =~ s/&/&amp;/g;
  my $pub = $record->copyrightDate || '';
  my $field260a = '';
  my $field260b = '';
  eval {
    my $xpath  = q{//*[local-name()='datafield' and @tag='260']/*[local-name()='subfield' and @code='a']};
    $field260a = $record->xml->findvalue($xpath) || '';
    $xpath  = q{//*[local-name()='datafield' and @tag='260']/*[local-name()='subfield' and @code='b']};
    $field260b = $record->xml->findvalue($xpath) || '';
  };
  $n++;
  @cols = ($id, $record->sysid, $au, $ti, $pub, $field260a . ' ' . $field260b);
  $worksheet->write_string($n, $_, $cols[$_]) for (0 .. scalar @cols - 1);
}
$workbook->close();
$subj .= " ($n)";
if (scalar @mails)
{
  @mails = map { ($_ =~ m/@/)? $_:($_ . '@umich.edu'); } @mails;
  $subj = $crms->SubjectLine($subj);
  $txt = 'This is an automatically generated report on possible federal'.
         ' government documents detected by a CRMS heuristic.'. "\n\n";
  if ($n > 0)
  {
    $txt .= 'We believe these should have an "f" flag in the 008 MARC field.'.
            ' Please notify the other addressees of any volumes that do not seem'.
            ' to meet these criteria.'. "\n";
  }
  else
  {
    $txt .= 'There are no volumes in the report for this period.'. "\n";
  }
  my $bytes = encode('utf8', $txt);
  use MIME::Base64;
  use Mail::Sendmail;
  my $boundary = "====" . time() . "====";
  my %mail = ('from'         => 'crms-mailbot@umich.edu',
              'to'           => (join ',', @mails),
              'subject'      => $subj,
              'content-type' => "multipart/mixed; boundary=\"$boundary\""
              );
  open (F, $excelpath) or die "Cannot read $excelpath: $!";
  binmode F; undef $/;
  my $enc = encode_base64(<F>);
  close F;
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
$crms->PrepareSubmitSql('DELETE FROM und WHERE src="gov"');
print "Warning: $_\n" for @{$crms->GetErrors()};
