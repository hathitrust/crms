#!/usr/bin/perl

use strict;
use warnings;
use utf8;

BEGIN { unshift(@INC, $ENV{'SDRROOT'}. '/crms/cgi'); }

use Encode;
use Test::More;
use CRMS;
use Jira;

my $crms = CRMS->new();
is(Jira::LinkToJira($crms, 'HT-000'),
   '<a href="https://tools.lib.umich.edu/jira/browse/HT-000" target="_blank">HT-000</a>',
   'Jira::LinkToJira produces the correct URL');
done_testing();

