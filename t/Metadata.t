#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use Test::More;

use lib $ENV{SDRROOT} . '/crms/cgi';
use Metadata;

$ENV{CRMS_METADATA_FIXTURES_PATH} = $ENV{'SDRROOT'} . '/crms/t/fixtures/metadata';

subtest "Metadata::US_Cities" => sub {
  my $cities = Metadata::US_Cities;
  ok(ref $cities eq 'HASH', 'Metadata::US_Cities return value is a hashref');
  ok(scalar keys %$cities > 0, 'Metadata::US_Cities hash has multiple keys');
};

subtest "Metadata->new with HTID" => sub {
  my $id = 'coo.31924000029250';
  my $record = Metadata->new('id' => $id);
  isa_ok($record, 'Metadata');
  ok(!$record->is_error);
  is($record->id, $id);
  is($record->sysid, '001502282');
};

subtest "Metadata->new with CID" => sub {
  my $id = '001502282';
  my $record = Metadata->new('id' => $id);
  isa_ok($record, 'Metadata');
  ok(!$record->is_error);
  is($record->id, $id);
  is($record->sysid, '001502282');
};

subtest "Record cities hash" => sub {
  my $id = 'coo.31924000029250';
  my $record = Metadata->new('id' => $id);
  my $cities = $record->cities;
  ok(ref $cities eq 'HASH', 'cities return value is a hashref');
  ok(ref $cities->{'us'} eq 'ARRAY', 'cities us value is an arrayref');
  ok(ref $cities->{'non-us'} eq 'ARRAY', 'cities non-us value is an arrayref');
};

delete $ENV{CRMS_METADATA_FIXTURES_PATH};

done_testing();

