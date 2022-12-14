#!/usr/bin/perl

use strict;
use warnings;
use utf8;

BEGIN { unshift(@INC, $ENV{'SDRROOT'}. '/crms/cgi'); }

use Encode;
use Test::More;

use Jira;

is(Jira::LinkToJira('HT-000'),
   '<a href="https://hathitrust.atlassian.net/browse/HT-000" target="_blank">HT-000</a>',
   'Jira::LinkToJira produces the correct URL');
my $req = Jira::Request('GET', 'some/path/to/something');
isa_ok $req, "HTTP::Request";

done_testing();
