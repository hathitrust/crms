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

use Getopt::Long qw(:config no_ignore_case bundling);

use CRMS;

binmode(STDOUT, ':encoding(UTF-8)');
my $usage = <<END;
USAGE: $0 [-hv] [-y YEAR]

Typically run a week or so into January. Reports on CRMS Core determinations with a
now-expired renewal date for the current year that are still closed.

This is a postmortem report intended to be run in January after new rights
from the PDD rollover have taken effect. There will generally be no reason to use
the -y flag; it is included here for consistency and in the hope it may be useful
for future development purposes.

The renDate fields that qualify are based on a current year minus 68 years scheme.
I will not attempt to derive that here except to note it relates to renewal terms
in some not-particularly-obvious way.

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

my $crms = CRMS->new(
  verbose  => $verbose,
  instance => 'production'
);

$verbose = 0 unless defined $verbose;
print "Verbosity $verbose\n" if $verbose;
$year = $crms->GetTheYear() unless $year;
my $target_year = $year - 68;
my $target_year_digits = substr $target_year, -2;
print "Checking renewals for $target_year, renDate *$target_year_digits\n" if $verbose;

my $jsonxs = JSON::XS->new;
my $sql = 'SELECT r.id,rd.data FROM historicalreviews r' .
          ' INNER JOIN exportdata e ON r.gid=e.gid' .
          ' INNER JOIN projects p ON e.project=p.id' .
          ' LEFT JOIN reviewdata rd ON r.data=rd.id' .
          ' WHERE r.validated=1 AND e.project=1' .
          ' AND rd.data LIKE "%renDate%"' .
          ' ORDER BY r.id ASC' .
          #' LIMIT 1000';
          '';
my $ref = $crms->SelectAll($sql);
#printf "%d results\n", scalar @$ref;
my %seen;
print "HTID\trenDate\tCurrent rights\n";
foreach my $row (@$ref) {
  my $id = $row->[0];
  my $data = $row->[1];
  next if $seen{$id};
  my $record = $jsonxs->decode($data);
  my $renDate = $record->{'renDate'};
  if ($renDate && $renDate =~ m/\d+(\D\D\D)(\d\d)/) {
    my $ren_date_year = $2;
    my $ref = $crms->RightsQuery($id)->[-1];
    my ($attr2,$reason2,$src2,$usr2,$date2,$note2) = @{$ref};
    if ($ren_date_year eq $target_year_digits) {
      if ($attr2 ne 'pd' && $attr2 ne 'pdus') {
        #print "$id: $renDate (current rights $attr2/$reason2)\n";
        print "$id\t$renDate\t$attr2/$reason2\n";
        $seen{$id} = 1;
      } else {
        #print BLUE "$id: $renDate $1 $2 ($attr2/$reason2)\n";
      }
    } else {
      #print GREEN "$id: $renDate $1 $2 ($attr2/$reason2)\n";
    }
  } else {
    #print RED "Can't decode $id: $renDate ($data)\n" if defined $renDate && length $renDate;
  }
}

print "Warning: $_\n" for @{$crms->GetErrors()};
