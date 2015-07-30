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
use Unicode::Normalize;

use Term::ANSIColor qw(:constants);
$Term::ANSIColor::AUTORESET = 1;


my $usage = <<END;
USAGE: $0 [-aChipqv] [-s VOL_ID [-s VOL_ID2...]]
          [-m MAIL_ADDR [-m MAIL_ADDR2...]] [-n TBL [-n TBL...]]
          [-x SYS] [start_date[ time] [end_date[ time]]]

Reports on the volumes that can inherit ADD from this morning's export,
or, if start_date is specified, exported after then and before end_date
if it is specified.

-a         Report on all exports, regardless of date range.
-h         Print this help message.
-i         Insert entries in the inherit table.
-m ADDR    Mail the report to ADDR. May be repeated for multiple addresses.
-n TBL     Suppress table TBL (which is often huge in candidates cleanup),
           where TBL is one of {chron,nodups,noexport,unneeded}.
           May be repeated for multiple tables.
-p         Run in production.
-q         Do not emit report (ignored if -m is used).
-s VOL_ID  Report only for HT volume VOL_ID. May be repeated for multiple volumes.
-v         Emit debugging information.
-x SYS     Set SYS as the system to execute.
END

my $all;
my $help;
my $insert;
my @mails;
my @no;
my $production;
my $quiet;
my @singles;
my $sys;
my $verbose;

Getopt::Long::Configure ('bundling');
die 'Terminating' unless GetOptions(
           'a'    => \$all,
           'h|?'  => \$help,
           'i'    => \$insert,
           'm:s@' => \@mails,
           'n:s@' => \@no,
           'p'    => \$production,
           'q'    => \$quiet,
           's:s@' => \@singles,
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
my $src = 'export';
print "Verbosity $verbose$delim" if $verbose;
my $sql = 'SELECT DATE(NOW())';
my $start = $crms->SimpleSqlGet($sql);
my $end = $start;
if ($all)
{
  $sql = sprintf 'SELECT MIN(time) FROM %s', 'exportdata';
  $start = $crms->SimpleSqlGet($sql);
  $sql = sprintf 'SELECT MAX(time) FROM %s', 'exportdata';
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
                    ($DLPS_DEV)? 'Dev':'Prod';
$start .= ' 00:00:00' unless $start =~ m/\d\d:\d\d:\d\d$/;
$end .= ' 23:59:59' unless $end =~ m/\d\d:\d\d:\d\d$/;
my $xpc;
my %data = %{ADDReport($start,$end,\@singles)};
my $txt = $crms->StartHTML($title);
$delim = "<br/>\n";

for (@{$crms->GetErrors()})
{
  s/\n/<br\/>/g;
  $txt .= "<i>Warning: $_</i>$delim\n";
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

sub ADDReport
{
  my $start   = shift;
  my $end     = shift;
  my $singles = shift;

  my %data = ();
  my %seen = ();
  my $sql = 'SELECT e.id,e.gid,e.attr,e.reason,e.time,e.src FROM exportdata e INNER JOIN bibdata b' .
            " ON e.id=b.id WHERE e.src!='inherited' AND e.time>'$start' AND e.time<='$end'" .
            " AND (e.attr='pd' OR e.attr='pdus') AND e.reason='add' ORDER BY b.author ASC LIMIT 100";
  if ($singles && scalar @{$singles})
  {
    $sql = sprintf('SELECT e.id,e.gid,e.attr,e.reason,e.time,e.src FROM exportdata e INNER JOIN bibdata b' .
                   " ON e.id=b.id WHERE e.id IN ('%s') ORDER BY b.author ASC", join "','", @{$singles});
  }
  print "$sql\n" if $verbose > 1;
  my $ref = $crms->SelectAll($sql);
  my %auths = (); # Long name -> arrayref of gids
  foreach my $row (@{$ref})
  {
    my $id = $row->[0];
    my $gid = $row->[1];
    my $attr = $row->[2];
    my $reason = $row->[3];
    my $time = $row->[4];
    $sql = "SELECT renDate FROM historicalreviews WHERE renDate IS NOT NULL AND gid=$gid " .
           ' AND validated!=0 ORDER BY expert DESC, validated ASC LIMIT 1';
    my $add = $crms->SimpleSqlGet($sql);
    if ($verbose)
    {
      print "Checking $id ($gid, ";
      print GREEN "$attr/$reason";
      print ")\n";
    }
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
    if ($time ne $latest)
    {
      print "Later export ($latest) for $id ($time); skipping\n" if $verbose;
      next;
    }
    # THIS is the export we're going to inherit from.
    $seen{$id} = $id;
    $data{'total'}->{$id} = 1;
    my $author = $record->author(1);
    if (!$author)
    {
      print "Empty author for $id; skipping\n" if $verbose;
      next;
    }
    push @{$auths{$author}}, $gid;
  }
  foreach my $author (sort keys %auths)
  {
    my @gids = @{$auths{$author}};
    my %adds;
    #printf "GIDS: %s\n", join ', ', @gids;
    foreach my $gid (@gids)
    {
      $sql = "SELECT renDate FROM historicalreviews WHERE renDate IS NOT NULL AND gid=$gid " .
           ' AND validated!=0 ORDER BY expert DESC, validated ASC LIMIT 1';
      my $add = $crms->SimpleSqlGet($sql);
      $adds{$add} = 1;
    }
    if (scalar keys %adds > 1)
    {
      printf BOLD RED "Multiple dates for $author: %s\n", join ', ', keys %adds if $verbose;
      next;
    }
    my $add = (keys %adds)[0];
    my $id = $crms->SimpleSqlGet(sprintf "SELECT id FROM exportdata WHERE gid='%s'", $gids[-1]);
    my $attr = $crms->SimpleSqlGet(sprintf "SELECT attr FROM exportdata WHERE gid='%s'", $gids[-1]);
    my $reason = $crms->SimpleSqlGet(sprintf "SELECT reason FROM exportdata WHERE gid='%s'", $gids[-1]);
    my $record = $crms->GetMetadata($id);
    my $shortauthor = lc $record->author;
    my $solrauthor = $shortauthor;
    $shortauthor =~ s/[.,;]+$//;
    $shortauthor = NFD($shortauthor);
    $shortauthor =~ s/\pM//og;
    $shortauthor =~ s/[^a-z]//g;
    my $title = $record->title;
    my $pubdate = $crms->FormatPubDate($id, $record);
    if ($verbose)
    {
      print "$author (";
      print BLUE "ADD $add";
      print "): $title ($pubdate) ($id)\n";
    }
    my $results = GetSOLRData($solrauthor);
    #printf "%d results for $id\n", scalar @{$results} if $verbose;
    foreach my $res (@{$results})
    {
      my @ids = ();
      my @records = $xpc->findnodes('./arr[@name="ht_id"]/str', $res);
      #printf "%d HT ids for $id\n", scalar @records if $verbose;
      my $skip = 0;
      foreach my $id2 (@records)
      {
        $id2 = $id2->to_literal();
        $skip = 1 if $id eq $id2;
        push @ids, $id2;
      }
      printf "Skipping (%s)\n", join ',', @ids if $skip and $verbose >= 4;
      next if $skip;
      my $id2 = $ids[0];
      my @records = $xpc->findnodes('./str[@name="fullrecord"]', $res);
      my $record = $records[0]->to_literal();
      my $parser2 = XML::LibXML->new();
      my $source;
      eval {
        $source = $parser2->parse_string($record);
      };
      if ($@) { $crms->SetError("failed to parse ($record) for $id2: $@");}
      my $xpc2 = XML::LibXML::XPathContext->new($source);
      my $ns = 'http://www.loc.gov/MARC21/slim';
      $xpc2->registerNs(ns => $ns);
      @records = $xpc2->findnodes('//ns:record');
      $record = $records[0];
      my $shortauthor2 = lc $crms->GetRecordAuthor($ids[0], $record);
      $shortauthor2 =~ s/[.,;]+$//;
      $shortauthor2 = NFD($shortauthor2);
      $shortauthor2 =~ s/\pM//og;
      $shortauthor2 =~ s/[^a-z]//g;
      my $author2 = $crms->GetRecordAuthor($ids[0], $record, 1);
      my $title2 = $crms->GetRecordTitle($ids[0], $record);
      my $pubdate2 = $crms->GetRecordPubDate($ids[0], $record);
      my $errs = $crms->GetViolations($ids[0], $record);
      my $src = $crms->ShouldVolumeBeFiltered($ids[0], $record);
      #print "'$shortauthor' vs '$shortauthor2'\n";
      if ($shortauthor ne $shortauthor2)
      {
        print BOLD RED "  $author2";
        print ": $title2\n" if $verbose;
        next;
      }
      my $err = '';
      if (scalar @{$errs} > 0 || $src)
      {
        $err = join '; ', @{$errs} if scalar @{$errs} > 0;
        if ($src)
        {
          $err .= '; ' if $err;
          $err .= "UND: $src";
        }
      }
      if ($verbose)
      {
        printf "  $author2: $title2 ($pubdate2)";
        print BOLD RED " $err" if $err;
      }
      my $rows = $crms->VolumeIDsQuery(undef, $record);
      my $haschron = 0;
      foreach my $line (@{$rows})
      {
        my ($id2,$chron2,$rights2) = split '__', $line;
        if ($chron2 && $chron2 !~ /co?py/)
        {
          $haschron = 1;
          last;
        }
      }
      if ($verbose)
      {
        print BOLD RED " [CHRON/ENUM]" if $haschron;
        print "\n";
      }
      next if $haschron or $err;
      my $exp = undef;
      foreach my $line (@{$rows})
      {
        my ($id2,$chron2,$rights2) = split '__', $line;
        $sql = "SELECT CONCAT(attr,'/',reason) FROM exportdata WHERE id='$id2' ORDER BY time DESC LIMIT 1";
        $exp = $crms->SimpleSqlGet($sql) unless $exp;
      }
      my $ok = !defined $exp;
      foreach my $line (@{$rows})
      {
        my ($id2,$chron2,$rights2) = split '__', $line;
        my ($attr2,$reason2,$src2,$usr2,$time2,$note2) = @{$crms->RightsQuery($id2,1)->[0]};
        my $rights = "$attr2/$reason2";
        my $inh = $crms->SimpleSqlGet("SELECT COUNT(*) FROM inherit WHERE id='$id2'");
        $ok = (($attr ne $attr2 && $reason2 eq 'bib') || $reason2 eq 'gfv') if $ok;
        my $rid = $crms->PredictRights($id2, $add, undef, undef, $record);
        my $predicteda = $crms->TranslateAttr($crms->SimpleSqlGet("SELECT attr FROM rights WHERE id=$rid"));
        my $predictedr = $crms->TranslateReason($crms->SimpleSqlGet("SELECT reason FROM rights WHERE id=$rid"));
        $ok = undef if $ok and $predicteda ne 'pd' and $predicteda ne 'pdus';
        $ok = undef if $ok and $inh;
        if ($verbose > 1)
        {
          printf "    [%s] $id2 ($rights", ($ok)? 'x':' ';
          if ($ok && $predicteda ne $attr2)
          {
            print "->";
            print GREEN "$predicteda/$predictedr";
          }
          printf ")%s", ($chron2)? " [$chron2]":'';
          print BOLD RED " [EXPORTED $exp]" if $exp;
          print BOLD RED " [INHERITING]" if $inh;
          print BOLD RED " [PREDICTED $predicteda/$predictedr]"if $predicteda ne 'pd' and $predicteda ne 'pdus';
          print "\n";
        }
      }
    }
    print "==========\n" if $verbose;
  }
  #$crms->PrepareSubmitSql("DELETE FROM unavailable WHERE src='$src'") if $insert;
  return \%data;
}

sub GetSOLRData
{
  my $self = $crms;
  my $author = shift;

  my $query = qq{author:"$author"};
  $query = URI::Escape::uri_escape_utf8($query);
  my $url = 'http://solr-sdr-catalog.umdl.umich.edu:9033/catalog/select?rows=50&q=' . $query;
  print "SOLR query: $url\n" if $verbose;
  my $ua = LWP::UserAgent->new;
  $ua->timeout(1000);
  my $req = HTTP::Request->new(POST => $url);
  my $res = $ua->request($req);
  if (!$res->is_success)
  {
    $self->SetError($url . ' failed: ' . $res->message());
    return;
  }
  my $xml = $res->content;
  print "$xml\n\n" if $verbose >= 4;
  my $parser = $crms->get('parser');
  if (!$parser)
  {
    $parser = XML::LibXML->new();
    $crms->set('parser',$parser);
  }
  my $source;
  eval {
    $xml = Encode::decode('utf8', $xml);
    $source = $parser->parse_string($xml);
  };
  if ($@) { $crms->SetError("failed to parse ($xml) for $author: $@"); return; }
  $xpc = XML::LibXML::XPathContext->new($source);
  #my $ns = 'http://www.loc.gov/MARC21/slim';
  #$xpc->registerNs(ns => $ns);
  my @records = $xpc->findnodes('/response/result[@name="response"]/doc');
  #$self->set($id,$records[0]);
  return \@records;
}
