#!/usr/bin/perl

my $DLXSROOT;
my $DLPS_DEV;
BEGIN 
{ 
  $DLXSROOT = $ENV{'DLXSROOT'}; 
  $DLPS_DEV = $ENV{'DLPS_DEV'}; 
  unshift (@INC, $DLXSROOT . '/cgi/c/crms/');
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
$DLPS_DEV = undef if $production;
print "Verbosity $verbose\n" if $verbose;
die "$usage\n\n" if $help;

my $crms = CRMS->new(
    logFile => "$DLXSROOT/prep/c/crms/gov_hist.txt",
    sys     => $sys,
    verbose => $verbose,
    root    => $DLXSROOT,
    dev     => $DLPS_DEV
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
my $excelpath = sprintf('/l1/prep/c/crms/GovDocs_%s.xls', $month);
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
  use Mail::Sender;
  my $where = $crms->WhereAmI() or 'Prod';
  $subj = $crms->System() . ' ' . $where . ': ' . $subj;
  my $sender = new Mail::Sender { smtp => 'mail.umdl.umich.edu',
                                  from => $crms->GetSystemVar('adminEmail', ''),
                                  on_errors => 'undef' }
    or die "Error in mailing : $Mail::Sender::Error\n";
  $sender->OpenMultipart({
    to => (join ',', @mails),
    subject => $subj,
    ctype => 'text/plain',
    encoding => 'utf-8'
    }) or die "Error in opening : $Mail::Sender::Error\n";
  $sender->Body();
  $txt = 'This is an automatically generated report on possible federal government docs from the previous ' .
          "month. We believe these should have an 'f' inserted into the 008 MARC field. " .
          "Please notify the other addressees of any volumes that do not seem to meet these criteria.\n"; 
  my $bytes = encode('utf8', $txt);
  $sender->SendEnc($bytes);
  $sender->Attach({
      description => 'Gov Report',
      ctype => 'application/vnd.ms-excel',
      encoding => 'Base64',
      disposition => 'attachment; filename=*',
      file => $excelpath
      });
  $sender->Close();
}
$crms->PrepareSubmitSql('DELETE FROM und WHERE src="gov"') unless $noop;
print "Warning: $_\n" for @{$crms->GetErrors()};
