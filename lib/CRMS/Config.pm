package CRMS::Config;

# Create a CRMS::Config object for reading config.yml and credentials.yml.
# my $crms_config = CRMS::Config->new;
# my $config_hashref = $crms_config->config;
# my $credentials_hashref = $crms_config->credentials;
# my $some_password = $credentials_hashref->{some_password};

# The two methods pull config variables from (in increasing order and priority):
# config/{config, credentials}.yml
# config/{config, credentials}.local.yml
# ENV

# Derive ENV variable names from YML keys by upcasing and adding "CRMS_" prefix.
# If the key is, for example, "db_name" then the corresponding ENV is CRMS_DB_NAME

use strict;
use warnings;
use utf8;

use File::Spec;
use YAML::XS;

use lib "$ENV{SDRROOT}/crms/lib";
use CRMS::Instance;

sub config_directory {
  return File::Spec->catfile($ENV{SDRROOT}, 'crms', 'config');
}

sub new {
  my ($class, %args) = @_;
  my $self = bless {}, $class;
  return $self;
}

# Read config.yml (and config.local.yml if it exists)
# and overwrite any keys with values found in ENV.
sub config {
  my $self = shift;

  if (!defined $self->{config}) {
    my $config = $self->_read_config_files();
    $self->{config} = $self->_merge_env($config);
  }
  return $self->{config};
}

# Read credentials.yml (and credentials.local.yml if it exists)
# and overwrite any keys with values found in ENV.
# Does not memoize value as this is sensitive data.
sub credentials {
  my $self = shift;

  my $credentials = $self->_read_credentials_files();
  return $self->_merge_env($credentials);
}

# Read basename.yml, basename.local.yml, instances/<instance_name>.yml, instances/<instance_name>.local.yml
# merging values from the latter into the former.
sub _read_config_files {
  my $self = shift;

  my $config = {};
  my @config_files = (
    File::Spec->catfile(config_directory, 'config.yml'),
    File::Spec->catfile(config_directory, 'config.local.yml'),
    File::Spec->catfile(config_directory, 'instances', CRMS::Instance->new->name . '.yml'),
    File::Spec->catfile(config_directory, 'instances', CRMS::Instance->new->name . '.local.yml')
  );
  foreach my $file (@config_files) {
    next unless -f $file;
    my $contents = YAML::XS::LoadFile($file);
    foreach my $key (keys %$contents) {
      $config->{$key} = $contents->{$key};
    }
  }
  return $config;
}

# Read credentials.yml and credentials.local.yml, merging values from the latter into the former.
sub _read_credentials_files {
  my $self = shift;

  my $config = {};
  my @credentials_files = (
    File::Spec->catfile(config_directory, 'credentials.yml'),
    File::Spec->catfile(config_directory, 'credentials.local.yml')
  );
  foreach my $file (@credentials_files) {
    next unless -f $file;
    my $contents = YAML::XS::LoadFile($file);
    foreach my $key (keys %$contents) {
      $config->{$key} = $contents->{$key};
    }
  }
  return $config;
}

# Swap in config values from environment, modifying $config in place and returning it.
sub _merge_env {
  my $self   = shift;
  my $config = shift;

  foreach my $key (keys %$config) {
    my $env_key = 'CRMS_' . uc($key);
    if (defined $ENV{$env_key}) {
      $config->{$key} = $ENV{$env_key};
    }
  }
  return $config;
}

1;
