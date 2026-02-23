use strict;
use warnings;
use utf8;

use Test::Exception;
use Test::More;

use lib "$ENV{SDRROOT}/crms/lib";

use CRMS::Utility::Data;

subtest '#new' => sub {
  ok(defined CRMS::Utility::Data->new);
};

subtest '#uuid' => sub {
  my $uuid = CRMS::Utility::Data->new->uuid;
  ok(
    $uuid =~ m/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/,
    'UUID matches expected format'
  );
};

done_testing();
