#!/usr/bin/perl

use strict;
use warnings;
use utf8;

BEGIN {
  die "SDRROOT environment variable not set" unless defined $ENV{'SDRROOT'};
  use lib $ENV{'SDRROOT'} . '/crms/cgi';
  use lib $ENV{'SDRROOT'} . '/crms/lib';
}

use Getopt::Long qw(:config no_ignore_case bundling);

use CRMS;
use CRMS::CollectionBuilder;

binmode(STDOUT, ':encoding(UTF-8)');
my $usage = <<END;
USAGE: $0 [-hv] [-y YEAR] [-V VISIBILITY]

Creates a collection for the upcoming public domain rollover on January 1 of YEAR.
Intended to be run by a cron job in November of YEAR - 1. (So the default -y YEAR
value used internally is current year plus one.)

First creates a text file of non-US HTIDs HTIDs with a publication/copyright date of the current YEAR - 126,
minus any with "permanently closed" rights attributes {pd-pvt, nobody, supp}.

Then, uses mb/scripts/batch-collection.pl to create a collection based on the report.

This is similar to the logic in pdd_collection.pl except it uses an earlier cutoff
date, and it uses the 008-derived value in bib_rights_bi.pub_place to exclude US publications.

Uses the crms.bib_rights_bi and crms.bib_rights_bri tables which is kept up-to-date by a nightly script.
This could be done with the ht.hf (HathiFiles metadata) table, but since there are
some discrepancies between crms.bib_rights_bri.date_used and ht.hf.bib_date_used
I am using the former because I understand it better.

Note: the Collection Builder component of this script runs long and should be invoked with nohup.

-h             Print this help message.
-v             Emit verbose debugging information. May be repeated.
-V VISIBILITY  Set collection to VISIBILITY (in {public, private, draft}). Default "private".
-y YEAR        Use this YEAR instead of the current one.
END


my $help;
my $instance;
my $verbose;
my $visibility;
my $year;

Getopt::Long::Configure('bundling');
die 'Terminating' unless GetOptions(
           'h|?'  => \$help,
           'v+'   => \$verbose,
           'V:s'  => \$visibility,
           'y:s'  => \$year);

if ($help) { print $usage. "\n"; exit(0); }

my $crms = CRMS->new(
  verbose  => $verbose,
  instance => 'production'
);

$verbose = 0 unless defined $verbose;
print "Verbosity $verbose\n" if $verbose;
$year = $crms->GetTheYear() + 1 unless $year;
my $target_date = $year - 126;
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
# YEAR - 126 and non-US pub place.
# Print these out in order, excluding anything in the rights exclusion list.
$sql = <<'SQL';
SELECT bri.id,bi.pub_place FROM bib_rights_bi bi
INNER JOIN bib_rights_bri bri
ON bi.bib_key=bri.bib_key
WHERE bri.date_used=?
AND substr(bi.pub_place,3,1)!='u'
ORDER BY id
SQL

my $outfile = $ENV{'SDRROOT'} . "/crms/prep/pdd_collection_worldwide_$year.txt";
open(my $fh, '>:encoding(UTF-8)', $outfile) or die "Could not open '$outfile' $!";
$ref = $crms->SelectAll($sql, $target_date);
foreach my $row (@$ref) {
  my $htid = $row->[0];
  my $attr = $excludes->{$htid};
  next if defined $attr;
  print $fh "$htid\n";
}
close $fh;

my $title = "Newly Opened Worldwide January $year";
my $cb = CRMS::CollectionBuilder->new;
my $cmd = $cb->create_collection_cmd(
  'title' => $title,
  'description' => "Volumes newly opened to the world as of January 1, $year based on bibliographic data",
  'file' => $outfile
);
print `$cmd`;
$sql = 'SELECT MColl_ID FROM mb_collection WHERE owner_name="HathiTrust" AND collname=?';
my $coll_id = $crms->SimpleSqlGetSDR($sql, $title);
$cmd = $cb->set_visibility_cmd('coll_id' => $coll_id, 'visibility' => $visibility);
print `$cmd`;

print "Warning: $_\n" for @{$crms->GetErrors()};
