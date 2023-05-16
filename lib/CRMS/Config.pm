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
# If the key is, for example, "ht_db_name" then the corresponding ENV is CRMS_HT_DB_NAME

use strict;
use warnings;
use utf8;

use Carp;
use File::Spec;
use YAML::XS;

# Translate CRMS_INSTANCE value into canonical non-empty string.
sub translate_instance_name {
  my $inst = shift || $ENV{CRMS_INSTANCE_NAME} || $ENV{CRMS_INSTANCE} || '';

  return 'production' if $inst eq 'production';
  return 'training' if $inst eq 'crms-training' || $inst eq 'crms_training' || $inst eq 'training';
  return 'development';
}

sub new {
  my ($class, %args) = @_;
  my $self = bless {}, $class;
  $self->{instance_name} = translate_instance_name($args{instance});
  return $self;
}

sub instance_name {
  my $self = shift;

  return $self->{instance_name};
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

# Read db.yml (and db.local.yml if it exists) and extract the subhash for CRMS_INSTANCE
sub db {
  my $self = shift;

  if (!defined $self->{db}) {
    my $db = $self->_read_config_files('db', $self->{instance_name});
    $self->{db} = $self->_merge_db_env($db);
  }
  return $self->{db};
}

# Read basename.yml and basename.local.yml, merging values from the latter into the former.
# If $instance is defined, pick out only the per-instance part of db.yml
# Alternatively, use Hash::Merge but that isn't available on our non-containerized environments.
sub _read_config_files {
  my $self     = shift;
  my $basename = shift;
  my $instance = shift;

  my $config = {};
  foreach my $file (($basename . '.yml', $basename . '.local.yml')) {
    my $path = File::Spec->catfile($self->_config_dir, $file);
    next unless -f $path;
    my $contents = YAML::XS::LoadFile($path);
    $contents = $contents->{$instance} if defined $instance;
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

# Swap in config values from environment, modifying $config in place and returning it.
# Keys are constructed as CRMS_DB_<INSTANCE>_<KEY>, eg CRMS_DB_PRODUCTION_HOST
sub _merge_db_env {
  my $self     = shift;
  my $config   = shift;

  foreach my $key (keys %$config) {
    my $env_key = join('_', 'CRMS', 'DB', uc($self->{instance_name}), uc($key));
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
