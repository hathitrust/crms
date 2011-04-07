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
USAGE: $0 [-ahpv] [-m MAIL_ADDR [-m MAIL_ADDR2...]] [start_date [end_date]]

Reports on the volumes that can inherit from this morning's export,
or, if start_date is specified, exported after then and before end_date
if it is specified.

-a          Report on all exports, regardless of date range.
-h          Print this help message.
-m ADDR     Mail the report to ADDR. May be repeated for multiple addresses.
-p          Run in production.
END

my $all;
my $help;
my @mails;
my $production;
my $verbose;

Getopt::Long::Configure ('bundling');
die 'Terminating' unless GetOptions('a' => \$all,
           'h|?' => \$help,
           'm:s@' => \@mails,
           'p' => \$production,
           'v+' => \$verbose);
$DLPS_DEV = undef if $production;
die "$usage\n\n" if $help;

my $configFile = "$DLXSROOT/bin/c/crms/crms.cfg";
my $crms = CRMS->new(
    logFile      =>   "$DLXSROOT/prep/c/crms/gov_hist.txt",
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
my @iddups = ();
my $sql = "SELECT id,gid,attr,reason FROM exportdata WHERE time>'$start 00:00:00' AND time<='$end 23:59:59' ORDER BY id";
#$sql = "SELECT id,gid,attr,reason FROM exportdata WHERE id='loc.ark:/13960/t8z899j4p' OR id='loc.ark:/13960/t1td9vw1j' ORDER BY id";
print "$sql\n" if $verbose > 1;
my $ref = $dbh->selectall_arrayref($sql);
my $n = 0;
my $txt = '';
my $data = '';
my $dates = $start;
$dates .= " to $end" if $end ne $start;
my $title = "CRMS Inheritance, $dates";
$txt .= '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">' . "\n";
$txt .= '<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en"><head>' .
        "<meta http-equiv='Content-Type' content='text/html; charset=utf-8'/>\n" .
        "<title>$title</title></head><body>\n";
$delim = "<br/>\n";
my %inherit = ();
my %inheritsys = ();
my %unneeded = ();
my %unneededsys = ();
my %chron = ();
my %chronsys = ();
my %nodups = ();
my %nodupssys = ();
my %disallowed = ();
my %disallowedsys = ();
my %total = ();
my %totalsys = ();
my %inheriting = ();
foreach my $row (@{$ref})
{
  my $id = $row->[0];
  my $gid = $row->[1];
  my $attr = $row->[2];
  my $reason = $row->[3];
  my $sysid = $crms->BarcodeToId($id);
  #print "$sysid\n" if $totalsys{$sysid};
  $total{$id} = 1;
  $totalsys{$sysid} = 1;
  my $record = $crms->GetMetadata($sysid);
  DuplicateVolumes($id,$gid,$sysid,$attr,$reason);
}

if (scalar keys %nodups)
{
  $txt .= "<h4>Volumes which were single-copy</h4>\n";
  $txt .= "<table border='1'><tr><th>#</th><th>Volume Checked (<span style='color:blue;'>volume retrieval</span>)</th>" .
          "<th>Sys ID (<span style='color:blue;'>catalog</span>)</th></tr>\n";
  my $n = 0;
  foreach my $id (keys %nodups)
  {
    my @lines = split "\n", $nodups{$id};
    foreach my $line (@lines)
    {
      $n++;
      my ($a,$b) = split "\t", $line;
      my $htCatLink = "http://catalog.hathitrust.org/Record/$b";
      my $retrLink = "https://quod.lib.umich.edu/cgi/c/crms/crms?p=retrieve;query=$b";
      $txt .= "<tr><td>$n</td><td><a href='$retrLink' target='_blank'>$a</a></td><td><a href='$htCatLink' target='_blank'>$b</a></td></tr>\n";
    }
  }
  $txt .= "</table>$delim";
}
if (scalar keys %chron)
{
  $txt .= "<h4>Volumes skipped because of chron/enum</h4>\n";
  $txt .= "<table border='1'><tr><th>#</th><th>Volume Checked (<span style='color:blue;'>volume retrieval</span>)</th>" .
          "<th>Sys ID (<span style='color:blue;'>catalog</span>)</th>\n" .
          "<th>Source (<span style='color:blue;'>historical</span>)</th></tr>\n";
  my $n = 0;
  foreach my $id (keys %chron)
  {
    my @lines = split "\n", $chron{$id};
    foreach my $line (@lines)
    {
      $n++;
      my ($a,$b) = split "\t", $line;
      my $htCatLink = "http://catalog.hathitrust.org/Record/$b";
      my $retrLink = "https://quod.lib.umich.edu/cgi/c/crms/crms?p=retrieve;query=$b";
      my $histLink = "https://quod.lib.umich.edu/cgi/c/crms/crms?p=adminHistoricalReviews;search1=SysID;search1value=$b";
      $txt .= "<tr><td>$n</td><td><a href='$retrLink' target='_blank'>$a</a></td><td><a href='$htCatLink' target='_blank'>$b</a></td>\n";
      $txt .= "<td><a href='$histLink' target='_blank'>$id</a></td></tr>\n";
    }
  }
  $txt .= "</table>$delim";
}
if (scalar keys %unneeded)
{
  $txt .= "<h4>Volumes for which inheritance was unneeded</h4>\n";
  $txt .= "<table border='1'><tr><th>#</th><th>Volume Checked (<span style='color:blue;'>volume retrieval</span>)</th>" .
          "<th>Sys ID (<span style='color:blue;'>catalog</span>)</th><th>Rights</th><th>New Rights</th>" .
          "<th>Source (<span style='color:blue;'>historical</span>)</th></tr>\n";
  my $n = 0;
  foreach my $id (keys %unneeded)
  {
    my @lines = split "\n", $unneeded{$id};
    foreach my $line (@lines)
    {
      $n++;
      my ($a,$b,$c,$d,$e) = split "\t", $line;
      my $htCatLink = "http://catalog.hathitrust.org/Record/$b";
      my $retrLink = "https://quod.lib.umich.edu/cgi/c/crms/crms?p=retrieve;query=$b";
      my $histLink = "https://quod.lib.umich.edu/cgi/c/crms/crms?p=adminHistoricalReviews;search1=SysID;search1value=$b";
      $txt .= "<tr><td>$n</td><td><a href='$retrLink' target='_blank'>$a</a></td><td><a href='$htCatLink' target='_blank'>$b</a></td>";
      $txt .= "<td>$c</td><td>$d</td><td><a href='$histLink' target='_blank'>$e</a></td></tr>\n";
    }
  }
  $txt .= "</table>$delim";
}
if (scalar keys %disallowed)
{
  $txt .= "<h4>Volumes for which inheritance was not allowed</h4>\n";
  $txt .= "<table border='1'><tr><th>#</th><th>Volume Checked (<span style='color:blue;'>volume retrieval</span>)</th>" .
          "<th>Sys ID (<span style='color:blue;'>catalog</span>)</th><th>Rights</th><th>New Rights</th>" .
          "<th>Source (<span style='color:blue;'>historical</span>)</th><th>Why</th></tr>\n";
  my $n = 0;
  foreach my $id (keys %disallowed)
  {
    my @lines = split "\n", $disallowed{$id};
    foreach my $line (@lines)
    {
      $n++;
      my ($a,$b,$c,$d,$e,$note) = split "\t", $line;
      my $htCatLink = "http://catalog.hathitrust.org/Record/$b";
      my $retrLink = "https://quod.lib.umich.edu/cgi/c/crms/crms?p=retrieve;query=$b";
      my $histLink = "https://quod.lib.umich.edu/cgi/c/crms/crms?p=adminHistoricalReviews;search1=SysID;search1value=$b";
      $txt .= "<tr><td>$n</td><td><a href='$retrLink' target='_blank'>$a</a></td><td><a href='$htCatLink' target='_blank'>$b</a></td>";
      $txt .= "<td>$c</td><td>$d</td><td><a href='$histLink' target='_blank'>$id</a></td><td>$note</td></tr>\n";
    }
  }
  $txt .= "</table>$delim";
}

if (scalar keys %inherit)
{
  my @cols = ('#','Volume&nbsp;Inheriting<br/>(<span style="color:blue;">volume retrieval</span>)',
              'Sys ID<br/>(<span style="color:blue;">catalog</span>)','Rights','New Rights','In CRMS?',
              'Inheriting&nbsp;From<br/>(<span style="color:blue;">historical</span>)','Title');
  $txt .= '<h4>Volumes for which inheritance was needed</h4>';
  $txt .= '<table border="1"><tr><th>' . join('</th><th>', @cols) . "</th></tr>\n";
  foreach my $id (keys %inherit)
  {
    my @lines = split "\n", $inherit{$id};
    foreach my $line (@lines)
    {
      my ($id2,$sysid,$attr2,$reason2,$attr,$reason) = split "\t", $line;
      $n++;
      my $catLink = "http://mirlyn.lib.umich.edu/Record/$sysid/Details#tabs";
      my $htCatLink = "http://catalog.hathitrust.org/Record/$sysid";
      my $histLink = "https://quod.lib.umich.edu/cgi/c/crms/crms?p=adminHistoricalReviews;search1=SysID;search1value=$sysid";
      my $retrLink = "https://quod.lib.umich.edu/cgi/c/crms/crms?p=retrieve;query=$sysid";
      my $record = $crms->GetMetadata($id2);
      #my $author = $crms->GetRecordAuthor($id2, $record);
      #$author =~ s/&/&amp;/g;
      my $title = $crms->GetRecordTitle($id2, $record);
      $title =~ s/&/&amp;/g;
      my ($pd,$pdus,$icund) = (0,0,0);
      $pd = 1 if ($attr eq 'pd' || $attr2 eq 'pd');
      $pdus = 1 if ($attr eq 'pdus' || $attr2 eq 'pdus');
      $icund = 1 if ($attr eq 'ic' || $attr2 eq 'ic');
      $icund = 1 if ($attr eq 'und' || $attr2 eq 'und');
      my $incrms = ($attr2 eq 'ic' && $reason2 eq 'bib')? '':'&nbsp;&nbsp;&nbsp;&#x2713';
      my $change = ($incrms && (($pd == 1 && $icund == 1) || ($pd == 1 && $pdus == 1) || ($icund == 1 && $pdus == 1)));
      #print "$change from $pd and $icund ($attr,$attr2)\n";
      my $ar = "$attr/$reason";
      $ar = "<span style='color:red;'>$ar</span>" if $change;
      $txt .= "<tr><td>$n</td><td><a href='$retrLink' target='_blank'>$id2</a></td><td><a href='$htCatLink' target='_blank'>$sysid</a></td>";
      $txt .= "<td>$attr2/$reason2</td><td>$ar</td><td>$incrms</td><td><a href='$histLink' target='_blank'>$id</a></td><td>$title</td></tr>\n";
      $inheriting{$id2} = 1;
    }
  }
  $txt .= '</table>';
}

my $header = sprintf("Total # volumes w/ final determinations checked for inheritance from $dates: %d$delim", scalar keys %total);
$header .= sprintf("Total # unique Sys IDs: %d$delim$delim", scalar keys %totalsys);
$header .= sprintf("Volumes single copy: %d$delim$delim", scalar keys %nodups);
$header .= sprintf("Volumes w/ chron/enum: %d$delim$delim", scalar keys %chron);
$header .= sprintf("Volumes not allowed to inherit: %d$delim$delim", scalar keys %disallowed);
$header .= sprintf("Volumes checked, no inheritance needed: %d$delim", scalar keys %unneeded);
$header .= sprintf("Unique Sys IDs checked, no inheritance needed: %d$delim$delim", scalar keys %unneededsys);
$header .= sprintf("Volumes checked - inheritance permitted: %d$delim", scalar keys %inherit);
$header .= sprintf("Unique Sys IDs w/ volumes inheriting rights: %d$delim", scalar keys %inheritsys);
$header .= sprintf("Volumes inheriting rights: %d$delim", scalar keys %inheriting);
$txt = $header . $delim . $txt;
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

sub DuplicateVolumes
{
  my $id     = shift;
  my $gid    = shift;
  my $sysid  = shift;
  my $attr   = shift;
  my $reason = shift;

  my %okatrr = ('pd/ncn' => 1,
                'pd/ren' => 1,
                'pd/cdpp' => 1,
                'pdus/cdpp' => 1,
                'pd/crms' => 1,
                'pd/add' => 1,
                'ic/ren' => 1,
                'ic/cdpp' => 1,
                'ic/crms' => 1,
                'und/nfi' => 1,
                'und/crms' => 1,
                'ic/bib' => 1);
  my $rows = $crms->VolumeIDsQuery($sysid);
  if (1 == scalar @{$rows})
  {
    $nodups{$id} = '' unless $nodups{$id};
    $nodups{$id} .= "$id\t$sysid\n";
    $nodupssys{$sysid} = 1;
  }
  else
  {
    # Get most recent CRMS determination for any volume on this record
    # and see if it's more recent that what we're exporting.
    my $candidate = $id;
    my $candidateTime = $crms->SimpleSqlGet("SELECT MAX(time) FROM historicalreviews WHERE id='$id'");
    my $sawchron = 0;
    foreach my $line (@{$rows})
    {
      my ($id2,$chron2,$rights2) = split '__', $line;
      $sawchron = 1 if $chron2;
      next if $id eq $id2;
      my $time = $crms->SimpleSqlGet("SELECT MAX(time) FROM historicalreviews WHERE id='$id2'");
      if ($time && $time gt $candidateTime)
      {
        $candidate = $id2;
        $candidateTime = $time;
        #print "Candidate now $candidate, time $candidateTime (src id $id)\n";
      }
    }
    foreach my $line (@{$rows})
    {
      my ($id2,$chron2,$rights2) = split '__', $line;
      my ($attr2,$reason2,$src2,$usr2,$time2,$note2) = @{$crms->RightsQuery($id2,1)->[0]};
      if ($sawchron)
      {
        $chron{$id} = '' unless $chron{$id};
        $chron{$id} .= "$id2\t$sysid\n";
        $chronsys{$sysid} = 1;
        delete $unneeded{$id};
        delete $unneededsys{$sysid};
        delete $inherit{$id};
        delete $inheritsys{$sysid};
        delete $disallowed{$id};
        delete $disallowedsys{$sysid};
        return;
      }
      elsif ($candidate ne $id && $candidate ne $id2)
      {
        $disallowed{$id} = '' unless $disallowed{$id};
        $disallowed{$id} .= "$id2\t$sysid\t$attr2/$reason2\t$attr/$reason\t$id\t$candidate has newer review ($candidateTime)\n";
        $disallowedsys{$sysid} = 1;
        delete $unneeded{$id};
        delete $unneededsys{$sysid};
        delete $inherit{$id};
        delete $inheritsys{$sysid};
        #return;
      }
      elsif ($id2 ne $id && !$chron{$id})
      {
        if ($okatrr{"$attr2/$reason2"})
        {
          if ($attr2 eq $attr && $reason2 ne 'bib')
          {
            $unneeded{$id} = '' unless $unneeded{$id};
            $unneeded{$id} .= "$id2\t$sysid\t$attr2/$reason2\t$attr/$reason\t$id\n";
            $unneededsys{$sysid} = 1;
          }
          else
          {
            $inherit{$id} = '' unless $inherit{$id};
            $inherit{$id} .= "$id2\t$sysid\t$attr2\t$reason2\t$attr\t$reason\n";
            $inheritsys{$sysid} = 1;
          }
        }
        else
        {
          $disallowed{$id} = '' unless $disallowed{$id};
          $disallowed{$id} .= "$id2\t$sysid\t$attr2/$reason2\t$attr/$reason\t$id\tRights\n";
          $disallowedsys{$sysid} = 1;
        }
      }
    }
  }
}

