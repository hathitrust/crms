package CRMS::Database::HT;

use strict;
use warnings;
use utf8;

use Carp;
use Data::Dumper;
use DBI;

use lib "$ENV{SDRROOT}/crms/cgi";
use lib "$ENV{SDRROOT}/crms/lib/CRMS";

use CRMS::Config;
#use CRMS::Instance;
#use Utilities;

use parent 'CRMS::Database';
# The database name (db_name) from config.
# CRMS_DB_NAME or CRMS_HT_DB_NAME
sub name {
  my $self = shift;

  return $self->{config}->config->{ht_db_name};
}

# The database host (db_host) from config.
# CRMS_DB_HOST or CRMS_HT_DB_HOST
sub host {
  my $self = shift;

  return $self->{config}->config->{ht_db_host};
}

sub credentials {
  my $self = shift;

  return {
    username => $self->{config}->credentials->{ht_db_user},
    password => $self->{config}->credentials->{ht_db_password}
  };
}

1;
