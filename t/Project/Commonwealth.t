#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use CGI;
use Data::Dumper;
use Test::More;

use lib $ENV{'SDRROOT'} . '/crms/cgi';
use lib $ENV{'SDRROOT'} . '/crms/t/support';
use CRMS;
use FakeMetadata;

require_ok($ENV{'SDRROOT'}. '/crms/cgi/Project/Commonwealth.pm');

my $crms = CRMS->new();
# TODO: Project::for_name would be a much nicer way to do this.
my $sql = 'SELECT id FROM projects WHERE name="Commonwealth"';
my $project_id = $crms->SimpleSqlGet($sql);
my $proj = Commonwealth->new(crms => $crms, id => $project_id);
ok(defined $proj);

subtest 'Commonwealth::year_range' => sub {
  my $year = 2020;
  my $test_data = {
    'United Kingdom' => [1895, 1949],
    'Australia' => [1895, 1949],
    'Canada' => [1895, 1971],
    'Undetermined' => [0, 0]
  };
  foreach my $country (keys %$test_data) {
    is_deeply($proj->year_range($country, $year), $test_data->{$country}, "year_range for $country");
  }
};

subtest 'Commonwealth::PresentationOrder' => sub {
  my $order = $proj->PresentationOrder;
  ok(defined $order);
  ok(length $order > 0);
};

done_testing();


