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

First creates a text file of non-US HTIDs with a publication/copyright date of the current YEAR - 126,
minus any with "permanently closed" rights attributes {pd-pvt, nobody, supp}.

Then, uses mb/scripts/batch-collection.pl to create a collection based on the report.

This is similar to the logic in pdd_collection_us.pl except it uses an earlier cutoff
date, and it uses the 008-derived value in hathifiles.hf.pub_place to exclude US publications.

Note: the Collection Builder component of this script runs long and should be invoked with nohup.

-h             Print this help message.
-y YEAR        Use this YEAR instead of the current one.
END


my $help;
my $year;

Getopt::Long::Configure('bundling');
die 'Terminating' unless GetOptions(
           'h|?'  => \$help,
           'y:s'  => \$year);

if ($help) { print $usage. "\n"; exit(0); }

my $config = CRMS::Config->new(instance => 'production');
my $cb = CRMS::CollectionBuilder->new(year => $year);
my $db = CRMS::Database::HT->new;
my $target_year = $cb->pdd_us_collection_target_year(1);


# Now get everything from our local bib rights database that has a "date used" of
# YEAR - 126 and non-US pub place.
# Print these out in order, excluding anything in the rights exclusion list.
my $sql = <<'SQL';
SELECT htid,pub_place FROM hf
WHERE rights_date_used=?
AND rights_code NOT IN ('nobody','pd-pvt','supp')
AND substr(pub_place,3,1)!='u'
ORDER BY htid
SQL

my $collection_size = 0;
my $outfile = File::Spec->catfile($ENV{SDRROOT}, 'crms', 'prep', "pdd_collection_world_$year.txt");
open(my $fh, '>:encoding(UTF-8)', $outfile) or die "Could not open '$outfile' $!";
$db->for($sql, sub {
  my $row = shift;
  my $htid = $row->[0];
  print $fh "$htid\n";
  $collection_size++;
});
close $fh;

my $res = $cb->submit_create_collection(
  $cb->pdd_collection_name(1),
  $cb->pdd_collection_description(1),
  $outfile
);
print "Create collection exit code: $res->{result}\n";
if ($res->{status} != 0) {
  print "STDERR $res->{stderr}\n";
  die "Error communicating with Collection Builder, cannot continue.";
}

my $coll_id = $res->{collection}->{MColl_ID};
$res = $cb->submit_set_shared($coll_id, 'public');
print "Set collection shared exit code: $res->{result}\n";
if ($res->{status} != 0) {
  print "STDERR $res->{stderr}\n";
  die "Error communicating with Collection Builder, cannot continue.";
}

print "Done with World Collection: new id is $coll_id\n";
print "Expected size is $collection_size items\n";
printf "Actual size is %s\n", $res->{collection}->{num_items};
