
#!/usr/bin/perl

use strict;
use warnings;
BEGIN { unshift(@INC, $ENV{'SDRROOT'}. '/crms/cgi'); }

use Test::More;

require_ok($ENV{'SDRROOT'}. '/crms/cgi/CRMS.pm');
my $cgi = CGI->new();
my $crms = CRMS->new('cgi' => $cgi, 'verbose' => 0);
ok(defined $crms);
done_testing();
