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
use Getopt::Long qw(:config no_ignore_case bundling);
use Encode;

my $usage = <<END;
USAGE: $0 [-acChipquv] [-s VOL_ID [-s VOL_ID2...]]
          [-m MAIL_ADDR [-m MAIL_ADDR2...]] [-n TBL [-n TBL...]]
          [-x SYS] [start_date[ time] [end_date[ time]]]

Reports on the volumes that can inherit from this morning's export,
or, if start_date is specified, exported after then and before end_date
if it is specified.

-a         Report on all exports, regardless of date range.
-c         Report on recent addition to candidates.
-C         Use 'cleanup' as the source.
-h         Print this help message.
-i         Insert entries in the inherit table.
-m ADDR    Mail the report to ADDR. May be repeated for multiple addresses.
-n TBL     Suppress table TBL (which is often huge in candidates cleanup),
           where TBL is one of {chron,nodups,noexport,unneeded}.
           May be repeated for multiple tables.
-p         Run in production.
-q         Do not emit report (ignored if -m is used).
-s VOL_ID  Report only for HT volume VOL_ID. May be repeated for multiple volumes.
-u         Also report on recent additions to the und table (ignored if -c is not used).
-v         Emit debugging information.
-x SYS     Set SYS as the system to execute.
END

my $all;
my $candidates;
my $cleanup;
my $help;
my $insert;
my @mails;
my @no;
my $production;
my $quiet;
my @singles;
my $sys;
my $und;
my $verbose;

Getopt::Long::Configure ('bundling');
die 'Terminating' unless GetOptions(
           'a'    => \$all,
           'c'    => \$candidates,
           'C'    => \$cleanup,
           'h|?'  => \$help,
           'i'    => \$insert,
           'm:s@' => \@mails,
           'n:s@' => \@no,
           'p'    => \$production,
           'q'    => \$quiet,
           's:s@' => \@singles,
           'u'    => \$und,
           'v+'   => \$verbose,
           'x:s'  => \$sys);
$DLPS_DEV = undef if $production;
die "$usage\n\n" if $help;

my %no = ();
$no{$_}=1 for @no;

my $crms = CRMS->new(
    logFile => "$DLXSROOT/prep/c/crms/inherit_hist.txt",
    sys     => $sys,
    verbose => $verbose,
    root    => $DLXSROOT,
    dev     => $DLPS_DEV
);
$crms->set('ping','yes');
my $delim = "\n";
my $src = ($candidates)? 'candidates':'export';
$src = 'cleanup' if $cleanup;
print "Verbosity $verbose$delim" if $verbose;
my $dbh = $crms->GetDb();
my $sql = 'SELECT DATE(NOW())';
$sql = 'SELECT DATE(DATE_SUB(NOW(),INTERVAL 1 DAY))' if $candidates;
my $start = $crms->SimpleSqlGet($sql);
my $end = $start;
if ($all)
{
  $sql = sprintf 'SELECT MIN(time) FROM %s', ($candidates)? 'candidates':'exportdata';
  $start = $crms->SimpleSqlGet($sql);
  $sql = sprintf 'SELECT MAX(time) FROM %s', ($candidates)? 'candidates':'exportdata';
  $end = $crms->SimpleSqlGet($sql);
}
elsif (scalar @ARGV)
{
  $start = $ARGV[0];
  die "Bad date format ($start); should be in the form e.g. 2010-08-29" unless $start =~ m/^\d\d\d\d-\d\d-\d\d(\s+\d\d:\d\d:\d\d)?$/;
  if (scalar @ARGV > 1)
  {
    $end = $ARGV[1];
    die "Bad date format ($end); should be in the form e.g. 2010-08-29" unless $end =~ m/^\d\d\d\d-\d\d-\d\d(\s+\d\d:\d\d:\d\d)?$/;
  }
}
my $dates = $start;
$dates .= " to $end" if $end ne $start;
my $title = sprintf "%s %s: %s %sInheritance, $dates",
                    $crms->System(),
                    ($DLPS_DEV)? 'Dev':'Prod',
                    ($candidates)? 'Candidates':'Export', 
                    ($cleanup)? 'Cleanup ':'';
$start .= ' 00:00:00' unless $start =~ m/\d\d:\d\d:\d\d$/;
$end .= ' 23:59:59' unless $end =~ m/\d\d:\d\d:\d\d$/;
my %data = %{($candidates)? CandidatesReport($start,$end,\@singles):InheritanceReport($start,$end,\@singles)};
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
    if ($insert)
    {
      $sql = "REPLACE INTO unavailable (id,src) VALUES ('$id','$src')";
      print "$sql\n" if $verbose > 1;
      $crms->PrepareSubmitSql($sql);
    }
  }
  $txt .= "</table>$delim";
}
if (scalar keys %{$data{'nodups'}} && !$no{'nodups'})
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
if (scalar keys %{$data{'chron'}} && !$no{'chron'})
{
  $txt .= sprintf("<h4>Volumes skipped because of chron/enum%s</h4>\n", ($candidates)? ' - No Inheritance/Adding to Candidates':'');
  $txt .= "<table border='1'><tr><th>#</th><th>Source&nbsp;Volume<br/>(<span style='color:blue;'>historical/SysID</span>)</th>" .
          '<th>Volume Checked<br/>(<span style="color:blue;">volume tracking</span>)</th>' .
          '<th>Sys ID<br/>(<span style="color:blue;">catalog</span>)</th>' .
          "<th>Title</th></tr>\n";
  my $n = 0;
  my $th = GetTitleHash($data{'chron'}, \%data);
  foreach my $id (KeysSortedOnTitle($data{'chron'}), $th)
  {
    #my $record = $crms->GetMetadata($id);
    my $title2 = $th->{$id};
    $title2 =~ s/&/&amp;/g;
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
      $txt .= "<td><a href='$htCatLink' target='_blank'>$sysid</a></td><td>$title2</td></tr>\n";
    }
  }
  $txt .= "</table>$delim";
}
if (scalar keys %{$data{'unneeded'}} && !$no{'unneeded'})
{
  $txt .= sprintf("<h4>Volumes not needing inheritance</h4>\n", ($candidates)? ' - No Inheritance/Adding to Candidates':'');
  $txt .= "<table border='1'><tr><th>#</th><th>Source&nbsp;Volume<br/>(<span style='color:blue;'>historical/SysID</span>)</th>" .
          '<th>Volume Checked<br/>(<span style="color:blue;">volume tracking</span>)</th>' .
          '<th>Sys ID<br/>(<span style="color:blue;">catalog</span>)</th><th>Rights</th><th>New Rights</th>' .
          "<th>Title</th></tr>\n";
  my $n = 0;
  my $th = GetTitleHash($data{'unneeded'}, \%data);
  foreach my $id (KeysSortedOnTitle($data{'unneeded'}, $th))
  {
    #my $record = $crms->GetMetadata($id);
    my $title2 = $th->{$id};
    $title2 =~ s/&/&amp;/g;
    my @lines = split "\n", $data{'unneeded'}->{$id};
    foreach my $line (@lines)
    {
      $n++;
      my ($id2,$sysid,$c,$d,$e) = split "\t", $line;
      my $htCatLink = $crms->LinkToCatalog($sysid);
      my $retrLink = $crms->LinkToRetrieve($sysid,1);
      my $histLink = $crms->LinkToHistorical($sysid,1);
      $txt .= "<tr><td>$n</td><td><a href='$histLink' target='_blank'>$e</a></td><td><a href='$retrLink' target='_blank'>$id2</a></td>";
      $txt .= "<td><a href='$htCatLink' target='_blank'>$sysid</a></td><td>$c</td><td>$d</td><td>$title2</td></tr>\n";
    }
  }
  $data{'unneededcnt'} = $n;
  $txt .= "</table>$delim";
}
if (scalar keys %{$data{'noexport'}} && !$no{'noexport'})
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
if (scalar keys %{$data{'disallowed'}})
{
  $txt .= "<h4>Volumes not allowed to inherit</h4>\n";
  $txt .= "<table border='1'><tr><th>#</th><th>Source&nbsp;Volume<br/>(<span style='color:blue;'>historical/SysID</span>)</th>" .
          "<th>Volume Checked<br/>(<span style='color:blue;'>volume tracking</span>)</th><th>Sys ID<br/>(<span style='color:blue;'>catalog</span>)</th>" .
          "<th>Rights</th><th>New Rights</th><th>Why</th><th>Title</th></tr>\n";
  my $n = 0;
  my $th = GetTitleHash($data{'disallowed'}, \%data);
  foreach my $id (KeysSortedOnTitle($data{'disallowed'}, $th))
  {
    #my $record = $crms->GetMetadata($id);
    my $title2 = $th->{$id};
    $title2 =~ s/&/&amp;/g;
    my @lines = split "\n", $data{'disallowed'}->{$id};
    foreach my $line (@lines)
    {
      $n++;
      my ($id2,$sysid,$c,$d,$e,$note) = split "\t", $line;
      my $htCatLink = $crms->LinkToCatalog($sysid);
      my $retrLink = $crms->LinkToRetrieve($sysid,1);
      my $histLink = $crms->LinkToHistorical($sysid,1);
      $txt .= "<tr><td>$n</td><td><a href='$histLink' target='_blank'>$id</a></td><td><a href='$retrLink' target='_blank'>$id2</a></td>";
      $txt .= "<td><a href='$htCatLink' target='_blank'>$sysid</a></td><td>$c</td><td>$d</td><td>$note</td><td>$title2</td></tr>\n";
    }
  }
  $data{'disallowedcnt'} = $n;
  $txt .= "</table>$delim";
}
if (scalar keys %{$data{'inherit'}})
{
  my @cols = ('#','Source&nbsp;Volume<br/>(<span style="color:blue;">historical/SysID</span>)',
              'Volume&nbsp;Inheriting<br/>(<span style="color:blue;">volume tracking</span>)',
              'Sys ID<br/>(<span style="color:blue;">catalog</span>)','Rights','New Rights',
              'Access Change?');
  my $autotxt = ($candidates)?
    '<h4>Volumes where a duplicate w/CRMS determination exists (from June 2010 or later) - inheritance permitted -- Not Adding to Candidates - Status 9 Review awaiting approval</h4>'
    :
    '<h4>Volumes inheriting rights automatically</h4>';
  $autotxt .= '<table border="1"><tr><th>' . join('</th><th>', @cols) . "</th><th>Title</th><th>Tracking</th></tr>\n";
  my $pendtxt = '<h4>Volumes inheriting rights pending approval</h4><table border="1"><tr><th>' . join('</th><th>', @cols) .
                "</th><th>Prior<br/>CRMS<br/>Determ?</th><th>Prior<br/>Status 5<br/>Determ?</th><th>Title</th><th>Tracking</th></tr>\n";
  my $n = 0;
  my $npend = 0;
  my $th = GetTitleHash($data{'inherit'}, \%data);
  foreach my $id (KeysSortedOnTitle($data{'inherit'}, $th))
  {
    #my $record = $crms->GetMetadata($id);
    my $title2 = $th->{$id};
    $title2 =~ s/&/&amp;/g;
    my @lines = split "\n", $data{'inherit'}->{$id};
    foreach my $line (@lines)
    {
      my ($id2,$sysid,$attr2,$reason2,$attr,$reason,$gid) = split "\t", $line;
      print "$line\n" if $verbose > 1;
      my $catLink = "http://mirlyn.lib.umich.edu/Record/$sysid/Details#tabs";
      my $htCatLink = $crms->LinkToCatalog($sysid);
      my $histLink = $crms->LinkToHistorical($sysid,1);
      my $retrLink = $crms->LinkToRetrieve($sysid,1);
      my ($pd,$pdus,$icund) = (0,0,0);
      $pd = 1 if ($attr eq 'pd' || $attr2 eq 'pd');
      $pdus = 1 if ($attr eq 'pdus' || $attr2 eq 'pdus');
      $icund = 1 if ($attr eq 'ic' || $attr2 eq 'ic');
      $icund = 1 if ($attr eq 'und' || $attr2 eq 'und');
      my $incrms = ($reason2 eq 'bib' || $reason2 eq 'gfv')? '':'&nbsp;&nbsp;&nbsp;&#x2713;';
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
      my $change = (($pd == 1 && $icund == 1) || ($pd == 1 && $pdus == 1) || ($icund == 1 && $pdus == 1));
      #print "$change from $pd and $icund ($attr,$attr2)\n";
      my $ar = "$attr/$reason";
      $change = ($change)? '&nbsp;&nbsp;&nbsp;&#x2713;':'';
      my $tracking = $crms->GetTrackingInfo($id2);
      $$whichtxt .= "<tr><td>$whichn</td><td><a href='$histLink' target='_blank'>$id</a></td><td><a href='$retrLink' target='_blank'>$id2</a></td>";
      $$whichtxt .= "<td><a href='$htCatLink' target='_blank'>$sysid</a></td><td>$attr2/$reason2</td><td>$ar</td><td>$change</td>";
      $$whichtxt .= "<td>$incrms</td><td>$h5</td>" if ($incrms && !$candidates);
      $$whichtxt .= "<td>$title2</td><td>$tracking</td></tr>\n";
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
$header .= sprintf("Total # unique Sys IDs: %d$delim$delim", CountSystemIds(keys %{$data{'total'}}));
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
  $header .= sprintf("Unique Sys IDs checked, no duplicates with CRMS determination (from June 2010 or later): %d$delim$delim", CountSystemIds(keys %{$data{'noexport'}}));
  $header .= "<h4>Filtered from candidates temporarily:</h4>$delim";
  $header .= sprintf("Volumes checked, no duplicates with CRMS determination (from June 2010 or later), duplicate volume already in candidates: %d$delim", scalar keys %{$data{'already'}});
  $header .= sprintf("Unique Sys IDs checked, duplicate volume already in candidates: %d$delim$delim", CountSystemIds(keys %{$data{'already'}}));
}
else
{
  $header .= sprintf("Volumes checked, no inheritance needed: %d$delim", scalar keys %{$data{'unneeded'}});
  $header .= sprintf("Unique Sys IDs checked, no inheritance needed: %d$delim", CountSystemIds(keys %{$data{'unneeded'}}));
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
$header .= sprintf("Unique Sys IDs w/ volumes inheriting rights: %d$delim", CountSystemIds(keys %{$data{'inherit'}}));
$header .= sprintf("Volumes inheriting rights automatically: %d$delim", $data{'inheritcnt'});
if (!$candidates)
{
  $header .= sprintf("Volumes inheriting rights pending approval: %d$delim", $data{'pendinheritcnt'});
}
$txt = $head . $header . $delim . $txt;

if ($insert && scalar keys %{$data{'inherit'}})
{
  $txt .= '<h4>Now inserting inheritance data</h4>';
  foreach my $id (keys %{$data{'inherit'}})
  {
    my @lines = split "\n", $data{'inherit'}->{$id};
    foreach my $line (@lines)
    {
      my ($id2,$sysid,$attr2,$reason2,$attr,$reason,$gid) = split "\t", $line;
      $attr2 = $crms->TranslateAttr($attr2);
      $reason2 = $crms->TranslateReason($reason2);
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
my $hashref = $crms->GetSdrDb()->{mysql_dbd_stats};
$txt .= sprintf "SDR Database OK reconnects: %d, bad reconnects: %d<br/>\n", $hashref->{'auto_reconnects_ok'}, $hashref->{'auto_reconnects_failed'};

$txt .= "</body></html>\n\n";

if (@mails)
{
  use Mail::Sender;
  my $sender = new Mail::Sender { smtp => 'mail.umdl.umich.edu',
                                  from => $crms->GetSystemVar('adminEmail', ''),
                                  on_errors => 'undef' }
    or die "Error in mailing: $Mail::Sender::Error\n";
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
  my $start   = shift;
  my $end     = shift;
  my $singles = shift;

  my %data = ();
  my %seen = ();
  my $sql = "SELECT id,gid,attr,reason,time,src FROM exportdata WHERE (src!='inherited' AND time>'$start' AND time<='$end') " .
            "OR id IN (SELECT id FROM unavailable WHERE src='$src') ORDER BY time DESC";
  if ($singles && scalar @{$singles})
  {
    $sql = sprintf("SELECT id,gid,attr,reason,time,src FROM exportdata WHERE id in ('%s') ORDER BY time DESC", join "','", @{$singles});
  }
  print "$sql\n" if $verbose > 1;
  my $ref = $dbh->selectall_arrayref($sql);
  foreach my $row (@{$ref})
  {
    my $id = $row->[0];
    my $gid = $row->[1];
    my $attr = $row->[2];
    my $reason = $row->[3];
    my $time = $row->[4];
    my $src = $row->[5];
    print "InheritanceReport: checking $id ($gid, $attr/$reason, $time, $src)\n" if $verbose;
    if ($seen{$id})
    {
      print "Already saw $id; skipping\n" if $verbose;
      next;
    }
    my $sysid;
    my $record = $crms->GetMetadata($id, \$sysid);
    if (!$record)
    {
      print "Metadata unavailable for $id; skipping\n" if $verbose;
      $data{'unavailable'}->{$id} = 1;
      $crms->ClearErrors();
      next;
    }
    # When using date ranges, earlier export should not supersede later.
    my $latest = $crms->SimpleSqlGet("SELECT time FROM exportdata WHERE id='$id' ORDER BY time DESC LIMIT 1");
    if ($time lt $latest)
    {
      print "Later export ($latest) for $id ($time); skipping\n" if $verbose;
      next;
    }
    # THIS is the export we're going to inherit from.
    $seen{$id} = $id;
    $data{'total'}->{$id} = 1;
    $crms->DuplicateVolumesFromExport($id, $gid, $sysid, $attr, $reason,\%data, $record);
  }
  $crms->PrepareSubmitSql("DELETE FROM unavailable WHERE src='$src'") if $insert;
  return \%data;
}

sub CandidatesReport
{
  my $start   = shift;
  my $end     = shift;
  my $singles = shift;

  my %data = ();
  my $sql = "SELECT id,time FROM candidates WHERE (time>'$start' AND time<='$end') " .
            "OR id IN (SELECT id FROM unavailable WHERE src='$src')";
  $sql .= " UNION DISTINCT SELECT id,time FROM und WHERE (time>'$start' AND time<='$end') AND src!='no meta'" if $und;
  $sql .= ' ORDER BY time DESC';
  if ($singles && scalar @{$singles})
  {
    $sql = sprintf("SELECT id FROM candidates WHERE id in ('%s')", join "','", @{$singles});
    $sql .= sprintf(" UNION DISTINCT SELECT id FROM und WHERE id in ('%s')", join "','", @{$singles}) if $und;
    $sql .= ' ORDER BY id';
  }
  print "$sql\n" if $verbose > 1;
  my $ref = $dbh->selectall_arrayref($sql);
  my $of = scalar @{$ref};
  my $n = 1;
  foreach my $row (@{$ref})
  {
    my $id = $row->[0];
    print "CandidatesReport: checking $id ($n/$of)\n" if $verbose;
    my $sysid;
    my $record = $crms->GetMetadata($id, \$sysid);
    if (!$record)
    {
      print "Metadata unavailable for $id; skipping\n" if $verbose;
      $data{'unavailable'}->{$id} = 1;
      $crms->ClearErrors();
      next;
    }
    $data{'total'}->{$id} = 1;
    $crms->DuplicateVolumesFromCandidates($id, $sysid, \%data, $record);
    $n++;
  }
  $crms->PrepareSubmitSql("DELETE FROM unavailable WHERE src='$src'") if $insert;
  return \%data;
}

sub GetTitleHash
{
  my $ref  = shift;
  my $data = shift;
  
  my %h = ();
  $h{$_} = $data->{'titles'}->{$_} for keys %{$ref};
  return \%h;
}

sub KeysSortedOnTitle
{
  my $ref = shift;
  my $th  = shift;

  return sort {
    my $aa = lc $th->{$a};
    my $ba = lc $th->{$b};
    $crms->ClearErrors();
    #print "'$aa' cmp '$ba'?\n";
    $aa cmp $ba
    ||
    $a cmp $b;
  } keys %{$ref};
}

sub CountSystemIds
{
  my $self = shift;
  my @ids  = @_;

  my %sysids;
  foreach my $id (@ids)
  {
    $sysids{$crms->BarcodeToId($id)} = 1;
  }
  return scalar keys %sysids;
}

