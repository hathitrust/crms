use strict;
use warnings;
use utf8;

use Carp;
use File::Copy;
use Test::More;

use lib $ENV{'SDRROOT'} . '/crms/lib';

use CRMS::Config;

subtest 'CRMS::Config' => sub {
  my $config = CRMS::Config->new;
  ok(ref $config eq 'CRMS::Config');
};

subtest 'CRMS::Config::config' => sub {
  my $config = CRMS::Config->new->config;
  ok(ref $config eq 'HASH');
};

subtest 'CRMS::Config::config with overriding ENV' => sub {
  my $save_env = $ENV{'CRMS_DB_HOST'};
  $ENV{'CRMS_DB_HOST'} = 'test_crms_db_host_value';
  my $config = CRMS::Config->new->config;
  is($config->{'db_host'}, 'test_crms_db_host_value');
  $ENV{'CRMS_DB_HOST'} = $save_env;
};

subtest 'CRMS::Config::config with config.local.yml' => sub {
  my $config_local_sample = $ENV{'SDRROOT'} . '/crms/config/config.local.yml.sample';
  my $config_local = $ENV{'SDRROOT'} . '/crms/config/config.local.yml';
  File::Copy::copy($config_local_sample, $config_local) or Carp::confess "Copy failed: $!";
  my $config = CRMS::Config->new->config;
  is($config->{'host'}, 'sample.hathitrust.org');
  unlink $config_local;
};

subtest 'CRMS::Config::credentials' => sub {
  my $credentials = CRMS::Config->new->credentials;
  ok(ref $credentials eq 'HASH');
};

subtest 'CRMS::Config::credentials with overriding ENV' => sub {
  my $save_env = $ENV{'CRMS_DB_USER'};
  $ENV{'CRMS_DB_USER'} = 'test_crms_db_user_value';
  my $credentials = CRMS::Config->new->credentials;
  is($credentials->{'db_user'}, 'test_crms_db_user_value');
  $ENV{'CRMS_DB_USER'} = $save_env;
};

subtest 'CRMS::Config::credentials with credentials.local.yml' => sub {
  my $credentials_local_sample = $ENV{'SDRROOT'} . '/crms/config/credentials.local.yml.sample';
  my $credentials_local = $ENV{'SDRROOT'} . '/crms/config/credentials.local.yml';
  File::Copy::copy($credentials_local_sample, $credentials_local) or Carp::confess "Copy failed: $!";
  my $credentials = CRMS::Config->new->credentials;
  is($credentials->{'data_api_access_key'}, 'sample_value');
  unlink $credentials_local;
};

subtest 'sanity check config keys' => sub {
  my $config = CRMS::Config->new;
  foreach my $key (keys %{$config->config}) {
    ok($key =~ m/^[a-z_]+$/, "check key $key");
  }
  foreach my $key (keys %{$config->credentials}) {
    ok($key =~ m/^[a-z_]+$/, "check key $key");
  }
};


done_testing();
