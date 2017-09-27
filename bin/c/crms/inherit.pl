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

my $usage = <<END;
USAGE: $0 [-acCdhnpquv] [-s VOL_ID [-s VOL_ID2...]]
          [-m MAIL_ADDR [-m MAIL_ADDR2...]] [-P PROJ1 [-P PROJ2...]]
          [-t TBL [-t TBL...]] [-x SYS] [start_date[ time] [end_date[ time]]]

Reports on the volumes that can inherit from this morning's export,
or, if start_date is specified, exported after then and before end_date
if it is specified.

-a         Report on all exports, regardless of date range.
-c         Report on recent addition to candidates.
-C         Use 'cleanup' as the source.
-d         Use volumes filtered as duplicates, similar to the -c flag.
-h         Print this help message.
-m ADDR    Mail the report to ADDR. May be repeated for multiple addresses.
-n         No-op; do not modify the database.
-p         Run in production.
-P PROJ    For candidates inheritance, only check volumes in the specified project.
-q         Do not emit report (ignored if -m is used).
-s VOL_ID  Report only for HT volume VOL_ID. May be repeated for multiple volumes.
-t TBL     Suppress table TBL (which is often huge in candidates cleanup),
           where TBL is one of {chron,nodups,noexport,unneeded}.
           May be repeated for multiple tables.
-u         Also report on recent additions to the und table
           (ignored if -c is not used).
-v         Emit debugging information.
-x SYS     Set SYS as the system to execute.
END

my $all;
my $candidates;
my $cleanup;
my $duplicate;
my $help;
my @mails;
my @no;
my $noop;
my $production;
my @projs;
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
           'd'    => \$duplicate,
           'h|?'  => \$help,
           'm:s@' => \@mails,
           'n'    => \$noop,
           'p'    => \$production,
           'P:s@' => \@projs,
           'q'    => \$quiet,
           's:s@' => \@singles,
           't:s@' => \@no,
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
my $src = ($candidates)? 'candidates':'export';
$src = 'cleanup' if $cleanup;
print "Verbosity $verbose\n" if $verbose;
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
my $subj = $crms->SubjectLine(sprintf "%s %sInheritance, $dates%s",
                              ($candidates)? 'Candidates':'Export',
                              ($cleanup)? 'Cleanup ':'',
                              (scalar @projs)? (' Project: {'. join(',', @projs). '}'):'');
$start .= ' 00:00:00' unless $start =~ m/\d\d:\d\d:\d\d$/;
$end .= ' 23:59:59' unless $end =~ m/\d\d:\d\d:\d\d$/;
my %data = %{($candidates || $duplicate)?
             CandidatesReport($start, $end, \@singles):
             InheritanceReport($start, $end, \@singles)};
$crms->set('messages', $crms->StartHTML());

if (scalar keys %{$data{'inherit'}})
{
  my @cols = ('#','Source&nbsp;Volume (chron)<br/>(<span style="color:blue;">historical/SysID</span>)',
              'Volume&nbsp;Inheriting (chron)<br/>(<span style="color:blue;">volume tracking</span>)',
              'Sys ID<br/>(<span style="color:blue;">catalog</span>)','Rights','New Rights',
              'Access<br/>Change?');
  my $autotxt = '<h4>Volumes inheriting rights automatically</h4>';
  $autotxt .= '<table border="1"><tr><th>' . join('</th><th>', @cols) . "</th><th>Title</th><th>Tracking</th></tr>\n";
  my $pendtxt = '<h4>Volumes inheriting rights pending approval</h4><table border="1"><tr><th>' . join('</th><th>', @cols) .
                "</th><th>Prior<br/>Status 5<br/>Determ?</th><th>Title</th><th>Tracking</th></tr>\n";
  my $n = 0;
  my $npend = 0;
  my $th = GetTitleHash($data{'inherit'}, \%data);
  foreach my $id (KeysSortedOnTitle($data{'inherit'}, $th))
  {
    #my $record = $crms->GetMetadata($id);
    my $title = $th->{$id};
    $title =~ s/&/&amp;/g;
    my @lines = split "\n", $data{'inherit'}->{$id};
    foreach my $line (@lines)
    {
      # id2 is the inheriting volume
      my ($id2,$sysid,$attr2,$reason2,$attr,$reason,$gid,$chron,$chron2) = split "\t", $line;
      $chron = "($chron)" if length $chron;
      $chron2 = "($chron2)" if length $chron2;
      print "$line\n" if $verbose > 1;
      my $catLink = $crms->LinkToMirlynDetails($id);
      my $htCatLink = $crms->LinkToCatalog($sysid);
      my $histLink = $crms->LinkToHistorical($sysid,1);
      my $retrLink = $crms->LinkToRetrieve($sysid,1);
      my $auto = $crms->CanAutoSubmitInheritance($id2, $gid);
      my $status = $crms->SimpleSqlGet('SELECT status FROM exportdata WHERE gid=?', $gid);
      my $h5 = '';
      my $whichtxt = \$autotxt;
      my $whichn;
      if (!$auto)
      {
        $sql = "SELECT COUNT(*) FROM exportdata WHERE id='$id2' AND status=5";
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
      my $change = $crms->AccessChange($attr, $attr2);
      $change = ($change)? '&nbsp;&nbsp;&nbsp;&#x2713;':'';
      my $tracking = $crms->GetTrackingInfo($id2);
      $$whichtxt .= "<tr><td>$whichn</td><td><a href='$histLink' target='_blank'>$id</a> $chron</td>";
      $$whichtxt .= "<td><a href='$retrLink' target='_blank'>$id2</a> $chron2</td>";
      $$whichtxt .= "<td><a href='$htCatLink' target='_blank'>$sysid</a></td>";
      $$whichtxt .= "<td>$attr2/$reason2</td><td>$attr/$reason</td><td>$change</td>";
      $$whichtxt .= "<td>$h5</td>" unless $auto;
      $$whichtxt .= "<td>$title</td><td>$tracking</td></tr>\n";
    }
  }
  $data{'inheritcnt'} = $n;
  $data{'pendinheritcnt'} = $npend;
  $autotxt .= '</table>';
  $pendtxt .= '</table>';
  $crms->ReportMsg($autotxt) if $n;
  $crms->ReportMsg($pendtxt) if $npend;
}

if (scalar keys %{$data{'chron'}} && !$no{'chron'})
{
  my $table = sprintf("<h4>Volumes skipped because of nonmatching enumchron%s</h4>\n", ($candidates)? ' - No Inheritance':'');
  $table .= '<table border="1"><tr><th>#</th><th>Source&nbsp;Volume (chron)<br/>(<span style="color:blue;">historical/SysID</span>)</th>'.
            '<th>Volume Checked (chron)<br/>(<span style="color:blue;">volume tracking</span>)</th>'.
            '<th>Sys ID<br/>(<span style="color:blue;">catalog</span>)</th>'.
            '<th>Title</th></tr>';
  my $n = 0;
  my $th = GetTitleHash($data{'chron'}, \%data);
  foreach my $id (KeysSortedOnTitle($data{'chron'}), $th)
  {
    #my $record = $crms->GetMetadata($id);
    my $title = $th->{$id};
    $title =~ s/&/&amp;/g;
    my @lines = split "\n", $data{'chron'}->{$id};
    foreach my $line (@lines)
    {
      $n++;
      my ($id2,$sysid,$chron,$chron2) = split "\t", $line;
      $chron = " ($chron)" if length $chron;
      $chron2 = " ($chron2)" if length $chron2;
      my $htCatLink = $crms->LinkToCatalog($sysid);
      my $retrLink = $crms->LinkToRetrieve($sysid,1);
      my $histLink = $crms->LinkToHistorical($sysid,1);
      $table .= "<tr><td>$n</td><td><a href='$histLink' target='_blank'>$id</a>$chron</td>".
                "<td><a href='$retrLink' target='_blank'>$id2</a>$chron2</td>";
      $table .= "<td><a href='$htCatLink' target='_blank'>$sysid</a></td><td>$title</td></tr>";
    }
  }
  $crms->ReportMsg($table. '</table>');
}

if (scalar keys %{$data{'disallowed'}})
{
  my $table = "<h4>Volumes not allowed to inherit</h4>\n";
  $table .= '<table border="1"><tr><th>#</th><th>Source&nbsp;Volume<br/>(<span style="color:blue;">historical/SysID</span>)</th>'.
            '<th>Volume Checked<br/>(<span style="color:blue;">volume tracking</span>)</th><th>Sys ID<br/>(<span style="color:blue;">catalog</span>)</th>'.
            "<th>Rights</th><th>New Rights</th><th>Why</th><th>Title</th></tr>\n";
  my $n = 0;
  my $th = GetTitleHash($data{'disallowed'}, \%data);
  foreach my $id (KeysSortedOnTitle($data{'disallowed'}, $th))
  {
    #my $record = $crms->GetMetadata($id);
    my $title = $th->{$id};
    $title =~ s/&/&amp;/g;
    my @lines = split "\n", $data{'disallowed'}->{$id};
    foreach my $line (@lines)
    {
      $n++;
      my ($id2,$sysid,$c,$d,$e,$note) = split "\t", $line;
      my $htCatLink = $crms->LinkToCatalog($sysid);
      my $retrLink = $crms->LinkToRetrieve($sysid,1);
      my $histLink = $crms->LinkToHistorical($sysid,1);
      $table .= "<tr><td>$n</td><td><a href='$histLink' target='_blank'>$id</a></td><td><a href='$retrLink' target='_blank'>$id2</a></td>";
      $table .= "<td><a href='$htCatLink' target='_blank'>$sysid</a></td><td>$c</td><td>$d</td><td>$note</td><td>$title</td></tr>\n";
    }
  }
  $data{'disallowedcnt'} = $n;
  $crms->ReportMsg($table. '</table>');
}

if (scalar keys %{$data{'unavailable'}})
{
  my $table = "<h4>Volumes which had no metadata available</h4>\n";
  $table .= "<table border='1'><tr><th>#</th><th>Volume Checked<br/>(<span style='color:blue;'>volume tracking</span>)</th></tr>\n";
  my $n = 0;
  foreach my $id (keys %{$data{'unavailable'}})
  {
    $n++;
    my $retrLink = $crms->LinkToRetrieve($id,1);
    $table .= "<tr><td>$n</td><td><a href='$retrLink' target='_blank'>$id</a></td></tr>\n";
  }
  $crms->ReportMsg($table. '</table>');
}

if (scalar keys %{$data{'nodups'}} && !$no{'nodups'})
{
  my $table = sprintf("<h4>Volumes single copy/no duplicates%s</h4>\n", ($candidates)? ' - No Inheritance/Adding to Candidates':'');
  $table .= '<table border="1"><tr><th>#</th><th>Volume Checked<br/>(<span style="color:blue;">volume tracking</span>)</th>'.
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
      $table .= "<tr><td>$n</td><td><a href='$retrLink' target='_blank'>$id</a></td><td><a href='$htCatLink' target='_blank'>$sysid</a></td></tr>\n";
    }
  }
  $crms->ReportMsg($table. '</table>');
}

if (scalar keys %{$data{'unneeded'}} && !$no{'unneeded'})
{
  my $table = sprintf("<h4>Volumes not needing inheritance</h4>\n", ($candidates)? ' - No Inheritance/Adding to Candidates':'');
  $table .= '<table border="1"><tr><th>#</th><th>Source&nbsp;Volume<br/>(<span style="color:blue;">historical/SysID</span>)</th>'.
            '<th>Volume Checked<br/>(<span style="color:blue;">volume tracking</span>)</th>'.
            '<th>Sys ID<br/>(<span style="color:blue;">catalog</span>)</th><th>Rights</th><th>New Rights</th>'.
            "<th>Title</th></tr>\n";
  my $n = 0;
  my $th = GetTitleHash($data{'unneeded'}, \%data);
  foreach my $id (KeysSortedOnTitle($data{'unneeded'}, $th))
  {
    #my $record = $crms->GetMetadata($id);
    my $title = $th->{$id};
    $title =~ s/&/&amp;/g;
    my @lines = split "\n", $data{'unneeded'}->{$id};
    foreach my $line (@lines)
    {
      $n++;
      my ($id2,$sysid,$c,$d,$e) = split "\t", $line;
      my $htCatLink = $crms->LinkToCatalog($sysid);
      my $retrLink = $crms->LinkToRetrieve($id2,1);
      my $histLink = $crms->LinkToHistorical($sysid,1);
      $table .= "<tr><td>$n</td><td><a href='$histLink' target='_blank'>$e</a></td><td><a href='$retrLink' target='_blank'>$id2</a></td>";
      $table .= "<td><a href='$htCatLink' target='_blank'>$sysid</a></td><td>$c</td><td>$d</td><td>$title</td></tr>\n";
    }
  }
  $data{'unneededcnt'} = $n;
  $crms->ReportMsg($table. '</table>');
}
if (scalar keys %{$data{'noexport'}} && !$no{'noexport'})
{
  my $table = "<h4>Volumes checked, no duplicates with CRMS determination (from June 2010 or later) in CRMS exports table - No Inheritance/Adding to Candidates</h4>\n";
  $table .= '<table border="1"><tr><th>#</th><th>Volume Checked<br/>(<span style="color:blue;">volume tracking</span>)</th>'.
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
      $table .= "<tr><td>$n</td><td><a href='$retrLink' target='_blank'>$id</a></td><td><a href='$htCatLink' target='_blank'>$sysid</a></td></tr>\n";
    }
  }
  $crms->ReportMsg($table. '</table>');
}


$crms->ReportMsg("Total # volumes checked for inheritance from $dates: ". scalar keys %{$data{'total'}});
$crms->ReportMsg(sprintf("Volumes for which metadata was unavailable: %d<br/>\n", scalar keys %{$data{'unavailable'}}));
if ($candidates)
{
  $crms->ReportMsg('<h4>No inheritance - Adding to candidates:</h4>');
}
$crms->ReportMsg(sprintf("Volumes single copy/no duplicates: %d<br/>\n", scalar keys %{$data{'nodups'}}));
$crms->ReportMsg(sprintf("Volumes w/ chron/enum: %d<br/>\n", scalar keys %{$data{'chron'}}));
if ($candidates)
{
  $crms->ReportMsg(sprintf("Volumes checked, no duplicates with CRMS determination (from June 2010 or later) in CRMS exports table: %d", scalar keys %{$data{'noexport'}}));
  $crms->ReportMsg(sprintf("Unique Sys IDs checked, no duplicates with CRMS determination (from June 2010 or later): %d", CountSystemIds('noexport', keys %{$data{'noexport'}})));
  $crms->ReportMsg('<h4>Filtered from candidates temporarily:</h4>');
  $crms->ReportMsg(sprintf("Volumes checked, no duplicates with CRMS determination (from June 2010 or later), duplicate volume already in candidates: %d", scalar keys %{$data{'already'}}));
  $crms->ReportMsg(sprintf("Unique Sys IDs checked, duplicate volume already in candidates: %d<br/>\n", CountSystemIds('already', keys %{$data{'already'}})));
}
else
{
  $crms->ReportMsg(sprintf("Volumes checked, no inheritance needed: %d", scalar keys %{$data{'unneeded'}}));
  $crms->ReportMsg('Unique Sys IDs checked, no inheritance needed: '. CountSystemIds('unneeded', keys %{$data{'unneeded'}}));
  $crms->ReportMsg(sprintf("Volumes not needing inheritance: %d", $data{'unneededcnt'}));
}
$crms->ReportMsg('Volumes checked, inheritance not permitted: '. scalar keys %{$data{'disallowed'}});
$crms->ReportMsg(sprintf("Volumes not allowed to inherit: %d<br/>\n", $data{'disallowedcnt'}));
if ($candidates)
{
  $crms->ReportMsg('<h4>Inheritance Permitted - Not Adding to Candidates - Status 9 Review awaiting approval:</h4>');
  $crms->ReportMsg('Volumes checked - duplicate w/CRMS determination exists (from June 2010 or later) - inheritance permitted: '. scalar keys %{$data{'inherit'}});
}
else
{
  $crms->ReportMsg('Volumes checked - inheritance permitted: '. scalar keys %{$data{'inherit'}});
}
$crms->ReportMsg(sprintf('Unique Sys IDs w/ volumes inheriting rights: %d', CountSystemIds('inherit', keys %{$data{'inherit'}})));
$crms->ReportMsg('Volumes inheriting rights automatically: '. $data{'inheritcnt'});
if (!$candidates)
{
  $crms->ReportMsg('Volumes inheriting rights pending approval: '. $data{'pendinheritcnt'});
}

if (!$noop && scalar keys %{$data{'inherit'}})
{
  $crms->ReportMsg('<h4>Now inserting inheritance data</h4>');
  foreach my $id (keys %{$data{'inherit'}})
  {
    my @lines = split "\n", $data{'inherit'}->{$id};
    foreach my $line (@lines)
    {
      my ($id2,$sysid,$attr2,$reason2,$attr,$reason,$gid) = split "\t", $line;
      $attr2 = $crms->TranslateAttr($attr2);
      $reason2 = $crms->TranslateReason($reason2);
      my $sql = "REPLACE INTO inherit (id,attr,reason,gid,src) VALUES (?,?,?,?,?)";
      #print "$sql\n";
      $crms->PrepareSubmitSql($sql, $id2, $attr2, $reason2, $gid, $src);
      $crms->Filter($id2, 'duplicate') if $crms->IsVolumeInCandidates($id2);
    }
  }
  if ($candidates)
  {
    $crms->ReportMsg('<h4>Now filtering duplicates in candidates</h4>');
    foreach my $id (keys %{$data{'already'}})
    {
      my @lines = split "\n", $data{'already'}->{$id};
      foreach my $line (@lines)
      {
        my ($id2,$sysid) = split "\t", $line;
        FilterCandidates($id2, $id);
      }
    }
  }
}

UnfilterVolumes('chron') unless $noop;
UnfilterVolumes('unneeded') unless $noop;
UnfilterVolumes('disallowed') unless $noop;

for (@{$crms->GetErrors()})
{
  s/\n/<br\/>/g;
  $crms->ReportMsg("<i>Warning: $_</i>");
}
my $hashref = $crms->GetSdrDb()->{mysql_dbd_stats};
$crms->ReportMsg(sprintf "SDR Database OK reconnects: %d, bad reconnects: %d<br/>\n",
                 $hashref->{'auto_reconnects_ok'},
                 $hashref->{'auto_reconnects_failed'});
$crms->ReportMsg("</body></html>\n");

@mails = map { ($_ =~ m/@/)? $_:($_ . '@umich.edu'); } @mails;
my $to = join(',', @mails);
printf "Mailing to: $to\n" if $verbose;
my $txt = $crms->get('messages');
if (scalar @mails)
{
  use Mail::Sendmail;
  use Encode;
  my $bytes = encode('utf8', $txt);
  my %mail = ('from'         => $crms->GetSystemVar('adminEmail'),
              'to'           => $to,
              'subject'      => $subj,
              'content-type' => 'text/html; charset="UTF-8"',
              'body'         => $bytes
              );
  sendmail(%mail) || $crms->SetError("Error: $Mail::Sendmail::error\n");
}
else
{
  print "$txt\n" unless $quiet;
}

# For 'disallowed' and 'unneeded', unfilter exactly one volume to act as the new candidate.
# For 'chron', unfilter and enqueue all of them.
sub UnfilterVolumes
{
  my $reason = shift;

  foreach my $id (keys %{$data{$reason}})
  {
    $txt .= "<h5>Unfiltering $id</h5>\n";
    my @lines = split "\n", $data{$reason}->{$id};
    foreach my $line (@lines)
    {
      my @fields = split "\t", $line;
      my $id2 = shift @fields;
      next unless $crms->IsFiltered($id2);
      $txt .= "&nbsp;&nbsp;$id2";
      $crms->Unfilter($id2);
      $crms->AddItemToQueue($id2) if $crms->IsVolumeInCandidates($id2);
      if ($reason eq 'disallowed' or $reason eq 'unneeded')
      {
        $txt .= " (only one)<br/>\n";
        last;
      }
      else
      {
        $txt .= "<br/>\n";
      }
    }
  }
}

sub InheritanceReport
{
  my $start   = shift;
  my $end     = shift;
  my $singles = shift;

  my %data = ();
  my %seen = ();
  my $ref;
  my $sql = 'SELECT id,gid,attr,reason,time,src FROM exportdata WHERE ';
  my @params = ();
  if ($singles && scalar @{$singles})
  {
    $sql .= sprintf 'id IN %s ORDER BY time DESC', $crms->WildcardList(scalar @{$singles});
    @params = @{$singles};
  }
  else
  {
    $sql .= ' src!="inherited" AND time>? AND time<=?'.
            ' AND NOT EXISTS (SELECT * FROM exportdata e2 WHERE e2.id=id AND e2.time>time)'.
            ' ORDER BY time DESC';
    @params = ($start, $end);
  }
  $ref = $crms->SelectAll($sql, @params);
  use Utilities;
  printf "%s\n", Utilities::StringifySql($sql, @params) if $verbose > 1;
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
    my $record = $crms->GetMetadata($id);
    if (!$record)
    {
      print "Metadata unavailable for $id; skipping\n" if $verbose;
      $data{'unavailable'}->{$id} = 1;
      $crms->ClearErrors();
      next;
    }
    # THIS is the export we're going to inherit from.
    $seen{$id} = $id;
    $data{'total'}->{$id} = 1;
    $crms->DuplicateVolumesFromExport($id, $gid, $record->sysid, $attr, $reason,\%data, $record);
  }
  return \%data;
}

sub CandidatesReport
{
  my $start   = shift;
  my $end     = shift;
  my $singles = shift;

  my %data = ();
  my $sql = "SELECT id,time FROM candidates WHERE (time>'$start' AND time<='$end')";
  if (scalar @projs)
  {
    $sql .= sprintf " AND project IN ('%s')", join "','", @projs;
  }
  $sql = "SELECT id,time FROM und WHERE (time>'$start' AND time<='$end') AND src!='no meta'" if $und;
  $sql = 'SELECT id,time FROM und WHERE src="duplicate"' if $duplicate;
  $sql .= ' ORDER BY time DESC';
  if ($singles && scalar @{$singles})
  {
    $sql = sprintf("SELECT id FROM candidates WHERE id in ('%s')", join "','", @{$singles});
    $sql .= sprintf(" UNION DISTINCT SELECT id FROM und WHERE id in ('%s')", join "','", @{$singles}) if $und;
    $sql .= ' ORDER BY id';
  }
  #$sql .= ' LIMIT 5000';
  $crms->ReportMsg("<code>$sql</code>") if $verbose > 1;
  my $ref = $crms->SelectAll($sql);
  my $of = scalar @{$ref};
  my $n = 1;
  foreach my $row (@{$ref})
  {
    my $id = $row->[0];
    print "CandidatesReport: checking $id ($n/$of)\n" if $verbose > 1 and $n % 100 == 0;
    my $record = $crms->GetMetadata($id);
    if (!$record)
    {
      print "Metadata unavailable for $id; skipping\n" if $verbose;
      $data{'unavailable'}->{$id} = 1;
      $crms->ClearErrors();
      next;
    }
    $data{'total'}->{$id} = 1;
    $crms->DuplicateVolumesFromCandidates($id, $record->sysid, \%data, $record);
    $n++;
  }
  return \%data;
}

# Prevent multiple volumes from getting in the queue.
# If possible (if not already in queue) filter oldVol as src=duplicate
# Otherwise filter (if possible) newVol.
sub FilterCandidates
{
  my $oldVol = shift;
  my $newVol = shift;

  if ($crms->SimpleSqlGet('SELECT COUNT(*) FROM queue WHERE id=?', $oldVol) == 0)
  {
    $crms->Filter($oldVol, 'duplicate');
  }
  elsif ($crms->SimpleSqlGet('SELECT COUNT(*) FROM queue WHERE id=?', $newVol) == 0)
  {
    $crms->Filter($newVol, 'duplicate');
  }
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
  my $report = shift;
  my @ids    = @_;

  my %sysids;
  foreach my $id (@ids)
  {
    my $record = $crms->GetMetadata($id);
    my $sysid = $record->sysid;
    print "$id: $sysid\n" if $verbose > 1;
    $sysids{$sysid} = 1;
  }
  printf "Counted %d sys ids for $report\n", scalar keys %sysids if $verbose > 1;
  return scalar keys %sysids;
}

