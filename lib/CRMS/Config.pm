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

sub new {
  my ($class, %args) = @_;
  my $self = bless {}, $class;
  return $self;
}

# Read config.yml (and config.local.yml if it exists)
# and overwrite any keys with values found in ENV.
sub config {
  my $self = shift;

  # uncoverable branch false
  if (!defined $self->{config}) {
    my $config = $self->_read_config_files('config');
    $self->{config} = $self->_merge_env($config);
  }
  return $self->{config};
}

# Read credentials.yml (and credentials.local.yml if it exists)
# and overwrite any keys with values found in ENV.
sub credentials {
  my $self = shift;

  # uncoverable branch false
  if (!defined $self->{credentials}) {
    my $credentials = $self->_read_config_files('credentials');
    $self->{credentials} = $self->_merge_env($credentials);
  }
  return $self->{credentials};
}

# Read basename.yml and basename.local.yml, merging values from the latter into the former.
sub _read_config_files {
  my $self     = shift;
  my $basename = shift;

  my $config = {};
  foreach my $file (($basename . '.yml', $basename . '.local.yml')) {
    my $path = File::Spec->catfile($self->_config_dir, $file);
    next unless -f $path;
    my $contents = YAML::XS::LoadFile($path);
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

sub _config_dir {
  my $self = shift;

  return File::Spec->catfile($ENV{SDRROOT}, 'crms', 'config');
}

1;
