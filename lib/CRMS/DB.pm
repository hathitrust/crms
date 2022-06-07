package CRMS::DB;

use strict;
use warnings;
use utf8;
use 5.010;

use DBI;

use CRMS::Config;

# Global map of DSN to DBH so we don't run out of connections.
my %DSN_DBH_MAP;

# Module-local copies of config and secret config with environment variables
# swapped in for Docker compatibility.
sub Config {
  state $CONFIG = undef;
  return $CONFIG if defined $CONFIG;

  my $config = CRMS::Config::Config();
  $CONFIG = {};
  # Copy just the keys relevant to database connections.
  my @config_keys = qw(mysqlServer mysqlServerDev mysqlDbName
    mysqlMdpServer mysqlMdpServerDev mysqlMdpDbName);
  $CONFIG->{$_} = $config->{$_} for @config_keys;
  return $CONFIG;
}

sub SecretConfig {
  state $SECRET_CONFIG = undef;
  return $SECRET_CONFIG if defined $SECRET_CONFIG;
  
  my $config = CRMS::Config::SecretConfig();
  $SECRET_CONFIG = {
    mysqlUser => $config->{mysqlUser} || $ENV{'CRMS_SQL_USER'},
    mysqlPasswd => $config->{mysqlPasswd} || $ENV{'CRMS_SQL_PASSWD'},
    mysqlMdpUser => $config->{mysqlMdpUser} || $ENV{'CRMS_SQL_USER_HT'},
    mysqlMdpPasswd => $config->{mysqlMdpPasswd} || $ENV{'CRMS_SQL_PASSWD_HT'}
  };
  return $SECRET_CONFIG;
}


package CRMS::DB::CRMS {
  use parent 'CRMS::DB';
  sub new {
    my ($class, %args) = @_;
    my $self = bless {}, $class;
    return $self;
  }

  sub name {
    my $self = shift;

    return $self->{config}->{mysqlDbName};
  }

  sub host {
    my $self = shift;

    return $ENV{CRMS_SQL_HOST} if defined $ENV{CRMS_SQL_HOST};
    return ($self->{instance} eq 'production' || $self->{instance} eq 'crms-training') ?
      $self->{config}->{mysqlServer} : $self->{config}->{mysqlServerDev};
  }
  
  sub credentials {
    my $config = CRMS::DB::SecretConfig();
    return { 'user' => $config->{'mysqlUser'}, 'passwd' => $config->{'mysqlPasswd'} };
  }
}

package CRMS::DB::HT {
  use parent 'CRMS::DB';
  sub new {
    my ($class, %args) = @_;
    my $self = bless {}, $class;
    return $self;
  }

  sub name {
    my $self = shift;

    return $self->{config}->{mysqlMdpDbName};
  }

  sub host {
    my $self = shift;

    return $ENV{CRMS_SQL_HOST_HT} || $self->{config}->{mysqlServer};
  }
  
  sub credentials {
    my $config = CRMS::DB::SecretConfig();
    return { 'user' => $config->{'mysqlMdpUser'}, 'passwd' => $config->{'mysqlMdpPasswd'} };
  }
}

# The "name" parameter may not correspond to the actual database names since
# we're going to use the config values to end up with a DSN.
# So we'll use name => 'crms' to mean "whatever the CRMS database name is"
# in spite of the fact that it is "crms" and unlikely to ever change.
# We'll use <anything else> to mean "whatever the HT database/view" is,
# understanding that it might be necessary to once again care about
# ht_rights vs ht_repository as in ages past.
sub new {
  my $class = shift;
  my %args = @_;
  my $self = bless {}, $class;
  my $name = $args{name} || 'crms';

  if ($name eq 'crms') {
    $self = CRMS::DB::CRMS->new(@_);
  } else {
    $self = CRMS::DB::HT->new(@_);
  }
  #$self->{name} = $name;
  # Blank instance is dev.
  # Can also be 'crms-training' to use crms_training DB.
  # Can also be 'production' to use production host.
  # FIXME: this is too complex. We shouldn't have to pass the instance every time we talk to a database.
  $self->{instance} = $args{instance} || '';
  $self->{config} = Config();
  return $self;
}

sub dsn {
  my $self = shift;

  return $self->{dsn} if defined $self->{dsn};

  $self->{dsn} = sprintf "DBI:mysql:database=%s;host=%s", $self->name, $self->host;
  return $self->{dsn};
}

sub dbh {
  my $self = shift;

  return $self->{dbh} if defined $self->{dbh};
  
  my $credentials = $self->credentials;
  my $dbh = $DB::DSN_DBH_MAP{$self->dsn};
  return $dbh if defined $dbh && $dbh->ping;
  $dbh = DBI->connect($self->dsn, $credentials->{user}, $credentials->{passwd},
         { PrintError => 0, RaiseError => 1, AutoCommit => 1 }) || die "Cannot connect: $DBI::errstr";
  $dbh->{mysql_enable_utf8} = 1;
  $dbh->{mysql_auto_reconnect} = 1;
  $dbh->do('SET NAMES "utf8";');
  $self->{dbh} = $dbh;
  $DB::DSN_DBH_MAP{$self->dsn} = $dbh;
  return $dbh;
}

1;
