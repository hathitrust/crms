package CRMS::Utility::Time;
# Date and time functions

use strict;
use warnings;
use utf8;

use POSIX qw();

# This is a stateless class so it's fine for the singleton pattern.
my $ONE_TRUE_UTILITY_TIME;

sub new {
  my ($class, %args) = @_;
  my $self = bless {}, $class;

  if (!defined $ONE_TRUE_UTILITY_TIME) {
    $ONE_TRUE_UTILITY_TIME = $self;
  }
  return $ONE_TRUE_UTILITY_TIME;
}

# Current year in 'YYYY' format.
sub year {
  my $self = shift;

  return POSIX::strftime "%Y", localtime;
}

1;
