#!/usr/bin/perl

use strict;
use warnings;
BEGIN { unshift(@INC, $ENV{'SDRROOT'}. '/crms/cgi'); }

use Test::More;
use CRMS;

my $crms = CRMS->new();
my $record = Metadata->new('id' => 'coo.31924000029250', 'crms' => $crms);
my $cities = $record->_ReadCities;
ok(ref $cities eq 'HASH', '_ReadCities return value is a hashref');
ok(scalar keys %$cities > 0, '_ReadCities hash has multiple keys');

$cities = $record->cities;
ok(ref $cities eq 'HASH', 'cities return value is a hashref');
ok(ref $cities->{'us'} eq 'ARRAY', 'cities us value is an arrayref');
ok(ref $cities->{'non-us'} eq 'ARRAY', 'cities non-us value is an arrayref');
done_testing();
