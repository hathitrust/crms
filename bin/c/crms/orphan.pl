#!/l/local/bin/perl

# This script can be run from crontab

my $DLXSROOT;
my $DLPS_DEV;
BEGIN 
{ 
  $DLXSROOT = $ENV{'DLXSROOT'}; 
  $DLPS_DEV = $ENV{'DLPS_DEV'}; 
  unshift ( @INC, $ENV{'DLXSROOT'} . "/cgi/c/crms/" );
}

use strict;
use CRMS;
use Getopt::Long;
use Spreadsheet::WriteExcel;
use Encode;

my $usage = <<END;
USAGE: $0 [-ahipv] [-n N] [-r TYPE] [-s VOL_ID [-s VOL_ID2...]]
          [-m MAIL_ADDR [-m MAIL_ADDR2...]]

Creates a report of recent exports for the orphan works project.

-a         Ignore the -n flag and export all.
-h         Print this help message.
-i         Insert the volumes into the orphan table.
-m ADDR    Mail the report to ADDR. May be repeated for multiple addresses.
-n N       Export no more than N volumes. (Default is 3000.)
-p         Run in production.
-r TYPE    Print a report of TYPE where TYPE={html,none,tsv,excel}.
           In the case of excel it will be created in place and
           attached to any outgoing mail. Default is excel.
-s VOL_ID  Report only for HT volume VOL_ID. May be repeated for multiple volumes.
-v         Be verbose. May be repeated.
END
my $all;
my $help;
my $insert;
my @mails;
my $n;
my $production;
my $report = 'excel';
my @singles;
my $verbose;

Getopt::Long::Configure ('bundling');
die 'Terminating' unless GetOptions('a' => \$all,
           'h|?' => \$help,
           'i' => \$insert,
           'm:s@' => \@mails,
           'n:s' => \$n,
           'p' => \$production,
           'r:s' => \$report,
           's:s@' => \@singles,
           'v+' => \$verbose);
$DLPS_DEV = undef if $production;
print "Verbosity $verbose\n" if $verbose;
die "$usage\n\n" if $help;

my $configFile = "$DLXSROOT/bin/c/crms/crms.cfg";
my $crms = CRMS->new(
    logFile      =>   "$DLXSROOT/prep/c/crms/orph_hist.txt",
    configFile   =>   $configFile,
    verbose      =>   $verbose,
    root         =>   $DLXSROOT,
    dev          =>   $DLPS_DEV
);
$crms->set('ping','yes');
require $configFile;

my %reports = ('html'=>1,'none'=>1,'tsv'=>1,'excel'=>1);
die "Bad value '$report' for -r flag" unless defined $reports{$report};
my $dbh = $crms->GetDb();
$n = 3000 unless $n and $n > 0;
my $sql = "SELECT id,gid FROM exportdata WHERE attr='ic' AND reason='ren'";
if (@singles && scalar @singles)
{
  #$sql = sprintf("SELECT id,gid FROM exportdata WHERE attr='ic' AND id in ('%s')", join "','", @singles);
  $sql = sprintf("SELECT id,gid FROM exportdata WHERE id in ('%s')", join "','", @singles);
}
$sql .= ' AND src!="inherited" AND id NOT IN (SELECT id FROM orphan)';
$sql .= ' ORDER BY time DESC';
print "$sql\n" if $verbose > 1;
my $ref = $dbh->selectall_arrayref($sql);
my $now = $crms->SimpleSqlGet("SELECT DATE(NOW())");
my $txt = '';
my $title = "CRMS Orphan Works Report $now";
my ($workbook,$worksheet);
my $excelpath = sprintf('/l1/prep/c/crms/OrphanCand_%s.xls', $now);
my @cols= ('#', 'ID','Renewal #','Renewal Date','Title','Author Last Name','Author First Name','Author Dates',
           'Publisher 1 Location','Publisher 1 Name','Publisher 1 Year',
           'Publisher 2 Location','Publisher 2 Name','Publisher 2 Year',
           'Publisher 3 Location','Publisher 3 Name','Publisher 3 Year',
           'Publisher 4 Location','Publisher 4 Name','Publisher 4 Year');
my $pub1NameIdx = 8; # For sorting (# is prepended after the sort)
if ($report eq 'html')
{
  $txt .= '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">' . "\n";
  $txt .= '<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en"><head>' .
        "<meta http-equiv='Content-Type' content='text/html; charset=utf-8'/>\n" .
        "<title>$title</title>\n" .
        '</head><body><table border="1"><tr><th>' . join('</th><th>', @cols) . "</th></tr>\n";
}
elsif ($report eq 'tsv')
{
  $txt .= join("\t", @cols) . "\n";
}
elsif ($report eq 'excel')
{
  $workbook  = Spreadsheet::WriteExcel->new($excelpath);
  $worksheet = $workbook->add_worksheet();
  $worksheet->write_string(0, $_, $cols[$_]) for (0 .. scalar @cols);
}
my $found = 0;
my %seen = ();
printf "%d volumes found, %s sought\n", scalar @{$ref}, ($all)?'all':$n if $verbose;
my @rows = ();
foreach my $row (@{$ref})
{
  my $id = $row->[0];
  my $gid = $row->[1];
  print "Record: $id ($gid)\n" if $verbose;
  next if $seen{$id};
  $sql = 'SELECT r.renNum,r.renDate FROM historicalreviews r INNER JOIN users u ON r.user=u.id ' .
         "WHERE r.gid=$gid AND r.renNum IS NOT NULL AND r.renDate IS NOT NULL " .
         'ORDER BY u.reviewer+(2*u.advanced)+(4*u.expert)+(8*u.admin)+(16*u.superadmin) DESC LIMIT 1';
  print "$sql\n" if $verbose > 1;
  my $ref2 = $dbh->selectall_arrayref($sql);
  next unless $ref2 && scalar @{$ref2};
  my ($attr,$reason,$src,$usr,$time,$note) = @{$crms->RightsQuery($id,1)->[0]};
  next unless $attr eq 'ic';
  $seen{$id} = 1;
  $found++;
  printf "Found: $found of %s\n", ($all)?'all':$n if $verbose;
  my ($renNum,$renDate) = @{$ref2->[0]};
  my $sysid = $crms->BarcodeToId($id);
  my $record = $crms->GetMetadata($sysid);
  my $author = $crms->GetRecordAuthor($id, $record);
  my ($authlast,$authrest) = split m/,\s*/, $author, 2;
  my $title = $crms->GetRecordTitle($id, $record);
  my $dates = GetRecordAuthorDates($id, $record);
  my @fields = ($id, $renNum, $renDate, $title, $authlast, $authrest, $dates);
  my @pubs = (['','',''],['','',''],['','',''],['','','']);
  my $pubn = 0;
  my $nodes = $record->findnodes("//*[local-name()='datafield' and \@tag='260']/*[local-name()='subfield']");
  my $code = '';
  my $lastcode = undef;
  my %h = ('a'=>0,'b'=>1,'c'=>2);
  foreach my $node ($nodes->get_nodelist())
  {
    printf "Doing a subfield: $node (%s)\n", $node->localname if $verbose > 2;
    my $code = lc $node->getAttribute('code');
    my $field = $node->textContent();
    $field =~ s/[,\.]+\s*$// if $code eq 'c';
    print "Field: '$field' for '$code'\n" if $verbose > 1;
    # If we are seeing a code same as or less than the one we last saw, advance.
    $pubn++ if $lastcode and $code le $lastcode;
    last if $pubn == 5;
    $pubs[$pubn]->[$h{$code}] = $field;
    #printf "pubs[$pubn]->%s = '$field' from '$code'\n", $h{$code};
    $lastcode = $code;
    #print "pubn $pubn, code $code, lastcode $lastcode\n";
  }
  push @fields, @{$pubs[$_]} for (0 .. 3);
  printf "Have %d pubs, %d fields\n", scalar @pubs, scalar @fields if $verbose > 1;
  push @rows, join '____', @fields;
  $crms->PrepareSubmitSql("INSERT INTO orphan (id) VALUES ('$id')") if $insert;
  last if !$all and $found >= $n;
}
$found = 0;
foreach my $row (SortByPub(\@rows))
{
  my @fields = split m/____/, $row;
  $found++;
  unshift @fields, $found;
  if ($report eq 'html')
  {
    $txt .= sprintf("<tr><td>%s</td></tr>\n", join '</td><td>', map {s/&/&amp;/g;$_;} @fields);
  }
  elsif ($report eq 'tsv')
  {
    $txt .= join "\t", @fields;
    #$txt .= join "\t", map {s/\s+/ /g;$_;} @fields;
    $txt .= "\n";
  }
  elsif ($report eq 'excel')
  {
    $worksheet->write_string($found, $_, $fields[$_]) for (0 .. scalar @fields);
  }
}
if ($report eq 'html')
{
  $txt .= "</table></body></html>\n\n";
}
$workbook->close() if $report eq 'excel';

if (@mails)
{
  use Mail::Sender;
  $title = 'Dev: ' . $title if $DLPS_DEV;
  my $sender = new Mail::Sender { smtp => 'mail.umdl.umich.edu',
                                  from => $CRMSGlobals::adminEmail,
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
    $txt = "Attached please find $found ic/ren volumes to be considered for the Orphan Works Project.\n"; 
  }
  my $bytes = encode('utf8', $txt);
  $sender->SendEnc($bytes);
  if ($report eq 'excel')
  {
    $sender->Attach({
      description => 'Orphan Report',
      ctype => 'application/vnd.ms-excel',
      encoding => 'Base64',
      disposition => 'attachment; filename=*',
      file => $excelpath
      });
  }
  $sender->Close();
}
else
{
  print $txt;
}

print "Warning: $_\n" for @{$crms->GetErrors()};

sub GetRecordAuthorDates
{
  my $id     = shift;
  my $record = shift;

  my $data = $crms->GetMarcDatafield($id,'100','d',$record);
  $data = $crms->GetMarcDatafield($id,'700','d',$record) unless $data;
  my $len = length $data;
  if ($len && $len % 3 == 0)
  {
    my $s = $len / 3;
    my $f1 = substr $data, 0, $s;
    my $f2 = substr $data, $s, $s;
    my $f3 = substr $data, 2*$s, $s;
    #print "'$f1' + '$f2' + '$f3' from '$data' ($id)\n";
    $data = $f1 if $f1 eq $f2 and $f2 eq $f3;
  }
  $data =~ s/[\.,:;]\s*$//;
  return $data;
}

sub SortByPub
{
  my $ref = shift;

  return sort {
    my @aar = split m/____/, $a;
    my @bar = split m/____/, $b;
    my $aa = lc $aar[$pub1NameIdx];
    my $ba = lc $bar[$pub1NameIdx];
    $aa cmp $ba;
  } @{$ref};
}
