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

# Standard reference year to make the math simpler.
# Used in most of the tests. Changing this will require
# some of the tests to be updated.
my $REF_YEAR = 2020;

subtest 'RightsPredictor::new' => sub {
  subtest 'Missing metadata' => sub {
    dies_ok { CRMS::RightsPredictor->new; };
  };
};

subtest 'RightsPredictor::last_source_copyright' => sub {
  subtest 'UK' => sub {
    my $f008 = '850423s1940    uk a          000 0 eng d';
    my $record = FakeMetadata::fake_record_with_008_and_leader($f008);
    my $rp = CRMS::RightsPredictor->new(record => $record, effective_date => 2000);
    is($rp->last_source_copyright, 2070, 'UK baseline 70-year term');

  };

  subtest 'UK corporate work' => sub {
    my $f008 = '850423s1940    uk a          000 0 eng d';
    my $record = FakeMetadata::fake_record_with_008_and_leader($f008);
    my $rp = CRMS::RightsPredictor->new(record => $record, effective_date => 2000, is_corporate => 1);
    is($rp->last_source_copyright, 2070, 'UK corporate/anonymous 70-year term');
  };

  subtest 'UK crown' => sub {
    my $f008 = '850423s1940    uk a          000 0 eng d';
    my $record = FakeMetadata::fake_record_with_008_and_leader($f008);
    my $rp = CRMS::RightsPredictor->new(record => $record, effective_date => 2000, is_crown => 1);
    is($rp->last_source_copyright, 2050, 'UK crown copyright 50-year term');
  };

  subtest 'Canada pre-1972' => sub {
    my $f008 = '850423s1940    cn a          000 0 eng d';
    my $record = FakeMetadata::fake_record_with_008_and_leader($f008);
    my $rp = CRMS::RightsPredictor->new(record => $record, effective_date => 1970);
    is($rp->last_source_copyright, 2020, 'Canada has 50-year term when the effective date is prior to 1972');
  };

  subtest 'Canada 1972 author death date' => sub {
    my $f008 = '850423s1940    cn a          000 0 eng d';
    my $record = FakeMetadata::fake_record_with_008_and_leader($f008);
    my $rp = CRMS::RightsPredictor->new(record => $record, effective_date => 1972);
    is($rp->last_source_copyright, 2042, 'Canada has 70-year term for author death dates on or after 1972');
  };

  subtest 'Canada 1972 corporate work' => sub {
    my $f008 = '850423s1940    cn a          000 0 eng d';
    my $record = FakeMetadata::fake_record_with_008_and_leader($f008);
    my $rp = CRMS::RightsPredictor->new(record => $record, effective_date => 1972, is_corporate => 1);
    is($rp->last_source_copyright, 2047, 'Canada has 75-year term for corporate/anonymous works published on or after 1972');
  };

  subtest 'Canada post-1972 author death date' => sub {
    my $f008 = '850423s1940    cn a          000 0 eng d';
    my $record = FakeMetadata::fake_record_with_008_and_leader($f008);
    my $rp = CRMS::RightsPredictor->new(record => $record, effective_date => 2000);
    is($rp->last_source_copyright, 2070, 'Canada has 70-year term for author death dates on or after 1972');
  };

  subtest 'Canada post-1972 corporate work' => sub {
    my $f008 = '850423s1940    cn a          000 0 eng d';
    my $record = FakeMetadata::fake_record_with_008_and_leader($f008);
    my $rp = CRMS::RightsPredictor->new(record => $record, effective_date => 2000, is_corporate => 1);
    is($rp->last_source_copyright, 2075, 'Canada has 75-year term for corporate/anonymous works published on or after 1972');
  };

  subtest 'Canada pre-1972 crown' => sub {
    my $f008 = '850423s1940    cn a          000 0 eng d';
    my $record = FakeMetadata::fake_record_with_008_and_leader($f008);
    my $rp = CRMS::RightsPredictor->new(record => $record, effective_date => 1970, is_crown => 1);
    is($rp->last_source_copyright, 2020, 'Canada has 50-year term for crown copyright works regardless of effective date');
  };

  subtest 'Canada 1972 crown' => sub {
    my $f008 = '850423s1940    cn a          000 0 eng d';
    my $record = FakeMetadata::fake_record_with_008_and_leader($f008);
    my $rp = CRMS::RightsPredictor->new(record => $record, effective_date => 1972, is_crown => 1);
    is($rp->last_source_copyright, 2022, 'Canada has 50-year term for crown copyright works regardless of effective date');
  };

  subtest 'Canada post-1972 crown' => sub {
    my $f008 = '850423s1940    cn a          000 0 eng d';
    my $record = FakeMetadata::fake_record_with_008_and_leader($f008);
    my $rp = CRMS::RightsPredictor->new(record => $record, effective_date => 2000, is_crown => 1);
    is($rp->last_source_copyright, 2050, 'Canada has 50-year term for crown copyright works regardless of effective date');
  };

  subtest 'Australia pre-1955' => sub {
    my $f008 = '850423s1940    at a          000 0 eng d';
    my $record = FakeMetadata::fake_record_with_008_and_leader($f008);
    my $rp = CRMS::RightsPredictor->new(record => $record, effective_date => 1950);
    is($rp->last_source_copyright, 2000, 'Australia has 50-year term when the effective date is prior to 1955');
  };

  subtest 'Australia 1955' => sub {
    my $f008 = '850423s1940    at a          000 0 eng d';
    my $record = FakeMetadata::fake_record_with_008_and_leader($f008);
    my $rp = CRMS::RightsPredictor->new(record => $record, effective_date => 1955);
    is($rp->last_source_copyright, 2025, 'Australia has 70-year term when the effective date is on or after 1955');
  };

  subtest 'Australia post-1955' => sub {
    my $f008 = '850423s1940    at a          000 0 eng d';
    my $record = FakeMetadata::fake_record_with_008_and_leader($f008);
    my $rp = CRMS::RightsPredictor->new(record => $record, effective_date => 2000);
    is($rp->last_source_copyright, 2070, 'Australia has 70-year term when the effective date is on or after 1955');
  };

  subtest 'Australia pre-1955 crown' => sub {
    my $f008 = '850423s1940    at a          000 0 eng d';
    my $record = FakeMetadata::fake_record_with_008_and_leader($f008);
    my $rp = CRMS::RightsPredictor->new(record => $record, effective_date => 2000, is_crown => 1);
    is($rp->last_source_copyright, 2050, 'Australia has 50-year term for crown copyright works regardless of effective date');
  };

  subtest 'Australia 1955 crown' => sub {
    my $f008 = '850423s1940    at a          000 0 eng d';
    my $record = FakeMetadata::fake_record_with_008_and_leader($f008);
    my $rp = CRMS::RightsPredictor->new(record => $record, effective_date => 1955, is_crown => 1);
    is($rp->last_source_copyright, 2005, 'Australia has 50-year term for crown copyright works regardless of effective date');
  };

  subtest 'Australia post-1955 crown' => sub {
    my $f008 = '850423s1940    at a          000 0 eng d';
    my $record = FakeMetadata::fake_record_with_008_and_leader($f008);
    my $rp = CRMS::RightsPredictor->new(record => $record, effective_date => 2000, is_crown => 1);
    is($rp->last_source_copyright, 2050, 'Australia has 50-year term for crown copyright works regardless of effective date');
  };

  subtest 'Unknown country' => sub {
    my $f008 = '850423s1940       a          000 0 eng d';
    my $record = FakeMetadata::fake_record_with_008_and_leader($f008);
    my $rp = CRMS::RightsPredictor->new(record => $record, effective_date => 2000);
    ok(!defined $rp->last_source_copyright);
    ok($rp->description =~ m/country/i);
  };

  subtest 'Bogus year inputs' => sub {
    my $f008 = '850423s1940    cn a          000 0 eng d';
    my $record = FakeMetadata::fake_record_with_008_and_leader($f008);
    my @bogus_years = (undef, 'abcd', '', 12345);
    foreach my $year (@bogus_years) {
      my $rp = CRMS::RightsPredictor->new(record => $record, effective_date => $year);
      ok(!defined $rp->last_source_copyright);
      ok($rp->description =~ m/unsupported/i);
    }
  };

  subtest 'Acceptable year inputs' => sub {
    my $f008 = '850423s1940    cn a          000 0 eng d';
    my $record = FakeMetadata::fake_record_with_008_and_leader($f008);
    my @ok_years = ('-1', '-0', '0000', 999999);
    foreach my $year (@ok_years) {
      my $rp = CRMS::RightsPredictor->new(record => $record, effective_date => 2000);
      ok(defined $rp->last_source_copyright);
      ok(join(', ', $rp->{description}) !~ m/unsupported/i);
    }
  };
};

subtest 'RightsPredictor::rights' => sub {
  subtest 'icus/gatt' => sub {
    my $f008 = '850423s1940    uk a          000 0 eng d';
    my $record = FakeMetadata::fake_record_with_008_and_leader($f008);
    my $rp = CRMS::RightsPredictor->new(effective_date => 1940,
      record => $record, reference_year => $REF_YEAR);
    is($rp->rights, 'icus/gatt');
  };

  subtest 'pd/exp' => sub {
    my $f008 = '850423s1940    uk a          000 0 eng d';
    my $record = FakeMetadata::fake_record_with_008_and_leader($f008);
    my $rp = CRMS::RightsPredictor->new(effective_date => 1920, is_corporate => 1,
      record => $record, reference_year => $REF_YEAR);
    is($rp->rights, 'pd/exp');
  };

  subtest 'pd/exp with crown' => sub {
    my $f008 = '850423s1940    uk a          000 0 eng d';
    my $record = FakeMetadata::fake_record_with_008_and_leader($f008);
    my $rp = CRMS::RightsPredictor->new(effective_date => 1940, is_corporate => 1, is_crown => 1,
      record => $record, reference_year => $REF_YEAR);
    is($rp->rights, 'pd/exp');
  };

  subtest 'pd/add' => sub {
    my $f008 = '850423s1940    uk a          000 0 eng d';
    my $record = FakeMetadata::fake_record_with_008_and_leader($f008);
    my $rp = CRMS::RightsPredictor->new(effective_date => 1920,
      record => $record, reference_year => $REF_YEAR);
    is($rp->rights, 'pd/add');
  };

  subtest 'pd/add pub < 1923' => sub {
    my $f008 = '850423s1920    uk a          000 0 eng d';
    my $record = FakeMetadata::fake_record_with_008_and_leader($f008);
    my $rp = CRMS::RightsPredictor->new(effective_date => 1950,
      record => $record, reference_year => 2100);
    is($rp->rights, 'pd/add');
  };
  
  subtest 'pd/add pub > 1923' => sub {
    my $f008 = '850423s1930    uk a          000 0 eng d';
    my $record = FakeMetadata::fake_record_with_008_and_leader($f008);
    my $rp = CRMS::RightsPredictor->new(effective_date => 1950,
      record => $record, reference_year => 2100);
    is($rp->rights, 'pd/add');
  };

  subtest 'ic/cdpp' => sub {
    my $f008 = '850423s1940    uk a          000 0 eng d';
    my $record = FakeMetadata::fake_record_with_008_and_leader($f008);
    my $rp = CRMS::RightsPredictor->new(effective_date => 1980, is_corporate => 1,
      record => $record, reference_year => $REF_YEAR);
    is($rp->rights, 'ic/cdpp');
  };

  subtest 'ic/add' => sub {
    my $f008 = '850423s1940    uk a          000 0 eng d';
    my $record = FakeMetadata::fake_record_with_008_and_leader($f008);
    my $rp = CRMS::RightsPredictor->new(effective_date => 1980,
      record => $record, reference_year => $REF_YEAR);
    is($rp->rights, 'ic/add');
  };
  
  subtest 'pdus/exp' => sub {
    plan skip_all => 'pdus/exp does not appear to be possible';
    # my $f008 = '850423s1930    cn a          000 0 eng d';
    # my $record = FakeMetadata::fake_record_with_008_and_leader($f008);
    # my $rp = CRMS::RightsPredictor->new(effective_date => 1930, is_corporate => 1,
    #   record => $record, reference_year => $REF_YEAR);
    # is($rp->rights, 'pdus/exp');
  };

  subtest 'pdus/add' => sub {
    my $f008 = '850423s1920    uk a          000 0 eng d';
    my $record = FakeMetadata::fake_record_with_008_and_leader($f008);
    my $rp = CRMS::RightsPredictor->new(effective_date => 1960,
      record => $record, reference_year => $REF_YEAR);
    is($rp->rights, 'pdus/add');
  };

  subtest 'unknown place of publication' => sub {
    my $f008 = '850423m19201970   a          000 0 eng d';
    my $record = FakeMetadata::fake_record_with_008_and_leader($f008);
    my $rp = CRMS::RightsPredictor->new(effective_date => 1960,
      record => $record, reference_year => $REF_YEAR);
    ok(!defined $rp->rights);
    ok($rp->description =~ m/country/i);
  };

  subtest 'using current year' => sub {
    my $f008 = '850423s1920    uk a          000 0 eng d';
    my $record = FakeMetadata::fake_record_with_008_and_leader($f008);
    my $rp = CRMS::RightsPredictor->new(effective_date => 1960, record => $record);
    ok(defined $rp->rights);
  };

  subtest 'with pub date range' => sub {
    subtest 'actual pub date supplied' => sub {
      my $f008 = '850423m19201970uk a          000 0 eng d';
      my $record = FakeMetadata::fake_record_with_008_and_leader($f008);
      my $rp = CRMS::RightsPredictor->new(effective_date => 1960, pub_date => 1940,
        record => $record, reference_year => $REF_YEAR);
      is($rp->rights, 'ic/add');
    };

    subtest 'invalid actual pub date supplied' => sub {
      my $f008 = '850423m19201970uk a          000 0 eng d';
      my $record = FakeMetadata::fake_record_with_008_and_leader($f008);
      my $rp = CRMS::RightsPredictor->new(effective_date => 1960, pub_date => 'xyz',
        record => $record, reference_year => $REF_YEAR);
      ok(!defined $rp->rights);
      ok($rp->description =~ m/unsupported pub date format/i);
    };

    subtest 'actual pub date omitted' => sub {
      my $f008 = '850423m19201970uk a          000 0 eng d';
      my $record = FakeMetadata::fake_record_with_008_and_leader($f008);
      my $rp = CRMS::RightsPredictor->new(effective_date => 1960,
        record => $record, reference_year => $REF_YEAR);
      ok(!defined $rp->rights);
      ok($rp->description =~ m/no pub date provided/i);
    };
  };
};

done_testing();
