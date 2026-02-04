package CRMS::Utility;

use strict;
use warnings;
use utf8;

use lib "$ENV{SDRROOT}/crms/lib";
use CRMS::Utility::Data qw();

# This is a stateless class so it's fine for the singleton pattern.
my $ONE_TRUE_UTILITY;

sub new {
  my ($class, %args) = @_;
  my $self = bless {}, $class;

  if (!defined $ONE_TRUE_UTILITY) {
    $ONE_TRUE_UTILITY = $self;
  }
  return $ONE_TRUE_UTILITY;
}

sub data {
  my $self = shift;

  if (!defined $self->{data}) {
    $self->{data} = CRMS::Utility::Data->new;
  }
  return $self->{data};
}

1;
