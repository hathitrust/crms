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

binmode(STDOUT, ':encoding(UTF-8)');
my $usage = <<END;
USAGE: $0 [-hpv] [-o FILE] [-y YEAR]

Reports proposed new rights for volumes that would otherwise not be eligible
for bib rights redetermination. Creates a TSV report and a .rights file under
crms/prep.

NOTE: this is a long-running script -- should be invoked in a screen(1) session.

-h         Print this help message.
-p         Run in production.
-t TICKET  Use Jira ticket TICKET in the .rights note field.
-v         Emit verbose debugging information. May be repeated.
-y YEAR    Use this year instead of the current one.
END


my $help;
my $instance;
my $noop;
my $production;
my $ticket;
my $verbose;
my $year;

Getopt::Long::Configure('bundling');
die 'Terminating' unless GetOptions(
           'h|?'  => \$help,
           'p'    => \$production,
           't'    => \$ticket,
           'v+'   => \$verbose,
           'y:s'  => \$year);
$instance = 'production' if $production;
if ($help) { print $usage. "\n"; exit(0); }

my $crms = CRMS->new(instance => $instance);

$verbose = 0 unless defined $verbose;
print "Verbosity $verbose\n" if $verbose;
$year = $crms->GetTheYear() unless $year;

$ENV{BIB_RIGHTS_DATE} = $year if defined $year;
my $bib_rights = BibRights->new();
my $br = $bib_rights->bib_rights;

my $sql = 'SELECT JOIN(r.namespace,".",r.id),a.name,rs.name FROM rights_current r'.
          ' INNER JOIN attributes a ON r.attr=a.id'.
          ' INNER JOIN reasons rs ON r.reason=rs.id'.
          ' WHERE CONCAT(a.name,"/",rs.name)'.
          ' IN ("ic-world/con","ic/cdpp","ic/crms","ic/ipma","ic/man","ic/ren","op/ipma",
                "pdus/cdpp","pdus/crms","pdus/gfv","pdus/ncn","pdus/ren","und/crms",
                "und/nfi","und/ren")'.
          ' ORDER BY a.name,rs.name';
my $ref = $crms->SelectAllSDR($sql);

my @cols = ('HTID', 'Current rights/reason', "$year bib rights", 'date_used',
            'pub place', 'us fed doc?', 'bib rights determination reason');

my $date = $crms->GetTodaysDate();
$date =~ s/[:\s]+/_/g;
my $report_file = $crms->FSPath('prep', 'bib_newyear_' . $date. '.tsv');
my $rights_file = $crms->FSPath('prep', 'bib_newyear_' . $date. '.rights');
my ($report_fh, $rights_fh);
open($report_fh, '>:encoding(UTF-8)', $report_file) or die $!;
open($rights_fh, '>:encoding(UTF-8)', $rights_file) or die $!;
printf $report_fh "%s\n", join("\t", @cols);

foreach my $row (@{$ref}) {
  my ($htid, $attr, $reason) = @$row;

  my $query_result = $bib_rights->query($htid);
  if (defined $query_result->{error}) {
    warn $query_result->{error};
    next;
  }
  my $bri = $query_result->{entries}->[0];
  # Report if the bib rights algorithm date is us_pd_cutoff_year minus one
  # Example: current year 2025, us_pd_cutoff_year is 1930, so we are looking for
  # a date_used of 1929 exactly.
  # Could look for 1929 or earlier but that might be a rabbit hole, or it could
  # pick up strays that escaped us in previous years.
  # Report on anything predicted pd, as well as anything predicted pdus that is not already pd.
  if ($bri->{date_used} && $bri->{date_used} == $br->{us_pd_cutoff_year} - 1 &&
      ($bri->{attr} eq 'pd' || ($bri->{attr} eq 'pdus' && $attr ne 'pd'))) {
    my $line = join "\t", ($htid, $attr. '/'. $reason, $bri->{'attr'},
                           $bri->{'date_used'}, $bri->{'pub_place'},
                           $bri->{'us_fed_doc'}, $bri->{'reason'});
    print $report_fh $line . "\n";
    my $note = 'null';
    if (defined $ticket && length $ticket) {
      $note = "$ticket - revert to bib rights for PD rolling wall";
    }
    $line = join "\t", ($htid, $attr, $reason, 'crms', 'null', $note);
    print $rights_fh $line . "\n";
  }
}

close $report_fh;
close $rights_fh;

print "Warning: $_\n" for @{$crms->GetErrors()};
