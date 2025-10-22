#!/usr/bin/perl

use strict;
use warnings;
use utf8;

BEGIN {
  die "SDRROOT environment variable not set" unless defined $ENV{'SDRROOT'};
  use lib $ENV{'SDRROOT'} . '/crms/cgi';
}

use CRMS;
use Getopt::Long;
use Utilities;
use Encode;
use JSON::XS;

my $usage = <<END;
USAGE: $0 [-hlptv] [-m USER [-m USER...]]

One-off script for migrating CRMS-US renNum/renDate information
to reviewdata table.

-h       Print this help message.
-p       Run in production.
-t       Run in training.
-v       Emit verbose debugging information. May be repeated.
END

my $help;
my $instance;
my $production;
my $training;
my $verbose = 0;

Getopt::Long::Configure ('bundling');
die 'Terminating' unless GetOptions('h|?'  => \$help,
           'p'    => \$production,
           't'    => \$training,
           'v+'   => \$verbose);
$instance = 'production' if $production;
$instance = 'crms-training' if $training;
if ($help) { print $usage. "\n"; exit(0); }
print "Verbosity $verbose\n" if $verbose;

my $crms = CRMS->new(
    verbose  => $verbose,
    instance => $instance
);

MigrateUSReviewData();
MigrateUSReviewData(1);

sub MigrateUSReviewData
{
  my $historical = shift;

  my $table = ($historical)? 'historicalreviews':'reviews';
  my $jsonxs = JSON::XS->new->utf8->canonical(1)->pretty(0);
  my $sql = 'SELECT id,user,time,renNum,renDate FROM '. $table. ' WHERE data IS NULL'.
            ' AND renNum IS NOT NULL AND renNum!=""';
  my $ref = $crms->SelectAll($sql);
  foreach my $row (@{$ref})
  {
    my ($id, $user, $time, $renNum, $renDate) = @{$row};
    # renNum or renDate must be defined and nonzero-length for an entry to be made.
    if ((defined $renNum && length $renNum) ||
        (defined $renDate && length $renDate))
    {
      my $data = {'renNum' => $renNum, 'renDate' => $renDate};
      my $encdata = $jsonxs->encode($data);
      $sql = 'SELECT id FROM reviewdata WHERE data=? LIMIT 1';
      my $did = $crms->SimpleSqlGet($sql, $encdata);
      if (!$did)
      {
        $sql = 'INSERT INTO reviewdata (data) VALUES (?)';
        $crms->PrepareSubmitSql($sql, $encdata);
        $sql = 'SELECT MAX(id) FROM reviewdata WHERE data=?';
        $did = $crms->SimpleSqlGet($sql, $encdata);
        $sql = 'SELECT COUNT(*) FROM reviewdata WHERE id=? AND data=?';
        my $count = $crms->SimpleSqlGet($sql, $did, $encdata);
        die "ERROR: data id $did does not match $encdata\n" unless 1 == $count;
      }
      $sql = 'UPDATE '. $table. ' SET data=? WHERE id=? AND user=? AND time=?';
      $crms->PrepareSubmitSql($sql, $did, $id, $user, $time);
    }
  }
}

print "Warning: $_\n" for @{$crms->GetErrors()};
