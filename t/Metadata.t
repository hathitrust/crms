#!/usr/bin/perl

use strict;
use warnings;
BEGIN { unshift(@INC, $ENV{'SDRROOT'}. '/crms/cgi'); }

use Test::More;
use CRMS;
#use Data::Dumper;

#my $cgi = CGI->new();
my $crms = CRMS->new();
my $record = Metadata->new('id' => 'coo.31924000029250', 'crms' => $crms);
my $cities = $record->_ReadCities;
ok(ref $cities eq 'HASH', 'cities return value is a hashref');
ok(scalar keys %$cities > 0, 'cities hash has multiple keys');
done_testing();
