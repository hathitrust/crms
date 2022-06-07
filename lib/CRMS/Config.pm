package CRMS::Config;

use strict;
use warnings;
use utf8;
use 5.010;

use Carp;
use YAML::XS;

sub Config {
  state $CONFIG;

  unless (defined $CONFIG) {
    $CONFIG = __read_config_file(__config_dir() . 'settings.yml');
  }
  return $CONFIG;
}

sub SecretConfig {
  state $SECRET_CONFIG;

  unless (defined $SECRET_CONFIG) {
    $SECRET_CONFIG = __read_config_file(__config_dir() . 'credentials.yml');
  }
  return $SECRET_CONFIG;
}

# To be moved from crms/bin to crms/etc or crms/config.
sub __config_dir {
  my $path = $ENV{SDRROOT};
  $path .= '/' unless $path =~ m/\/$/;
  $path .= 'crms/config/';
  return $path;
}

sub __read_config_file {
  my $path = shift;

  my $config = {};
  return $config unless (-f $path);
  $config = YAML::XS::LoadFile($path);
  return $config;
}

1;
