#!/usr/bin/perl

use strict;
use warnings;
use utf8;

BEGIN {
  die "SDRROOT environment variable not set" unless defined $ENV{'SDRROOT'};
  use lib $ENV{'SDRROOT'} . '/crms/cgi';
}

use Encode;
use Getopt::Long qw(:config no_ignore_case bundling);
use Data::Dumper;
use File::Slurp;
use MARC::Record;
use MARC::File::XML(BinaryEncoding => 'utf8');

use BibRights;

binmode(STDOUT, ':encoding(UTF-8)');

my $usage = <<END;
USAGE: $0 [-hp] [-i path/to/file] [htid_or_cid_1 [htid_or_cid_2 ...]]

Reports the bibliographic rights for one or more HathiTrust and/or catalog ids.

-h, -?    Print this help message.
-i        Input file with whitespace-delimited (space, tab, newline) list of ids.
-v        Report all fields in the bib_rights_info data structure.
-y YEAR   Use YEAR instead of the current one (for predicting new year rollover).
END


my $help;
my $infile;
my $verbose;
my $year;

Getopt::Long::Configure('bundling');
die 'Terminating' unless GetOptions(
  'h|?'  => \$help,
  'i:s'  => \$infile,
  'v+'   => \$verbose,
  'y:s'  => \$year);

if ($help) { print $usage. "\n"; exit(0); }

if (defined $year) {
  $ENV{BIB_RIGHTS_DATE} = $year;
}

my @ids;

if (defined $infile) {
  unless (-e $infile) {
    die "Error: can't read $infile";
  }
  my $text = File::Slurp::read_file($infile);
  push @ids, $_ for split(/\s+/, $text);
}

push @ids, $_ for @ARGV;

my $bib_rights = BibRights->new;
foreach my $id (@ids) {
  my $res = $bib_rights->query($id);
  if ($res->{error}) {
    print "$id: $res->{error}\n";
    next;
  }
  DisplayEntry($id, $_) for @{ $res->{entries} };
}

sub DisplayEntry {
  my $id    = shift;
  my $entry = shift;

  print "$entry->{id} $entry->{bib_key} $entry->{attr}\n";
  return unless $verbose;
  foreach my $field (@BibRights::BIB_RIGHTS_INFO_FIELDS) {
    next if $field eq 'id' || $field eq 'bib_key' || $field eq 'attr';
    my $val = $entry->{$field} || '';
    print "  $field: $val\n";
  }
}
