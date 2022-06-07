use strict;
use warnings;
use utf8;

use Data::Dumper;
use FindBin;
use Test::More;

use lib "$FindBin::Bin/lib";
use TestHelper;

use CRMS::Config;

ok(ref CRMS::Config::Config() eq 'HASH');
ok(ref CRMS::Config::SecretConfig() eq 'HASH');

done_testing();
