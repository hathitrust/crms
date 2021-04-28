#!/usr/bin/perl

use strict;
use warnings;
BEGIN { unshift(@INC, $ENV{'SDRROOT'}. '/crms/cgi'); }

use Test::More;
use CRMS;

my $crms = CRMS->new();
my $licensing = Licensing->new('crms' => $crms);
ok($licensing , 'new returns a value');
# my $query = $licensing->query(['coo.31924086708454']);
ok(ref $licensing->attributes() eq 'ARRAY', 'attributes return value is arrayref');
ok(ref $licensing->reasons() eq 'ARRAY', 'reasons return value is arrayref');
done_testing();

