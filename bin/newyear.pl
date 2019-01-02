#!/usr/bin/perl

BEGIN 
{ 
  unshift(@INC, $ENV{'SDRROOT'}. '/crms/cgi');
}

use strict;
use CRMS;
use Getopt::Long qw(:config no_ignore_case bundling);
use Encode;
use Term::ANSIColor qw(:constants colored);
$Term::ANSIColor::AUTORESET = 1;

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
-v             Be verbose. May be repeated for increased verbosity.
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
die "$usage\n\n" if $help;

my $crms = CRMS->new(
    sys      => 'crmsworld',
    verbose  => $verbose,
    instance => $instance
);

print "Verbosity $verbose\n" if $verbose;
$crms->set('noop', 1) if $noop;

my ($workbook, $worksheet);
my $wsrow = 1;
if ($excel)
{
  require Excel::Writer::XLSX;
  my $excelpath = $crms->FSPath('prep', $excel);
  my @cols = ('ID', 'Author', 'Title', 'Pub Date', 'Current Rights',
              'Extracted Dates', 'Predictions', 'Action', 'Message');
  $workbook  = Excel::Writer::XLSX->new($excelpath);
  $worksheet = $workbook->add_worksheet();
  $worksheet->write_string(0, $_, $cols[$_]) for (0 .. scalar @cols - 1);
}

my $nyp = $crms->SimpleSqlGet('SELECT id FROM projects WHERE name="New Year"');
die "Can't get New Year project" unless defined $nyp;
$year = $crms->GetTheYear() unless $year;
my $sql = 'SELECT e.id,e.gid,e.time,e.attr,e.reason FROM exportdata e'.
          #' INNER JOIN bibdata b ON e.id=b.id'.
          ' WHERE (e.attr="pdus" OR e.attr="ic" OR e.attr="icus")'.
          #' AND b.pub_date="1923-01-01"'.
          ' AND e.exported=1 AND e.src="candidates" AND YEAR(DATE(e.time))<?'.
          ' AND e.id NOT IN (SELECT id FROM queue)'.
          ' AND e.id NOT IN (SELECT DISTINCT id FROM exportdata WHERE project=?)';
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
print "$sql, $year\n" if $verbose > 1;
my $ref = $crms->SelectAll($sql, $year, $nyp);
my %seen;
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
  my ($acurr,$rcurr,$src,$usr,$time,$note) = @{$rq->[0]};
  next if $acurr eq 'pd';
  my $gid = $row->[1];
  my $time = $row->[2];
  $seen{$id} = 1;
  #my $msg = '';
  $sql = 'SELECT renDate,renNum,category,note,user FROM historicalreviews'.
         ' WHERE gid=? AND validated=1 AND renDate IS NOT NULL';
  my $ref2 = $crms->SelectAll($sql, $gid);
  my $n = scalar @{$ref2};
  next unless $n > 0;
  my %alldates;
  my %predictions;
  my $bogus;
  foreach my $row2 (@{$ref2})
  {
    my $pub;
    my %dates = ();
    my $renDate = $row2->[0];
    $dates{$renDate} = 1 if $renDate;
    my $renNum = $row2->[1];
    my $cat = $row2->[2];
    my $note = $row2->[3];
    my $user = $row2->[4];
    my @matches = $note =~ /(?<!\d)1\d\d\d(?![\d\-])/g;
    my $crown = $crms->TolerantCompare($cat, 'Crown Copyright');
    foreach my $match (@matches)
    {
      $dates{$match} = 1 if length $match and $match < $year;
    }
    foreach $renDate (sort keys %dates)
    {
      my $rid = $crms->PredictRights($id, $renDate, $renNum,
                                     $crown, $record, undef, $year);
      if (!defined $rid)
      {
        $bogus = 1;
        last;
      }
      my ($pa, $pr) = $crms->TranslateAttrReasonFromCode($rid);
      $predictions{"$pa/$pr"} = 1;
    }
    $alldates{$_} = 1 for keys %dates;
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
      # Returns a status code (0=Add, 1=Error, 2=Skip, 3=Modify) followed by optional text.
      my $res = $crms->AddItemToQueueOrSetItemActive($id, 0, 1, 'newyear', undef, $record, $nyp);
      my $code = $res->{'status'};
      my $msg = $res->{'msg'};
      if ($code eq '1' || $code eq '2')
      {
        print ($code == 1)? RED:GREEN "Result for $id: $code $msg\n" if $verbose;
        $msg = '' if $code == 2;
      }
      else
      {
        $msg = '';
      }
      my ($a, $r) = split m/\//, $action;
      $a = $crms->TranslateAttr($a);
      $r = $crms->TranslateReason($r);
      my $note = "New Year $year";
      my $result = $crms->SubmitReview($id, 'autocrms', $a, $r, $note,
                                       undef, 1, undef, 'Expert Note', 1);
      $msg = 'Could not submit review' if $result == 0;
      if ($excel)
      {
        $worksheet->write_string($wsrow, 0, $id);
        $worksheet->write_string($wsrow, 1, $record->author || '');
        $worksheet->write_string($wsrow, 2, $record->title || '');
        $worksheet->write_string($wsrow, 3, $record->copyrightDate || '');
        $worksheet->write_string($wsrow, 4, "$acurr/$rcurr");
        $worksheet->write_string($wsrow, 5, join(',', sort keys %alldates));
        $worksheet->write_string($wsrow, 6, join(',', sort keys %predictions));
        $worksheet->write_string($wsrow, 7, $action);
        $worksheet->write_string($wsrow, 8, $msg);
        $wsrow++;
      }
    }
  }
}

$workbook->close();
print RED "Warning: $_\n" for @{$crms->GetErrors()};

