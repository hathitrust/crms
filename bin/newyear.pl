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
if ($excel) {
  require Excel::Writer::XLSX;
  my $excelpath = $crms->FSPath('prep', $excel);
  my @cols = ('ID', 'Project', 'Author', 'Title', 'Pub Date', 'Country', 'Current Rights',
              'Extracted Data', 'Predictions', 'New Rights', 'Message');
  $workbook  = Excel::Writer::XLSX->new($excelpath);
  $worksheet = $workbook->add_worksheet();
  $worksheet->write_string(0, $_, $cols[$_]) for (0 .. scalar @cols - 1);
}

my $nyp = $crms->SimpleSqlGet('SELECT id FROM projects WHERE name="New Year"');
my $commonwealth_pid = $crms->SimpleSqlGet('SELECT id FROM projects WHERE name="Commonwealth"');
my $pubdate_pid = $crms->SimpleSqlGet('SELECT id FROM projects WHERE name="Publication Date"');
my $crown_copyright_pid = $crms->SimpleSqlGet('SELECT id FROM projects WHERE name="Crown Copyright"');
die "Can't get New Year project" unless defined $nyp;
die "Can't get Commonwealth project" unless defined $commonwealth_pid;
die "Can't get Publication Date project" unless defined $pubdate_pid;
die "Can't get Publication Date project" unless defined $crown_copyright_pid;
my $nyp_ref = $crms->GetProjectRef($nyp);
$year = $crms->GetTheYear() unless $year;
my $pdus_cutoff_year = $year - 95;
my $pd_cutoff_year = $year - 125;
my $jsonxs = JSON::XS->new->utf8;
ProcessCommonwealthProject();
ProcessPubDateProject();
ProcessCrownCopyrightProject();

sub ProcessCommonwealthProject {
  my $sql = 'SELECT e.id,e.gid,e.time,e.attr,e.reason FROM exportdata e'.
            ' WHERE (e.attr="pdus" OR e.attr="ic" OR e.attr="icus")'.
            ' AND e.exported=1 AND e.project=? AND YEAR(DATE(e.time))<?'.
            ' AND e.id NOT IN (SELECT id FROM queue)';
  if (scalar @singles) {
    $sql .= sprintf(" AND e.id IN ('%s')", join "','", @singles);
  }
  if (scalar @excludes) {
    $sql .= sprintf(" AND NOT e.id IN ('%s')", join "','", @excludes);
  }
  $sql .= ' ORDER BY e.time DESC';
  print Utilities::StringifySql($sql, $commonwealth_pid, $year). "\n" if $verbose > 1;
  my $ref = $crms->SelectAll($sql, $commonwealth_pid, $year);
  my %seen;
  printf "Checking %d possible Commonwealth determinations…\n", scalar @$ref;
  foreach my $row (@{$ref}) {
    my $id = $row->[0];
    next if $seen{$id};
    my $rq = $crms->RightsQuery($id, 1);
    if (!defined $rq) {
      print RED "No rights available for $id, skipping.\n";
      next;
    }
    my ($acurr, $rcurr, $src, $usr, $timecurr, $note) = @{$rq->[0]};
    next if $acurr eq 'pd' or $acurr =~ m/^cc/;
    my $record = $crms->GetMetadata($id);
    next unless defined $record;
    my $gid = $row->[1];
    my $time = $row->[2];
    $seen{$id} = 1;
    $sql = 'SELECT r.note,r.user,d.data FROM historicalreviews r'.
           ' INNER JOIN reviewdata d ON r.data=d.id'.
           ' WHERE r.gid=? AND r.validated=1 AND r.data IS NOT NULL';
    my $ref2 = $crms->SelectAll($sql, $gid);
    next if scalar @$ref2 == 0;
    my %alldates;
    my %predictions;
    my $bogus;
    foreach my $row2 (@{$ref2}) {
      my $note = $row2->[0] || '';
      my $user = $row2->[1];
      my $data = $row2->[2];
      #print "$gid: $data\n";
      $data = $jsonxs->decode($data);
      my $date = $data->{'date'};
      my $pub = $data->{'pub'};
      my $crown = $data->{'crown'};
      my $dates = [];
      push @$dates, [$date, $pub] if defined $date;
      my @matches = $note =~ /(?<!\d)1\d\d\d(?![\d\-])/g;
      foreach my $match (@matches) {
        push @$dates, [$match, 0] if length $match and $match < $year;
      }
      foreach my $date (@$dates) {
        my $rid = $crms->PredictRights($id, $date->[0], $date->[1],
                                       $crown, $record, undef, $year);
        if (!defined $rid) {
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
    foreach my $pred (keys %predictions) {
      $ic = $pred if $pred =~ m/^ic\//;
      $icus = $pred if $pred =~ m/^icus/;
      $pd = $pred if $pred =~ m/^pd\//;
      $pdus = $pred if $pred =~ m/^pdus/;
    }
    if (scalar keys %predictions && !defined $ic && ($icus || $pd || $pdus)) {
      my $new_rights;
      if (defined $pd) {
        $new_rights = ($acurr eq 'pd')? undef:$pd;
      }
      if (defined $pdus) {
        $new_rights = ($acurr =~ m/^pd/)? undef:$pdus;
      }
      if (defined $icus) {
        $new_rights = ($acurr =~ m/^pd/ || $acurr =~ m/^icus/)? undef:$icus;
      }
      if (defined $new_rights) {
        my ($a, $r) = split m/\//, $new_rights;
        SubmitNewYearReview($id, $a, $r, 'Commonwealth', $record,
                            join(',', sort keys %alldates),
                            join(',', sort keys %predictions));
      }
    }
  }
}

sub ProcessPubDateProject
{
  my $sql = 'SELECT id,gid FROM exportdata e WHERE e.project=?'.
            ' AND e.attr!="und" AND e.attr!="pd"'.
            ' AND e.exported=1'.
            ' AND e.id NOT IN (SELECT id FROM queue)';
  if (scalar @singles) {
    $sql .= sprintf(" AND e.id IN ('%s')", join "','", @singles);
  }
  if (scalar @excludes) {
    $sql .= sprintf(" AND NOT e.id IN ('%s')", join "','", @excludes);
  }
  $sql .= ' ORDER BY e.time DESC';
  print Utilities::StringifySql($sql, $pubdate_pid). "\n" if $verbose > 1;
  my $ref = $crms->SelectAll($sql, $pubdate_pid);
  printf "Checking %d possible Publication Date determinations…\n", scalar @$ref;
  foreach my $row (@$ref) {
    my $id = $row->[0];
    $sql = 'SELECT COUNT(*) FROM exportdata e INNER JOIN projects p ON e.project=p.id'.
           ' WHERE e.id=? AND p.name="Special"';
    my $special_review = $crms->SimpleSqlGet($sql, $id);
    next if $special_review;
    my $gid = $row->[1];
    $sql = 'SELECT data FROM historicalreviews WHERE gid=? AND data IS NOT NULL AND validated=1';
    my $ref2 = $crms->SelectAll($sql, $gid);
    next unless scalar @$ref2;
    my %dates = ();
    my %extracted_data = (); 
    foreach my $row2 (@$ref2) {
      my $did = $row2->[0];
      my $data = $crms->SimpleSqlGet('SELECT data FROM reviewdata WHERE id=?', $did);
      $extracted_data{$data} = 1 if defined $data;
      my $json = $jsonxs->decode($data);
      my $date = $json->{'date'};
      $date =~ s/^\s+|\s+$//g;
      $dates{$date} = $date if defined $date;
    }
    my $date_str = join ', ', keys %dates;
    if (scalar keys %dates == 1) {
      my $rq = $crms->RightsQuery($id, 1);
      if (!defined $rq) {
        print RED "No rights available for $id, skipping.\n";
        next;
      }
      my ($acurr, $rcurr, $src, $usr, $timecurr, $note) = @{$rq->[0]};
      next if $acurr eq 'pd' or $acurr =~ m/^cc/;
      my $record = $crms->GetMetadata($id);
      if (!defined $record) {
        #print RED "Unable to get metadata for $id\n";
        next;
      }
      my $date = (keys %dates)[0];
      if ($date =~ m/^\d\d\d\d-(\d\d\d\d)$/) {
        $date = $1;
      }
      my $attr = undef;
      if ($date <= $pd_cutoff_year - 1) {
        $attr = 'pd';
      }
      elsif ($date <= $pdus_cutoff_year - 1) {
        $attr = 'pdus';
      }
      if (defined $attr && $attr ne $acurr) {
        SubmitNewYearReview($id, $attr, 'cdpp', 'Publication Date', $record,
                            join(',', sort keys %extracted_data), '');
      }
    }
  }
}

sub ProcessCrownCopyrightProject {
  my $sql = 'SELECT e.id,e.gid,e.time,e.attr,e.reason FROM exportdata e'.
            ' WHERE (e.attr="ic" OR e.attr="icus")'.
            ' AND e.exported=1 AND e.project=? AND YEAR(DATE(e.time))<?'.
            ' AND e.id NOT IN (SELECT id FROM queue)';
  if (scalar @singles) {
    $sql .= sprintf(" AND e.id IN ('%s')", join "','", @singles);
  }
  if (scalar @excludes) {
    $sql .= sprintf(" AND NOT e.id IN ('%s')", join "','", @excludes);
  }
  $sql .= ' ORDER BY e.time DESC';
  print Utilities::StringifySql($sql, $crown_copyright_pid, $year). "\n" if $verbose > 1;
  my $ref = $crms->SelectAll($sql, $crown_copyright_pid, $year);
  my %seen;
  printf "Checking %d possible Crown Copyright determinations…\n", scalar @$ref;
  foreach my $row (@{$ref}) {
    my $id = $row->[0];
    next if $seen{$id};
    my $rq = $crms->RightsQuery($id, 1);
    if (!defined $rq) {
      print RED "No rights available for $id, skipping.\n";
      next;
    }
    my ($acurr, $rcurr, $src, $usr, $timecurr, $note) = @{$rq->[0]};
    next if $acurr eq 'pd' or $acurr =~ m/^cc/;
    my $record = $crms->GetMetadata($id);
    next unless defined $record;
    my $gid = $row->[1];
    my $time = $row->[2];
    $seen{$id} = 1;
    $sql = 'SELECT r.note,r.user,d.data FROM historicalreviews r'.
           ' INNER JOIN reviewdata d ON r.data=d.id'.
           ' WHERE r.gid=? AND r.validated=1 AND r.data IS NOT NULL';
    my $ref2 = $crms->SelectAll($sql, $gid);
    next unless scalar @$ref2 > 0;
    my %alldates;
    my %predictions = ();
    my %dates = ();
    my $bogus = 0;
    foreach my $row2 (@{$ref2}) {
      my $note = $row2->[0] || '';
      my $user = $row2->[1];
      my $data = $row2->[2];
      $data = $jsonxs->decode($data);
      my $date = $data->{'date'};
      $date =~ s/^\s+|\s+$//g;
      $dates{$date} = $date if defined $date;
      foreach my $date (keys %dates) {
        my $rid = $crms->PredictRights($id, $date, 1, 1, $record, undef, $year);
        if (!defined $rid) {
          $bogus = 1;
          last;
        }
        my ($pa, $pr) = $crms->TranslateAttrReasonFromCode($rid);
        $predictions{"$pa/$pr"} = 1;
      }
      $alldates{$_} = 1 for keys %dates;
    }
    print RED "  BOGUS rights code '$bogus'\n" if $bogus;
    next if $bogus;
    my ($ic, $icus, $pd, $pdus);
    foreach my $pred (keys %predictions) {
      $ic = $pred if $pred =~ m/^ic\//;
      $icus = $pred if $pred =~ m/^icus/;
      $pd = $pred if $pred =~ m/^pd\//;
      $pdus = $pred if $pred =~ m/^pdus/;
    }
    if (scalar keys %predictions && !defined $ic && ($icus || $pd || $pdus)) {
      my $new_rights;
      if (defined $pd) {
        $new_rights = ($acurr eq 'pd')? undef:$pd;
      }
      if (defined $pdus) {
        $new_rights = ($acurr =~ m/^pd/)? undef:$pdus;
      }
      if (defined $icus) {
        $new_rights = ($acurr =~ m/^pd/ || $acurr =~ m/^icus/)? undef:$icus;
      }
      if (defined $new_rights) {
        my ($a, $r) = split m/\//, $new_rights;
        SubmitNewYearReview($id, $a, $r, 'Crown Copyright', $record,
                            join(',', sort keys %alldates),
                            join(',', sort keys %predictions));
      }
    }
  }
}

sub SubmitNewYearReview
{
  my $id             = shift;
  my $new_attr       = shift;
  my $new_reason     = shift;
  my $project_name   = shift;
  my $record         = shift;
  my $extracted_data = shift;
  my $predictions    = shift;

  $crms->UpdateMetadata($id, 1, $record);
  my $res = $crms->AddItemToQueueOrSetItemActive($id, 0, 1, 'newyear', undef, $record, $nyp);
  my $code = $res->{'status'};
  my $msg = $res->{'msg'};
  if ($code eq '1' || $code eq '2') {
    if ($verbose) {
      print GREEN "Result for $id: $code $msg\n" if $code == 0;
      print RED "Result for $id: $code $msg\n" if $code == 1;
    }
    $msg = '' if $code == 2;
  }
  else {
    $msg = '';
  }
  my $rights = $crms->GetCodeFromAttrReason($crms->TranslateAttr($new_attr),
                                            $crms->TranslateReason($new_reason));
  die "Can't get rights code from $new_attr/$new_reason\n" unless defined $rights;
  my $params = {'rights' => $rights,
                'note' => "New Year $year",
                'category' => 'Expert Note'};
  my $result = $crms->SubmitReview($id, 'autocrms', $params, $nyp_ref);
  if ($result) {
    print RED "SubmitReview() for $id: $result\n";
  }
  if ($excel) {
    my $rq = $crms->RightsQuery($id, 1);
    my ($acurr, $rcurr, $src, $usr, $timecurr, $note) = @{$rq->[0]};
    $worksheet->write_string($wsrow, 0, $id);
    $worksheet->write_string($wsrow, 1, $project_name);
    $worksheet->write_string($wsrow, 2, $record->author || '');
    $worksheet->write_string($wsrow, 3, $record->title || '');
    $worksheet->write_string($wsrow, 4, $record->copyrightDate || '');
    $worksheet->write_string($wsrow, 5, $record->country || '');
    $worksheet->write_string($wsrow, 6, "$acurr/$rcurr");
    $worksheet->write_string($wsrow, 7, $extracted_data);
    $worksheet->write_string($wsrow, 8, $predictions);
    $worksheet->write_string($wsrow, 9, "$new_attr/$new_reason");
    $worksheet->write_string($wsrow, 10, $msg);
    print GREEN "Worksheet row $wsrow written\n";
    $wsrow++;
  }
}

$workbook->close() if $excel;

print RED "Warning: $_\n" for @{$crms->GetErrors()};

