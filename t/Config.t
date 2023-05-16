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
  isa_ok($config, 'CRMS::Config');
};

subtest 'CRMS::Config::instance_name' => sub {
  is(CRMS::Config::translate_instance_name('production'), 'production');
  is(CRMS::Config::translate_instance_name('training'), 'training');
  is(CRMS::Config::translate_instance_name('crms-training'), 'training');
  is(CRMS::Config::translate_instance_name('crms_training'), 'training');
  is(CRMS::Config::translate_instance_name('development'), 'development');
  is(CRMS::Config::translate_instance_name(''), 'development');
  is(CRMS::Config::translate_instance_name(), 'development');
};

subtest '#config' => sub {
  my $config = CRMS::Config->new->config;
  isa_ok($config, 'HASH');

  subtest 'with overriding ENV' => sub {
    my $save_env = $ENV{'CRMS_HT_DB_HOST'};
    $ENV{'CRMS_HT_DB_HOST'} = 'test_crms_ht_db_host_value';
    my $config = CRMS::Config->new->config;
    is($config->{'ht_db_host'}, 'test_crms_ht_db_host_value');
    $ENV{'CRMS_HT_DB_HOST'} = $save_env;
  };

  subtest 'with config.local.yml' => sub {
    my $config_local_sample = $ENV{'SDRROOT'} . '/crms/config/config.local.yml.sample';
    my $config_local = $ENV{'SDRROOT'} . '/crms/config/config.local.yml';
    File::Copy::copy($config_local_sample, $config_local) or Carp::confess "Copy failed: $!";
    my $config = CRMS::Config->new->config;
    is($config->{'host'}, 'sample.hathitrust.org');
    unlink $config_local;
  };
};

subtest '#credentials' => sub {
  my $credentials = CRMS::Config->new->credentials;
  isa_ok($credentials, 'HASH');

  subtest 'with overriding ENV' => sub {
    my $save_env = $ENV{'CRMS_HT_DB_USER'};
    $ENV{'CRMS_HT_DB_USER'} = 'test_crms_ht_db_user_value';
    my $credentials = CRMS::Config->new->credentials;
    is($credentials->{'ht_db_user'}, 'test_crms_ht_db_user_value');
    $ENV{'CRMS_HT_DB_USER'} = $save_env;
  };

  subtest 'with credentials.local.yml' => sub {
    my $credentials_local_sample = $ENV{'SDRROOT'} . '/crms/config/credentials.local.yml.sample';
    my $credentials_local = $ENV{'SDRROOT'} . '/crms/config/credentials.local.yml';
    File::Copy::copy($credentials_local_sample, $credentials_local) or Carp::confess "Copy failed: $!";
    my $credentials = CRMS::Config->new->credentials;
    is($credentials->{'data_api_access_key'}, 'sample_value');
    unlink $credentials_local;
  };
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

subtest '#db' => sub {
  my $db = CRMS::Config->new->db;
  isa_ok($db, 'HASH');
  
  subtest 'with overriding ENV' => sub {
    my $save_env = $ENV{'CRMS_DB_DEVELOPMENT_HOST'};
    $ENV{'CRMS_DB_DEVELOPMENT_HOST'} = 'test_crms_db_development_host_value';
    my $db = CRMS::Config->new->db;
    is($db->{'host'}, 'test_crms_db_development_host_value');
    $ENV{'CRMS_DB_DEVELOPMENT_HOST'} = $save_env;
  };
  
  subtest 'with db.local.yml' => sub {
    my $db_local_sample = $ENV{'SDRROOT'} . '/crms/config/db.local.yml.sample';
    my $db_local = $ENV{'SDRROOT'} . '/crms/config/db.local.yml';
    File::Copy::copy($db_local_sample, $db_local) or Carp::confess "Copy failed: $!";
    my $db = CRMS::Config->new->db;
    is($db->{'name'}, 'sample-development-name');
    unlink $db_local;
  };
};

done_testing();
