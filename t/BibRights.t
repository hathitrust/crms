#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use Test::More;

use lib "$ENV{SDRROOT}/crms/cgi";
use BibRights;

$ENV{CRMS_METADATA_FIXTURES_PATH} = $ENV{'SDRROOT'} . '/crms/t/fixtures/metadata';

subtest "Creates a BibRights object" => sub {
  my $br = BibRights->new();
  isa_ok $br, "BibRights";
};

subtest "Makes a BibRights query for HT id" => sub {
  my $br = BibRights->new();
  my $result = $br->query('coo.31924000029250');
  isa_ok($result, 'HASH');
  ok(!defined $result->{error});
  isa_ok($result->{entries}, 'ARRAY');
  ok(scalar @{$result->{entries}} == 1);
};

subtest "Makes a BibRights query for HT id with enumcron" => sub {
  my $br = BibRights->new();
  my $result = $br->query('mdp.39076000925557');
  ok(!defined $result->{error});
  ok(scalar @{$result->{entries}} == 1);
  ok(length($result->{entries}->[0]->{desc}) > 0);
};

subtest "Makes a BibRights query for catalog id" => sub {
  my $br = BibRights->new();
  my $result = $br->query('001502282');
  isa_ok($result, 'HASH');
  ok(!defined $result->{error});
  isa_ok($result->{entries}, 'ARRAY');
};

subtest "Makes a failing BibRights query" => sub {
  my $br = BibRights->new();
  my $result = $br->query('000000000');
  isa_ok($result, 'HASH');
  ok(defined $result->{error});
  #isa_ok($result->{entries}, 'ARRAY');
};

delete $ENV{CRMS_METADATA_FIXTURES_PATH};

done_testing();
