#!/usr/bin/perl

use strict;
use warnings;

use Test::Exception;
use Test::More;

use lib $ENV{'SDRROOT'} . '/crms/lib';
use CRMS::PublicationDate;

subtest '::new' => sub {
  subtest 'without enumcron' => sub {
    my $pd = CRMS::PublicationDate->new(date_type => 'm', date_1 => '1923', date_2 => '1963');
    isa_ok($pd, 'CRMS::PublicationDate');
  };

  subtest 'with enumcron' => sub {
    my $pd = CRMS::PublicationDate->new(date_type => 'm', date_1 => '1923', date_2 => '1963',
      enumcron_date => '1923');
    isa_ok($pd, 'CRMS::PublicationDate');
  };
};

subtest '::clean_date' => sub {
  is(CRMS::PublicationDate::clean_date('||||'), undef, 'no digits');
  is(CRMS::PublicationDate::clean_date('1900'), '1900', 'all digits');
  is(CRMS::PublicationDate::clean_date('19uu'), '19uu', 'partial date');
  is(CRMS::PublicationDate::clean_date('0000'), undef, 'all-zero considered invalid');
};

subtest '::round_up' => sub {
  is(CRMS::PublicationDate::round_up(), undef, 'undef');
  is(CRMS::PublicationDate::round_up('1900'), '1900', 'fully-specified date');
  is(CRMS::PublicationDate::round_up('190u'), '1909', 'unspecified year');
  is(CRMS::PublicationDate::round_up('19uu'), '1999', 'unspecified decade');
  is(CRMS::PublicationDate::round_up('uuuu', 1), '9999', 'completely unspecified in range');
  is(CRMS::PublicationDate::round_up('uuuu'), undef, 'completely unspecified, no range');
};

subtest '::round_down' => sub {
  is(CRMS::PublicationDate::round_down(), undef, 'undef');
  is(CRMS::PublicationDate::round_down('1900'), '1900', 'fully-specified date');
  is(CRMS::PublicationDate::round_down('190u'), '1900', 'unspecified year');
  is(CRMS::PublicationDate::round_down('19uu'), '1900', 'unspecified decade');
  is(CRMS::PublicationDate::round_down('uuuu'), '0000', 'completely unspecified');
};

subtest "#to_s" => sub {
  my $pd = CRMS::PublicationDate->new(date_type => 'm', date_1 => '1923', date_2 => '1963');
  is(ref $pd->to_s, '', '#to_s returns a string');
};

subtest "#text" => sub {
  my $test_data = [
    # type date1  date2   expected
    # ==== =====  =====   ========
    ['b', '####', '####', ''],
    ['s', '1972', '####', '1972'],
    ['s', '197u', '####', '1970-1979'],
    ['m', 'uuuu', '1981', '0000-1981'],
    ['m', '197u', '1987', '1970-1987'],
    ['m', '1943', '197u', '1943-1979'],
    ['m', '1998', '9999', '1998-9999'],
    ['n', 'uuuu', 'uuuu', ''],
  ];

  foreach my $test (@$test_data) {
    my $pd = CRMS::PublicationDate->new(
      date_type => $test->[0],
      date_1 => $test->[1],
      date_2 => $test->[2]);
    is($pd->text, $test->[3], "String for type $test->[0] ($test->[1], $test->[2])");
  }
};

subtest "#inspect" => sub {
  my $pd = CRMS::PublicationDate->new(date_type => 'm', date_1 => '1923', date_2 => '1963');
  is(ref $pd->inspect, '', '#inspect returns a string');
};

my $TEST_DATA = [
    # type date1  date2   extract_dates     exact_copyright_date  maximum_copyright_date  is_single_date
    # ==== =====  =====   =============     ====================  ======================  ==============
    ['b', '####', '####', [],               undef,                undef,                  ''],
    ['c', '19uu', '9999', ['1900', '9999'], undef,                '9999',                 ''],
    ['d', '1uuu', '1958', ['1000', '1958'], undef,                '1958',                 ''],
    ['d', '1945', '19uu', ['1945', '1999'], undef,                '1999',                 ''],
    ['e', '1983', '0615', ['1983'],         '1983',               '1983',                 1],
    # FIXME: do we have examples of type e with underspecified date1?
    ['i', '1765', '1770', ['1765', '1770'], undef,                '1770',                 ''],
    ['i', '18uu', '1890', ['1800', '1890'], undef,                '1890',                 ''],
    ['i', '1988', '1988', ['1988'],         '1988',               '1988',                 1],
    ['k', '1796', '1896', ['1796', '1896'], undef,                '1896',                 ''],
    ['k', '1854', '1854', ['1854'],         '1854',               '1854',                 1],
    ['m', '1972', '1975', ['1972', '1975'], undef,                '1975',                 ''],
    ['m', 'uuuu', '1981', ['0000', '1981'], undef,                '1981',                 ''],
    ['m', '197u', '1987', ['1970', '1987'], undef,                '1987',                 ''],
    ['m', '1943', '197u', ['1943', '1979'], undef,                '1979',                 ''],
    ['m', '1998', '9999', ['1998', '9999'], undef,                '9999',                 ''],
    ['m', 'uuuu', 'uuuu', ['0000', '9999'], undef,                '9999',                 ''],
    ['n', 'uuuu', 'uuuu', [],               undef,                undef,                  ''],
    ['p', '1982', '1967', ['1967'],         '1967',               '1967',                 1],
    ['q', '1963', '1966', ['1963', '1966'], undef,                '1966',                 ''],
    ['q', '18uu', '19uu', ['1800', '1999'], undef,                '1999',                 ''],
    ['r', '1983', '1857', ['1857'],         '1857',               '1857',                 1],
    ['r', '1966', 'uuuu', [],               undef,                undef,                  ''],
    ['r', 'uuuu', '1963', ['1963'],         '1963',               '1963',                 1],
    ['s', '1946', '####', ['1946'],         '1946',               '1946',                 1],
    ['s', '198u', '####', ['1980', '1989'], undef,                '1989',                 ''],
    ['s', '19uu', '####', ['1900', '1999'], undef,                '1999',                 ''],
    ['t', '1982', '1949', ['1949'],         '1949',               '1949',                 1],
    ['t', '198u', '1979', ['1979'],         '1979',               '1979',                 1],
    ['u', '1948', 'uuuu', ['1948', '9999'], undef,                '9999',                 ''],
    ['u', '19uu', 'uuuu', ['1900', '9999'], undef,                '9999',                 ''],
    ['u', '1uuu', 'uuuu', ['1000', '9999'], undef,                '9999',                 ''],
    # Degenerate examples
    ['s', 'abcd', '####', [],               undef,                undef,                  ''],
    ['m', 'abcd', 'efgh', [],               undef,                undef,                  ''],
    ['m', '1880', 'efgh', [],               undef,                undef,                  ''],
    ['p', '1982', 'uuuu', [],               undef,                undef,                  ''],
    ['p', '1967', '1982', ['1982'],         '1982',               '1982',                 1],
  ];

# Examples taken from https://www.loc.gov/marc/bibliographic/bd008a.html
# FIXME: Degenerate examples will be taken from HathiTrust collection.
subtest '#extract_dates' => sub {
  foreach my $test (@$TEST_DATA) {
    my $pd = CRMS::PublicationDate->new(
      date_type => $test->[0],
      date_1 => $test->[1],
      date_2 => $test->[2]);
    is_deeply($pd->extract_dates, $test->[3], "Type $test->[0] ($test->[1], $test->[2])");
  }

  subtest 'with enumcron date' => sub {
    foreach my $test (@$TEST_DATA) {
      my $pd = CRMS::PublicationDate->new(
        date_type => $test->[0],
        date_1 => $test->[1],
        date_2 => $test->[2],
        enumcron_date => '2000');
      is_deeply($pd->extract_dates, ['2000'], "Type $test->[0] ($test->[1], $test->[2]) with enumcron");
    }
  }
};

subtest '#exact_copyright_date' => sub {
  foreach my $test (@$TEST_DATA) {
    my $pd = CRMS::PublicationDate->new(
      date_type => $test->[0],
      date_1 => $test->[1],
      date_2 => $test->[2]);
    is($pd->exact_copyright_date, $test->[4], "Type $test->[0] ($test->[1], $test->[2])");
  }
};

subtest '#maximum_copyright_date' => sub {
  foreach my $test (@$TEST_DATA) {
    my $pd = CRMS::PublicationDate->new(
      date_type => $test->[0],
      date_1 => $test->[1],
      date_2 => $test->[2]);
    is($pd->maximum_copyright_date, $test->[5], "Type $test->[0] ($test->[1], $test->[2])");
  }
};

subtest '#is_single_date' => sub {
  foreach my $test (@$TEST_DATA) {
    my $pd = CRMS::PublicationDate->new(
      date_type => $test->[0],
      date_1 => $test->[1],
      date_2 => $test->[2]);
    is($pd->is_single_date, $test->[6], "Type $test->[0] ($test->[1], $test->[2])");
  }
};

subtest 'do_dates_overlap' => sub {
  subtest 'dies on undefined start date' => sub {
    my $pd = CRMS::PublicationDate->new(date_type => 'm', date_1 => '1900', date_2 => '2000');
    dies_ok { $pd->do_dates_overlap(undef, '2000'); }
  };

  subtest 'dies on undefined end date' => sub {
    my $pd = CRMS::PublicationDate->new(date_type => 'm', date_1 => '1900', date_2 => '2000');
    dies_ok { $pd->do_dates_overlap('1900'); }
  };
  my $test_data = [
    # type date1  date2   start   end     expected
    # ==== =====  =====   =====   ===     ========
    ['b', '####', '####', '1890', '1970', 0],
    ['m', '1972', '1975', '1890', '1970', 0],
    ['m', 'uuuu', '1981', '1890', '1970', 1],
    ['m', '197u', '1987', '1890', '1970', 1],
    ['m', '1943', '197u', '1890', '1970', 1],
    ['m', '1998', '9999', '1890', '1970', 0],
    ['n', 'uuuu', 'uuuu', '1890', '1970', 0],
    ['s', '1930', '####', '1890', '1970', 1],
    ['s', '1880', '####', '1890', '1970', 0],
    # These could be considered degenerate cases but are included for coverage.
    ['m', '1975', '1972', '1890', '1970', 0],
    ['m', '1975', '1972', '1980', '1990', 0],
  ];

  foreach my $test (@$test_data) {
    my $pd = CRMS::PublicationDate->new(
      date_type => $test->[0],
      date_1 => $test->[1],
      date_2 => $test->[2]);
    is($pd->do_dates_overlap($test->[3], $test->[4]), $test->[5],
      "Type $test->[0] ($test->[1], $test->[2]) do_dates_overlapType($test->[3], $test->[4])");
  }
};

done_testing();
