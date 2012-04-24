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
USAGE: $0 [-ahiprv] [-n N] [-t TYPE] [-s VOL_ID [-s VOL_ID2...]]
          [-m MAIL_ADDR [-m MAIL_ADDR2...]] [SOURCE_FILE]

Creates a report of recent exports for the orphan works project.

-a         Ignore the -n flag and export all.
-h         Print this help message.
-i         Insert the volumes into the orphan table.
-m ADDR    Mail the report to ADDR. May be repeated for multiple addresses.
-n N       Export no more than N volumes. (Default is 3000.)
-p         Run in production.
-r         Re-report on all volumes in the orphan table. (Ignore -a and -n flags.)
-s VOL_ID  Report only for HT volume VOL_ID. May be repeated for multiple volumes.
-t TYPE    Print a report of TYPE where TYPE={html,none,tsv,excel}.
           In the case of excel it will be created in place and
           attached to any outgoing mail. Default is excel.
-v         Be verbose. May be repeated.
END
my $all;
my $help;
my $insert;
my @mails;
my $n;
my $production;
my $rereport;
my @singles;
my $type = 'excel';
my $verbose;
my $file = undef;
my $fh = undef;

Getopt::Long::Configure ('bundling');
die 'Terminating' unless GetOptions('a' => \$all,
           'h|?' => \$help,
           'i' => \$insert,
           'm:s@' => \@mails,
           'n:s' => \$n,
           'p' => \$production,
           'r' => \$rereport,
           's:s@' => \@singles,
           't:s' => \$type,
           'v+' => \$verbose);
$DLPS_DEV = undef if $production;
print "Verbosity $verbose\n" if $verbose;
die "$usage\n\n" if $help;
if (scalar @ARGV)
{
  $file = $ARGV[0];
  open $fh, $file or die "failed to open $file: $@ \n";
  $rereport = undef;
}
my $crms = CRMS->new(
    logFile => "$DLXSROOT/prep/c/crms/orph_hist.txt",
    #sys     => 'crms',
    verbose => $verbose,
    root    => $DLXSROOT,
    dev     => $DLPS_DEV
);

$crms->set('ping','yes');
my %metaissues = ();
my %types = ('html'=>1,'none'=>1,'tsv'=>1,'excel'=>1);
die "Bad value '$type' for -t flag" unless defined $types{$type};
my $dbh = $crms->GetDb();
$n = 3000 unless $n and $n > 0;
my $ref = undef;
if ($fh)
{
  $ref = GetDataFromFile($fh);
}
else
{
  my $sql = "SELECT id,gid FROM exportdata WHERE attr='ic' AND reason='ren'";
  if (@singles && scalar @singles)
  {
    #$sql = sprintf("SELECT id,gid,attr,reason FROM exportdata WHERE attr='ic' AND id in ('%s')", join "','", @singles);
    $sql = sprintf("SELECT id,gid,attr,reason FROM exportdata WHERE id in ('%s')", join "','", @singles);
  }
  $sql .= ' AND src!="inherited" AND id NOT IN (SELECT id FROM orphan)';
  $sql = 'SELECT id FROM orphan WHERE id IN (SELECT id FROM exportdata)' if $rereport;
  $sql .= ' ORDER BY time DESC';
  print "$sql\n" if $verbose > 1;
  $ref = $dbh->selectall_arrayref($sql);
}
my $now = $crms->SimpleSqlGet("SELECT DATE(NOW())");
my $txt = '';
my $title = "CRMS Orphan Works Report $now";
my ($workbook,$worksheet);
my $excelpath = sprintf('/l1/prep/c/crms/OrphanCand_%s.xls', $now);
my @cols= ('#', 'HT ID','attr','reason','Renewal #','Renewal Date','Title','Author Last Name','Author First Name','Author Dates',
           'Publisher 1 Location','Publisher 1 Name','Publisher 1 Year',
           'Publisher 2 Location','Publisher 2 Name','Publisher 2 Year',
           'Publisher 3 Location','Publisher 3 Name','Publisher 3 Year',
           'Publisher 4 Location','Publisher 4 Name','Publisher 4 Year',
           'Country of Publication');
my $sortIdx = 10; # For sorting on pub 1 name (# is prepended after the sort)
my $sort2Idx = -1;
if ($fh)
{
  $sortIdx = 21;
  $sort2Idx = 10;
}
if ($type eq 'html')
{
  $txt .= '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">' . "\n";
  $txt .= '<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en"><head>' .
        "<meta http-equiv='Content-Type' content='text/html; charset=utf-8'/>\n" .
        "<title>$title</title>\n" .
        '</head><body><table border="1"><tr><th>' . join('</th><th>', @cols) . "</th></tr>\n";
}
elsif ($type eq 'tsv')
{
  $txt .= join("\t", @cols) . "\n";
}
elsif ($type eq 'excel')
{
  $workbook  = Spreadsheet::WriteExcel->new($excelpath);
  $worksheet = $workbook->add_worksheet();
  $worksheet->write_string(0, $_, $cols[$_]) for (0 .. scalar @cols);
}
my $found = 0;
my %seen = ();
$n = scalar @{$ref} if $all || $rereport;
printf "%d volumes found, $n sought\n", scalar @{$ref} if $verbose;
my @rows = ();
foreach my $row (@{$ref})
{
  my $id = $row->[0];
  my $gid;
  
  if ($rereport)
  {
    my $sql = "SELECT gid FROM exportdata WHERE id='$id' ORDER BY time DESC LIMIT 1";
    $gid = $crms->SimpleSqlGet($sql);
  }
  else
  {
    $gid = $row->[1];
  }
  print "Record: $id ($gid)\n" if $verbose;
  if ($seen{$id})
  {
    print "Already saw $id\n";
    next;
  }
  next if $fh and $crms->SimpleSqlGet("SELECT COUNT(*) FROM orphan WHERE id='$id'");
  my $sql = 'SELECT r.renNum,r.renDate FROM historicalreviews r INNER JOIN users u ON r.user=u.id ' .
            "WHERE r.gid=$gid AND r.renNum IS NOT NULL AND r.renDate IS NOT NULL " .
            'ORDER BY u.reviewer+(2*u.advanced)+(4*u.expert)+(8*u.admin)+(16*u.superadmin) DESC LIMIT 1';
  my $ref2 = $dbh->selectall_arrayref($sql);
  printf "$sql; %d results\n", scalar @{$ref2} if $verbose > 1;
  #next unless $ref2 && scalar @{$ref2};
  my ($attr,$reason,$src,$usr,$time,$note) = @{$crms->RightsQuery($id,1)->[0]};
  if ($attr ne 'ic' && !$rereport && !$fh)
  {
    print "Next 1\n";
    next;
  }
  my $sysid = $crms->BarcodeToId($id);
  my $record = $crms->GetMetadata($sysid);
  if (!$sysid || !$record)
  {
    #print "Cannot get metadata for $id\n";
    $crms->ClearErrors();
    $metaissues{$id} = 1;
    next;
  }
  $seen{$id} = 1;
  $found++;
  printf "Found: $found of %s\n", ($all)?'all':$n if $verbose;
  my ($renNum,$renDate) = ('','');
  ($renNum,$renDate) = @{$ref2->[0]} if $ref2 && scalar @{$ref2};
  my $author = $crms->GetRecordAuthor($id, $record);
  my ($authlast,$authrest) = split m/,\s*/, $author, 2;
  my $title = $crms->GetRecordTitle($id, $record);
  my $dates = GetRecordAuthorDates($id, $record);
  my @fields = ($id, $attr, $reason, $renNum, $renDate, $title, $authlast, $authrest, $dates);
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
  push @fields, $crms->GetPubCountry($id, $record);
  push @rows, join '____', @fields;
  $crms->PrepareSubmitSql("INSERT INTO orphan (id) VALUES ('$id')") if $insert and !$rereport;
  if ($found >= $n and !$all and !$rereport)
  {
    print "I'm done! found $found n $n all $all\n" if $verbose;
    last;
  }
  
}
$found = 0;
foreach my $row (SortByPub(\@rows))
{
  my @fields = split m/____/, $row;
  $found++;
  unshift @fields, $found;
  if ($type eq 'html')
  {
    $txt .= sprintf("<tr><td>%s</td></tr>\n", join '</td><td>', map {s/&/&amp;/g;$_;} @fields);
  }
  elsif ($type eq 'tsv')
  {
    $txt .= join "\t", @fields;
    #$txt .= join "\t", map {s/\s+/ /g;$_;} @fields;
    $txt .= "\n";
  }
  elsif ($type eq 'excel')
  {
    $worksheet->write_string($found, $_, $fields[$_]) for (0 .. scalar @fields);
  }
}
if ($type eq 'html')
{
  $txt .= "</table></body></html>\n\n";
}
$workbook->close() if $type eq 'excel';

if (@mails)
{
  use Mail::Sender;
  $title = 'Dev: ' . $title if $DLPS_DEV;
  my $sender = new Mail::Sender { smtp => 'mail.umdl.umich.edu',
                                  from => $crms->GetSystemVar('adminEmail', ''),
                                  on_errors => 'undef' }
    or die "Error in mailing : $Mail::Sender::Error\n";
  my $to = join ',', @mails;
  my $ctype = ($type eq 'html')? 'text/html':'text/plain';
  $sender->OpenMultipart({
    to => $to,
    subject => $title,
    ctype => $ctype,
    encoding => 'utf-8'
    }) or die $Mail::Sender::Error,"\n";
  $sender->Body();
  if ($type eq 'excel')
  {
    $txt = "Attached please find $found volumes to be considered for Orphan Works/CRMS World.\n"; 
  }
  my $bytes = encode('utf8', $txt);
  $sender->SendEnc($bytes);
  if ($type eq 'excel')
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
print "Could not get metadata for $_\n" for sort keys %metaissues;
print "Warning: $_\n" for @{$crms->GetErrors()};

close $fh if $fh;

# array ref of arrayrefs (id,gid)
sub GetDataFromFile
{
  my $fh = shift;

  my @data = ();
  my $cnt = 0;
  my @ary = ();
  foreach my $sysid (<$fh>)
  {
    chomp $sysid;
    next if $sysid =~ m/^\s*$/;
    push @ary, $sysid;
  }
  @ary = sort {
    (rand() < 0.5)? $a cmp $b:$b cmp $a;
  } @ary;
  foreach my $sysid (@ary)
  {
    my $record = $crms->GetMetadata($sysid);
    my $rows = $crms->VolumeIDsQuery($sysid, $record);
    my ($id2,$chron,$rights) = split '__', $rows->[0];
    # FIXME: make it possible to specify this on the command line.
    my $orig = $crms->GetPubCountry($id2, $record);
    next if $orig !~ m/^Canada/ && $orig !~ m/^England/ && $orig !~ m/Australia/;
    next if $crms->SimpleSqlGet("SELECT COUNT(*) FROM orphan WHERE id='$id2'");
    push @data, [$id2,0];
    print "Got $id2 for $sysid\n" if $verbose;
    $cnt++;
    last if $cnt >= $n;
  }
  return \@data;
}

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
    my $aa = lc $aar[$sortIdx];
    my $ba = lc $bar[$sortIdx];
    my $ret = $aa cmp $ba;
    if ($sort2Idx >= 0 && !$ret)
    {
      my $ab = lc $aar[$sort2Idx];
      my $bb = lc $bar[$sort2Idx];
      $ret = $ab cmp $bb;
    }
    return $ret;
  } @{$ref};
}

