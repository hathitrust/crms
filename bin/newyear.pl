#!/usr/bin/perl

use strict;
use warnings;
BEGIN { unshift(@INC, $ENV{'SDRROOT'}. '/crms/cgi'); }

use utf8;
binmode(STDOUT, ':encoding(UTF-8)');
use CRMS;
use Getopt::Long qw(:config no_ignore_case bundling);
use Encode;
use JSON::XS;
use Term::ANSIColor qw(:constants colored);
$Term::ANSIColor::AUTORESET = 1;
use Data::Dumper;

my $usage = <<END;
USAGE: $0 [-hnpv] [-e HTID [-e HTID...]]
       [-s HTID [-s HTID...]] [-x EXCEL_FILE] [-y YEAR]

Reports on and submits new determinations for previous determinations
that may now, as of the new year, have had copyright expire from ic*
to either pd* or icus.

Accumulates death/pub dates for each determination, whether entered as the
master date, or in the notes field, and creates new determinations based
on both the 50/70-year predicted copyright term, and the 95-year US term
opening 1923 volumes in 2019.

The dates accumulated for each volume are translated into a set
of rights predictions, and if the most restrictive of these is more open
than the current rights, a new determination is submitted in the CRMS
database as a queue entry and autocrms review with the new rights.

-e HTID        Exclude HTID from being considered.
-h             Print this help message.
-n             No-op. Makes no changes to the database.
-p             Run in production.
-s HTID        Report only for volume HTID. May be repeated for multiple volumes.
-v             Emit verbose debugging information. May be repeated.
-x EXCEL_FILE  Write report on new determinations to EXCEL_FILE.
-y YEAR        Use this year instead of the current one.
END

my @excludes;
my $help;
my $instance;
my $noop;
my $production;
my @singles;
my $verbose;
my $excel;
my $year;

Getopt::Long::Configure('bundling');
die 'Terminating' unless GetOptions(
           'e:s@' => \@excludes,
           'h|?'  => \$help,
           'n'    => \$noop,
           'p'    => \$production,
           's:s@' => \@singles,
           'v+'   => \$verbose,
           'x:s'  => \$excel,
           'y:s'  => \$year);
$instance = 'production' if $production;
if ($help) { print $usage. "\n"; exit(0); }

my $crms = CRMS->new(
    sys      => 'crmsworld',
    verbose  => $verbose,
    instance => $instance
);

$verbose = 0 unless defined $verbose;
print "Verbosity $verbose\n" if $verbose;
$crms->set('noop', 1) if $noop;

my ($workbook, $worksheet);
my $wsrow = 1;
if ($excel)
{
  require Excel::Writer::XLSX;
  my $excelpath = $crms->FSPath('prep', $excel);
  my @cols = ('ID', 'Author', 'Title', 'Pub Date', 'Country', 'Current Rights',
              'Extracted Dates', 'Predictions', 'Action', 'Message');
  $workbook  = Excel::Writer::XLSX->new($excelpath);
  $worksheet = $workbook->add_worksheet();
  $worksheet->write_string(0, $_, $cols[$_]) for (0 .. scalar @cols - 1);
}

my $nyp = $crms->SimpleSqlGet('SELECT id FROM projects WHERE name="New Year"');
my $commonwealth = $crms->SimpleSqlGet('SELECT id FROM projects WHERE name="Commonwealth"');
die "Can't get New Year project" unless defined $nyp;
die "Can't get Commonwealth project" unless defined $commonwealth;
my $nyp_ref = $crms->GetProjectRef($nyp);
$year = $crms->GetTheYear() unless $year;
my $sql = 'SELECT e.id,e.gid,e.time,e.attr,e.reason FROM exportdata e'.
          ' WHERE (e.attr="pdus" OR e.attr="ic" OR e.attr="icus")'.
          ' AND e.exported=1 AND e.project=? AND YEAR(DATE(e.time))<?'.
          ' AND e.id NOT IN (SELECT id FROM queue)';
if (scalar @singles)
{
  $sql .= sprintf(" AND e.id IN ('%s')", join "','", @singles);
}
if (scalar @excludes)
{
  $sql .= sprintf(" AND NOT e.id IN ('%s')", join "','", @excludes);
}
$sql .= ' ORDER BY e.time DESC';
#$sql .= ' LIMIT 1000';
print Utilities::StringifySql($sql, $commonwealth, $year). "\n" if $verbose > 1;
my $jsonxs = JSON::XS->new->utf8->canonical(1)->pretty(0);
my $ref = $crms->SelectAll($sql, $commonwealth, $year);
my %seen;
printf "Checking %d possible determinations…\n", scalar @$ref;
foreach my $row (@{$ref})
{
  my $id = $row->[0];
  next if $seen{$id};
  my $record = $crms->GetMetadata($id);
  next unless defined $record;
  my $rq = $crms->RightsQuery($id, 1);
  if (!defined $rq)
  {
    print RED "No rights available for $id, skipping.\n";
    next;
  }
  my ($acurr,$rcurr,$src,$usr,$timecurr,$note) = @{$rq->[0]};
  next if $acurr eq 'pd';
  my $gid = $row->[1];
  my $time = $row->[2];
  $seen{$id} = 1;
  $sql = 'SELECT r.note,r.user,d.data FROM historicalreviews r'.
         ' INNER JOIN reviewdata d ON r.data=d.id'.
         ' WHERE r.gid=? AND r.validated=1 AND r.data IS NOT NULL';
  #print Utilities::StringifySql($sql, $gid). "\n" if $verbose > 1;
  my $ref2 = $crms->SelectAll($sql, $gid);
  my $n = scalar @{$ref2};
  next unless $n > 0;
  my %alldates;
  my %predictions;
  my $bogus;
  foreach my $row2 (@{$ref2})
  {
    my $note = $row2->[0] || '';
    my $user = $row2->[1];
    my $data = $row2->[2];
    print "$gid: $data\n";
    $data = $jsonxs->decode($data);
    my $date = $data->{'date'};
    my $pub = $data->{'pub'};
    my $crown = $data->{'crown'};
    my $dates = [];
    push @$dates, [$date, $pub] if defined $date;
    my @matches = $note =~ /(?<!\d)1\d\d\d(?![\d\-])/g;
    foreach my $match (@matches)
    {
      push @$dates, [$match, 0] if length $match and $match < $year;
    }
    foreach my $date (@$dates)
    {
      my $rid = $crms->PredictRights($id, $date->[0], $date->[1],
                                     $crown, $record, undef, $year);
      if (!defined $rid)
      {
        $bogus = 1;
        last;
      }
      my ($pa, $pr) = $crms->TranslateAttrReasonFromCode($rid);
      $predictions{"$pa/$pr"} = 1;
    }
    $alldates{$_->[0]} = 1 for @$dates;
  }
  next if $bogus;
  my ($ic, $icus, $pd, $pdus);
  foreach my $pred (keys %predictions)
  {
    $ic = $pred if $pred =~ m/^ic\//;
    $icus = $pred if $pred =~ m/^icus/;
    $pd = $pred if $pred =~ m/^pd\//;
    $pdus = $pred if $pred =~ m/^pdus/;
  }
  if (scalar keys %predictions && !defined $ic && ($icus || $pd || $pdus))
  {
    my $action;
    if (defined $pd)
    {
      $action = ($acurr eq 'pd')? undef:$pd;
    }
    if (defined $pdus)
    {
      $action = ($acurr =~ m/^pd/)? undef:$pdus;
    }
    if (defined $icus)
    {
      $action = ($acurr =~ m/^pd/ || $acurr =~ m/^icus/)? undef:$icus;
    }
    if (defined $action)
    {
      $crms->UpdateMetadata($id, 1, $record);
      my $res = $crms->AddItemToQueueOrSetItemActive($id, 0, 1, 'newyear', undef, $record, $nyp);
      my $code = $res->{'status'};
      my $msg = $res->{'msg'};
      if ($code eq '1' || $code eq '2')
      {
        if ($verbose)
        {
          print GREEN "Result for $id: $code $msg\n" if $code == 0;
          print RED "Result for $id: $code $msg\n" if $code == 1;
        }
        $msg = '' if $code == 2;
      }
      else
      {
        $msg = '';
      }
      my ($a, $r) = split m/\//, $action;
      my $rights = $crms->GetCodeFromAttrReason($crms->TranslateAttr($a), $crms->TranslateReason($r));
      die "Can't get rights code from $a/$r\n" unless defined $rights;
      my $params = {'rights' => $rights,
                    'note' => "New Year $year",
                    'category' => 'Expert Note'};
      #print Dumper $params;
      my $result = $crms->SubmitReview($id, 'autocrms', $params, $nyp_ref);
      if ($result)
      {
        print RED "SubmitReview() for $id: $result\n";
      }
      if ($excel)
      {
        $worksheet->write_string($wsrow, 0, $id);
        $worksheet->write_string($wsrow, 1, $record->author || '');
        $worksheet->write_string($wsrow, 2, $record->title || '');
        $worksheet->write_string($wsrow, 3, $record->copyrightDate || '');
        $worksheet->write_string($wsrow, 4, $record->country || '');
        $worksheet->write_string($wsrow, 5, "$acurr/$rcurr");
        $worksheet->write_string($wsrow, 6, join(',', sort keys %alldates));
        $worksheet->write_string($wsrow, 7, join(',', sort keys %predictions));
        $worksheet->write_string($wsrow, 8, $action);
        $worksheet->write_string($wsrow, 9, $msg);
        print GREEN "Worksheet row $wsrow written\n";
        $wsrow++;
      }
    }
  }
}

$workbook->close() if $excel;

print RED "Warning: $_\n" for @{$crms->GetErrors()};

