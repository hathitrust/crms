package CRMS::DB;

use strict;
use warnings;
use utf8;
#use 5.010;

use Carp;
use Data::Dumper;
use DBI;

use lib "$ENV{SDRROOT}/crms/cgi";

use CRMS::Config;
use Utilities;

# Global map of DSN to DBH so we don't run out of connections.
my %DSN_DBH_MAP;

package CRMS::DB::CRMS {
  use parent 'CRMS::DB';
  sub new {
    my ($class, %args) = @_;
    my $self = bless {}, $class;
    return $self;
  }

  sub name {
    my $self = shift;

    return $self->{config}->db->{name};
  }

  sub host {
    my $self = shift;

    return $self->{config}->db->{host};
  }

  sub credentials {
    my $self = shift;

    return {
      user => $self->{config}->db->{user},
      passwd => $self->{config}->db->{password}
    };
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

    return $self->{config}->config->{ht_db_name};
  }

  sub host {
    my $self = shift;

    return $self->{config}->config->{ht_db_host};
  }
  
  sub credentials {
    my $self = shift;

    return {
      user => $self->{config}->credentials->{ht_db_user},
      passwd => $self->{config}->credentials->{ht_db_password}
    };
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
  my $name = $args{name} || 'crms';

  my $config = CRMS::Config->new(instance => $args{instance});
  my $self = ($name eq 'crms') ? CRMS::DB::CRMS->new : CRMS::DB::HT->new;
  $self->{config} = $config;
  $self->{noop} = $args{noop};
  $self->{error_handler} = $args{error_handler};
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

  return $self->{dbh} if defined $self->{dbh} && $self->{dbh}->ping;
  my $dbh = $DB::DSN_DBH_MAP{$self->dsn};
  return $dbh if defined $dbh && $dbh->ping;

  my $credentials = $self->credentials;
  $dbh = DBI->connect($self->dsn, $credentials->{user}, $credentials->{passwd},
         { PrintError => 0, RaiseError => 1, AutoCommit => 1 }) || die "Cannot connect: $DBI::errstr";
  $dbh->{mysql_enable_utf8} = 1;
  $dbh->{mysql_auto_reconnect} = 1;
  $dbh->do('SET NAMES "utf8";');
  $self->{dbh} = $dbh;
  $DB::DSN_DBH_MAP{$self->dsn} = $dbh;
  return $dbh;
}

sub all {
  my $self = shift;
  my $sql  = shift;

  my $ref;
  eval {
    $ref = $self->dbh->selectall_arrayref($sql, undef, @_);
  };
  if ($@) {
    $self->handle_error($@, $sql, @_);
    return;
  }
  return $ref;
}

sub one {
  my $self = shift;
  my $sql  = shift;

  my $ref = $self->all($sql, @_);
  return $ref->[0]->[0];
}

sub submit {
  my $self = shift;
  my $sql  = shift;

  return 1 if $self->{noop};
  my $sth = $self->dbh->prepare($sql);
  eval {
    $sth->execute(@_);
    $sth->finish;
  };
  if ($@) {
    $self->handle_error($sth->errstr, $sql, @_);
    return 0;
  }
  return 1;
}

sub handle_error {
  my $self   = shift;
  my $errstr = shift;
  my $sql    = shift;

  if ($self->{error_handler}) {
    $self->{error_handler}->($errstr, $sql, @_);
  } else {
    my $sql_s = Utilities::StringifySql($sql, @_);
    Carp::confess("SQL failed ($sql_s): $errstr");
  }
}

sub info {
  my $self = shift;

  my $db_config = $self->{config}->db;
  my $db_user = $self->credentials->{user};
  my $dsn = $self->dsn();
  return "DB Info:\nInstance $self->{config}->instance_name\n$dsn as $db_user";
}

1;
