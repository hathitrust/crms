package User;

use strict;
use warnings;
use utf8;
use 5.010;

use Carp;
use Data::Dumper;
use Scalar::Util;

use DB;
use Institution;
use Utilities;


# Everything that can be saved, which is all the fields in the DB minus id.
my $PERMITTED_FIELDS = {'email' => 1, 'name' => 1,
  'reviewer' => 1, 'advanced' => 1, 'expert' => 1, 'admin' => 1,
  'role' => 1, 'note' => 1, 'institution' => 1, 'commitment' => 1,
  'project' => 1, 'active' => 1, 'internal' => 1};
# Must be defined
my $REQUIRED_FIELDS = {'email' => 1, 'name' => 1,
  'reviewer' => 1, 'advanced' => 1, 'expert' => 1, 'admin' => 1,
  'institution' => 1, 'active' => 1, 'internal' => 1}; 
# Textual fields that should have whitespace trimmed
my $TRIM_FIELDS = {'email' => 1, 'name' => 1, 'note' => 1, 'commitment' => 1};
# Numeric fields that should be zero if not defined
my $ZERO_FIELDS = {'reviewer' => 1, 'advanced' => 1, 'expert' => 1, 'admin' => 1,
                   'internal' => 1};
# Numeric fields that should be one if not defined.
my $ONE_FIELDS = {'active' => 1};
# Textual fields that should be set to undef/NULL if empty.
my $NULL_FIELDS = {'note' => 1};


sub All {
  my $sql = 'SELECT * FROM users ORDER BY id';
  my $ref = __CRMS_DBH()->selectall_hashref($sql, 'id');
  return __users_from_hashref($ref);
}

sub Find {
  my $id = shift;

  Carp::confess "User::Find called with undef" unless defined $id;

  my $sql = 'SELECT * FROM users WHERE id=?';
  my $ref = __CRMS_DBH()->selectall_hashref($sql, 'id', undef, $id);
  my $users = __users_from_hashref($ref);
  return (scalar @$users)? $users->[0] : undef;
}

sub Where {
  my $constraints = { @_ };

  my $sql = 'SELECT * FROM users';
  my @clauses;
  my @values;
  if (scalar keys %$constraints) {
    $sql .= ' WHERE ';
    foreach my $key (keys %$constraints) {
      push @clauses, "$key=?";
      push @values, $constraints->{$key};
    }
    $sql .= join('AND', @clauses);
  }
  $sql .= ' ORDER BY active DESC, name';
  my $ref = __CRMS_DBH()->selectall_hashref($sql, 'id', undef, @values);
  return __users_from_hashref($ref);
}

sub __CRMS_DBH {
  state $dbh = CRMS::DB->new->dbh;
  return $dbh;
}

sub new {
  my $class = shift;

  my $self = { @_ };
  bless($self, $class);
  return $self;
}

sub __users_from_hashref {
  my $hashref = shift;

  my @users;
  push @users, new User(%{$hashref->{$_}}, 'persisted', 1) for keys %$hashref;
  return \@users;
}

# Returns Boolean for success of validation and database write.
sub save {
  my $self = shift;

  my $data = $self->__validate;
  if (scalar @{$self->{errors}}) {
    return 0;
  }
  my @fields;
  my @values;
  foreach my $field (keys %$data) {
    push @fields, $field;
    push @values, $data->{$field};
  }
  my $sql;
  if ($self->{persisted}) {
    my $assignments = join(',', map { "$_=?"; } @fields);
    $sql = "UPDATE users SET $assignments WHERE id=?";
    push @values, $self->{id};
  } else {
    my $field_names = join ',', @fields;
    my $bind_variables = join ',', map { '?'; } @values;
    $sql = "INSERT INTO users ($field_names) VALUES ($bind_variables)";
  }
  my $sth = __CRMS_DBH()->prepare($sql);
  eval { $sth->execute(@values); };
  # uncoverable branch true
  if ($@) {
    # Validations should prevent the operation from failing here due to bogus
    # field values so it makes sense to throw an exception.
    # Foreign key validation is a grey area.
    Carp::confess sprintf 'SQL failed (%s): %s',
      Utilities->new->StringifySql($sql, @values), $sth->errstr;
  }
  if (!$self->{persisted}) {
    $self->{id} = $sth->{mysql_insertid};
    $self->{persisted} = 1;
  }
  # Write validated data back into self.
  # Cheaper than doing a SELECT * which would, I suppose, be equivalent.
  foreach my $field_name (keys %$data) {
    $self->{$field_name} = $data->{$field_name};
  }
  return 1;
}

# Produce field -> value hash with squishy values massaged to be more DB-friendly,
# for example empty strings may make more sense as undef/NULL.
# Anything that is non-coercible or otherwise just plain wrong populates $self->{errors}
# as a side effect.
sub __validate {
  my $self = shift;
  
  $self->{errors} = [];
  my $data = {};
  my @fields = keys %$PERMITTED_FIELDS;
  foreach my $field (@fields) {
    my $normalized = $self->__normalize_field_value($field, $self->{$field});
    $data->{$field} = $normalized;
  }
  @fields = keys %$REQUIRED_FIELDS;
  foreach my $field (@fields) {
    if (!defined $data->{$field}) {
      $self->__add_error("$field must be defined");
    }
  }
  return $data;
}

sub __normalize_field_value {
  my $self  = shift;
  my $field = shift;
  my $value = shift;

  if (defined $value) {
    $value =~ s/^\s+|\s+$//g if $TRIM_FIELDS->{$field};
    $value = undef if $value eq '' and $NULL_FIELDS->{$field};
    $value = $self->__normalize_commitment($value) if $field eq 'commitment';
  } else {
    $value = 0 if $ZERO_FIELDS->{$field};
    $value = 1 if $ONE_FIELDS->{$field};
    $value = $self->__predict_institution if $field eq 'institution';
  }
  return $value;
}

sub __predict_institution {
  my $self = shift;

  my $inst = Institution::FindByEmail($self->{email});
  return $inst->{inst_id};
}

sub __normalize_commitment {
  my $self       = shift;
  my $commitment = shift;

  return undef unless length $commitment;

  if ($commitment !~ m/^\d*(\.?\d)*%?$/) {
    $self->__add_error("commitment '$commitment' not numeric");
    return $commitment;
  }
  if ($commitment =~ s/%$//) {
    $commitment /= 100.0;
  }
  return $commitment;
}

sub __add_error {
  my $self = shift;
  my $err  = shift;

  push @{$self->{errors}}, $err;
}

sub errors {
  my $self = shift;

  $self->__validate();
  return $self->{errors};
}

sub is_persisted {
  my $self = shift;

  return ($self->{persisted})? 1 : 0;
}

sub institution {
  my $self = shift;

  return undef unless $self->{institution};
  return Institution::Find($self->{institution});
}

sub is_reviewer {
  my $self = shift;

  return $self->{reviewer};
}

sub is_advanced {
  my $self = shift;

  return $self->{advanced};
}

sub is_expert {
  my $self = shift;

  return $self->{expert};
}

sub is_at_least_expert {
  my $self = shift;

  return $self->{expert} || $self->{admin};
}

sub is_admin {
  my $self = shift;

  return $self->{admin};
}

# Used for display.
sub privilege_level {
  my $self = shift;

  ($self->{reviewer} || 0)
    + (2 * ($self->{advanced} || 0))
    + (4 * ($self->{expert} || 0))
    + (8 * ($self->{admin} || 0));
}

# Only used in test suite.
# Could enable this functionality with an environment variable.
sub destroy {
  my $self = shift;

  if ($self->{persisted}) {
    my $sql = 'DELETE FROM users WHERE id=?';
    my $sth = __CRMS_DBH()->prepare($sql);
    eval { $sth->execute($self->{id}); };
    # uncoverable branch false
    if (!$@) {
      $self->{persisted} = 0;
    }
  }
}

1;

