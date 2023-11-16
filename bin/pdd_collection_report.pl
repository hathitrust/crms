#!/usr/bin/perl

use strict;
use warnings;
use utf8;
use v5.10;

BEGIN {
  die "SDRROOT environment variable not set" unless defined $ENV{'SDRROOT'};
  use lib $ENV{'SDRROOT'} . '/crms/cgi';
}

use Getopt::Long qw(:config no_ignore_case bundling);
use Term::ANSIColor qw(:constants colored);

use CRMS;

$Term::ANSIColor::AUTORESET = 1;
binmode(STDOUT, ':encoding(UTF-8)');
my $usage = <<END;
USAGE: $0 [-hv] [-y YEAR]

Reports to STDOUT all HTIDs with a publication/copyright date of the current YEAR - 96,
minus any with "permanently closed" rights attributes {pd-pvt, nobody, supp}.

Uses the crms.bib_rights_bri table which is kept up-to-date by a nightly script.
This could be done with the ht.hf (HathiFiles metadata) table, but since there are
some discrepancies between crms.bib_rights_bri.date_used and ht.hf.bib_date_used
I am using the former because I understand it better.

NOTE: this script should take no more than a couple of minutes to run.

-h         Print this help message.
-v         Emit verbose debugging information. May be repeated.
-y YEAR    Use this YEAR instead of the current one.
END


my $help;
my $instance;
my $verbose;
my $year;

Getopt::Long::Configure('bundling');
die 'Terminating' unless GetOptions(
           'h|?'  => \$help,
           'v+'   => \$verbose,
           'y:s'  => \$year);

if ($help) { print $usage. "\n"; exit(0); }

my $crms = CRMS->new(
  verbose  => $verbose,
  instance => 'production'
);

$verbose = 0 unless defined $verbose;
print "Verbosity $verbose\n" if $verbose;
$year = $crms->GetTheYear() unless $year;
my $target_date = $year - 96;
print "Using copyright date $target_date from $year\n" if $verbose;

# First get a hash of all HTIDs with rights attribute {nobody, pd-pvt, supp}
# This so we need not JOIN with CONCAT(rights_current.namespace,".",rights_current.id)
# which really slows things down and is a PITA.
# There should be between 10k and 20k of these excludes.
my $excludes = {};
my $sql = <<'SQL';
SELECT CONCAT(rc.namespace,".",rc.id),attr.name FROM rights_current rc
INNER JOIN attributes attr ON rc.attr=attr.id
WHERE attr.name IN ('nobody','pd-pvt','supp')
SQL

my $ref = $crms->SelectAllSDR($sql);
my $n = scalar @{$ref};
print "$n results for {nobody, pd-pvt, supp}\n" if $verbose;
foreach my $row (@$ref) {
  $excludes->{$row->[0]} = $row->[1];
}

# Now get everything from our local bib rights database that has a "date used" of
# YEAR - 96. Print these out in order, excluding anything in the rights exclusion list.
$sql = <<'SQL';
SELECT id FROM bib_rights_bri
WHERE date_used=?
ORDER BY id
SQL

$ref = $crms->SelectAll($sql, $target_date);
foreach my $row (@$ref) {
  my $htid = $row->[0];
  my $attr = $excludes->{$htid};
  if (defined $attr) {
    print RED "Skipping $htid ($attr)\n" if $verbose;
  } else {
    say $htid;
  }
}

print "Warning: $_\n" for @{$crms->GetErrors()};
