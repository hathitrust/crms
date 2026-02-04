package CRMS::Utility::Data;

use strict;
use warnings;
use utf8;

use UUID qw();

# This is a stateless class so it's fine for the singleton pattern.
my $ONE_TRUE_UTILITY_DATA;

sub new {
  my ($class, %args) = @_;
  my $self = bless {}, $class;

  if (!defined $ONE_TRUE_UTILITY_DATA) {
    $ONE_TRUE_UTILITY_DATA = $self;
  }
  return $ONE_TRUE_UTILITY_DATA;
}

# TODO: deprecate CRMS::UUID in favor of this method.
sub uuid {
  my $self = shift;

  return UUID::uuid4;
}

1;

