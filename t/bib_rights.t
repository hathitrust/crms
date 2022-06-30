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
use Encode;
use JSON::XS;
use bib_rights;
use MARC::File::XML(BinaryEncoding => 'utf8');
use Test::More;

my $crms = CRMS->new();
my $fixtures_dir = $ENV{'SDRROOT'} . '/crms/t/fixtures/bib_rights/';
my $test_struct = read_json('bib_rights_tests.json');
  
foreach my $htid (sort keys %$test_struct) {
  run_tests_for_htid($htid);
}

### MISCELLANEOUS COVERAGE TESTS
delete $ENV{BIB_RIGHTS_DATE};

# Pass nonexistent fed docs file
$ENV{'us_fed_pub_exception_file'} = $fixtures_dir . 'no_such_file.txt';
my $br = bib_rights->new();
# Clone existing BR object
ok(my $br2 = $br->new());

delete $ENV{'us_fed_pub_exception_file'};

my $date = bib_rights::getDate(0);
is($date, '19700101:00:00:00');

my $fake_marc_xml = '<record><leader>03895cas a2200517I  4500</leader></record>';
my $fake_marc = MARC::Record->new_from_xml($fake_marc_xml);
my $bib_info = $br->get_bib_info($fake_marc, 'BOGUS RECORD 2');
ok(!scalar keys %$bib_info);

$fake_marc_xml = '<record></record>';
$fake_marc = MARC::Record->new_from_xml($fake_marc_xml);
$bib_info = $br->get_bib_info($fake_marc, 'BOGUS RECORD 3');
ok(!scalar keys %$bib_info);

$fake_marc_xml = '<record><leader>03895cas a2200517I  4500</leader><controlfield tag="001">000000000</controlfield></record>';
$fake_marc = MARC::Record->new_from_xml($fake_marc_xml);
bib_rights::output_field($fake_marc->field('001'));

test_fed_docs_exception_list();
test_date_type_e_no_date1_edge_case();
test_nrc_canada_edge_case();
test_biblevel_s_edge_case();
test_clean_pub_place();
test_get_volume_date_page_part();
test_get_volume_date_strip_months();
test_get_volume_date_report_number();
done_testing();

sub run_tests_for_htid {
  my $htid = shift;

  my $marc;
  my $fixture = $fixtures_dir . $htid . ".xml";
  die "can't find fixture $fixture" unless (-e $fixture);

  open my $fh, '<:utf8', $fixture or die "error opening $fixture: $!";
  my $xml = do { local $/; <$fh> };
  close $fh;
  eval { $marc = MARC::Record->new_from_xml($xml); };
  die "problem processing marc xml: $@" if $@;

  my $cid = $marc->field('001')->as_string();
  my $enumcron = extract_enumcron($marc, $htid);
  foreach my $year (sort keys %{$test_struct->{$htid}->{years}}) {
    my $attr = $test_struct->{$htid}->{years}->{$year};
    $ENV{BIB_RIGHTS_DATE} = $year;
    my $br = bib_rights->new();
    my $bib_info = $br->get_bib_info($marc, $cid);
    my $bib_rights_info = $br->get_bib_rights_info($htid, $bib_info, $enumcron);
    ok($bib_rights_info->{attr} eq $attr);
    # Hit the API for coverage.
    my $debug_line = $br->debug_line($bib_info, $bib_rights_info);
    my $imprint = bib_rights::get_bib_data($marc, "260", 'bc');
  }
}

# Extract enumcron for HTID from MARC::Record 974z
sub extract_enumcron {
  my $marc = shift;
  my $htid = shift;
  
  my @fields = $marc->field('974');
  foreach my $field (@fields) {
    if ($htid eq $field->subfield('u')) {
      return $field->subfield('z') || '';
    }
  }
  return '';
}

# Read a JSON test file into a Perl struct.
sub read_json {
  my $file = shift;

  my $jsonxs = JSON::XS->new->utf8->canonical(1)->pretty(1);
  my $fixture_file = $fixtures_dir . $file;
  open my $fh, '<:utf8', $fixture_file or die "error opening $fixture_file: $!";
  my $test_data = do { local $/; <$fh> };
  close $fh;
  return $jsonxs->decode($test_data);
}

# Use the fake feddoc_oclc_nums.txt fixture to get coverage of exceptions.
sub test_fed_docs_exception_list {
  $ENV{'us_fed_pub_exception_file'} = $fixtures_dir . 'feddoc_oclc_nums.txt';
  my $fake_marc_xml = <<END_OF_RECORD;
<record>
  <leader>03895cas a2200517I  4500</leader>
  <controlfield tag="001">000000000</controlfield>
  <controlfield tag="008">720225m19679999dcu      b   f000 0 eng u</controlfield>
  <datafield tag="035" ind1=" " ind2=" "><subfield code="a">(OCoLC)000</subfield></datafield>
</record>
END_OF_RECORD
  my $fake_marc = MARC::Record->new_from_xml($fake_marc_xml);
  my $br = bib_rights->new();
  my $bib_info = $br->get_bib_info($fake_marc, 'BOGUS RECORD 1');
  ok($bib_info->{us_fed_pub_exception} && $bib_info->{us_fed_pub_exception} eq 'exception list');
}

# Fake the currently unattested situation with "date type e--no date1"
sub test_date_type_e_no_date1_edge_case {
  $fake_marc_xml = <<END_OF_RECORD;
<record>
  <leader>03895cas a2200517I  4500</leader>
  <controlfield tag="001">000000000</controlfield>
  <controlfield tag="008">950818e||||2001njumr1p       0   a0eng d</controlfield>
</record>
END_OF_RECORD
  $fake_marc = MARC::Record->new_from_xml($fake_marc_xml);
  $bib_info = $br->get_bib_info($fake_marc, 'BOGUS RECORD 4');
  my $bib_rights_info = $br->get_bib_rights_info('mdp.0000000000', $bib_info, '');
  ok($bib_rights_info->{date_desc} eq 'date type e--no date1');
}

# Fake currently unattested situation of a US publication with "National Research Council" and "Canada" imprint
sub test_nrc_canada_edge_case {
  $fake_marc_xml = <<END_OF_RECORD;
<record>
  <leader>01022cam a2200289I  4500</leader>
  <controlfield tag="001">000000000</controlfield>
  <controlfield tag="008">720225m19679999dcu      b   f000 0 eng u</controlfield>
  <datafield tag="610" ind1="2" ind2="0">
    <subfield code="a">National Research Council Canada</subfield>
  </datafield>
</record>
END_OF_RECORD
  $fake_marc = MARC::Record->new_from_xml($fake_marc_xml);
  $bib_info = $br->get_bib_info($fake_marc, 'BOGUS RECORD 6');
  ok(!$bib_info->{us_fed_pub_exception} || $bib_info->{us_fed_pub_exception} ne 'national research council');
}

# Fake the currently unattested situation with leader bibLevel "s" but no matching recTYpe
sub test_biblevel_s_edge_case {
  $fake_marc_xml = <<END_OF_RECORD;
<record>
  <leader>03895czs a2200517I  4500</leader>
  <controlfield tag="001">000000000</controlfield>
  <controlfield tag="008">950818e||||2001njumr1p       0   a0eng d</controlfield>
</record>
END_OF_RECORD
  $fake_marc = MARC::Record->new_from_xml($fake_marc_xml);
  my $fmt = bib_rights::getBibFmt('BOGUS RECORD 5', $fake_marc);
  is($fmt, 'SE');
}

# Test normalization of all the random garbage that shows up in 008 pub_place fields.
# These are all the attested values and what bib_rights::clean_pub_place should produce.
# SELECT DISTINCT CONCAT("['",SUBSTR(f008,16,3),"','",pub_place,"'],") AS s FROM bib_rights_bi ORDER BY s;
sub test_clean_pub_place {
  my $test_struct = read_json('clean_pub_place_tests.json');

  foreach my $test (@$test_struct) {
    is(bib_rights::clean_pub_place($test->{'008'}), $test->{pub_place});
  }
}

sub test_get_volume_date_page_part {
  my $bogus_year = '1970';
  my $real_year = '1960';
  # Test the most common manifestations of the page/part regex.
  # Embed 1970 in the page/part strings to make sure the real year 1960
  # is extracted and the 1970 is removed.
  # This examples cover about 99.5% of the enumcron corpus that match the page/part regex.
  my $first_prefixes = ['v.', 'no.', 'p.', 'pp.', 'pt.'];
  my $second_prefixes = [' ', ''];
  my $patterns = [
    '1970', '1970/', '1970,', '1970-', '1970.',
    '1970/1970', '1970/1970-1970', '1970.1970',
    '1970-1970', '1970,1970', '1970-1970,1970', '1970,1970-1970', '1970-1970,1970-1970',
    '1970-1970-1970'
  ];
  foreach my $pattern (@$patterns) {
    foreach my $first_prefix (@$first_prefixes) {
      foreach my $second_prefix (@$second_prefixes) {
        my $input = $first_prefix . $second_prefix . $pattern . ' ' . $real_year;
        my $output = $br->get_volume_date($input);
        is($output, $real_year);
      }
    }
  }
}

# Month stripping is not sensitive to spacing, so this in many cases brings the \b boundaries
# closer to the year strings we want to identify.
# Test by directly appending month/season strings before and after a target year.
# For each of {month, abbrev month, season, misc}, for each element X
# create the strings "X", "X-", as well as "X-", and "X.-" for non-season strings.
# To cover the typical case "jan.-jul.1999" we use a second month/season string.
# I haven't tried to estimate how complete this coverage is compared to real-world data.
sub test_get_volume_date_strip_months {
  my $real_year = '1960';
  my @times = qw(january february march april may june july august september october november december
               jan feb mar apr may jun jul aug sept sep oct nov dec
               supplement suppl quarter qtr jahr);
  my @seasons = qw(winter spring summer fall autumn);
  my @patterns1;
  push(@patterns1, ($_, $_ . ".", $_ . "-", $_ . ".-")) for @times;
  push(@patterns1, ($_, $_ . "-")) for @seasons;
  my @patterns2 = @patterns1;
  push(@patterns2, "");
  foreach my $pattern1 (@patterns1) {
    foreach my $pattern2 (@patterns2) {
      my $input = $pattern1 . $pattern2 . $real_year;
      my $output = $br->get_volume_date($input);
      is($output, $real_year);
      $input = $real_year . $pattern1 . $pattern2;
      $output = $br->get_volume_date($input);
      is($output, $real_year);
    }
  }
}

# A selection of real-world cases where the "report numbers" test comes into play.
# I am beginning to suspect this is throwing out too many valid years.
sub test_get_volume_date_report_number {
  my $tests = [
    ["no.49-52 1990/91:Wint.-1992:Summer", "1991"], # Degenerate case throws out the 1992
    ["wrc-0168 1968:April", "1968"],
    ["v.31:1914:Okt.-1915:Marz", "1914"], # degenerate
    ["v1(1916:F-1917:JA)", "1916"], # degenerate
    ["v.76 bis-1988", ""], # degenerate
    ["v.6(1912:Mr-1913:F)", "1912"], # degenerate
    ["v.529B-530B (2002)", "2002"],
    ["Book 2 (r:TID-7534)", ""],
    ["OML--OML-AO-2028 (July 19, 1991-Feb. 28, 1992, Inc.)", "1992"],
    ["no.CR-2035 1972", "1972"],
    ["1975:II-1986 Yhteishakemisto Osa 1", "1975"], # degenerate
    ["1997:closeout ed.-1999 closeout ed.", "1997"], # degenerate
    ["no.201-247(1969:Je-1979:Ag)", "1969"], # degenerate
    ["v.1:2-V.3:4 1975:N-1977:AG", "1975"], # degenerate
  ];
  foreach my $test (@$tests) {
    my ($input, $expected) = @$test;
    my $output = $br->get_volume_date($input);
    is($output, $expected);
  }
}
