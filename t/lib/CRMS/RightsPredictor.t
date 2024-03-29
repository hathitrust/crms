#!/usr/bin/perl

use strict;
use warnings;

use Data::Dumper;
use Test::Exception;
use Test::More;

use lib $ENV{'SDRROOT'} . '/crms/lib';
use lib $ENV{'SDRROOT'} . '/crms/t/support';
use CRMS::RightsPredictor;
use FakeMetadata;

subtest 'RightsPredictor::new' => sub {
  subtest 'Missing metadata' => sub {
    dies_ok { CRMS::RightsPredictor->new; };
  };
};

subtest 'RightsPredictor::last_source_copyright' => sub {
  subtest 'UK' => sub {
    my $f008 = '850423s1940    uk a          000 0 eng d';
    my $record = FakeMetadata::fake_record_with_008_and_leader($f008);
    my $rp = CRMS::RightsPredictor->new(record => $record);
    my $res = $rp->last_source_copyright(2000);
    is($res->{last_source_copyright_year}, 2070, 'UK baseline 70-year term');
  };

  subtest 'UK corporate work' => sub {
    my $f008 = '850423s1940    uk a          000 0 eng d';
    my $record = FakeMetadata::fake_record_with_008_and_leader($f008);
    my $rp = CRMS::RightsPredictor->new(record => $record);
    my $res = $rp->last_source_copyright(2000, 1);
    is($res->{last_source_copyright_year}, 2070), 'UK corporate/anonymous 70-year term';
  };

  subtest 'UK crown' => sub {
    my $f008 = '850423s1940    uk a          000 0 eng d';
    my $record = FakeMetadata::fake_record_with_008_and_leader($f008);
    my $rp = CRMS::RightsPredictor->new(record => $record);
    my $res = $rp->last_source_copyright(2000, 0, 1);
    is($res->{last_source_copyright_year}, 2050, 'UK crown copyright 50-year term');
  };

  subtest 'Canada pre-1972' => sub {
    my $f008 = '850423s1940    cn a          000 0 eng d';
    my $record = FakeMetadata::fake_record_with_008_and_leader($f008);
    my $rp = CRMS::RightsPredictor->new(record => $record);
    my $res = $rp->last_source_copyright(1970);
    is($res->{last_source_copyright_year}, 2020, 'Canada has 50-year term when the effective date is prior to 1972');
  };

  subtest 'Canada 1972 author death date' => sub {
    my $f008 = '850423s1940    cn a          000 0 eng d';
    my $record = FakeMetadata::fake_record_with_008_and_leader($f008);
    my $rp = CRMS::RightsPredictor->new(record => $record);
    my $res = $rp->last_source_copyright(1972);
    is($res->{last_source_copyright_year}, 2042, 'Canada has 70-year term for author death dates on or after 1972');
  };

  subtest 'Canada 1972 corporate work' => sub {
    my $f008 = '850423s1940    cn a          000 0 eng d';
    my $record = FakeMetadata::fake_record_with_008_and_leader($f008);
    my $rp = CRMS::RightsPredictor->new(record => $record);
    my $res = $rp->last_source_copyright(1972, 1);
    is($res->{last_source_copyright_year}, 2047, 'Canada has 75-year term for corporate/anonymous works published on or after 1972');
  };

  subtest 'Canada post-1972 author death date' => sub {
    my $f008 = '850423s1940    cn a          000 0 eng d';
    my $record = FakeMetadata::fake_record_with_008_and_leader($f008);
    my $rp = CRMS::RightsPredictor->new(record => $record);
    my $res = $rp->last_source_copyright(2000);
    is($res->{last_source_copyright_year}, 2070, 'Canada has 70-year term for author death dates on or after 1972');
  };

  subtest 'Canada post-1972 corporate work' => sub {
    my $f008 = '850423s1940    cn a          000 0 eng d';
    my $record = FakeMetadata::fake_record_with_008_and_leader($f008);
    my $rp = CRMS::RightsPredictor->new(record => $record);
    my $res = $rp->last_source_copyright(2000, 1);
    is($res->{last_source_copyright_year}, 2075, 'Canada has 75-year term for corporate/anonymous works published on or after 1972');
  };

  subtest 'Canada pre-1972 crown' => sub {
    my $f008 = '850423s1940    cn a          000 0 eng d';
    my $record = FakeMetadata::fake_record_with_008_and_leader($f008);
    my $rp = CRMS::RightsPredictor->new(record => $record);
    my $res = $rp->last_source_copyright(1970, 0, 1);
    is($res->{last_source_copyright_year}, 2020, 'Canada has 50-year term for crown copyright works regardless of effective date');
  };

  subtest 'Canada 1972 crown' => sub {
    my $f008 = '850423s1940    cn a          000 0 eng d';
    my $record = FakeMetadata::fake_record_with_008_and_leader($f008);
    my $rp = CRMS::RightsPredictor->new(record => $record);
    my $res = $rp->last_source_copyright(1972, 0, 1);
    is($res->{last_source_copyright_year}, 2022, 'Canada has 50-year term for crown copyright works regardless of effective date');
  };

  subtest 'Canada post-1972 crown' => sub {
    my $f008 = '850423s1940    cn a          000 0 eng d';
    my $record = FakeMetadata::fake_record_with_008_and_leader($f008);
    my $rp = CRMS::RightsPredictor->new(record => $record);
    my $res = $rp->last_source_copyright(2000, 0, 1);
    is($res->{last_source_copyright_year}, 2050, 'Canada has 50-year term for crown copyright works regardless of effective date');
  };

  subtest 'Australia pre-1955' => sub {
    my $f008 = '850423s1940    at a          000 0 eng d';
    my $record = FakeMetadata::fake_record_with_008_and_leader($f008);
    my $rp = CRMS::RightsPredictor->new(record => $record);
    my $res = $rp->last_source_copyright(1950);
    is($res->{last_source_copyright_year}, 2000, 'Australia has 50-year term when the effective date is prior to 1955');
  };

  subtest 'Australia 1955' => sub {
    my $f008 = '850423s1940    at a          000 0 eng d';
    my $record = FakeMetadata::fake_record_with_008_and_leader($f008);
    my $rp = CRMS::RightsPredictor->new(record => $record);
    my $res = $rp->last_source_copyright(1955);
    is($res->{last_source_copyright_year}, 2025, 'Australia has 70-year term when the effective date is on or after 1955');
  };

  subtest 'Australia post-1955' => sub {
    my $f008 = '850423s1940    at a          000 0 eng d';
    my $record = FakeMetadata::fake_record_with_008_and_leader($f008);
    my $rp = CRMS::RightsPredictor->new(record => $record);
    my $res = $rp->last_source_copyright(2000);
    is($res->{last_source_copyright_year}, 2070, 'Australia has 70-year term when the effective date is on or after 1955');
  };

  subtest 'Australia pre-1955 crown' => sub {
    my $f008 = '850423s1940    at a          000 0 eng d';
    my $record = FakeMetadata::fake_record_with_008_and_leader($f008);
    my $rp = CRMS::RightsPredictor->new(record => $record);
    my $res = $rp->last_source_copyright(1940, 0, 1);
    is($res->{last_source_copyright_year}, 1990, 'Australia has 50-year term for crown copyright works regardless of effective date');
  };

  subtest 'Australia 1955 crown' => sub {
    my $f008 = '850423s1940    at a          000 0 eng d';
    my $record = FakeMetadata::fake_record_with_008_and_leader($f008);
    my $rp = CRMS::RightsPredictor->new(record => $record);
    my $res = $rp->last_source_copyright(1955, 0, 1);
    is($res->{last_source_copyright_year}, 2005, 'Australia has 50-year term for crown copyright works regardless of effective date');
  };

  subtest 'Australia post-1955 crown' => sub {
    my $f008 = '850423s1940    at a          000 0 eng d';
    my $record = FakeMetadata::fake_record_with_008_and_leader($f008);
    my $rp = CRMS::RightsPredictor->new(record => $record);
    my $res = $rp->last_source_copyright(2000, 0, 1);
    is($res->{last_source_copyright_year}, 2050, 'Australia has 50-year term for crown copyright works regardless of effective date');
  };

  subtest 'Unknown country' => sub {
    my $f008 = '850423s1940       a          000 0 eng d';
    my $record = FakeMetadata::fake_record_with_008_and_leader($f008);
    my $rp = CRMS::RightsPredictor->new(record => $record);
    my $res = $rp->last_source_copyright(2000);
    ok(!defined $res->{last_source_copyright_year}, 'Last source copyright year cannot be defined for unknown country');
    ok(join(', ', @{$res->{desc}}) =~ m/country/i);
  };

  subtest 'Bogus year inputs' => sub {
    my $f008 = '850423s1940    cn a          000 0 eng d';
    my $record = FakeMetadata::fake_record_with_008_and_leader($f008);
    my $rp = CRMS::RightsPredictor->new(record => $record);
    my @bogus_years = (undef, 'abcd', '', 12345);
    foreach my $year (@bogus_years) {
      my $res = $rp->last_source_copyright($year);
      ok(!defined $res->{last_source_copyright_year}, 'Last source copyright year cannot be defined for unknown country');
      ok(join(', ', @{$res->{desc}}) =~ m/unsupported/i);
    }
  };

  subtest 'Acceptable year inputs' => sub {
    my $f008 = '850423s1940    cn a          000 0 eng d';
    my $record = FakeMetadata::fake_record_with_008_and_leader($f008);
    my $rp = CRMS::RightsPredictor->new(record => $record);
    my @ok_years = ('-1', '-0', '0000', 999999);
    foreach my $year (@ok_years) {
      my $res = $rp->last_source_copyright(2000);
      ok(defined $res->{last_source_copyright_year}, "Last source copyright year is defined even if the input is $year");
      ok(join(', ', $res->{desc}) !~ m/unsupported/i, "No 'unsupported date format' error for $year");
    }
  };
};

subtest 'RightsPredictor::rights' => sub {
  subtest 'icus/gatt' => sub {
    my $f008 = '850423s1940    uk a          000 0 eng d';
    my $record = FakeMetadata::fake_record_with_008_and_leader($f008);
    my $rp = CRMS::RightsPredictor->new(record => $record);
    my $res = $rp->rights(1940, 0, 0, 2020);
    is($res->{rights}, 'icus/gatt');
  };

  subtest 'pd/exp' => sub {
    my $f008 = '850423s1940    uk a          000 0 eng d';
    my $record = FakeMetadata::fake_record_with_008_and_leader($f008);
    my $rp = CRMS::RightsPredictor->new(record => $record);
    my $res = $rp->rights(1920, 1, 0, 2020);
    is($res->{rights}, 'pd/exp');
  };

  subtest 'pd/exp with crown' => sub {
    my $f008 = '850423s1940    uk a          000 0 eng d';
    my $record = FakeMetadata::fake_record_with_008_and_leader($f008);
    my $rp = CRMS::RightsPredictor->new(record => $record);
    my $res = $rp->rights(1940, 1, 1, 2020);
    is($res->{rights}, 'pd/exp');
  };

  subtest 'pd/add' => sub {
    my $f008 = '850423s1940    uk a          000 0 eng d';
    my $record = FakeMetadata::fake_record_with_008_and_leader($f008);
    my $rp = CRMS::RightsPredictor->new(record => $record);
    my $res = $rp->rights(1920, 0, 0, 2020);
    is($res->{rights}, 'pd/add');
  };

  subtest 'pd/add pub < 1923' => sub {
    my $f008 = '850423s1920    uk a          000 0 eng d';
    my $record = FakeMetadata::fake_record_with_008_and_leader($f008);
    my $rp = CRMS::RightsPredictor->new(record => $record);
    my $res = $rp->rights(1950, 0, 0, 2100);
    is($res->{rights}, 'pd/add');
  };
  
  subtest 'pd/add pub > 1923' => sub {
    my $f008 = '850423s1930    uk a          000 0 eng d';
    my $record = FakeMetadata::fake_record_with_008_and_leader($f008);
    my $rp = CRMS::RightsPredictor->new(record => $record);
    my $res = $rp->rights(1950, 0, 0, 2100);
    is($res->{rights}, 'pd/add');
  };

  subtest 'ic/cdpp' => sub {
    my $f008 = '850423s1940    uk a          000 0 eng d';
    my $record = FakeMetadata::fake_record_with_008_and_leader($f008);
    my $rp = CRMS::RightsPredictor->new(record => $record);
    my $res = $rp->rights(1980, 1, 0, 2020);
    is($res->{rights}, 'ic/cdpp');
  };

  subtest 'ic/add' => sub {
    my $f008 = '850423s1940    uk a          000 0 eng d';
    my $record = FakeMetadata::fake_record_with_008_and_leader($f008);
    my $rp = CRMS::RightsPredictor->new(record => $record);
    my $res = $rp->rights(1980, 0, 0, 2020);
    is($res->{rights}, 'ic/add');
  };
  
  subtest 'pdus/exp' => sub {
    plan skip_all => 'pdus/exp does not appear to be possible';
    # my $f008 = '850423s1930    cn a          000 0 eng d';
    # my $record = FakeMetadata::fake_record_with_008_and_leader($f008);
    # my $rp = CRMS::RightsPredictor->new(record => $record);
    # my $res = $rp->rights(1930, 1, 0, 2020);
    # is($res->{rights}, 'pdus/exp');
  };

  subtest 'pdus/add' => sub {
    my $f008 = '850423s1920    uk a          000 0 eng d';
    my $record = FakeMetadata::fake_record_with_008_and_leader($f008);
    my $rp = CRMS::RightsPredictor->new(record => $record);
    my $res = $rp->rights(1960, 0, 0, 2020);
    is($res->{rights}, 'pdus/add');
  };
  
  subtest 'pub date range disallowed' => sub {
    my $f008 = '850423m19201970uk a          000 0 eng d';
    my $record = FakeMetadata::fake_record_with_008_and_leader($f008);
    my $rp = CRMS::RightsPredictor->new(record => $record);
    my $res = $rp->rights(1960, 0, 0, 2020);
    ok(!defined $res->{rights});
    ok(join(', ', @{$res->{desc}}) =~ m/unsupported pub date format/i);
  };

  subtest 'unknown place of publication' => sub {
    my $f008 = '850423m19201970   a          000 0 eng d';
    my $record = FakeMetadata::fake_record_with_008_and_leader($f008);
    my $rp = CRMS::RightsPredictor->new(record => $record);
    my $res = $rp->rights(1960, 0, 0, 2020);
    ok(!defined $res->{rights});
    ok(join(', ', @{$res->{desc}}) =~ m/country/i);
  };

  subtest 'using current year' => sub {
    my $f008 = '850423s1920    uk a          000 0 eng d';
    my $record = FakeMetadata::fake_record_with_008_and_leader($f008);
    my $rp = CRMS::RightsPredictor->new(record => $record);
    my $res = $rp->rights(1960);
    ok(defined $res->{rights});
  };
};

done_testing();
