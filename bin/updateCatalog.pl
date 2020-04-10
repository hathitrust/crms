#!/usr/bin/perl

use strict;
use warnings;
BEGIN { unshift(@INC, $ENV{'SDRROOT'}. '/crms/cgi'); }

use CRMS;
use Encode;
use Getopt::Long;
use JSON::XS;


my $usage = <<END;
USAGE: $0 [-hnpv] [-m MAIL [-m MAIL2...]]

Updates the catalog table in production based on Zephir files of the form
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
-v       Emit debugging information. May be repeated.
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
print "Verbosity $verbose\n" if $verbose;
die "$usage\n\n" if $help;

my $crms = CRMS->new(
    verbose  => $verbose,
    instance => $instance
);

$secs = 600 unless defined $secs;
$crms->set('noop', 1) if $noop;

my $report = '';

my $lastFull = $crms->GetSystemVar('lastCatalogImport');
my $lastDate;
if (defined $lastFull && $lastFull =~ m/^zephir_full_(\d{8})_vufind.json.gz$/i)
{
  $lastDate = $1;
}
my $lastCount = $crms->GetSystemVar('lastCatalogImportCount');
my $lastUpdate = $crms->GetSystemVar('lastCatalogUpdate');
if (defined $lastUpdate && $lastUpdate =~ m/^zephir_upd_(\d{8}).json.gz$/i)
{
  $lastDate = $1 if $1 gt $lastDate;
}
my $catalogPath = '/htapps/moseshll.babel/';

opendir(DIR, "$catalogPath") or die "Can't open $catalogPath\n";
my @files = sort readdir(DIR);
closedir(DIR);

my $nextImportFile;
my $nextUpdateFile;
foreach my $file (@files)
{
  my $date;
  if ($file =~ m/^zephir_full_(\d{8})_vufind\.json\.gz$/i &&
      (!defined $lastFull || $file gt $lastFull))
  {
    $date = $1;
    $nextImportFile = $file;
  }
  if ($file =~ m/^zephir_upd_(\d{8})\.json\.gz$/i && !defined $nextUpdateFile)
  {
    $date = $1;
    if (defined $lastDate && $date gt $lastDate)
    {
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
my $fileToProcess;
my $type = 'full';
if (defined $nextImportFile)
{
  $report .=  "Moving on to next full import $nextImportFile<br/>\n";
  $fileToProcess = $nextImportFile;
  $lastCount = 0;
}
elsif (defined $lastCount)
{
  $report .=  "Continuing $lastFull at $lastCount<br/>\n";
  $fileToProcess = $lastFull;
}
elsif (defined $nextUpdateFile)
{
  $report .= "Beginning update $nextUpdateFile<br/>\n";
  $fileToProcess = $nextUpdateFile;
  $type = 'update';
}


my $alarmFired = 0;
local $SIG{ALRM} = sub { $report .= "ALARM FIRED<br/>\n"; $alarmFired = 1; };

if (!defined $fileToProcess)
{
  $report .= "<b>No file found to process.</b><br/>\n";
}
else
{
  $report .= "<b>Importing from $fileToProcess</b><br/>\n";
  my $sql = 'SELECT id FROM catalog ORDER BY id DESC LIMIT 1';
  my $max = $crms->SimpleSqlGet($sql);
  $sql = 'SELECT COUNT(*) FROM catalog';
  my $size = $crms->SimpleSqlGet($sql);
  $report .= "MAX ID $max, SIZE $size<br/>";
  use IO::Zlib;
  my $json = JSON::XS->new;
  my $fh = new IO::Zlib;
  my $i = 0;
  my $done = 0;
  if ($fh->open($catalogPath. $fileToProcess, 'rb'))
  {
    if (defined $lastCount && $lastCount > 0)
    {
      $report .= "Skipping $lastCount records...<br/>\n";
      for (my $j = 0; $j < $lastCount; $j++)
      {
        $fh->getline();
      }
    }
    my $t1 = Time::HiRes::time();
    alarm $secs if $type eq 'full';
    while (1)
    {
      last if $alarmFired;
      my $sysid = undef;
      my $f_008 = undef;
      my $buff = $fh->getline();
      if (!defined $buff)
      {
        $report .= "Finished reading gzip file.<br/>\n";
        $done = 1;
        last;
      }
      last unless defined $buff;
      my $obj = $json->decode($buff);
      my $leader = $obj->{'leader'};
      my $fields = $obj->{'fields'};
      foreach my $dict (@$fields)
      {
        foreach my $key (keys %$dict)
        {
          $f_008 = $dict->{$key} if $key eq '008';
          $sysid = $dict->{$key} if $key eq '001';
        }
      }
      if ($leader && $sysid && $f_008)
      {
        $report .= "$sysid: $leader, $f_008<br/>\n" if $i % 1000 == 0;
        $sql = 'REPLACE INTO catalog (id,leader,f_008) VALUES (?,?,?)';
        $crms->PrepareSubmitSql($sql, $sysid, $leader, $f_008);
        $report .= "Warning: $_<br/>\n" for @{$crms->GetErrors()};
        $i++;
      }
      else
      {
        $report .= "ERROR: no sysid, leader, or 008<br/>\n";
        $report .= Dumper $obj;
        $report .= "<br/>\n";
      }
    }
    my $t2 = Time::HiRes::time();
    $sql = 'SELECT id FROM catalog ORDER BY id DESC LIMIT 1';
    my $max2 = $crms->SimpleSqlGet($sql);
    $sql = 'SELECT COUNT(*) FROM catalog';
    my $size2 = $crms->SimpleSqlGet($sql);
    $report .= "MAX ID $max2, SIZE $size2<br/>\n";
    my $secs = $t2 - $t1;
    $report .= sprintf("Took %.2f seconds to import %d records, %f records per second<br/>\n",
                       $secs, $i, $i/$secs);
    $fh->close;
  }
  if ($done)
  {
    $sql = 'DELETE FROM systemvars WHERE name=?';
    $crms->PrepareSubmitSql($sql, 'lastCatalogImportCount');
  }
  else
  {
    if (defined $lastCount)
    {
      $sql = 'REPLACE INTO systemvars (name,value) VALUES (?,?)';
      $crms->PrepareSubmitSql($sql, 'lastCatalogImportCount', $lastCount + $i);
    }
  }
  if ($fileToProcess =~ m/^zephir_full.*?\.gz$/i)
  {
    $sql = 'REPLACE INTO systemvars (name,value) VALUES (?,?)';
    $crms->PrepareSubmitSql($sql, 'lastCatalogImport', $fileToProcess);
  }
  else
  {
    $sql = 'REPLACE INTO systemvars (name,value) VALUES (?,?)';
    $crms->PrepareSubmitSql($sql, 'lastCatalogUpdate', $fileToProcess);
  }
}

$report .= "<i>Warning: $_</i><br/>\n" for @{$crms->GetErrors()};


my $subj = $crms->SubjectLine('Catalog Update');
if (@mails)
{
  @mails = map { ($_ =~ m/@/)? $_:($_ . '@umich.edu'); } @mails;
  my $bytes = encode('utf8', $report);
  my $to = join ',', @mails;
  use Mail::Sendmail;
  my %mail = ('from'         => $crms->GetSystemVar('senderEmail'),
              'to'           => $to,
              'subject'      => $subj,
              'content-type' => 'text/html; charset="UTF-8"',
              'body'         => $bytes
              );
  sendmail(%mail) || die("Error: $Mail::Sendmail::error\n");
}
else
{
  $report =~ s/<br\/>//g;
  print "$report\n";
}


