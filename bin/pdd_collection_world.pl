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

use CRMS::Config;
use CRMS::Database::HT;
use CRMS::CollectionBuilder;

binmode(STDOUT, ':encoding(UTF-8)');
my $usage = <<END;
USAGE: $0 [-h]

Creates a collection for the upcoming public domain rollover on January 1 of YEAR.
Intended to be run by a cron job in November of YEAR - 1.

First creates a text file of non-US HTIDs with a publication/copyright date of YEAR - 126,
minus any with "permanently closed" rights attributes {pd-pvt, nobody, supp}.
These are written to SDRROOT/crms/prep/pdd_world_collection_YEAR.txt

Then, uses mb/scripts/batch-collection.pl to create a collection based on the report.

This is similar to the logic in pdd_collection_us.pl except it uses an earlier cutoff
date, and it uses the 008-derived value in hathifiles.hf.pub_place to exclude US publications.

Note: the Collection Builder component of this script runs long and should be invoked with nohup.

-h             Print this help message.
END


my $help;

Getopt::Long::Configure('bundling');
die 'Terminating' unless GetOptions(
  'h|?'  => \$help,
);

if ($help) { print $usage. "\n"; exit(0); }

my $config = CRMS::Config->new(instance => 'production');
my $cb = CRMS::CollectionBuilder->new;
my $db = CRMS::Database::HT->new;
my $target_year = $cb->pdd_collection_target_year(1);

# Export a file with all htids from hathifiles with a "date used" of
# YEAR - 126 and non-US pub place, excluding "permanently closed" rights.
my $sql = <<'SQL';
SELECT htid FROM hf
WHERE rights_date_used=?
AND rights_code NOT IN ('nobody','pd-pvt','supp')
AND substr(pub_place,3,1)!='u'
ORDER BY htid
SQL

my $collection_size = 0;
my $outfile = File::Spec->catfile($ENV{SDRROOT}, 'crms', 'prep', "pdd_world_collection_$cb->{year}.txt");
open(my $fh, '>:encoding(UTF-8)', $outfile) or die "Could not open '$outfile' $!";
$db->for($sql, $target_year, sub {
  my $row = shift;
  print $fh $row->{htid} . "\n";
  $collection_size++;
});
close $fh;

my $res = $cb->submit_create_collection(
  $cb->pdd_collection_name(1),
  $cb->pdd_collection_description(1),
  $outfile
);
print "Create collection exit code: $res->{status}\n";
if ($res->{status} != 0) {
  print "STDERR $res->{stderr}\n";
  die "Error from Collection Builder, cannot continue.";
}

my $collection = $res->{collection};
print "World collection id: $collection->{MColl_ID}\n";
print "Expected size: $collection_size items\n";
print "Actual size: $collection->{num_items}\n";

# Set status tp "public"
$res = $cb->submit_set_shared($collection->{MColl_ID}, 'public');
print "Set collection shared exit code: $res->{status}\n";
if ($res->{status} != 0) {
  print "STDERR $res->{stderr}\n";
  die "Error from Collection Builder, cannot continue.";
}
