package CRMS::Entitlements;

# NOTE THIS IS A TEMPORARY NAME
# CRMS::Rights conflicts with a method defined in the CRMS module
# Once this module is proven, it can replace some/all of the rights/attributes/reasons
# methods in CRMS.pm

# Manages an in-memory copy of the crms.rights table
# and through it the attributes and reasons it ties together.

# As of CRMS version 8.7.1 the crms.rights table has a UNIQUE constraint on the attr,reason
# combination. As a result, a method like `rights_by_attribute_reason` need never worry
# about handling more than one result.

use strict;
use warnings;

use Data::Dumper;

# This is a singleton. Rights, attributes, and reasons are static and can be cached.
# Derivatives based on project_rights, if any, should not be cached because they can change.
my $ONE_TRUE_ENTITLEMENTS;

sub new {
  my ($class, %args) = @_;
  if (!$ONE_TRUE_ENTITLEMENTS) {
    my $self = bless {}, $class;
    # TODO: once we have a standalone DB module this can go away.
    my $crms = $args{crms};
    if (!defined $crms) {
      die "CRMS::Entitlements module needs CRMS instance.";
    }
    $self->{crms} = $crms;
    # Eager load lookup tables
    $self->_load_tables;
    $ONE_TRUE_ENTITLEMENTS = $self;
  }
  return $ONE_TRUE_ENTITLEMENTS;
}

sub rights_by_id {
  my $self = shift;
  my $id   = shift;

  return $self->{rights}->{$id};
}

sub rights_by_attribute_reason {
  my $self      = shift;
  my $attribute = shift;
  my $reason    = shift;

  # Translate attribute and reason into names if numeric
  if ($attribute =~ m/^\d+$/) {
    $attribute = $self->attribute_by_id($attribute)->{name};
  }
  if ($reason =~ m/^\d+$/) {
    $reason = $self->reason_by_id($reason)->{name};
  }
  return $self->{rights_by_name}->{"$attribute/$reason"};
}

# Returns a hashref with the fields id, type, dscr, name just as they appear in the
# `attributes` table
sub attribute_by_id {
  my $self = shift;
  my $id   = shift;

  return $self->{attributes_by_id}->{$id};
}

# Returns a hashref with the fields id, type, dscr, name just as they appear in the
# `attributes` table
sub attribute_by_name {
  my $self = shift;
  my $name = shift;

  return $self->{attributes_by_name}->{$name};
}

# Returns a hashref with the fields id, dscr, name just as they appear in the
# `reasons` table
sub reason_by_id {
  my $self = shift;
  my $id   = shift;

  return $self->{reasons_by_id}->{$id};
}

# Returns a hashref with the fields id, dscr, name just as they appear in the
# `reasons` table
sub reason_by_name {
  my $self = shift;
  my $name = shift;

  return $self->{reasons_by_name}->{$name};
}

# Set up slightly duplicative lookup tables for fast attribute/reason access by id or by name.
# Also set up rights lookup by id.
sub _load_tables {
  my $self = shift;

  # crms.attributes
  my $sql = 'SELECT * FROM attributes ORDER BY id';
  $self->{attributes_by_id} = $self->{crms}->GetDb->selectall_hashref($sql, 'id');
  $self->{attributes_by_name} = $self->{crms}->GetDb->selectall_hashref($sql, 'name');
  # crms.reasons
  $sql = 'SELECT * FROM reasons ORDER BY id';
  $self->{reasons_by_id} = $self->{crms}->GetDb->selectall_hashref($sql, 'id');
  $self->{reasons_by_name} = $self->{crms}->GetDb->selectall_hashref($sql, 'name');
  # crms.rights
  $self->{rights} = {};
  $self->{rights_by_name} = {};
  $sql = 'SELECT * FROM rights ORDER BY id';
  $self->{rights} = $self->{crms}->GetDb->selectall_hashref($sql, 'id');
  # Decorare each entry with attribute and reason names
  foreach my $id (keys %{$self->{rights}}) {
    my $rights = $self->{rights}->{$id};
    my $attr_name = $self->attribute_by_id($rights->{attr})->{name};
    my $reason_name = $self->reason_by_id($rights->{reason})->{name};
    $rights->{attribute_name} = $attr_name;
    $rights->{reason_name} = $reason_name;
    $rights->{name} = "$attr_name/$reason_name";
    $self->{rights_by_name}->{$rights->{name}} = $rights;
  }
}

1;
