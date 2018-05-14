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
use CRMS;
use Getopt::Long;
use Spreadsheet::WriteExcel;
use Encode;

my $usage = <<END;
USAGE: $0 [-hnpv] [-m MAIL_ADDR [-m MAIL_ADDR2...]] [-x SYS]

Reports on suspected gov docs in the und table.

-h       Print this help message.
-m ADDR  Mail the report to ADDR. May be repeated for multiple addresses.
-n       No-op. Do not delete src='gov' entries in the und table.
-p       Run in production.
-v       Emit debugging information. May be repeated.
-x SYS   Set SYS as the system to execute.
END

my $help;
my $instance;
my @mails;
my $noop;
my $production;
my $sys;
my $verbose;

Getopt::Long::Configure ('bundling');
die 'Terminating' unless GetOptions(
           'h|?' => \$help,
           'm:s@' => \@mails,
           'n' => \$noop,
           'p' => \$production,
           'v+' => \$verbose,
           'x:s' => \$sys);
$instance = 'production' if $production;
print "Verbosity $verbose\n" if $verbose;
die "$usage\n\n" if $help;

my $crms = CRMS->new(
    sys      => $sys,
    verbose  => $verbose,
    instance => $instance
);

my $start = $crms->SimpleSqlGet('SELECT DATE(MIN(time)) FROM und WHERE src="gov"');
my $end = $crms->SimpleSqlGet('SELECT DATE(MAX(time)) FROM und WHERE src="gov"');
my $sql = 'SELECT id FROM und WHERE src="gov"';
my $ref = $crms->SelectAll($sql);
my $txt = '';
$sql = 'SELECT DATE_FORMAT(MAX(time), "%M %Y") FROM und WHERE src="gov"';
my $month = $crms->SimpleSqlGet($sql);
my $subj = "Suspected Gov Documents, $month";
$month =~ s/\s+/_/g;
my $excelname = 'GovDocs_'. $month. '.xls';
my $excelpath = '/l1/prep/c/crms/'. $excelname;
my @cols= ('ID','Sys ID','Author','Title','Pub Date','Pub');
my $workbook  = Spreadsheet::WriteExcel->new($excelpath);
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
  my $cat = $crms->ShouldVolumeBeFiltered($id, $record);
  if (defined $cat)
  {
    if ($cat ne 'gov')
    {
      $crms->Filter($id, $cat);
      next;
    }
  }
  else
  {
    next;
  }
  my $catLink = $crms->LinkToMirlynDetails($id);
  my $ptLink = 'https://babel.hathitrust.org/cgi/pt?debug=super;id=' . $id;
  my $au = $record->author;
  $au =~ s/&/&amp;/g;
  my $ti = $record->title;
  $ti =~ s/&/&amp;/g;
  my $pub = $record->copyrightDate;
  my $field260a = '';
  my $field260b = '';
  eval {
    my $xpath  = q{//*[local-name()='datafield' and @tag='260']/*[local-name()='subfield' and @code='a']};
    $field260a = $record->xml->findvalue($xpath);
    $xpath  = q{//*[local-name()='datafield' and @tag='260']/*[local-name()='subfield' and @code='b']};
    $field260b = $record->xml->findvalue($xpath);
  };
  $n++;
  @cols = ($id, $record->sysid, $au, $ti, $pub, $field260a . ' ' . $field260b);
  $worksheet->write_string($n, $_, $cols[$_]) for (0 .. scalar @cols - 1);
}
$workbook->close();
$subj .= " ($n)";
if (scalar @mails)
{
  $subj = $crms->SubjectLine($subj);
  $txt = 'This is an automatically generated report on possible federal government docs from the previous ' .
          "month. We believe these should have an 'f' inserted into the 008 MARC field. " .
          "Please notify the other addressees of any volumes that do not seem to meet these criteria.\n";
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
  # FIXME: should find a way to specify filename.
  $mail{body} = <<END_OF_BODY;
$boundary
Content-Type: text/plain; charset="UTF-8"
Content-Transfer-Encoding: quoted-printable

$txt
$boundary
Content-Type: application/vnd.ms-excel; name="$excelpath"
Content-Transfer-Encoding: base64
Content-Disposition: attachment; filename="$excelname"

$enc
$boundary--
END_OF_BODY

  sendmail(%mail) || $crms->SetError("Error: $Mail::Sendmail::error\n");
}
$crms->PrepareSubmitSql('DELETE FROM und WHERE src="gov"') unless $noop;
print "Warning: $_\n" for @{$crms->GetErrors()};
