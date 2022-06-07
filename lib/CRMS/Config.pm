package CRMS::Config;

use strict;
use warnings;
use utf8;
use 5.010;

sub Config {
  state $CONFIG;

  unless (defined $CONFIG) {
    $CONFIG = __read_config_file(__config_dir() . 'crms.cfg');
  }
  return $CONFIG;
}

sub SecretConfig {
  state $SECRET_CONFIG;

  unless (defined $SECRET_CONFIG) {
    $SECRET_CONFIG = __read_config_file(__config_dir() . 'crmspw.cfg');
  }
  return $SECRET_CONFIG;
}

# To be moved from crms/bin to crms/etc.
sub __config_dir {
  my $path = $ENV{SDRROOT};
  $path .= '/' unless $path =~ m/\/$/;
  $path .= 'crms/bin/';
  return $path;
}

sub __read_config_file {
  my $path = shift;

  my $config = {};
  my $fh;
  unless (open $fh, '<:encoding(UTF-8)', $path) {
    return $config;
  }
  read $fh, my $buff, -s $path;
  close $fh;
  my @lines = split "\n", $buff;
  foreach my $line (@lines) {
    $line =~ s/#.*//;
    if ($line =~ m/(\S+)\s*=\s*(\S+(\s+\S+)*)/i) {
      $config->{$1} = $2;
    }
  }
  return $config;
}

1;
