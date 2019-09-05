#!/usr/bin/perl

use strict;
use warnings;
BEGIN { unshift(@INC, $ENV{'SDRROOT'}. '/crms/cgi'); }

use Getopt::Long qw(:config no_ignore_case bundling);
use Encode;

my $usage = <<END;
USAGE: $0 [-hlptvwz] [-i ID] [-m MAIL_ADDR [-m MAIL_ADDR2...]] [-r TYPE]
          [-s SUMMARY_PATH] [-t REPORT_TYPE] [start_date [end_date]]

Reports on CRMS determinations for volumes that have duplicates,
multiple volumes, or conflicting determinations.

-h       Print this help message.
-i ID    Report only for volume ID (start and end dates are ignored). May be repeated.
-l       Use legacy determinations instead of CRMS determinations.
-m ADDR  Mail the report to ADDR. May be repeated for multiple addresses.
-p       Run in production.
-r TYPE  Print a report of TYPE where TYPE={html,none,tsv}.
-s PATH  Emit a TSV summary (for duplicates) with ID, rights, reason.
-t TYPE  Report on situations of type TYPE:
           duplicate:     >0 matching CRMS determinations, >0 ic/bib (default)
           conflict:      conflicting CRMS determinations, >0 ic/bib
           crms_conflict: conflicting CRMS determinations, no ic/bib
           resolvable:    partially conflicting CRMS determinations that can be resolved
                          with a pd/crms, ic/crms, or und/crms determination, >0 ic/bib
         May be repeated.
-v       Be verbose. May be repeated.
-z       Generate hyperlinks in the TSV file for Excel.
END

my $help;
my @ids;
my $instance;
my $legacy;
my @mails;
my $production;
my $report = 'none';
my $summary;
my @types;
my $verbose;
my $link;

die 'Terminating' unless GetOptions('h|?' => \$help,
           'i:s@' => \@ids,
           'l'    => \$legacy,
           'm:s@' => \@mails,
           'p'    => \$production,
           'r:s'  => \$report,
           's:s'  => \$summary,
           't=s@' => \@types,
           'v+'   => \$verbose,
           'z'    => \$link);
$instance = 'production' if $production;
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
    verbose  => $verbose,
    instance => $instance
);


sub Date1Field
{
  my $id     = shift;
  my $record = shift;

  if ( ! $record ) { $crms->SetError("no record in Date1Field: $id"); return; }
  my $leader = $record->GetControlfield('008');
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
  my $leader = $record->GetControlfield('008');
  my $d = substr $leader, 11, 4;
  #print "Date2: '$d'\n";
  return $d;
}

my $txt = '';
my $dates = $start;
$dates .= " to $end" if $end ne $start;
my $title = $crms->SubjectLine(sprintf "%s Duplicates, $dates", join ',', map {ucfirst $_;} @types);
if ($report eq 'tsv')
{
  $txt .= "System ID\tVolume ID\tTitle\tAttr\tReason\tChron/Enum\tDate 1\tDate 2\tTime of Determination\tTracking\tType\n";
}
elsif ($report eq 'html')
{
  $txt .= "<!DOCTYPE html PUBLIC '-//W3C//DTD XHTML 1.0 Transitional//EN' 'http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd'>\n" .
        '<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en"><head>' .
        "<meta http-equiv='Content-Type' content='text/html; charset=utf-8'/>\n" .
        "<title>$title</title></head><body>\n" .
        "<table border='1'>\n" .
        '<tr><th>System&nbsp;ID</th><th>Volume&nbsp;ID</th><th>Title</th><th>Attr</th><th>Reason</th>' .
        '<th>Chron/Enum</th><th>Date&nbsp;1</th><th>Date&nbsp;2</th><th>Export&nbsp;Date</th><th>Tracking</th><th>Type</th></tr>' .
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
my $ref = $crms->SelectAll($sql);
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
    $attr = $crms->TranslateAttr($attr);
    $reason = $crms->TranslateReason($reason);
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
  my $record = $crms->GetMetadata($id);
  my $sysid = $record->sysid;
  next unless defined $record;
  my $holdings = $crms->VolumeIDsQuery($id, $record);
  next unless scalar @{$holdings} > 1;
  my $date1 = Date1Field($id, $record);
  my $date2 = Date2Field($id, $record);
  my $ti = $record->title;
  $ti =~ s/\t+/ /g;
  my @lines = ();
  my %attrs;
  my %rights;
  $attrs{$attr} = 1;
  $rights{"$attr/$reason"} = 1;
  my $chron = '';
  print "Original: $id ($sysid) $attr/$reason\n" if $verbose;
  foreach my $ref (@{$holdings})
  {
    my $hi = $ref->{'id'};
    if ($hi eq $id)
    {
      $chron = $ref->{'chron'};
      last;
    }
  }
  if ($chron)
  {
    print "  Chron '$chron'; skipping.\n" if $verbose;
    next;
  }
  my $catlink = $crms->LinkToMirlynDetails($id);
  my $tracking = $crms->GetTrackingInfo($id);
  if ($report eq 'tsv')
  {
    push @lines, sprintf "$sysid\t$id\t$ti\t$attr\t$reason\t$chron\t$date1\t$date2\t$date\t$tracking";
  }
  elsif ($report eq 'html')
  {
    my $ptlink = 'https://babel.hathitrust.org/cgi/pt?attr=1;id=' . $id;
    push @lines, "<tr><td><a href='$catlink' target='_blank'>$sysid</a></td><td><a href='$ptlink' target='_blank'>$id</a></td><td>$ti</td><td>$attr</td><td>$reason</td><td>$chron</td><td>$date1</td><td>$date2</td><td>$date</td><td>$tracking</td>";
  }
  my $situation = '';
  my %dups = ();
  my $icbib = 0;
  my $conflict = 0;
  foreach my $holding (@{$holdings})
  {
    my ($id2,$chron2,$hblah) = split '__', $holding;
    #print "ID2: $id2\n";
    if ($chron2)
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
      my $ti2;
      $sql = "SELECT attr,reason,time FROM exportdata WHERE id='$id2' ORDER BY time DESC LIMIT 1";
      my $ref2 = $crms->SelectAll($sql);
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
      #my $record2 = $crms->GetRecordMetadata($id2);
      #$title2 = $crms->GetRecordTitleBc2Meta($id2) unless $title2;
      #my $date12 = Date1Field($id2, $record);
      #my $date22 = Date2Field($id2, $record);
      if ($attr2 eq 'ic' and $reason2 eq 'bib')
      {
        $icbib = 1;
        $dups{$id2} = $record;
      }
      my $tracking2 = $crms->GetTrackingInfo($id2);
      if ($report eq 'tsv')
      {
        push @lines, "$sysid\t$id2\t\t$attr2\t$reason2\t$chron2\t\t\t$date2\t$tracking2";
      }
      elsif ($report eq 'html')
      {
        my $ptlink2 = 'https://babel.hathitrust.org/cgi/pt?attr=1;id=' . $id2;
        push @lines, "<tr><td><a href='$catlink' target='_blank'>$sysid</a></td><td><a href='$ptlink2' target='_blank'>$id2</a></td><td/><td>$attr2</td><td>$reason2</td><td>$chron2</td><td/><td/><td>$date2</td><td>$tracking2</td>";
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
      $txt .= $line unless $report eq 'none';
      $txt .= "\t$situation\n" if $report eq 'tsv';
      $txt .= "<td>$situation</td></tr>\n" if $report eq 'html';
    }
    if ($situation eq 'duplicate' && $summary)
    {
      foreach my $id2 (keys %dups)
      {
        print $summfh "$id2\t$attr\t$reason\n";
      }
    }
    $counts{$situation}++ if $situation;
  }
  #print "For $id the situation is '$situation'\n" if $verbose;
}

$txt .= "</table>\n" if $report eq 'html';
close $summfh if $summfh;
my $n = 0;
foreach my $cat (sort keys %counts)
{
  $txt .= sprintf("Count for $cat: %d\n", $counts{$cat}) if scalar keys %counts > 0;
  $n += $counts{$cat};
}
$txt .= "Total System IDs: $n\n";

print "Warning: $_\n" for @{$crms->GetErrors()};

my $hashref = $crms->GetSdrDb()->{mysql_dbd_stats};
printf "SDR Database OK reconnects: %d, bad reconnects: %d\n", $hashref->{'auto_reconnects_ok'}, $hashref->{'auto_reconnects_failed'} if $verbose;
$txt .= "</body></html>\n\n" if $report eq 'html';
if (@mails)
{
  use Encode;
  use Mail::Sendmail;
  my $bytes = encode('utf8', $txt);
  my $to = join ',', @mails;
  my %mail = ('from'         => from => $crms->GetSystemVar('adminEmail', ''),
              'to'           => $to,
              'subject'      => $title,
              'content-type' => 'text/html; charset="UTF-8"',
              'body'         => $bytes
              );
  sendmail(%mail) || $crms->SetError("Error: $Mail::Sendmail::error\n");
}
else
{
  print "$txt\n";# unless $quiet;
}

