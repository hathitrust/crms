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
use Getopt::Long qw(:config no_ignore_case bundling);
use Encode;

my $usage = <<END;
USAGE: $0 [-acChipqv] [-s VOL_ID [-s VOL_ID2...]]
          [-m MAIL_ADDR [-m MAIL_ADDR2...]] [start_date [end_date]]

Reports on the volumes that can inherit from this morning's export,
or, if start_date is specified, exported after then and before end_date
if it is specified.

-a         Report on all exports, regardless of date range.
-c         Report on recent addition to candidates.
-C         Use 'cleanup' as the source.
-h         Print this help message.
-i         Insert entries in the dev inherit table.
-m ADDR    Mail the report to ADDR. May be repeated for multiple addresses.
-p         Run in production.
-q         Do not emit report (ignored if -m is used).
-s VOL_ID  Report only for HT volume VOL_ID. May be repeated for multiple volumes.
-v         Emit debugging information.
END

my $all;
my $candidates;
my $cleanup;
my $help;
my $insert;
my @mails;
my $production;
my $quiet;
my @singles;
my $verbose;

Getopt::Long::Configure ('bundling');
die 'Terminating' unless GetOptions(
           'a'    => \$all,
           'c'    => \$candidates,
           'C'    => \$cleanup,
           'h|?'  => \$help,
           'i'    => \$insert,
           'm:s@' => \@mails,
           'p'    => \$production,
           'q'    => \$quiet,
           's:s@' => \@singles,
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
my $sql = 'SELECT DATE(NOW())';
$sql = 'SELECT DATE(DATE_SUB(NOW(),INTERVAL 1 DAY))' if $candidates;
my $start = $crms->SimpleSqlGet($sql);
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
my %data = %{($candidates)? CandidatesReport($start,$end,\@singles):InheritanceReport($start,$end,\@singles)};

my $dates = $start;
$dates .= " to $end" if $end ne $start;
my $title = sprintf "CRMS %s Inheritance, $dates", ($candidates)? 'Candidates':'Export';
my $head = '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">' . "\n";
$head .= '<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en"><head>' .
        "<meta http-equiv='Content-Type' content='text/html; charset=utf-8'/>\n" .
        "<title>$title</title></head><body>\n";
my $txt = '';
$delim = "<br/>\n";

if (scalar keys %{$data{'unavailable'}})
{
  $txt .= "<h4>Volumes which had no metadata available</h4>\n";
  $txt .= "<table border='1'><tr><th>#</th><th>Volume Checked<br/>(<span style='color:blue;'>volume tracking</span>)</th></tr>\n";
  my $n = 0;
  foreach my $id (keys %{$data{'unavailable'}})
  {
    $n++;
    my $retrLink = $crms->LinkToRetrieve($id,1);
    $txt .= "<tr><td>$n</td><td><a href='$retrLink' target='_blank'>$id</a></td></tr>\n";
    $crms->PrepareSubmitSql("REPLACE INTO unavailable (id) VALUES ('$id')");
  }
  $txt .= "</table>$delim";
}
if (scalar keys %{$data{'nodups'}})
{
  $txt .= sprintf("<h4>Volumes single copy/no duplicates%s</h4>\n", ($candidates)? ' - No Inheritance/Adding to Candidates':'');
  $txt .= "<table border='1'><tr><th>#</th><th>Volume Checked<br/>(<span style='color:blue;'>volume tracking</span>)</th>" .
          "<th>Sys ID<br/>(<span style='color:blue;'>catalog</span>)</th></tr>\n";
  my $n = 0;
  foreach my $id (keys %{$data{'nodups'}})
  {
    my @lines = split "\n", $data{'nodups'}->{$id};
    foreach my $sysid (@lines)
    {
      $n++;
      my $htCatLink = $crms->LinkToCatalog($sysid);
      my $retrLink = $crms->LinkToRetrieve($sysid,1);
      $txt .= "<tr><td>$n</td><td><a href='$retrLink' target='_blank'>$id</a></td><td><a href='$htCatLink' target='_blank'>$sysid</a></td></tr>\n";
    }
  }
  $txt .= "</table>$delim";
}
if (scalar keys %{$data{'chron'}})
{
  $txt .= sprintf("<h4>Volumes skipped because of chron/enum%s</h4>\n", ($candidates)? ' - No Inheritance/Adding to Candidates':'');
  $txt .= "<table border='1'><tr><th>#</th><th>Source&nbsp;Volume<br/>(<span style='color:blue;'>historical/SysID</span>)</th>" .
          '<th>Volume Checked<br/>(<span style="color:blue;">volume tracking</span>)</th>' .
          '<th>Sys ID<br/>(<span style="color:blue;">catalog</span>)</th>' .
          "<th>Title</th></tr>\n";
  my $n = 0;
  foreach my $id (KeysSortedOnTitle($data{'chron'}))
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
      my $retrLink = $crms->LinkToRetrieve($sysid,1);
      my $histLink = $crms->LinkToHistorical($sysid,1);
      $txt .= "<tr><td>$n</td><td><a href='$histLink' target='_blank'>$id</a></td>" .
              "<td><a href='$retrLink' target='_blank'>$id2</a></td>\n";
      $txt .= "<td><a href='$htCatLink' target='_blank'>$sysid</a></td><td>$title</td></tr>\n";
    }
  }
  $txt .= "</table>$delim";
}
if (scalar keys %{$data{'unneeded'}})
{
  $txt .= sprintf("<h4>Volumes not needing inheritance</h4>\n", ($candidates)? ' - No Inheritance/Adding to Candidates':'');
  $txt .= "<table border='1'><tr><th>#</th><th>Source&nbsp;Volume<br/>(<span style='color:blue;'>historical/SysID</span>)</th>" .
          '<th>Volume Checked<br/>(<span style="color:blue;">volume tracking</span>)</th>' .
          '<th>Sys ID<br/>(<span style="color:blue;">catalog</span>)</th><th>Rights</th><th>New Rights</th>' .
          "<th>Title</th></tr>\n";
  my $n = 0;
  foreach my $id (KeysSortedOnTitle($data{'unneeded'}))
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
      my $retrLink = $crms->LinkToRetrieve($sysid,1);
      my $histLink = $crms->LinkToHistorical($sysid,1);
      $txt .= "<tr><td>$n</td><td><a href='$histLink' target='_blank'>$e</a></td><td><a href='$retrLink' target='_blank'>$id2</a></td>";
      $txt .= "<td><a href='$htCatLink' target='_blank'>$sysid</a></td><td>$c</td><td>$d</td><td>$title</td></tr>\n";
    }
  }
  $data{'unneededcnt'} = $n;
  $txt .= "</table>$delim";
}
if (scalar keys %{$data{'disallowed'}})
{
  $txt .= "<h4>Volumes not allowed to inherit</h4>\n";
  $txt .= "<table border='1'><tr><th>#</th><th>Source&nbsp;Volume<br/>(<span style='color:blue;'>historical/SysID</span>)</th>" .
          "<th>Volume Checked<br/>(<span style='color:blue;'>volume tracking</span>)</th><th>Sys ID<br/>(<span style='color:blue;'>catalog</span>)</th>" .
          "<th>Rights</th><th>New Rights</th><th>Why</th><th>Title</th></tr>\n";
  my $n = 0;
  foreach my $id (KeysSortedOnTitle($data{'disallowed'}))
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
      my $retrLink = $crms->LinkToRetrieve($sysid,1);
      my $histLink = $crms->LinkToHistorical($sysid,1);
      $txt .= "<tr><td>$n</td><td><a href='$histLink' target='_blank'>$id</a></td><td><a href='$retrLink' target='_blank'>$id2</a></td>";
      $txt .= "<td><a href='$htCatLink' target='_blank'>$sysid</a></td><td>$c</td><td>$d</td><td>$note</td><td>$title</td></tr>\n";
    }
  }
  $data{'disallowedcnt'} = $n;
  $txt .= "</table>$delim";
}
if (scalar keys %{$data{'noexport'}})
{
  $txt .= "<h4>Volumes checked, no duplicates with CRMS determination (from June 2010 or later) in CRMS exports table - No Inheritance/Adding to Candidates</h4>\n";
  $txt .= "<table border='1'><tr><th>#</th><th>Volume Checked<br/>(<span style='color:blue;'>volume tracking</span>)</th>" .
          "<th>Sys ID<br/>(<span style='color:blue;'>catalog</span>)</th></tr>\n";
  my $n = 0;
  foreach my $id (keys %{$data{'noexport'}})
  {
    my @lines = split "\n", $data{'noexport'}->{$id};
    foreach my $sysid (@lines)
    {
      $n++;
      my $htCatLink = $crms->LinkToCatalog($sysid);
      my $retrLink = $crms->LinkToRetrieve($sysid,1);
      $txt .= "<tr><td>$n</td><td><a href='$retrLink' target='_blank'>$id</a></td><td><a href='$htCatLink' target='_blank'>$sysid</a></td></tr>\n";
    }
  }
  $txt .= "</table>$delim";
}
if (scalar keys %{$data{'already'}})
{
  $txt .= "<h4>Volumes checked, no duplicates with CRMS determination (from June 2010 or later), duplicate volume already in candidates - Filtered from candidates temporarily</h4>\n";
  $txt .= "<table border='1'><tr><th>#</th><th>Source&nbsp;Volume</th>" .
          '<th>Volume Checked<br/>(<span style="color:blue;">volume tracking</span>)</th>' .
          "<th>Sys ID<br/>(<span style='color:blue;'>catalog</span>)</th></tr>\n";
  my $n = 0;
  foreach my $id (keys %{$data{'already'}})
  {
    my @lines = split "\n", $data{'already'}->{$id};
    foreach my $line (@lines)
    {
      $n++;
      my ($id2,$sysid) = split "\t", $line;
      my $htCatLink = $crms->LinkToCatalog($sysid);
      my $retrLink = $crms->LinkToRetrieve($sysid,1);
      $txt .= "<tr><td>$n</td><td>$id2</td><td><a href='$retrLink' target='_blank'>$id</a></td><td><a href='$htCatLink' target='_blank'>$sysid</a></td></tr>\n";
    }
  }
  $txt .= "</table>$delim";
}

if (scalar keys %{$data{'inherit'}})
{
  my @cols = ('#','Source&nbsp;Volume<br/>(<span style="color:blue;">historical/SysID</span>)',
              'Volume&nbsp;Inheriting<br/>(<span style="color:blue;">volume tracking</span>)',
              'Sys ID<br/>(<span style="color:blue;">catalog</span>)','Rights','New Rights',
              'Access Change?');
  my $autotxt = '';
  if ($candidates)
  {
    $autotxt .= '<h4>Volumes where a duplicate w/CRMS determination exists (from June 2010 or later) - inheritance permitted -- Not Adding to Candidates - Status 9 Review awaiting approval</h4>';
  }
  else
  {
    push @cols, ('Prior<br/>CRMS<br/>Determ?','Prior<br/>Status 5<br/>Determ?');
    $autotxt .= '<h4>Volumes inheriting rights automatically</h4>';
  }
  push @cols, 'Missing/Wrong Record?','Title','Tracking';
  $autotxt .= '<table border="1"><tr><th>' . join('</th><th>', @cols) . "</th></tr>\n";
  my $pendtxt = '<h4>Volumes inheriting rights pending approval</h4><table border="1"><tr><th>' . join('</th><th>', @cols) . "</th></tr>\n";
  my $n = 0;
  my $npend = 0;
  foreach my $id (KeysSortedOnTitle($data{'inherit'}))
  {
    my $record = $crms->GetMetadata($id);
    my $title = $crms->GetRecordTitle($id, $record);
    $title =~ s/&/&amp;/g;
    my @lines = split "\n", $data{'inherit'}->{$id};
    foreach my $line (@lines)
    {
      my ($id2,$sysid,$attr2,$reason2,$attr,$reason,$gid) = split "\t", $line;
      my $catLink = "http://mirlyn.lib.umich.edu/Record/$sysid/Details#tabs";
      my $htCatLink = $crms->LinkToCatalog($sysid);
      my $histLink = $crms->LinkToHistorical($sysid,1);
      my $retrLink = $crms->LinkToRetrieve($sysid,1);
      my ($pd,$pdus,$icund) = (0,0,0);
      $pd = 1 if ($attr eq 'pd' || $attr2 eq 'pd');
      $pdus = 1 if ($attr eq 'pdus' || $attr2 eq 'pdus');
      $icund = 1 if ($attr eq 'ic' || $attr2 eq 'ic');
      $icund = 1 if ($attr eq 'und' || $attr2 eq 'und');
      my $incrms = (($attr2 eq 'ic' && $reason2 eq 'bib') || $reason2 eq 'gfv')? '':'&nbsp;&nbsp;&nbsp;&#x2713;';
      my $h5 = '';
      my $whichtxt = \$autotxt;
      my $whichn;
      if ($incrms)
      {
        my $sql = "SELECT COUNT(*) FROM historicalreviews WHERE id='$id2' AND status=5";
        $h5 = '&nbsp;&nbsp;&nbsp;&#x2713;' if $crms->SimpleSqlGet($sql);
        $whichtxt = \$pendtxt;
        $npend++;
        $whichn = $npend;
      }
      else
      {
        $n++;
        $whichn = $n;
      }
      my $miss = ($crms->HasMissingOrWrongRecord($sysid)>0)? '&nbsp;&nbsp;&nbsp;&#x2713;':'';
      my $change = (($pd == 1 && $icund == 1) || ($pd == 1 && $pdus == 1) || ($icund == 1 && $pdus == 1));
      #print "$change from $pd and $icund ($attr,$attr2)\n";
      my $ar = "$attr/$reason";
      $change = ($change)? '&nbsp;&nbsp;&nbsp;&#x2713;':'';
      my $tracking = $crms->GetTrackingInfo($id2);
      $$whichtxt .= "<tr><td>$whichn</td><td><a href='$histLink' target='_blank'>$id</a></td><td><a href='$retrLink' target='_blank'>$id2</a></td>";
      $$whichtxt .= "<td><a href='$htCatLink' target='_blank'>$sysid</a></td><td>$attr2/$reason2</td><td>$ar</td><td>$change</td>";
      $$whichtxt .= "<td>$incrms</td><td>$h5</td>" unless $candidates;
      $$whichtxt .= "<td>$miss</td><td>$title</td><td>$tracking</td></tr>\n";
    }
  }
  $data{'inheritcnt'} = $n;
  $data{'pendinheritcnt'} = $npend;
  $autotxt .= '</table>';
  $pendtxt .= '</table>';
  $txt .= $autotxt if $n;
  $txt .= $pendtxt if $npend;
}

my $header = sprintf("Total # volumes checked for inheritance from $dates: %d$delim", scalar keys %{$data{'total'}});
$header .= sprintf("Total # unique Sys IDs: %d$delim$delim", $crms->CountSystemIds(keys %{$data{'total'}}));
$header .= sprintf("Volumes for which metadata was unavailable: %d$delim$delim", scalar keys %{$data{'unavailable'}});
if ($candidates)
{
  $header .= "<h4>No inheritance - Adding to candidates:</h4>$delim";
}
$header .= sprintf("Volumes single copy/no duplicates: %d$delim$delim", scalar keys %{$data{'nodups'}});
$header .= sprintf("Volumes w/ chron/enum: %d$delim$delim", scalar keys %{$data{'chron'}});
if ($candidates)
{
  $header .= sprintf("Volumes checked, no duplicates with CRMS determination (from June 2010 or later) in CRMS exports table: %d$delim", scalar keys %{$data{'noexport'}});
  $header .= sprintf("Unique Sys IDs checked, no duplicates with CRMS determination (from June 2010 or later): %d$delim$delim", $crms->CountSystemIds(keys %{$data{'noexport'}}));
  $header .= "<h4>Filtered from candidates temporarily:</h4>$delim";
  $header .= sprintf("Volumes checked, no duplicates with CRMS determination (from June 2010 or later), duplicate volume already in candidates: %d$delim", scalar keys %{$data{'already'}});
  $header .= sprintf("Unique Sys IDs checked, duplicate volume already in candidates: %d$delim$delim", $crms->CountSystemIds(keys %{$data{'already'}}));
}
else
{
  $header .= sprintf("Volumes checked, no inheritance needed: %d$delim", scalar keys %{$data{'unneeded'}});
  $header .= sprintf("Unique Sys IDs checked, no inheritance needed: %d$delim", $crms->CountSystemIds(keys %{$data{'unneeded'}}));
  $header .= sprintf("Volumes not needing inheritance: %d$delim$delim", $data{'unneededcnt'});
}
$header .= sprintf("Volumes checked, inheritance not permitted: %d$delim", scalar keys %{$data{'disallowed'}});
$header .= sprintf("Volumes not allowed to inherit: %d$delim$delim", $data{'disallowedcnt'});
if ($candidates)
{
  $header .= "<h4>Inheritance Permitted - Not Adding to Candidates - Status 9 Review awaiting approval:</h4>$delim";
  $header .= sprintf("Volumes checked - duplicate w/CRMS determination exists (from June 2010 or later) - inheritance permitted: %d$delim", scalar keys %{$data{'inherit'}});
}
else
{
  $header .= sprintf("Volumes checked - inheritance permitted: %d$delim", scalar keys %{$data{'inherit'}});
}
$header .= sprintf("Unique Sys IDs w/ volumes inheriting rights: %d$delim", $crms->CountSystemIds(keys %{$data{'inherit'}}));
$header .= sprintf("Volumes inheriting rights automatically: %d$delim", $data{'inheritcnt'});
if (!$candidates)
{
  $header .= sprintf("Volumes inheriting rights pending approval: %d$delim", $data{'pendinheritcnt'});
}
$txt = $head . $header . $delim . $txt;

if ($insert && scalar keys %{$data{'inherit'}})
{
  $txt .= '<h4>Now inserting inheritance data</h4>';
  my $src = ($candidates)? 'candidates':'export';
  $src = 'cleanup' if $cleanup;
  foreach my $id (keys %{$data{'inherit'}})
  {
    my @lines = split "\n", $data{'inherit'}->{$id};
    foreach my $line (@lines)
    {
      my ($id2,$sysid,$attr2,$reason2,$attr,$reason,$gid) = split "\t", $line;
      $attr2 = $crms->GetRightsNum($attr2);
      $reason2 = $crms->GetReasonNum($reason2);
      my $sql = "REPLACE INTO inherit (id,attr,reason,gid,src) VALUES ('$id2',$attr2,$reason2,$gid,'$src')";
      #print "$sql\n";
      $crms->PrepareSubmitSql($sql);
      $crms->Filter($id2, 'duplicate') if $crms->IsVolumeInCandidates($id2);
    }
  }
  if ($candidates)
  {
    $txt .= '<h4>Now filtering duplicates in candidates</h4>';
    foreach my $id (keys %{$data{'already'}})
    {
      my @lines = split "\n", $data{'already'}->{$id};
      foreach my $line (@lines)
      {
        my ($id2,$sysid) = split "\t", $line;
        $crms->FilterCandidates($id2, $id);
      }
    }
  }
}
if ($insert && scalar keys %{$data{'disallowed'}})
{
  foreach my $id (keys %{$data{'disallowed'}})
  {
    my @lines = split "\n", $data{'disallowed'}->{$id};
    foreach my $line (@lines)
    {
      my ($id2,$sysid,$oldrights,$newrights,$ignore,$note) = split "\t", $line;
      if ($note =~ m/^Missing/ && $crms->IsFiltered($id2, 'duplicate'))
      {
        $txt .= "<h5>Unfiltering $id2</h5>\n";
        $crms->Unfilter($id2) 
      }
    }
  }
  
}

for (@{$crms->GetErrors()})
{
  s/\n/<br\/>/g;
  $txt .= "<i>Warning: $_</i><br/>\n";
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
  print "$txt\n" unless $quiet;
}


sub InheritanceReport
{
  my $start = shift;
  my $end   = shift;
  my $singles = shift;

  my %data = ();
  my %seen = ();
  my $sql = "SELECT id,gid,attr,reason,time FROM exportdata WHERE (time>'$start 00:00:00' AND time<='$end 23:59:59') " .
            'OR id IN (SELECT id FROM unavailable) ORDER BY time DESC';
  if ($singles && scalar @{$singles})
  {
    $sql = sprintf("SELECT id,gid,attr,reason,time FROM exportdata WHERE id in ('%s') ORDER BY id", join "','", @{$singles});
  }
  #print "$sql\n";
  my $ref = $dbh->selectall_arrayref($sql);
  foreach my $row (@{$ref})
  {
    my $id = $row->[0];
    my $gid = $row->[1];
    my $attr = $row->[2];
    my $reason = $row->[3];
    my $time = $row->[4];
    next if $seen{$id};
    $seen{$id} = $id;
    my $sysid = $crms->BarcodeToId($id);
    if (!$sysid)
    {
      $data{'unavailable'}->{$id} = 1;
      $crms->ClearErrors();
      next;
    }
    # When using date ranges, earlier export should not supersede later.
    my $latest = $crms->SimpleSqlGet("SELECT time FROM exportdata WHERE id='$id' ORDER BY time DESC LIMIT 1");
    next if $time lt $latest;
    $data{'total'}->{$id} = 1;
    $crms->DuplicateVolumesFromExport($id,$gid,$sysid,$attr,$reason,\%data);
  }
  $crms->PrepareSubmitSql('DELETE FROM unavailable');
  return \%data;
}

sub CandidatesReport
{
  my $start   = shift;
  my $end     = shift;
  my $singles = shift;

  my %data = ();
  my $sql = "SELECT id FROM candidates WHERE (time>'$start 00:00:00' AND time<='$end 23:59:59') " .
            'OR id IN (SELECT id FROM unavailable) ORDER BY time DESC';
  if ($singles && scalar @{$singles})
  {
    $sql = sprintf("SELECT id FROM candidates WHERE id in ('%s') ORDER BY id", join "','", @{$singles});
  }
  my $ref = $dbh->selectall_arrayref($sql);
  foreach my $row (@{$ref})
  {
    my $id = $row->[0];
    my $sysid = $crms->BarcodeToId($id);
    $data{'total'}->{$id} = 1;
    $crms->DuplicateVolumesFromCandidates($id,$sysid,\%data);
  }
  $crms->PrepareSubmitSql('DELETE FROM unavailable');
  return \%data;
}

sub KeysSortedOnTitle
{
  my $ref = shift;

  return sort {
    my $aa = lc $crms->GetRecordTitle($a);
    my $ba = lc $crms->GetRecordTitle($b);
    #print "'$aa' cmp '$ba'?\n";
    $aa cmp $ba
    ||
    $a cmp $b;
  } keys %{$ref};
}

