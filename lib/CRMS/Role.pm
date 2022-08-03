package CRMS::Role;

use strict;
use warnings;
use utf8;
use 5.010;

use Carp;
use Data::Dumper;
use Scalar::Util;

use DB;
use Utilities;

sub All {
  my $sql = 'SELECT * FROM roles ORDER BY id';
  my $ref = CRMS::DB->new->dbh->selectall_hashref($sql, 'id');
  return __roles_from_hashref($ref);
}

sub Find {
  my $id = shift;

  Carp::confess "Role::Find called with undef" unless defined $id;

  my $sql = 'SELECT * FROM roles WHERE id=?';
  my $ref = CRMS::DB->new->dbh->selectall_hashref($sql, 'id', undef, $id);
  my $roles = __roles_from_hashref($ref);
  return (scalar @$roles)? $roles->[0] : undef;
}

sub Where {
  my $constraints = { @_ };

  my $sql = 'SELECT * FROM roles';
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
  $sql .= ' ORDER BY id ASC';
  my $ref = CRMS::DB->new->dbh->selectall_hashref($sql, 'id', undef, @values);
  return __roles_from_hashref($ref);
}

sub new {
  my $class = shift;

  my $self = { @_ };
  bless($self, $class);
  return $self;
}

sub __roles_from_hashref {
  my $hashref = shift;

  my @roles;
  push @roles, new CRMS::Role(%{$hashref->{$_}}) for keys %$hashref;
  return \@roles;
}

1;

