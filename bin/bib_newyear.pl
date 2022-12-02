#!/usr/bin/perl

use strict;
use warnings;
BEGIN {
  unshift(@INC, $ENV{'SDRROOT'}. '/crms/cgi');
  unshift(@INC, $ENV{'SDRROOT'}. '/crms/post_zephir_processing');
}

use utf8;
binmode(STDOUT, ':encoding(UTF-8)');
use CRMS;
use Getopt::Long qw(:config no_ignore_case bundling);
use Encode;
use Term::ANSIColor qw(:constants colored);
$Term::ANSIColor::AUTORESET = 1;
use Data::Dumper;
use bib_rights;
use MARC::File::XML(BinaryEncoding => 'utf8');

my $usage = <<END;
USAGE: $0 [-hpv] [-o FILE] [-y YEAR]

Reports proposed new rights for volumes that would otherwise not be eligible
for bib rights determination.

NOTE: this is a long-running script -- should be invoked in a screen(1) session.

-h         Print this help message.
-o FILE    Write or append report on new determinations to FILE.
-p         Run in production.
-v         Emit verbose debugging information. May be repeated.
-y YEAR    Use this year instead of the current one.
END


my $help;
my $instance;
my $noop;
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
    sys      => 'crmsworld',
    verbose  => $verbose,
    instance => $instance
);

$verbose = 0 unless defined $verbose;
print "Verbosity $verbose\n" if $verbose;
$year = $crms->GetTheYear() unless $year;

$ENV{BIB_RIGHTS_DATE} = $year if defined $year;

my $sql = 'SELECT r.namespace,r.id,a.name,rs.name FROM rights_current r'.
          ' INNER JOIN attributes a ON r.attr=a.id'.
          ' INNER JOIN reasons rs ON r.reason=rs.id'.
          ' WHERE CONCAT(a.name,"/",rs.name)'.
          ' IN ("ic-world/con","ic/cdpp","ic/crms","ic/ipma","ic/man","ic/ren","op/ipma",
                "pd/cdpp","pd/crms","pd/ncn","pd/ren","pdus/cdpp",
                "pdus/crms","pdus/gfv","pdus/ncn","pdus/ren","und/crms",
                "und/nfi","und/ren")'.
          ' ORDER BY a.name,rs.name';
my $ref = $crms->SelectAllSDR($sql);
my $n = scalar @{$ref};
my $last_processed;
my $last_processed_seen;

my @cols = ('HTID', 'Current rights/reason', "$year bib rights", 'date_used',
            'pub place', 'us fed doc?', 'bib rights determination reason');

my $fh;
my $exists;
my $changed = 0;
if ($outfile && -f $outfile) {
  $exists = -f $outfile;
  unless (open $fh, '<:encoding(UTF-8)', $outfile) {
    die ("failed to read file at $outfile: ". $!);
  }
  read $fh, my $buff, -s $outfile;
  close $fh;
  my @lines = split "\n", $buff;
  shift @lines;
  foreach my $line (@lines) {
    my @fields = split "\t", $line;
    if (scalar @fields == scalar @cols) {
      #printf "Marking %s as last processed.\n", $fields[0];
      $last_processed = $fields[0];
    }
    else {
      printf "NOT MARKING %s SINCE %s != %s\n", $fields[0], scalar @fields, scalar @cols;
    }
    $changed++;
  }
}

print "LAST PROCESSED: $last_processed\n" if $last_processed;

if ($outfile) {
  unless (open $fh, '>>:encoding(UTF-8)', $outfile) {
    die ("failed to read file at $outfile: ". $!);
  }
  printf $fh "%s\n", join("\t", @cols) unless $exists;
  flush $fh;
}

my $i = 0;

my $br = bib_rights->new();
my $of = scalar @$ref;
print "Checking $of items\n";
foreach my $row (@{$ref}) {
  $i++;
  print "$i/$of ($changed)\n" if $i % 1000 == 0;
  my $id = $row->[0]. '.'. $row->[1];
  if ($last_processed) {
    if ($last_processed eq $id) {
      print "=== LAST PROCEDDED $id ===\n";
      $last_processed_seen = 1;
      next;
    }
    unless ($last_processed_seen) {
      next;
    }
  }
  my $attr = $row->[2];
  my $reason = $row->[3];
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
    my $line = join "\t", ($id, $attr. '/'. $reason, $bri->{'attr'},
                           $bri->{'date_used'}, $bri->{'pub_place'},
                           $bri->{'us_fed_doc'}, $bri->{'reason'});
    print $fh $line. "\n" if $fh;
    flush $fh;
    $changed++;
  }
}

close $fh if defined $fh;

print "Warning: $_\n" for @{$crms->GetErrors()};

