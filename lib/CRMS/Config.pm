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

# Keys, particularly those for credentials, may have subkeys corresponding to
# canonical instance names {production, training, development}.
# For this reason, this module is the single point of truth for the instance,
# which currently is also used and abused inside CRMS.pm for display purposes.
# Using this module (until a CRMS::Instance module is eventually spun off) as the
# preferred source should help clean up some of the silliness there.

use strict;
use warnings;
use utf8;

use File::Spec;
use YAML::XS;

sub new {
  my ($class, %args) = @_;
  my $self = bless {}, $class;
  $self->{instance} = translate_instance_name($args{instance});
  return $self;
}

# The canonical name for the instance which can be used as a subkey for per-instance config.
# Translate CRMS_INSTANCE value into canonical non-empty string.
sub translate_instance_name {
  my $inst = shift || $ENV{CRMS_INSTANCE} || '';

  return 'production' if $inst eq 'production';
  return 'training' if $inst eq 'crms-training' || $inst eq 'crms_training' || $inst eq 'training';
  return 'development';
}

# Return the canonical instance name for use in CRMS.pm for various purposes.
sub instance {
  my $self = shift;

  return $self->{instance};
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
      my $value = $contents->{$key};
      # If the value is a hash, look for {production, training, development} subkeys.
      if (ref $value eq 'HASH') {
        # If misconfigured and instance is not available, use empty string.
        $value = $value->{$self->instance} || '';
      }
      $config->{$key} = $value;
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
