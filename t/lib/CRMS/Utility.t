use strict;
use warnings;
use utf8;

use Test::Exception;
use Test::More;

use lib "$ENV{SDRROOT}/crms/lib";

use CRMS::Utility;

subtest '#new' => sub {
  ok(defined CRMS::Utility->new);
};

subtest '#data' => sub {
  ok(defined CRMS::Utility->new->data);
};

done_testing();
