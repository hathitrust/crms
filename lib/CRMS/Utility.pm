package CRMS::Utility;

use strict;
use warnings;
use utf8;

use lib "$ENV{SDRROOT}/crms/lib";
use CRMS::Utility::Data qw();
use CRMS::Utility::URL qw();

# This is a stateless class so it's fine for the singleton pattern.
# Modules under the Utility umbrella are cached and/or singletons themselves.
# The important thing is, it must be easy and cheap to get the needed object
# given a top-level CRMS::Utility object.
# This singleton is passed to the templates as `utility` in `cgi/crms`
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

sub url {
  my $self = shift;

  if (!defined $self->{url}) {
    $self->{url} = CRMS::Utility::URL->new;
  }
  return $self->{url};
}

1;
