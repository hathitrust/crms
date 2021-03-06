#!/usr/bin/perl

use strict;
use warnings;
use utf8;

BEGIN { unshift(@INC, $ENV{'SDRROOT'}. '/crms/cgi'); }

use Encode;
use Test::More;
use CRMS;
use Keio;
binmode(STDOUT, ':encoding(UTF-8)');

my $crms = CRMS->new();
my $keio = Keio->new('crms' => $crms);
ok($keio , 'new returns a value');

ok(ref $keio->Tables() eq 'ARRAY', 'Tables return value is arrayref');
is(2, scalar $keio->Queries(), 'two possible queries');
is('Author Name', $keio->Translation('著者名'), '"Author Name" translation succeeds');
done_testing();

