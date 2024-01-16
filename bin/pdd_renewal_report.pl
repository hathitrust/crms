#!/usr/bin/perl

use strict;
use warnings;
use utf8;

BEGIN {
  die "SDRROOT environment variable not set" unless defined $ENV{'SDRROOT'};
  use lib $ENV{'SDRROOT'} . '/crms/cgi';
}

use Getopt::Long qw(:config no_ignore_case bundling);

use CRMS;

use constant {
  EXPECTED_RENEWAL_SUNSET => 68 # years
};

binmode(STDOUT, ':encoding(UTF-8)');
my $usage = <<END;
USAGE: $0 [-hv] [-y YEAR]

Typically run a week or so into January. Reports on CRMS Core determinations with a
now-expired renewal date for the current year that are still closed.

This is a postmortem report intended to be run in January after new rights
from the PDD rollover have taken effect. There will generally be no reason to use
the -y flag; it is included here for consistency and in the hope it may be useful
for future development purposes.

The renDate fields that qualify are based on a current year minus 68 years scheme
(see the magic constant EXPECTED_RENEWAL_EXPIRATION_YEARS). I will not attempt to derive
that here except to note it relates to renewal terms in some not-particularly-obvious way;
it is not an off-by-two derivation from 70 years but something more subtle. See Kristina
for more information if this needs to be revisited.

-h             Print this help message.
-v             Emit verbose debugging information. May be repeated.
-y YEAR        Use some other value for YEAR other than the current year.
END

my $help;
my $verbose;
my $year;

Getopt::Long::Configure('bundling');
die 'Terminating' unless GetOptions(
           'h|?'  => \$help,
           'v+'   => \$verbose,
           'y:s'  => \$year);

if ($help) {
  print $usage. "\n";
  exit 0;
}

$verbose = 0 unless defined $verbose;
print "Verbosity $verbose\n" if $verbose;

my $crms = CRMS->new(
  verbose  => $verbose,
  instance => 'production'
);

$year = $crms->GetTheYear() unless $year;

my $target_year = $year - EXPECTED_RENEWAL_SUNSET;
my $target_year_digits = substr $target_year, -2;
print "Checking renewals for $target_year, renDate pattern D[D]Mmm$target_year_digits\n" if $verbose;

my $jsonxs = JSON::XS->new;
# Find Core project reviews with (any) renewal date that have not been invalidated.
my $sql = <<'SQL';
  SELECT r.id,rd.data FROM historicalreviews r
  INNER JOIN exportdata e ON r.gid=e.gid
  INNER JOIN projects p ON e.project=p.id
  INNER JOIN reviewdata rd ON r.data=rd.id
  WHERE r.data IS NOT NULL
  AND r.validated=1
  AND p.name="Core"
  AND rd.data LIKE "%renDate%"
  ORDER BY r.id ASC
SQL

my $ref = $crms->SelectAll($sql);
my %seen;
print "HTID\trenDate\tCurrent rights\n";
foreach my $row (@$ref) {
  my ($id, $json) = @$row;
  next if $seen{$id};
  my $data = $jsonxs->decode($json);
  my $renDate = $data->{'renDate'};
  # Narrow results down to year of interest.
  # renDate as represented in Catalog of Copyright Entries is of the form D[D]mmmYY
  # e.g., "4Nov52" or "31Mar59"
  if ($renDate && $renDate =~ m/\d{1,2}\D{3}(\d{2})/) {
    my $ren_date_year = $1;
    if ($ren_date_year eq $target_year_digits) {
      # Narrow results further to anything not pd or pdus.
      my $rights = $crms->CurrentRightsString($id);
      if ($rights !~ /^pd/) {
        print "$id\t$renDate\t$rights\n";
        $seen{$id} = 1;
      }
    } 
  }
}

print "Warning: $_\n" for @{$crms->GetErrors()};
