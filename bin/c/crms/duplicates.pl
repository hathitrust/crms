#!/l/local/bin/perl

# This script can be run from crontab; it 

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
use Getopt::Std;

my $usage = <<END;
USAGE: $0 [-aehlnpstvw] [-S SUMMARY_PATH] [-t REPORT_TYPE] [-r TYPE] [-i ID] [start_date [end_date]]

Reports on CRMS determinations for volumes that have duplicates,
multiple volumes, or conflicting determinations.

-a       Use only attr mismatches to detect a conflict.
-e       Report only on records with chron/enum information.
-h       Print this help message.
-i ID    Report only for volume ID (start and end dates are ignored).
-l       Generate hyperlinks in the TSV file for Excel.
-n       Do not submit SQL for duplicates when -s flag is set.
-p       Run in production.
-r TYPE  Report on situations of type TYPE in {duplicate,conflict,crms_conflict,all}:
           duplicate:     >0 matching CRMS determinations, >0 ic/bib (default)
           conflict:      conflicting CRMS determinations, >0 ic/bib
           crms_conflict: conflicting CRMS determinations, no ic/bib
           all:           all of the above
-s       For true duplicates, submit a review for unreviewed duplicate volumes.
-S PATH  Emit a TSV summary (for duplicates) with ID, rights, reason.
-t TYPE  Print a report of TYPE where TYPE={html,none,tsv}.
-v       Be verbose.
END

my %opts;
getopts('aehi:lnpr:sS:t:v', \%opts);

my $attrOnly   = $opts{'a'};
my $enum       = $opts{'e'};
my $help       = $opts{'h'};
my $id         = $opts{'i'};
my $link       = $opts{'l'};
my $noop       = $opts{'n'};
my $production = $opts{'p'};
my $type       = $opts{'r'};
my $submit     = $opts{'s'};
my $summary    = $opts{'S'};
my $report     = $opts{'t'} || 'none';
my $verbose    = $opts{'v'};

my %reports = ('html'=>1,'none'=>1,'tsv'=>1);
die "Bad value '$report' for -t flag" unless defined $reports{$report};
my $summfh;
if ($summary)
{
  open $summfh, $summary or die "failed to open summary file $summary: $@ \n";
}
$type = 'duplicate' unless $type;
my $start = $ARGV[0] or '';
my $end   = $ARGV[1] or '';
die "Start date format should be YYYY-MM-DD\n" if $start and $start !~ m/\d\d\d\d-\d\d-\d\d/;
die "Start date format should be YYYY-MM-DD\n" if $end and $end !~ m/\d\d\d\d-\d\d-\d\d/;
if ($start > $end)
{
  my $tmp = $start;
  $start = $end;
  $end = $tmp;
}
$start .= ' 00:00:00' if $start;
$end   .= ' 23:59:59' if $end;

die "$usage\n\n" if $help;

my $crms = CRMS->new(
    logFile      =>   "$DLXSROOT/prep/c/crms/duplicates_hist.txt",
    configFile   =>   "$DLXSROOT/bin/c/crms/crms.cfg",
    verbose      =>   $verbose,
    root         =>   $DLXSROOT,
    dev          =>   !$production
);


sub HoldingsQueryForRecord
{
  my $id     = shift;
  my $record = shift;
  
  my @ids = ();
  eval {
    #print "Mirlyn ID: $rid\n";
    #printf "%s\n\n", $record->toString();
    my $nodes = $record->findnodes("//*[local-name()='datafield' and \@tag='974']");
    foreach my $node ($nodes->get_nodelist())
    {
      my $id = $node->findvalue("./*[local-name()='subfield' and \@code='u']");
      my $chron = $node->findvalue("./*[local-name()='subfield' and \@code='z']");
      my $rights = $node->findvalue("./*[local-name()='subfield' and \@code='r']");
      #print "$rights,$id,$chron<br/>\n";
      push @ids, $id . '__' . $chron . '__' . (('pd' eq substr($rights, 0, 2))? 'Full View':'Search Only');
    }
    $nodes = $record->findnodes("//*[local-name()='datafield' and \@tag='MDP']");
    foreach my $node ($nodes->get_nodelist())
    {
      my $id = $node->findvalue("./*[local-name()='subfield' and \@code='u']");
      my $chron = $node->findvalue("./*[local-name()='subfield' and \@code='z']");
      my $rights = $node->findvalue("./*[local-name()='subfield' and \@code='r']");
      #print "$rights,$id,$chron<br/>\n";
      push @ids, $id . '__' . $chron . '__' . (('pd' eq substr($rights, 0, 2))? 'Full View':'Search Only');
    }
  };
  $crms->SetError("Holdings query for $id failed: $@") if $@;
  @ids = sort @ids;
  return \@ids;
}

sub Date1Field
{
  my $id     = shift;
  my $record = shift;

  if ( ! $record ) { $crms->SetError("no record in Date1Field: $id"); return; }
  my $xpath  = q{//*[local-name()='controlfield' and @tag='008']};
  my $leader = $record->findvalue( $xpath );
  my $d = substr $leader, 7, 4;
  #print "Date1: '$d'\n";
  return $d;
}

sub Date2Field
{
  my $id     = shift;
  my $record = shift;

  if ( ! $record ) { $crms->SetError("no record in Date2Field: $id"); return; }
  my $xpath  = q{//*[local-name()='controlfield' and @tag='008']};
  my $leader = $record->findvalue( $xpath );
  my $d = substr $leader, 11, 4;
  #print "Date2: '$d'\n";
  return $d;
}

if ($report eq 'tsv')
{
  print "System ID\tVolume ID\tTitle\tAttr\tReason\tChron/Enum\tDate 1\tDate 2\tTime of Determination\tSituation\n";
}
elsif ($report eq 'html')
{
  print "<!DOCTYPE html PUBLIC '-//W3C//DTD XHTML 1.0 Transitional//EN' 'http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd'>\n" .
        '<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en"><head>' .
        "<meta http-equiv='Content-Type' content='text/html; charset=utf-8'/>\n" .
        "<title>Duplicate volumes with differing rights</title></head><body>\n" .
        "<table border='1'>\n" .
        '<tr><th>System&nbsp;ID</th><th>Volume&nbsp;ID</th><th>Title</th><th>Attr</th><th>Reason</th>' .
        '<th>Chron/Enum</th><th>Date&nbsp;1</th><th>Date&nbsp;2</th><th>Export&nbsp;Date</th><th>Type</th></tr>' .
        "\n";
}


my %seen;
my %counts;
my $idsql = '';
if ($id)
{
  $idsql = "WHERE id='$id'";
  $start = undef;
  $end = undef;
}
my $startsql = ($start)? "WHERE time>='$start'":'';
my $endsql = ($end)? "AND time<'$end'":'';
my $sql = "SELECT id,attr,reason,DATE(time),time,gid FROM exportdata $idsql $startsql $endsql ORDER BY time ASC";
my $ref = $crms->get('dbh')->selectall_arrayref($sql);
#print "$sql\n";
my $lastdate = '';
foreach my $row ( @{$ref} )
{
  $id = $row->[0];
  next if $seen{$id};
  $seen{$id} = 1;
  my $attr = $row->[1];
  my $reason = $row->[2];
  my $date = $row->[3];
  my $time = $row->[4];
  my $gid = $row->[5];
  $sql = "SELECT COUNT(*) FROM exportdata WHERE id='$id' AND time>'$time'";
  next if $crms->SimpleSqlGet($sql) > 0;
  my $rq = $crms->RightsQuery($id,1);
  my $attr2 = $rq->[0]->[0];
  my $reason2 = $rq->[0]->[1];
  if ($attr ne $attr2 || $reason ne $reason2)
  {
    print "$id: determination $attr/$reason overridden by $attr2/$reason2\n" if $verbose;
    next;
  }
  if ($verbose && $lastdate ne $date)
  {
    print "DOING EXPORTS FROM $time\n";
    foreach my $cat (sort keys %counts)
    {
      printf "  $cat: %d\n", $counts{$cat};
    }
  }
  $lastdate = $date;
  my $sysid = $crms->BarcodeToId($id);
  my $mrecord = $crms->GetMirlynMetadata($sysid);
  my $holdings = HoldingsQueryForRecord($sysid, $mrecord);
  next if 1 == scalar @{$holdings};
  my $record = $crms->GetRecordMetadata($id);
  my $date1 = Date1Field($id, $record);
  my $date2 = Date2Field($id, $record);
  my $title = $crms->GetTitle($id);
  $title =~ s/\t+/ /g;
  my @lines = ();
  my %attrs;
  $attrs{($attrOnly)? $attr:"$attr/$reason"} = 1;
  my $chron = '';
  print "Original: $id, $attr, $reason\n" if $verbose and 1 < scalar @{$holdings};
  foreach my $holding (@{$holdings})
  {
    #print "$holding\n";
    my ($hi,$hc,$hblah) = split '__', $holding;
    if ($hi eq $id)
    {
      $chron = $hc;
      last;
    }
  }
  if ($enum)
  {
    next unless $chron;
  }
  else
  {
    next if ($chron && $chron !~ m/cop[\.y]/);
  }
  my $catlink = "http://mirlyn.lib.umich.edu/Record/$sysid/Details#tabs";
  
  if ($report eq 'tsv')
  {
    push @lines, sprintf "$sysid\t$id\t$title\t$attr\t$reason\t$chron\t$date1\t$date2\t$date";
  }
  elsif ($report eq 'html')
  {
    my $ptlink = 'https://babel.hathitrust.org/cgi/pt?attr=1&amp;id=' . $id;
    push @lines, "<tr><td><a href='$catlink' target='_blank'>$sysid</a></td><td><a href='$ptlink' target='_blank'>$id</a></td><td>$title</td><td>$attr</td><td>$reason</td><td>$chron</td><td>$date1</td><td>$date2</td><td>$date</td>";
  }
  my $situation = '';
  my %dups = ();
  my $icbib = 0;
  my $conflict = 0;
  foreach my $holding (@{$holdings})
  {
    my ($id2,$chron2,$hblah) = split '__', $holding;
    #print "ID2: $id2\n";
    if ($chron2 && $chron2 !~ m/cop[\.y]/)
    {
      print "Bailing out on $id ($sysid) with chron\n" if $verbose;
      @lines = ();
      %dups = ();
      last;
    }
    if ($id2 ne $id)
    {
      next if $seen{$id2};
      $seen{$id2} = 1;
      my $title2;
      $situation = 'duplicate' unless $situation;
      $sql = "SELECT attr,reason,time FROM exportdata WHERE id='$id2' ORDER BY time DESC LIMIT 1";
      my $ref2 = $crms->get('dbh')->selectall_arrayref($sql);
      my $user = 'crms';
      my $ref3 = $crms->RightsQuery($id2,1);
      # Rights database supersedes if newer than our export
      if (!$ref2 || $ref3->[0]->[4] > $ref2->[0]->[4])
      {
        $ref2 = $ref3;
        $user = $ref2->[0]->[2];
      }
      $attr2 = $ref2->[0]->[0];
      $reason2 = $ref2->[0]->[1];
      $date2 = $ref2->[0]->[4];
      $date2 =~ s/(\d\d\d\d-\d\d-\d\d).*/$1/;
      if ($reason2 ne 'bib')
      {
        $conflict = 1 unless $attrs{($attrOnly)? $attr2:"$attr2/$reason2"};
        $attrs{($attrOnly)? $attr2:"$attr2/$reason2"} = 1;
      }
      print "  Holding: $id2, $attr2, $reason2 ($user)\n" if $verbose;
      my $record2 = $crms->GetRecordMetadata($id2);
      $title2 = $crms->GetRecordTitleBc2Meta($id2) unless $title2;
      my $date12 = Date1Field($id2, $record);
      my $date22 = Date2Field($id2, $record);
      if ($attr2 eq 'ic' and $reason2 eq 'bib')
      {
        $icbib = 1;
        $dups{$id2} = $record2;
      }
      if ($report eq 'tsv')
      {
        push @lines, "$sysid\t$id2\t$title2\t$attr2\t$reason2\t$chron2\t$date12\t$date22\t$date2";
      }
      elsif ($report eq 'html')
      {
        my $ptlink2 = 'https://babel.hathitrust.org/cgi/pt?attr=1&amp;id=' . $id2;
        push @lines, "<tr><td><a href='$catlink' target='_blank'>$sysid</a></td><td><a href='$ptlink2' target='_blank'>$id2</a></td><td>$title2</td><td>$attr2</td><td>$reason2</td><td>$chron2</td><td>$date12</td><td>$date22</td><td>$date2</td>";
      }
    }
  }
  if ($conflict)
  {
    $situation = ($icbib)? 'conflict':'crms_conflict';
  }
  elsif ($icbib && 0 < scalar keys %dups)
  {
    $situation = 'duplicate';
  }
  print "  Situation '$situation'\n" if $verbose;
  if (($situation eq $type || $type eq 'all') && 0 < scalar keys %dups)
  {
    foreach my $line (@lines)
    {
      print $line unless $report eq 'none';
      print "\t$situation\n" if $report eq 'tsv';
      print "<td>$situation</td></tr>\n" if $report eq 'html';
    }
    if ($situation eq 'duplicate' && $summary)
    {
      foreach my $id2 (keys %dups)
      {
        print $summfh "$id2\t$attr\t$reason";
      }
    }
    if ($submit && $situation eq 'duplicate' && !$enum)
    {
      foreach my $id2 (keys %dups)
      {
        my $record = $dups{$id2};
        $sql = "SELECT COUNT(*) FROM reviews WHERE id='$id2'";
        next if $crms->SimpleSqlGet($sql) > 0;
        $sql = "SELECT COUNT(*) FROM historicalreviews WHERE id='$id2'";
        if ($crms->SimpleSqlGet($sql) > 0)
        {
          print "There is an historical review for $id2; what gives?\n";
          next;
        }
        print "Updating queue and reviews for $id2 ($sysid from $id)\n" if $verbose;
        next if $noop;
        $sql = "REPLACE INTO queue (id,locked,status,pending_status,expcnt,source) VALUES ('$id2','autocrms',5,5,1,'duplicates')";
        $crms->PrepareSubmitSql($sql);
        my $note = "Record $sysid from $id";
        my $result = $crms->SubmitReview($id2,'autocrms',$attr,$reason,$note,undef,1,undef,'Duplicate',0,0);
        $crms->UpdateTitle($id2, undef, $record);
        $crms->UpdatePubDate($id2, undef, $record);
        $crms->UpdateAuthor($id2, undef, $record);
        $crms->PrepareSubmitSql("REPLACE INTO system (id,sysid) VALUES ('$id2','$sysid')");
      }
    }
    $counts{$situation}++ if $situation;
  }
  #print "For $id the situation is '$situation'\n" if $verbose;
}

print "</table></body></html>\n\n" if $report eq 'html';
close $summfh if $summfh;
foreach my $cat (sort keys %counts)
{
  #printf "Count for $cat: %d\n", $counts{$cat};
}

print "Warning: $_\n" for @{$crms->GetErrors()};

my $hashref = $crms->GetSdrDb()->{mysql_dbd_stats};
printf "SDR Database OK reconnects: %d, bad reconnects: %d\n", $hashref->{'auto_reconnects_ok'}, $hashref->{'auto_reconnects_failed'} if $verbose;

