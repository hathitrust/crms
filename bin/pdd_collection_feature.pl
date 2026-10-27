#!/usr/bin/perl

use strict;
use warnings;
use utf8;

BEGIN {
  die "SDRROOT environment variable not set" unless defined $ENV{'SDRROOT'};
  use lib $ENV{'SDRROOT'} . '/crms/cgi';
  use lib $ENV{'SDRROOT'} . '/crms/lib';
}
$ENV{'SDRDATAROOT'} = '/sdr1' unless defined $ENV{'SDRDATAROOT'};

use Data::Dumper;
use Getopt::Long qw(:config no_ignore_case bundling);

use CRMS::Config;
use CRMS::CollectionBuilder;

binmode(STDOUT, ':encoding(UTF-8)');
my $usage = <<END;
USAGE: $0 [-hv] [-y YEAR]

Features the following collections:
  - [YEAR - 96] Publications
  - Newly Opened Worldwide January [YEAR]
Un-features the following collections:
  - [YEAR - 97] Publications
  - Newly Opened Worldwide January [YEAR - 1]
Where YEAR is the new year, typically the current year + 1.
(If running in Nov 2026 then YEAR will be 2027.)

Uses mb/scripts/batch-collection.pl via `CRMS::CollectionBuilder`.

-h             Print this help message.
-n             No-op; do not communicate with batch-collection.pl, just report.
-y YEAR        Use some other value for YEAR other than the current year plus one.
END


my $help;
my $noop;
my $year;

Getopt::Long::Configure('bundling');
die 'Terminating' unless GetOptions(
  'h|?' => \$help,
  'n'   => \$noop,
  'y:s' => \$year
);

if ($help) { print $usage. "\n"; exit(0); }

# Establish production DB connection.
my $config = CRMS::Config->new(
  instance => 'production'
);

# This year's has an implicit "this year plus one" if no year given.
my $cb = CRMS::CollectionBuilder->new;
# Last year's collections use the current year.
my $prev_cb = CRMS::CollectionBuilder->new(year => CRMS::Utility::Time->new->year);
my $prev_us_collection = $cb->find_collection_by_name($prev_cb->pdd_collection_name);
my $prev_world_collection = $cb->find_collection_by_name($prev_cb->pdd_collection_name(1));

my $curr_us_collection = $cb->find_collection_by_name($cb->pdd_collection_name);
my $curr_world_collection = $cb->find_collection_by_name($cb->pdd_collection_name(1));

report_result($cb->submit_set_featured($prev_us_collection), 'Unfeature previous US collection');
report_result($cb->submit_set_featured($prev_world_collection), 'Unfeature previous World collection');
report_result($cb->submit_set_featured($curr_us_collection, 1), 'Feature new US collection');
report_result($cb->submit_set_featured($curr_us_collection, 1), 'Feature new World collection');

print "Collections unfeatured:\n";
printf "%s", Dumper $prev_us_collection;
printf "%s", Dumper $prev_world_collection;

print "Collections featured:\n";
printf "%s", Dumper $curr_us_collection;
printf "%s", Dumper $curr_world_collection;

sub report_result {
  my $res = shift;
  my $op  = shift;

  print "$op exit code: $res->{result}\n";
  if ($res->{result} != 0) {
    print "STDERR $res->{stderr}\n";
    die "Error communicating with Collection Builder, cannot continue.";
  }
}
