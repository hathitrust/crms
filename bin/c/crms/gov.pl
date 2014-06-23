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
USAGE: $0 [-ahptv] [-m MAIL_ADDR [-m MAIL_ADDR2...]]
          [-x SYS] [start_date [end_date]]

Reports on suspected gov docs in the und table.

-a       Report on all gov docs in und, regardless of date range.
-h       Print this help message.
-m ADDR  Mail the report to ADDR. May be repeated for multiple addresses.
-p       Run in production.
-r TYPE  Print a report of TYPE where TYPE={html,none,tsv,excel}.
         In the case of Excel it will be created in place and
         attached to any outgoing mail. Default is html.
-v       Emit debugging information. May be repeated.
-x SYS     Set SYS as the system to execute.
END

my $all;
my $help;
my @mails;
my $production;
my $report = 'html';
my $sys;
my $verbose;

Getopt::Long::Configure ('bundling');
die 'Terminating' unless GetOptions('a' => \$all,
           'h|?' => \$help,
           'm:s@' => \@mails,
           'p' => \$production,
           'r:s' => \$report,
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

my %reports = ('html'=>1,'none'=>1,'tsv'=>1,'excel'=>1);
die "Bad value '$report' for -r flag" unless defined $reports{$report};
my $dbh = $crms->GetDb();
my $start = $crms->SimpleSqlGet('SELECT DATE(DATE_SUB(NOW(), INTERVAL 1 DAY))');
my $end = $start;
if (scalar @ARGV)
{
  $start = $ARGV[0];
  die "Bad date format ($start); should be in the form e.g. 2010-08-29" unless $start =~ m/^\d\d\d\d-\d\d-\d\d$/;
  if (scalar @ARGV > 1)
  {
    $end = $ARGV[1];
    die "Bad date format ($end); should be in the form e.g. 2010-08-29" unless $end =~ m/^\d\d\d\d-\d\d-\d\d$/;
  }
}

my $startSQL = '';
my $endSQL = '';
if ($all)
{
  $start = $crms->SimpleSqlGet('SELECT DATE(MIN(time)) FROM und WHERE src="gov"');
  $end = $crms->SimpleSqlGet('SELECT DATE(MAX(time)) FROM und WHERE src="gov"');
}
else
{
  $startSQL = " AND time>'$start 00:00:00'";
  $endSQL = " AND time<='$end 23:59:59'";
}
my $sql = "SELECT id,time FROM und WHERE src='gov' $startSQL $endSQL ORDER BY id";
print "$sql\n" if $verbose>1;
my $ref = $dbh->selectall_arrayref($sql);
my $n = scalar @{$ref};
my $txt = '';
$sql = 'SELECT DATE_FORMAT(MAX(time), "%M %Y") FROM und WHERE DATE(time)!=DATE(NOW()) AND src="gov"';
my $month = $crms->SimpleSqlGet($sql);
my $title = "CRMS Suspected Gov Documents, $start to $end ($n)";
if ($all)
{
  $title = "CRMS Prod: Suspected Gov Documents, $month ($n)";
}
my ($workbook,$worksheet);
$month =~ s/\s+/_/g;
my $excelpath = sprintf('/l1/prep/c/crms/GovDocs_%s.xls', $month);
my @cols= ('#','ID','Sys ID','Time','Author','Title','Pub Date','Pub');
if ($report eq 'html')
{
  $txt .= $crms->StartHTML($title);
  $txt .= '<table border="1"><tr><th>' . join('</th><th>', @cols) . "</th></tr>\n";
}
elsif ($report eq 'tsv')
{
  $txt .= join("\t", @cols) . "\n";
}
elsif ($report eq 'excel')
{
  $workbook  = Spreadsheet::WriteExcel->new($excelpath);
  $worksheet = $workbook->add_worksheet();
  $worksheet->write_string(0, 0, 'ID');
  $worksheet->write_string(0, 1, 'Sys ID');
  $worksheet->write_string(0, 2, 'Time');
  $worksheet->write_string(0, 3, 'Author');
  $worksheet->write_string(0, 4, 'Title');
  $worksheet->write_string(0, 5, 'Pub Date');
  $worksheet->write_string(0, 6, 'Pub');
}
$n = 0;
foreach my $row (@{$ref})
{
  my $id = $row->[0];
  my $time = $row->[1];
  
  $n++;
  my $record = $crms->GetMetadata($id);
  if (!defined $record)
  {
    print "Error: no metadata for $id\n";
    next;
  }
  my $sysid = $record->sysid;
  my $catLink = "http://mirlyn.lib.umich.edu/Record/$sysid/Details#tabs";
  my $ptLink = 'https://babel.hathitrust.org/cgi/pt?debug=super;id=' . $id;
  my $author = $record->author;
  $author =~ s/&/&amp;/g;
  my $title = $record->title;
  $title =~ s/&/&amp;/g;
  my $pub = $record->pubdate;
  my $field260a = '';
  my $field260b = '';
  eval {
    my $xpath  = q{//*[local-name()='datafield' and @tag='260']/*[local-name()='subfield' and @code='a']};
    $field260a = $record->xml->findvalue( $xpath );
    $xpath  = q{//*[local-name()='datafield' and @tag='260']/*[local-name()='subfield' and @code='b']};
    $field260b = $record->xml->findvalue( $xpath );
  };
  $field260a .= ' ' . $field260b;
  if ($report eq 'html')
  {
    $time =~ s/\s+/&nbsp;/g;
    $field260a =~ s/&/&amp;/g;
    $txt .= "<tr><td>$n</td><td><a href='$ptLink' target='_blank'>$id</a></td><td><a href='$catLink' target='_blank'>$sysid</a></td>";
    $txt .= "<td>$time</td><td>$author</td><td>$title</td><td>$pub</td><td>$field260a</td></tr>\n";
  }
  elsif ($report eq 'tsv')
  {
    $field260a =~ s/\t+/ /g;
    $txt .= "$n\t$id\t$sysid\t$time\t$author\t$title\t$pub\t$field260a\n";
  }
  elsif ($report eq 'excel')
  {
    $worksheet->write_string($n, 0, $id);
    $worksheet->write_string($n, 1, $sysid);
    $worksheet->write_string($n, 2, $time);
    $worksheet->write_string($n, 3, $author);
    $worksheet->write_string($n, 4, $title);
    $worksheet->write_string($n, 5, $pub);
    $worksheet->write_string($n, 6, $field260a);
  }
}
if ($report eq 'html')
{
  $txt .= "</table></body></html>\n\n";
}
$workbook->close() if $report eq 'excel';

if (@mails)
{
  if ($n>0)
  {
    use Mail::Sender;
    $title = 'Dev: ' . $title if $DLPS_DEV;
    my $sender = new Mail::Sender { smtp => 'mail.umdl.umich.edu',
                                    from => $crms->GetSystemVar('adminEmail', ''),
                                    on_errors => 'undef' }
      or die "Error in mailing : $Mail::Sender::Error\n";
    my $to = join ',', @mails;
    my $ctype = ($report eq 'html')? 'text/html':'text/plain';
    $sender->OpenMultipart({
      to => $to,
      subject => $title,
      ctype => $ctype,
      encoding => 'utf-8'
      }) or die $Mail::Sender::Error,"\n";
    $sender->Body();
    if ($report eq 'excel')
    {
      $txt = 'This is an automatically generated report on possible federal government docs from the previous ' .
             "month. We believe these should have an 'f' inserted into the 008 MARC field. " .
             "Please notify the other addressees of any volumes that do not seem to meet these criteria.\n"; 
    }
    my $bytes = encode('utf8', $txt);
    $sender->SendEnc($bytes);
    if ($report eq 'excel')
    {
      $sender->Attach({
        description => 'Gov Report',
        ctype => 'application/vnd.ms-excel',
        encoding => 'Base64',
        disposition => 'attachment; filename=*',
        file => $excelpath
        });
    }
    $sender->Close();
  }
}
else
{
  print $txt;
}

print "Warning: $_\n" for @{$crms->GetErrors()};
