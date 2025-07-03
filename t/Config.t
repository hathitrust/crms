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

  subtest 'CRMS::Config is singleton' => sub {
    is_deeply($config, CRMS::Config->new);
  };
};

subtest 'CRMS::Config::instance' => sub {
  subtest 'CRMS::Config::instance production' => sub {
    my $instance = CRMS::Config->new(reinitialize => 1, instance => 'production')->instance;
    is($instance, 'production');
  };

  subtest 'CRMS::Config::instance training' => sub {
    my @variants = qw(crms-training crms_training training);
    foreach my $variant (@variants) {
      my $instance = CRMS::Config->new(reinitialize => 1, instance => $variant)->instance;
      is($instance, 'training');
    }
  };

  subtest 'CRMS::Config::instance development' => sub {
    my $instance = CRMS::Config->new(reinitialize => 1, instance => '')->instance;
    is($instance, 'development');

    subtest 'CRMS::Config with no instance param and no ENV defaults to `development`' => sub {
      $ENV{CRMS_INSTANCE} = 'development';
      my $instance = CRMS::Config->new(reinitialize => 1)->instance;
      is($instance, 'development');
      delete $ENV{CRMS_INSTANCE};
    };
  };
};

subtest 'CRMS::Config::config' => sub {
  my $config = CRMS::Config->new(reinitialize => 1)->config;
  ok(ref $config eq 'HASH');
};

subtest 'CRMS::Config::config with overriding ENV' => sub {
  my $save_env = $ENV{'CRMS_DB_HOST'};
  $ENV{'CRMS_DB_HOST'} = 'test_crms_db_host_value';
  my $config = CRMS::Config->new(reinitialize => 1)->config;
  is($config->{'db_host'}, 'test_crms_db_host_value');
  $ENV{'CRMS_DB_HOST'} = $save_env;
};

subtest 'CRMS::Config::config with config.local.yml' => sub {
  my $config_local_sample = $ENV{'SDRROOT'} . '/crms/config/config.local.yml.sample';
  my $config_local = $ENV{'SDRROOT'} . '/crms/config/config.local.yml';
  File::Copy::copy($config_local_sample, $config_local) or Carp::confess "Copy failed: $!";

  subtest 'subkey present' => sub {
    my $config = CRMS::Config->new(reinitialize => 1)->config;
    is($config->{'missing_subkey_test'}, 'missing_subkey_test_development');
  };

  subtest 'subkey missing' => sub {
    my $config = CRMS::Config->new(reinitialize => 1, instance => 'training')->config;
    is($config->{'missing_subkey_test'}, '');
  };

  unlink $config_local;
};

subtest 'CRMS::Config::credentials' => sub {
  my $credentials = CRMS::Config->new(reinitialize => 1)->credentials;
  ok(ref $credentials eq 'HASH');
};

subtest 'CRMS::Config::credentials with overriding ENV' => sub {
  my $save_env = $ENV{'CRMS_DB_USER'};
  $ENV{'CRMS_DB_USER'} = 'test_crms_db_user_value';
  my $credentials = CRMS::Config->new(reinitialize => 1)->credentials;
  is($credentials->{'db_user'}, 'test_crms_db_user_value');
  $ENV{'CRMS_DB_USER'} = $save_env;
};

subtest 'CRMS::Config::credentials with credentials.local.yml' => sub {
  my $credentials_local_sample = $ENV{'SDRROOT'} . '/crms/config/credentials.local.yml.sample';
  my $credentials_local = $ENV{'SDRROOT'} . '/crms/config/credentials.local.yml';
  File::Copy::copy($credentials_local_sample, $credentials_local) or Carp::confess "Copy failed: $!";
  my $credentials = CRMS::Config->new(reinitialize => 1)->credentials;
  is($credentials->{'db_user'}, 'sample_value');
  unlink $credentials_local;
};

subtest 'sanity check config keys' => sub {
  my $config = CRMS::Config->new(reinitialize => 1);
  foreach my $key (keys %{$config->config}) {
    ok($key =~ m/^[a-z_]+$/, "check key $key");
  }
  foreach my $key (keys %{$config->credentials}) {
    ok($key =~ m/^[a-z_]+$/, "check key $key");
  }
};

subtest 'database config for crms_training instance' => sub {
  my $config = CRMS::Config->new(reinitialize => 1, instance => 'crms_training');
  # docker-compose ENV messes with db_host and we don't have different values for db_user
  is($config->config->{'db_name'}, 'crms_training');
  is($config->credentials->{'db_password'}, 'crms_training');
};


done_testing();
