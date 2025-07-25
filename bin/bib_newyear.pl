#!/usr/bin/perl

use strict;
use warnings;
use utf8;

BEGIN {
  die "SDRROOT environment variable not set" unless defined $ENV{'SDRROOT'};
  use lib $ENV{'SDRROOT'} . '/crms/cgi';
  use lib $ENV{'SDRROOT'} . '/crms/post_zephir_processing';
}

use Data::Dumper;
use Encode;
use Getopt::Long qw(:config no_ignore_case bundling);
use JSON::XS;
use MARC::File::XML(BinaryEncoding => 'utf8');

use CRMS;
use bib_rights;

binmode(STDOUT, ':encoding(UTF-8)');
my $usage = <<END;
USAGE: $0 [-hpv] [-o FILE] [-y YEAR]

Reports proposed new rights for volumes that would otherwise not be eligible
for bib rights determination.

NOTE: this is a long-running script -- should be invoked in a screen(1) session.

-h         Print this help message.
-o FILE    Write report on new determinations to FILE.
-p         Run in production.
-v         Emit verbose debugging information. May be repeated.
-y YEAR    Use this year instead of the current one.
END


my $help;
my $instance;
my $outfile;
my $production;
my $verbose;
my $year;

Getopt::Long::Configure('bundling');
die 'Terminating' unless GetOptions(
           'h|?'  => \$help,
           'o:s'  => \$outfile,
           'p'    => \$production,
           'v+'   => \$verbose,
           'y:s'  => \$year);
$instance = 'production' if $production;
if ($help) { print $usage. "\n"; exit(0); }

my $crms = CRMS->new(
  verbose  => $verbose,
  instance => $instance
);

$verbose = 0 unless defined $verbose;
print "Verbosity $verbose\n" if $verbose;
$year = $crms->GetTheYear() unless $year;

$ENV{BIB_RIGHTS_DATE} = $year if defined $year;
my $jsonxs = JSON::XS->new->utf8;

my $sql = <<~'SQL';
  SELECT r.namespace, r.id, a.name, rs.name FROM rights_current r
  INNER JOIN attributes a ON r.attr = a.id
  INNER JOIN reasons rs ON r.reason = rs.id
  WHERE CONCAT(a.name, "/", rs.name) IN (
    "ic-world/con",
    "ic/cdpp",
    "ic/crms",
    "ic/ipma",
    "ic/ren",
    "op/ipma",
    "pdus/cdpp",
    "pdus/crms",
    "pdus/gfv",
    "pdus/ncn",
    "pdus/ren",
    "und/crms",
    "und/nfi",
    "und/ren"
  )
  ORDER BY a.name, rs.name, r.namespace, r.id
SQL

my $ref = $crms->SelectAllSDR($sql);
my $n = scalar @{$ref};

my @cols = ('HTID', 'Current rights/reason', "$year bib rights", 'date_used',
            'pub place', 'us fed doc?', 'bib rights reason', 'ic/ren data');
my $fh;
if ($outfile) {
  unless (open $fh, '>:encoding(UTF-8)', $outfile) {
    die ("failed to create file at $outfile: ". $!);
  }
  printf $fh "%s\n", join("\t", @cols);
  flush $fh;
}

my $i = 0;
my $changed = 0;

my $br = bib_rights->new();
my $of = scalar @$ref;
print "Checking $of items\n" if $verbose;
foreach my $row (@{$ref}) {
  $i++;
  print "$i/$of ($changed)\n" if $i % 1000 == 0 && $verbose;
  my $id = $row->[0]. '.'. $row->[1];
  my $attr = $row->[2];
  my $reason = $row->[3];
  my $like_clause = '%' . ($br->{'us_pd_cutoff_year'} - 1) . '-%';
  $sql = "SELECT imprint FROM hf WHERE htid=? AND imprint LIKE '$like_clause'";
  my $bad_imprint = $crms->SimpleSqlGetSDR($sql, $id);
  if ($bad_imprint) {
    print "$id: later dates found on imprint ($bad_imprint), skipping\n" if $verbose;
    next;
  }

  my $record = $crms->GetMetadata($id);
  if (!defined $record) {
    print "Unable to get metadata for $id\n";
    next;
  }
  my $xml = $record->xml;
  #$xml =~ tr/\xA0/ /;
  my $marc = undef;
  eval { $marc = MARC::Record->new_from_xml($xml); };
  $@ and do {
    print STDERR "problem processing marc xml\n";
    warn $@;
    print STDERR "$xml\n";
    next;
  };
  my $description = $record->enumchron($id);
  my $bib_info = $br->get_bib_info($marc, $record->sysid);
  my $bri = $br->get_bib_rights_info($id, $bib_info, $description);
  if ($bri->{'date_used'} && $bri->{'date_used'} == $br->{'us_pd_cutoff_year'} - 1 &&
      ($bri->{'attr'} eq 'pd' || ($bri->{'attr'} eq 'pdus' && $attr ne 'pd'))) {
    my $bri_attr = $bri->{'attr'};
    my $bri_reason = $bri->{'reason'};
    my $ic_ren_data = '';
    if ($attr eq 'ic' && $reason eq 'ren') {
      $ic_ren_data = get_ic_ren_data($id);
    }
    my $line = join "\t", ($id, $attr. '/'. $reason, $bri->{'attr'},
                           $bri->{'date_used'}, $bri->{'pub_place'},
                           $bri->{'us_fed_doc'}, $bri->{'reason'},
                           $ic_ren_data);
    print $fh $line. "\n" if $fh;
    flush $fh;
    $changed++;
  }
}

close $fh if defined $fh;

print "Warning: $_\n" for @{$crms->GetErrors()};

# Returns semicolon-delimited string of unique renDate values for all ic/ren determinations
# for the given HTID.
sub get_ic_ren_data {
  my $htid = shift;

  my %data = ();
  my $sql = <<~'SQL';
    SELECT rd.data FROM exportdata e
    INNER JOIN historicalreviews r ON e.gid = r.gid
    INNER JOIN reviewdata rd ON r.data = rd.id
    INNER JOIN attributes a ON r.attr = a.id
    INNER JOIN reasons rs ON r.reason = rs.id
    WHERE e.id = ?
    AND e.attr = "ic"
    AND e.reason = "ren"
    AND a.name = "ic"
    AND rs.name = "ren"
    AND r.validated != 0
  SQL
  my $reviewdata_ref = $crms->SelectAll($sql, $htid);
  foreach my $reviewdata_row (@$reviewdata_ref) {
    my $reviewdata_json = $reviewdata_row->[0];
    my $reviewdata = $jsonxs->decode($reviewdata_json);
    if ($reviewdata->{renDate}) {
      $data{$reviewdata->{renDate}} = 1;
    }
  }
  return join '; ', sort keys %data;
}
