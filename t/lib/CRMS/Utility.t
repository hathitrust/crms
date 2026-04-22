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
  my $data = CRMS::Utility->new->data;
  ok(defined $data);

  subtest 'CRMS::Utility::Data cached' => sub {
    is_deeply($data, CRMS::Utility->new->data);
  };
};

subtest '#url' => sub {
  my $url = CRMS::Utility->new->url;
  ok(defined $url);

  subtest 'CRMS::Utility::URL cached' => sub {
    is_deeply($url, CRMS::Utility->new->url);
  };
};

done_testing();
