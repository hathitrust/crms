package CRMS::Database;

use strict;
use warnings;
use utf8;

use Carp qw();
use Data::Dumper;
use DBI;

use lib "$ENV{SDRROOT}/crms/cgi";
# FIXME: needed?
use lib "$ENV{SDRROOT}/crms/lib/CRMS";

use CRMS::Config;
#use CRMS::Instance;
use Utilities;

# Global map of DSN to DBH so we don't run out of connections.
my %DSN_DBH_MAP;

sub new {
  my $class = shift;
  my %args  = @_;

  my $self = bless {}, $class;
  $self->{config} = CRMS::Config->new;
  $self->{noop} = $args{noop};
  return $self;
}

# ===== DEFAULT FOR crms DATABASE OVERRIDDEN BY CRMS::Database::HT subclass ===
# The database name (db_name) from config.
sub name {
  my $self = shift;

  return $self->{config}->config->{db_name};
}

# The database host (db_host) from config.
sub host {
  my $self = shift;

  return $self->{config}->config->{db_host};
}

# Database credentials (db_user/db_password) from config credentials.
# Note that the config name should be `db_username` instead of `db_user` for
# consistency with other HathiTrust codebases.
sub credentials {
  my $self = shift;

  return {
    username => $self->{config}->credentials->{db_user},
    password => $self->{config}->credentials->{db_password}
  };
}

# ===== THE REST OF THE MODULE SHOULD WORK FOR CRMS AND HT DATABASES ===
# DSN for connecting to the database, defaults to the CRMS database.
sub dsn {
  my $self = shift;

  return $self->{dsn} if defined $self->{dsn};

  $self->{dsn} = sprintf "DBI:mysql:database=%s;host=%s", $self->name, $self->host;
  return $self->{dsn};
}

# The database connection. The `DSN_DBH_MAP` makes these connections almost-global.
sub dbh {
  my $self = shift;

  return $self->{dbh} if defined $self->{dbh} && $self->{dbh}->ping;
  my $dbh = $DB::DSN_DBH_MAP{$self->dsn};
  return $dbh if defined $dbh && $dbh->ping;

  my $credentials = $self->credentials;
  $dbh = DBI->connect($self->dsn, $credentials->{username}, $credentials->{password},
         { PrintError => 0, RaiseError => 1, AutoCommit => 1 }) || die "Cannot connect: $DBI::errstr";
  $dbh->{mysql_enable_utf8} = 1;
  $dbh->{mysql_auto_reconnect} = 1;
  $dbh->do('SET NAMES "utf8";');
  $self->{dbh} = $dbh;
  $DB::DSN_DBH_MAP{$self->dsn} = $dbh;
  return $dbh;
}

# Get one result. Returns `undef` if there is no result.
# Raises on error.
sub one {
  my $self = shift;
  my $sql  = shift;

  my $ref;
  eval {
    $ref = $self->dbh->selectall_arrayref($sql, undef, @_);
  };
  if ($@) {
    $self->handle_error($@, $sql, @_);
  }
  return unless defined $ref;
  return $ref->[0]->[0];
}

# The old-style inefficient read-everything-into-memory approach.
# Returns an arrayref of hashrefs mapped to unmodified column names.
# Returns empty arrayref if no results.
# Raises on error.
sub all {
  my $self = shift;
  my $sql  = shift;

  my $ref;
  eval {
    $ref = $self->dbh->selectall_arrayref($sql, { Slice => {} }, @_);
  };
  if ($@) {
    $self->handle_error($@, $sql, @_);
  }
  return $ref;
}

# An efficient method that provides the caller's block with one hashref per row.
sub for {
  my $self = shift;
  my $sql  = shift;
  my $proc = pop;

  my $sth;
  my %row;
  eval {
    $sth = $self->dbh->prepare($sql);
    $sth->execute(@_);
    $sth->bind_columns(\@row{ @{$sth->{NAME}} });
  };
  if ($@) {
    $self->handle_error($sth->errstr, $sql, @_);
  }
  while ($sth->fetch) {
    &$proc(\%row);
  }
}

sub submit {
  my $self = shift;
  my $sql  = shift;

  return 1 if $self->{noop};
  my $sth;
  eval {
    $sth = $self->dbh->prepare($sql);
    die "NO STATEMENT HANDLE?" unless defined $sth;
    use Data::Dumper;
    printf "PARAMS %s\n", Dumper \@_;
    $sth->execute(@_);
    $sth->finish;
  };
  if ($@) {
    $self->handle_error($sth->errstr, $sql, @_);
  }
  return 1;
}

sub handle_error {
  my $self   = shift;
  my $errstr = shift;
  my $sql    = shift;

  my $sql_s = Utilities::StringifySql($sql, @_);
  Carp::confess("SQL failed ($sql_s): $errstr");
}

sub info {
  my $self = shift;

  my $db_user = $self->credentials->{username};
  my $dsn = $self->dsn();
  my $instance = $self->{config}->instance;
  return "DB Info:\nInstance $instance\n$dsn as $db_user";
}

1;