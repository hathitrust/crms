use strict;
use warnings;
use utf8;

use FindBin;
use Test::More;

use lib "$FindBin::Bin/../lib";

use CRMS::Jira;


is(CRMS::Jira::LinkToJira('HT-000'),
   '<a href="https://hathitrust.atlassian.net/browse/HT-000" target="_blank">HT-000</a>',
   'Jira::LinkToJira produces the correct URL');
my $req = CRMS::Jira::Request('GET', 'some/path/to/something');
isa_ok $req, "HTTP::Request";

done_testing();
