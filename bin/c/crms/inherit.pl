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
use Encode;

my $usage = <<END;
USAGE: $0 [-achipv] [-m MAIL_ADDR [-m MAIL_ADDR2...]] [start_date [end_date]]

Reports on the volumes that can inherit from this morning's export,
or, if start_date is specified, exported after then and before end_date
if it is specified.

-a         Report on all exports, regardless of date range.
-c         Report on recent addition to candidates.
-h         Print this help message.
-i         Insert entries in the dev inherit table.
-m ADDR    Mail the report to ADDR. May be repeated for multiple addresses.
-p         Run in production.
END

my $all;
my $candidates;
my $help;
my $insert;
my @mails;
my $production;
my $verbose;

Getopt::Long::Configure ('bundling');
die 'Terminating' unless GetOptions(
           'a'    => \$all,
           'c'    => \$candidates,
           'h|?'  => \$help,
           'i'    => \$insert,
           'm:s@' => \@mails,
           'p'    => \$production,
           'v+'   => \$verbose);
$DLPS_DEV = undef if $production;
die "$usage\n\n" if $help;

my $configFile = "$DLXSROOT/bin/c/crms/crms.cfg";
my $crms = CRMS->new(
    logFile      =>   "$DLXSROOT/prep/c/crms/inherit_hist.txt",
    configFile   =>   $configFile,
    verbose      =>   $verbose,
    root         =>   $DLXSROOT,
    dev          =>   $DLPS_DEV
);
require $configFile;
my $delim = "\n";
print "Verbosity $verbose$delim" if $verbose;
my $dbh = $crms->get('dbh');
my $start = $crms->SimpleSqlGet('SELECT DATE(NOW())');
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
my %data = %{($candidates)? CandidatesReport($start,$end):InheritanceReport($start,$end)};
my $txt = '';
my $dates = $start;
$dates .= " to $end" if $end ne $start;
my $title = sprintf "CRMS %s Inheritance, $dates", ($candidates)? 'Candidates':'Export';
$txt .= '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">' . "\n";
$txt .= '<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en"><head>' .
        "<meta http-equiv='Content-Type' content='text/html; charset=utf-8'/>\n" .
        "<title>$title</title></head><body>\n";
$delim = "<br/>\n";


if (scalar keys %{$data{'nodups'}})
{
  $txt .= "<h4>Volumes which were single-copy</h4>\n";
  $txt .= "<table border='1'><tr><th>#</th><th>Volume Checked (<span style='color:blue;'>volume retrieval</span>)</th>" .
          "<th>Sys ID (<span style='color:blue;'>catalog</span>)</th></tr>\n";
  my $n = 0;
  foreach my $id (keys %{$data{'nodups'}})
  {
    my @lines = split "\n", $data{'nodups'}->{$id};
    foreach my $sysid (@lines)
    {
      $n++;
      my $htCatLink = $crms->LinkToCatalog($sysid);
      my $retrLink = $crms->LinkToRetrieve($sysid);
      $txt .= "<tr><td>$n</td><td><a href='$retrLink' target='_blank'>$id</a></td><td><a href='$htCatLink' target='_blank'>$sysid</a></td></tr>\n";
    }
  }
  $txt .= "</table>$delim";
}
if (scalar keys %{$data{'noexport'}})
{
  $txt .= "<h4>Volumes which had no duplicates with CRMS exports from June 2010</h4>\n";
  $txt .= "<table border='1'><tr><th>#</th><th>Volume Checked (<span style='color:blue;'>volume retrieval</span>)</th>" .
          "<th>Sys ID (<span style='color:blue;'>catalog</span>)</th></tr>\n";
  my $n = 0;
  foreach my $id (keys %{$data{'noexport'}})
  {
    my @lines = split "\n", $data{'noexport'}->{$id};
    foreach my $sysid (@lines)
    {
      $n++;
      my $htCatLink = $crms->LinkToCatalog($sysid);
      my $retrLink = $crms->LinkToRetrieve($sysid);
      $txt .= "<tr><td>$n</td><td><a href='$retrLink' target='_blank'>$id</a></td><td><a href='$htCatLink' target='_blank'>$sysid</a></td></tr>\n";
    }
  }
  $txt .= "</table>$delim";
}
if (scalar keys %{$data{'chron'}})
{
  $txt .= "<h4>Volumes skipped because of chron/enum</h4>\n";
  $txt .= "<table border='1'><tr><th>#</th><th>Source&nbsp;Volume<br/>(<span style='color:blue;'>historical</span>)</th>" .
          '<th>Volume Checked<br/>(<span style="color:blue;">volume retrieval</span>)</th>' .
          '<th>Sys ID<br/>(<span style="color:blue;">catalog</span>)</th>' .
          "<th>Title</th></tr>\n";
  my $n = 0;
  foreach my $id (sort keys %{$data{'chron'}})
  {
    my $record = $crms->GetMetadata($id);
    my $title = $crms->GetRecordTitle($id, $record);
    $title =~ s/&/&amp;/g;
    my @lines = split "\n", $data{'chron'}->{$id};
    foreach my $line (@lines)
    {
      $n++;
      my ($id2,$sysid) = split "\t", $line;
      my $htCatLink = $crms->LinkToCatalog($sysid);
      my $retrLink = $crms->LinkToRetrieve($sysid);
      my $histLink = $crms->LinkToHistorical($sysid);
      $txt .= "<tr><td>$n</td><td><a href='$histLink' target='_blank'>$id</a></td>" .
              "<td><a href='$retrLink' target='_blank'>$id2</a></td>\n";
      $txt .= "<td><a href='$htCatLink' target='_blank'>$sysid</a></td><td>$title</td></tr>\n";
    }
  }
  $txt .= "</table>$delim";
}
if (scalar keys %{$data{'unneeded'}})
{
  $txt .= "<h4>Volumes for which inheritance was unneeded</h4>\n";
  $txt .= "<table border='1'><tr><th>#</th><th>Source&nbsp;Volume<br/>(<span style='color:blue;'>historical</span>)</th>" .
          '<th>Volume Checked<br/>(<span style="color:blue;">volume retrieval</span>)</th>' .
          '<th>Sys ID<br/>(<span style="color:blue;">catalog</span>)</th><th>Rights</th><th>New Rights</th>' .
          "<th>Title</th></tr>\n";
  my $n = 0;
  foreach my $id (sort keys %{$data{'unneeded'}})
  {
    my $record = $crms->GetMetadata($id);
    my $title = $crms->GetRecordTitle($id, $record);
    $title =~ s/&/&amp;/g;
    my @lines = split "\n", $data{'unneeded'}->{$id};
    foreach my $line (@lines)
    {
      $n++;
      my ($id2,$sysid,$c,$d,$e) = split "\t", $line;
      my $htCatLink = $crms->LinkToCatalog($sysid);
      my $retrLink = $crms->LinkToRetrieve($sysid);
      my $histLink = $crms->LinkToHistorical($sysid);
      $txt .= "<tr><td>$n</td><td><a href='$histLink' target='_blank'>$e</a></td><td><a href='$retrLink' target='_blank'>$id2</a></td>";
      $txt .= "<td><a href='$htCatLink' target='_blank'>$sysid</a></td><td>$c</td><td>$d</td><td>$title</td></tr>\n";
    }
  }
  $txt .= "</table>$delim";
}
if (scalar keys %{$data{'disallowed'}})
{
  $txt .= "<h4>Volumes for which inheritance was not allowed</h4>\n";
  $txt .= "<table border='1'><tr><th>#</th><th>Source&nbsp;Volume<br/>(<span style='color:blue;'>historical</span>)</th>" .
          "<th>Volume Checked<br/>(<span style='color:blue;'>volume retrieval</span>)</th><th>Sys ID<br/>(<span style='color:blue;'>catalog</span>)</th>" .
          "<th>Rights</th><th>New Rights</th><th>Why</th><th>Title</th></tr>\n";
  my $n = 0;
  foreach my $id (keys %{$data{'disallowed'}})
  {
    my $record = $crms->GetMetadata($id);
    my $title = $crms->GetRecordTitle($id, $record);
    $title =~ s/&/&amp;/g;
    my @lines = split "\n", $data{'disallowed'}->{$id};
    foreach my $line (@lines)
    {
      $n++;
      my ($id2,$sysid,$c,$d,$e,$note) = split "\t", $line;
      my $htCatLink = $crms->LinkToCatalog($sysid);
      my $retrLink = $crms->LinkToRetrieve($sysid);
      my $histLink = $crms->LinkToHistorical($sysid);
      $txt .= "<tr><td>$n</td><td><a href='$histLink' target='_blank'>$id</a></td><td><a href='$retrLink' target='_blank'>$id2</a></td>";
      $txt .= "<td><a href='$htCatLink' target='_blank'>$sysid</a></td><td>$c</td><td>$d</td><td>$note</td><td>$title</td></tr>\n";
    }
  }
  $txt .= "</table>$delim";
}

if (scalar keys %{$data{'inherit'}})
{
  my @cols = ('#','Source&nbsp;Volume<br/>(<span style="color:blue;">historical</span>)',
              'Volume&nbsp;Inheriting<br/>(<span style="color:blue;">volume retrieval</span>)',
              'Sys ID<br/>(<span style="color:blue;">catalog</span>)','Rights','New Rights',
              'Prior CRMS Review?','Access Change?','Title');
  $txt .= '<h4>Volumes for which inheritance was needed</h4>';
  $txt .= '<table border="1"><tr><th>' . join('</th><th>', @cols) . "</th></tr>\n";
  my $n = 0;
  foreach my $id (sort keys %{$data{'inherit'}})
  {
    my $record = $crms->GetMetadata($id);
    my $title = $crms->GetRecordTitle($id, $record);
    $title =~ s/&/&amp;/g;
    my @lines = split "\n", $data{'inherit'}->{$id};
    foreach my $line (@lines)
    {
      my ($id2,$sysid,$attr2,$reason2,$attr,$reason,$gid) = split "\t", $line;
      $n++;
      my $catLink = "http://mirlyn.lib.umich.edu/Record/$sysid/Details#tabs";
      my $htCatLink = $crms->LinkToCatalog($sysid);
      my $histLink = $crms->LinkToHistorical($sysid);
      my $retrLink = $crms->LinkToRetrieve($sysid);
      my ($pd,$pdus,$icund) = (0,0,0);
      $pd = 1 if ($attr eq 'pd' || $attr2 eq 'pd');
      $pdus = 1 if ($attr eq 'pdus' || $attr2 eq 'pdus');
      $icund = 1 if ($attr eq 'ic' || $attr2 eq 'ic');
      $icund = 1 if ($attr eq 'und' || $attr2 eq 'und');
      my $incrms = (($attr2 eq 'ic' && $reason2 eq 'bib') || $reason2 eq 'gfv')? '':'&nbsp;&nbsp;&nbsp;&#x2713';
      my $change = (($pd == 1 && $icund == 1) || ($pd == 1 && $pdus == 1) || ($icund == 1 && $pdus == 1));
      #print "$change from $pd and $icund ($attr,$attr2)\n";
      my $ar = "$attr/$reason";
      $change = ($change)? '&nbsp;&nbsp;&nbsp;&#x2713':'';
      $txt .= "<tr><td>$n</td><td><a href='$histLink' target='_blank'>$id</a></td><td><a href='$retrLink' target='_blank'>$id2</a></td>";
      $txt .= "<td><a href='$htCatLink' target='_blank'>$sysid</a></td><td>$attr2/$reason2</td><td>$ar</td><td>$incrms</td><td>$change</td><td>$title</td></tr>\n";
      $data{'inheriting'}->{$id2} = 1;
    }
  }
  $txt .= '</table>';
}

my $header = sprintf("Total # volumes checked for inheritance from $dates: %d$delim", scalar keys %{$data{'total'}});
$header .= sprintf("Total # unique Sys IDs: %d$delim$delim", scalar keys %{$data{'totalsys'}});
$header .= sprintf("Volumes single copy: %d$delim$delim", scalar keys %{$data{'nodups'}});
$header .= sprintf("Volumes w/ chron/enum: %d$delim$delim", scalar keys %{$data{'chron'}});
$header .= sprintf("Volumes not allowed to inherit: %d$delim$delim", scalar keys %{$data{'disallowed'}});
if ($candidates)
{
  $header .= sprintf("Volumes checked, no duplicates with CRMS exports from June 2010: %d$delim", scalar keys %{$data{'noexport'}});
  $header .= sprintf("Unique Sys IDs checked, no duplicates with CRMS exports from June 2010: %d$delim$delim", scalar keys %{$data{'noexportsys'}});
}
else
{
  $header .= sprintf("Volumes checked, no inheritance needed: %d$delim", scalar keys %{$data{'unneeded'}});
  $header .= sprintf("Unique Sys IDs checked, no inheritance needed: %d$delim$delim", scalar keys %{$data{'unneededsys'}});
}
$header .= sprintf("Volumes checked - inheritance permitted: %d$delim", scalar keys %{$data{'inherit'}});
$header .= sprintf("Unique Sys IDs w/ volumes inheriting rights: %d$delim", scalar keys %{$data{'inheritsys'}});
$header .= sprintf("Volumes inheriting rights: %d$delim", scalar keys %{$data{'inheriting'}});
$txt = $header . $delim . $txt;

if ($insert)
{
  $txt .= '<h4>Now inserting inheritance data</h4>';
  foreach my $id (keys %{$data{'inherit'}})
  {
    my @lines = split "\n", $data{'inherit'}->{$id};
    foreach my $line (@lines)
    {
      my ($id2,$sysid,$attr2,$reason2,$attr,$reason,$gid) = split "\t", $line;
      $attr2 = $crms->GetRightsNum($attr2);
      $reason2 = $crms->GetReasonNum($reason2);
      my $sql = "REPLACE INTO inherit (id,attr,reason,gid) VALUES ('$id2',$attr2,$reason2,$gid)";
      #print "$sql\n";
      $crms->PrepareSubmitSql($sql);
    }
  }
}

for (@{$crms->GetErrors()})
{
  s/\n/<br\/>/g;
  $txt .= "<i>Warning: $_</i><br/>\n" ;
}
$txt .= "</body></html>\n\n";

if (@mails)
{
  use Mail::Sender;
  $title = 'Dev: ' . $title if $DLPS_DEV;
  my $sender = new Mail::Sender { smtp => 'mail.umdl.umich.edu',
                                  from => $CRMSGlobals::adminEmail,
                                  on_errors => 'undef' }
    or die "Error in mailing : $Mail::Sender::Error\n";
  my $to = join ',', @mails;
  my $ctype = 'text/html';
  $sender->OpenMultipart({
    to => $to,
    subject => $title,
    ctype => $ctype,
    encoding => 'utf-8'
    }) or die $Mail::Sender::Error,"\n";
  $sender->Body();
  my $bytes = encode('utf8', $txt);
  $sender->SendEnc($bytes);
  $sender->Close();
}
else
{
  print "$txt\n";
}


sub InheritanceReport
{
  my $start = shift;
  my $end   = shift;

  my %data = ();
  my $sql = "SELECT id,gid,attr,reason FROM exportdata WHERE time>'$start 00:00:00' AND time<='$end 23:59:59' ORDER BY id";
  my $ref = $dbh->selectall_arrayref($sql);
  foreach my $row (@{$ref})
  {
    my $id = $row->[0];
    my $gid = $row->[1];
    my $attr = $row->[2];
    my $reason = $row->[3];
    my $sysid = $crms->BarcodeToId($id);
    $data{'total'}->{$id} = 1;
    $data{'totalsys'}->{$sysid} = 1;
    $crms->DuplicateVolumesFromExport($id,$gid,$sysid,$attr,$reason,\%data);
  }
  return \%data;
}

sub CandidatesReport
{
  my $start = shift;
  my $end   = shift;

  my %data = ();
  my $sql = "SELECT id FROM candidates WHERE time>'$start 00:00:00' AND time<='$end 23:59:59' ORDER BY id";
  #print "$sql\n";
  my $ref = $dbh->selectall_arrayref($sql);
  foreach my $row (@{$ref})
  {
    my $id = $row->[0];
    my $sysid = $crms->BarcodeToId($id);
    $data{'total'}->{$id} = 1;
    $data{'totalsys'}->{$sysid} = 1;
    $crms->DuplicateVolumesFromCandidates($id,$sysid,\%data);
  }
  return \%data;
}



