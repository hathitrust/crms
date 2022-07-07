#!/usr/bin/perl

use strict;
use warnings;
BEGIN {
  unshift(@INC, $ENV{'SDRROOT'}. '/crms/cgi');
  unshift(@INC, $ENV{'SDRROOT'}. '/crms/post_zephir_processing');
  # For local copies of MARC::Record code if otherwise unavailable
  unshift(@INC, $ENV{'SDRROOT'}. '/crms/bib_rights/lib');
}

use CRMS;
use Encode;
use Getopt::Long;
use IO::Zlib;
use Data::Dumper;
use bib_rights;
use MARC::Record;
use MARC::Record::MIJ;
use Term::ANSIColor qw(:constants colored);
$Term::ANSIColor::AUTORESET = 1;

$| = 1;

my $usage = <<END;
USAGE: $0 [-hnpv] [-m MAIL [-m MAIL2...]]

Updates the bib_rights_bi (bib information) and bib_rights_bri (bib rights information)
tables based on Zephir files of the form
/htapps/archive/catalog/zephir_full_YYYYMMDD_vufind.json.gz (last day of month)
and
/htapps/archive/catalog/zephir_upd_YYYYMMDD.json.gz (daily)

Importing the monthly files is extremely time-consuming, so each daily run
is expected to only process a portion of the catalog file.
I estimate this script can import about 400k records per hour.

To store import state, systemvars.lastCatalogImport contains the name of the
most recent full catalog dump completely or partially ingested.
systemvars.lastCatalogImportCount is the number of records ingested from
systemvars.lastCatalogImport -- absence of this data altogether means
systemvars.lastCatalogImport is complete.
systemvars.lastCatalogUpdate contains the most recent delta completely ingested.
We assume that deltas can be ingested all in one go, so we don't time out
the process or accommodate its resumption.

-h       Print this help message.
-m MAIL  Mail a report to MAIL. May be repeated for multiple addresses.
-n       No-op. Do not modify the CRMS database.
-p       Run in production.
-s SECS  Run importer for SECS seconds, rather than the default 600.
-v       Emit verbose debugging information. May be repeated.
END

my $help;
my $instance;
my @mails;
my $noop;
my $production;
my $secs;
my $verbose;

Getopt::Long::Configure ('bundling');
die 'Terminating' unless GetOptions(
           'h|?' => \$help,
           'm:s@' => \@mails,
           'n' => \$noop,
           'p' => \$production,
           's:s' => \$secs,
           'v+' => \$verbose);
$instance = 'production' if $production;
if ($help) { print $usage. "\n"; exit(0); }
print "Verbosity $verbose\n" if $verbose;

my $crms = CRMS->new(
    verbose  => $verbose,
    instance => $instance
);

$secs = 600 unless defined $secs;
$crms->set('noop', 1) if $noop;

my $report = '';
my $catalogPath = '';
my $fileToProcess;
my $lastCount = 0;
my $lastUpdate = 0;
my $type = 'full';

my $sql = 'SELECT COUNT(*) FROM systemvars WHERE name=?';
if ($crms->SimpleSqlGet($sql, 'catalogUpdateInProgress')) {
  exit(0);
}

if (scalar @ARGV && -e $ARGV[0]) {
  $fileToProcess = $ARGV[0];
  $report .= "Using $fileToProcess from command line\n";
  $type = 'manual';
} else {
  my $lastFull = $crms->GetSystemVar('lastCatalogImport');
  my $lastDate;
  if (defined $lastFull && $lastFull =~ m/^zephir_full_(\d{8})_vufind.json.gz$/i) {
    $lastDate = $1;
  }
  $lastCount = $crms->GetSystemVar('lastCatalogImportCount');
  $lastUpdate = $crms->GetSystemVar('lastCatalogUpdate');
  if (defined $lastUpdate && $lastUpdate =~ m/^zephir_upd_(\d{8}).json.gz$/i) {
    $lastDate = $1 if $1 gt $lastDate;
  }
  $catalogPath = '/htapps/archive/catalog/';

  opendir(DIR, "$catalogPath") or die "Can't open $catalogPath\n";
  my @files = sort readdir(DIR);
  closedir(DIR);

  my $nextImportFile;
  my $nextUpdateFile;
  foreach my $file (@files)
  {
    my $date;
    if ($file =~ m/^zephir_full_(\d{8})_vufind\.json\.gz$/i &&
        (!defined $lastFull || $file gt $lastFull)) {
      $date = $1;
      $nextImportFile = $file;
    }
    if ($file =~ m/^zephir_upd_(\d{8})\.json\.gz$/i && !defined $nextUpdateFile) {
      $date = $1;
      if (defined $lastDate && $date gt $lastDate) {
        $nextUpdateFile = $file;
      }
    }
  }
  $report .= sprintf "Next import %s, next update %s\n",
                     (defined $nextImportFile)? $nextImportFile:'[undef]',
                     (defined $nextUpdateFile)? $nextUpdateFile:'[undef]';

  # If there is a newer full file, abandon last file and start over with this one.
  # Otherwise, if the most recent full dump is incomplete (systemvars.lastCatalogImportCount
  # is present) then continue to work on that.
  # Otherwise ingest the oldest update file after systemvars.lastCatalogUpdate
  # (if it exists) without a timeout.
  if (defined $nextImportFile) {
    $report .=  "Moving on to next full import $nextImportFile<br/>\n";
    $fileToProcess = $nextImportFile;
    $lastCount = 0;
  }
  elsif (defined $lastCount) {
    $report .=  "Continuing $lastFull at $lastCount<br/>\n";
    $fileToProcess = $lastFull;
  }
  elsif (defined $nextUpdateFile) {
    $report .= "Beginning update $nextUpdateFile<br/>\n";
    $fileToProcess = $nextUpdateFile;
    $type = 'update';
  }
}

# De-spam the output of this script.
exit(0) unless defined $fileToProcess;

my $alarmFired = 0;
local $SIG{ALRM} = sub { $report .= "ALARM FIRED<br/>\n"; $alarmFired = 1; };
local $SIG{TERM} = sub { $report .= "TERM signal received<br/>\n"; cleanup(); };
local $SIG{INT} = sub { $report .= "INT signal received<br/>\n"; cleanup(); };

$sql = 'REPLACE INTO systemvars (name,value) VALUES (?,1)';
$crms->PrepareSubmitSql($sql, 'catalogUpdateInProgress');

my $br = bib_rights->new();
$report .= "<b>Importing from $fileToProcess</b><br/>\n";
my $fh = new IO::Zlib;
my $i = 0;
my $done = 0;
if ($fh->open($catalogPath. $fileToProcess, 'rb')) {
  if (defined $lastCount && $lastCount > 0) {
    $report .= "Skipping $lastCount records...<br/>\n";
    for (my $j = 0; $j < $lastCount; $j++) {
      $fh->getline();
    }
  }
  my $t1 = Time::HiRes::time();
  alarm $secs if $type eq 'full';
  while (1) {
    last if $alarmFired;
    my $sysid = undef;
    my $f_008 = undef;
    my $record = $fh->getline();
    if (!defined $record) {
      $report .= "Finished reading gzip file.<br/>\n";
      $done = 1;
      last;
    }
    process_record($record);
    $i++;
  }
  my $t2 = Time::HiRes::time();
  my $secs = $t2 - $t1;
  $report .= sprintf("Took %.2f seconds to import $i records, %f records per second<br/>\n",
                     $secs, $i/$secs);
  $fh->close;
}

record_progress();
cleanup();

$report .= "<i>Warning: $_</i><br/>\n" for @{$crms->GetErrors()};

if (scalar @mails) {
  my $subj = $crms->SubjectLine('Catalog Update');
  @mails = map { ($_ =~ m/@/)? $_:($_ . '@umich.edu'); } @mails;
  my $bytes = encode('utf8', $report);
  my $to = join ',', @mails;
  use Mail::Sendmail;
  my %mail = (
    'from'         => $crms->GetSystemVar('senderEmail'),
    'to'           => $to,
    'subject'      => $subj,
    'content-type' => 'text/html; charset="UTF-8"',
    'body'         => $bytes
  );
  sendmail(%mail) || die("Error: $Mail::Sendmail::error\n");
} else {
  $report =~ s/<br\/>//g;
  print "$report\n";
}

sub record_progress {
  if ($done) {
    $sql = 'DELETE FROM systemvars WHERE name=?';
    $crms->PrepareSubmitSql($sql, 'lastCatalogImportCount');
  } else {
    if (defined $lastCount) {
      $sql = 'REPLACE INTO systemvars (name,value) VALUES (?,?)';
      $crms->PrepareSubmitSql($sql, 'lastCatalogImportCount', $lastCount + $i);
    }
  }
  if ($fileToProcess =~ m/^zephir_full.*?\.gz$/i) {
    $sql = 'REPLACE INTO systemvars (name,value) VALUES (?,?)';
    $crms->PrepareSubmitSql($sql, 'lastCatalogImport', $fileToProcess);
  } else {
    $sql = 'REPLACE INTO systemvars (name,value) VALUES (?,?)';
    $crms->PrepareSubmitSql($sql, 'lastCatalogUpdate', $fileToProcess);
  }
}

sub cleanup {
  $report .= "Deleting catalogUpdateInProgress flag...<br/>\n";
  $sql = 'DELETE FROM systemvars WHERE name=?';
  $crms->PrepareSubmitSql($sql, 'catalogUpdateInProgress');
  $sql = 'SELECT COUNT(*) FROM systemvars WHERE name=?';
  if ($crms->SimpleSqlGet($sql, 'catalogUpdateInProgress') > 0) {
    $report .= "<b>HUH? systemvars.catalogUpdateInProgress is still there??</b><br/>\n";
  } else {
    $report .= "<b>systemvars.catalogUpdateInProgress removed</b><br/>\n";
  }
}

sub process_record {
  my $record = shift;

  my $marc;
  eval { $marc = MARC::Record->new_from_mij($record); };
  if ($@) {
    $crms->SetError("problem processing MARC JSON: $record\n");
    return;
  }
  my $catalog_id = $marc->field('001')->as_string;
  my $bib_info = $br->get_bib_info($marc, $catalog_id);
  # Get HTID and enumcron from 974u and 974z respectively
  my @fields = $marc->field('974');
  foreach my $field (@fields) {
    my $htid = $field->subfield('u');
    if (!$htid) {
      $report .= "WARNING: can't get HTID for $catalog_id<br/>\n";
      next;
    }
    my $enumcron = $field->subfield('z') || '';
    my $bib_rights_info = $br->get_bib_rights_info($htid, $bib_info, $enumcron);
    my @bib_rights_info_keys = keys %$bib_rights_info;
    my $sql = sprintf 'REPLACE INTO bib_rights_bri (%s) VALUES %s',
      join(',', map {"`$_`"; } @bib_rights_info_keys), $crms->WildcardList(scalar @bib_rights_info_keys);
    $crms->PrepareSubmitSql($sql, map { $bib_rights_info->{$_}; } @bib_rights_info_keys);
  }
  my @bib_info_keys = keys %$bib_info;
  my $sql = sprintf 'REPLACE INTO bib_rights_bi (%s) VALUES %s',
    join(',', @bib_info_keys), $crms->WildcardList(scalar @bib_info_keys);
  $crms->PrepareSubmitSql($sql, map { $bib_info->{$_}; } @bib_info_keys);
  $report .= "Warning: $_<br/>\n" for @{$crms->GetErrors()};
  $crms->ClearErrors();
}
