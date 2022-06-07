use strict;
use warnings;
use utf8;

use Data::Dumper;
use FindBin;
use Test::More;

use lib "$FindBin::Bin/lib";
use TestHelper;

use CRMS::Config;

subtest 'CRMS::Config::Config()' => sub {
  my $config = CRMS::Config::Config();
  ok(ref $config eq 'HASH');
  is($config->{senderEmail}, 'crms-mailbot@umich.edu');
};

subtest 'CRMS::Config::SecretConfig()' => sub {
  my $config = CRMS::Config::SecretConfig();
  ok(ref $config eq 'HASH');
};

done_testing();
