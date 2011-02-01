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
use Getopt::Long qw(:config no_ignore_case bundling);

my $usage = <<END;
USAGE: $0 [-ehlnpstvw] [-S SUMMARY_PATH] [-t REPORT_TYPE] [-r TYPE] [-i ID] [start_date [end_date]]

Reports on CRMS determinations for volumes that have duplicates,
multiple volumes, or conflicting determinations.

-e       Report only on records with chron/enum information.
-h       Print this help message.
-i ID    Report only for volume ID (start and end dates are ignored). May be repeated.
-l       Use legacy determinations instead of CRMS determinations.
-n       Do not submit SQL for duplicates when -s flag is set.
-p       Run in production.
-r TYPE  Print a report of TYPE where TYPE={html,none,tsv}.
-s       For true duplicates, submit a review for unreviewed duplicate volumes.
-S PATH  Emit a TSV summary (for duplicates) with ID, rights, reason.
-t TYPE  Report on situations of type TYPE:
           duplicate:     >0 matching CRMS determinations, >0 ic/bib (default)
           conflict:      conflicting CRMS determinations, >0 ic/bib
           crms_conflict: conflicting CRMS determinations, no ic/bib
           resolvable:    partially conflicting CRMS determinations that can be resolved
                          with a pd/crms, ic/crms, or und/crms determination, >0 ic/bib
         May be repeated.
-x       Generate hyperlinks in the TSV file for Excel.
-v       Be verbose. May be repeated.
END

my $enum;
my $help;
my @ids;
my $legacy;
my $noop;
my $production;
my $report = 'none';
#my $submit;
my $summary;
my @types;
my $verbose;
my $link;

die 'Terminating' unless GetOptions('e' => \$enum,
           'h|?' => \$help,
           'i:s@' => \@ids,
           'l' => \$legacy,
           'n' => \$noop,
           'p' => \$production,
           'r:s' => \$report,
#           's' => \$submit,
           'S:s' => \$summary,
           't=s@' => \@types,
           'x' => \$link,
           'v+' => \$verbose);
$DLPS_DEV = undef if $production;
print "Verbosity $verbose\n" if $verbose;
my %reports = ('html'=>1,'none'=>1,'tsv'=>1);
die "Bad value '$report' for -r flag" unless defined $reports{$report};
my $summfh;
if ($summary)
{
  open $summfh, '>', $summary or die "failed to open summary file $summary: $@ \n";
}
my %typesh;
push @types, 'duplicate' unless scalar @types;
$typesh{$_} = 1 for @types;

my $start = $ARGV[0];
my $end   = $ARGV[1];
die "Start date format should be YYYY-MM-DD; you said '$start'\n" if $start and $start !~ m/\d\d\d\d-\d\d-\d\d/;
die "End date format should be YYYY-MM-DD; you said '$end'\n" if $end and $end !~ m/\d\d\d\d-\d\d-\d\d/;
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
    dev          =>   $DLPS_DEV
);


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
my $idsql = 'id IS NOT NULL';
if (scalar @ids)
{
  $idsql = sprintf "id IN ('%s')", join "','", @ids;
  $start = undef;
  $end = undef;
}
my $startsql = ($start)? "AND time>='$start'":'';
my $endsql = ($end)? "AND time<'$end'":'';
my $sql = "SELECT id,attr,reason,DATE(time),time FROM exportdata WHERE $idsql $startsql $endsql ORDER BY time ASC";
$sql = "SELECT id,attr,reason,DATE(time),time FROM historicalreviews WHERE $idsql $startsql $endsql AND legacy=1 ORDER BY time ASC" if $legacy;
my $ref = $crms->get('dbh')->selectall_arrayref($sql);
print "$sql\n" if $verbose >= 2;
my $lastdate = '';
foreach my $row ( @{$ref} )
{
  my $id = $row->[0];
  next if $seen{$id};
  next if $legacy and 0 < $crms->SimpleSqlGet("SELECT COUNT(*) FROM exportdata WHERE id='$id'");
  $seen{$id} = 1;
  my $attr = $row->[1];
  my $reason = $row->[2];
  if ($legacy)
  {
    $attr = $crms->GetRightsName($attr);
    $reason = $crms->GetReasonName($reason);
  }
  my $date = $row->[3];
  my $time = $row->[4];
  next if $legacy and 0 < $crms->SimpleSqlGet("SELECT COUNT(*) FROM historicalreviews WHERE id='$id' AND time>'$time'");
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
  next unless $sysid;
  my $mrecord = $crms->GetMirlynMetadata($sysid);
  my $holdings = $crms->VolumeIDsQuery($sysid, $mrecord);
  next unless scalar @{$holdings} > 1;
  my $record = $crms->GetRecordMetadata($id);
  my $date1 = Date1Field($id, $record);
  my $date2 = Date2Field($id, $record);
  my $title = $crms->GetTitle($id);
  $title =~ s/\t+/ /g;
  my @lines = ();
  my %attrs;
  my %rights;
  $attrs{$attr} = 1;
  $rights{"$attr/$reason"} = 1;
  my $chron = '';
  print "Original: $id ($sysid) $attr/$reason\n" if $verbose;
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
    if ($chron && $chron !~ m/cop[\.y]/)
    {
      print "  Chron '$chron'; skipping.\n" if $verbose;
      next;
    }
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
      $sql = "SELECT attr,reason,time FROM exportdata WHERE id='$id2' ORDER BY time DESC LIMIT 1";
      my $ref2 = $crms->get('dbh')->selectall_arrayref($sql);
      my $user = 'crms';
      my $ref3 = $crms->RightsQuery($id2,1);
      # Rights database supersedes if newer than our export
      if (!$ref2 || $ref3->[0]->[4] > $ref2->[0]->[4])
      {
        $ref2 = $ref3;
        $user = $ref2->[0]->[3];
      }
      $attr2 = $ref2->[0]->[0];
      $reason2 = $ref2->[0]->[1];
      $date2 = $ref2->[0]->[4];
      $date2 =~ s/(\d\d\d\d-\d\d-\d\d).*/$1/;
      if ($reason2 ne 'bib')
      {
        $conflict = 1 unless $rights{"$attr2/$reason2"};
        $attrs{$attr2} = 1;
        $rights{"$attr2/$reason2"} = 1;
      }
      print "  Holding: $id2, $attr2/$reason2 ($user)\n" if $verbose;
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
    my $n = scalar keys %attrs;
    $situation = 'resolvable' if ($n == 1 || ($n == 2 && $attrs{'ic'} && $attrs{'und'}));
    print "Situation is $situation; n is $n; icbib is $icbib\n" if $verbose;
  }
  elsif ($icbib && 0 < scalar keys %dups)
  {
    $situation = 'duplicate';
  }
  printf "  Situation '$situation' (%s lines)\n", scalar @lines if $verbose;
  if ($typesh{$situation} && 1 < scalar @lines)
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
        print $summfh "$id2\t$attr\t$reason\n";
      }
    }
    #if ($submit && $situation eq 'duplicate' && !$enum)
    if (0)
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
  printf "Count for $cat: %d\n", $counts{$cat} if $verbose;
}

print "Warning: $_\n" for @{$crms->GetErrors()};

my $hashref = $crms->GetSdrDb()->{mysql_dbd_stats};
printf "SDR Database OK reconnects: %d, bad reconnects: %d\n", $hashref->{'auto_reconnects_ok'}, $hashref->{'auto_reconnects_failed'} if $verbose;

