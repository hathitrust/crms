package TestHelper;

use strict;
use warnings;
use utf8;
use 5.010;

use lib "$ENV{SDRROOT}/crms/cgi";
use lib "$ENV{SDRROOT}/crms/lib";

use CRMS;
use CRMS::DB;

my $TEST_HELPER_SINGLETON;

sub new {
  return $TEST_HELPER_SINGLETON if defined $TEST_HELPER_SINGLETON;

  my ($class, %args) = @_;
  my $self = bless {}, $class;
  $TEST_HELPER_SINGLETON = $self;
  return $self;
}

sub fixtures_directory {
  my $self = shift;

  state $fixtures_dir = $ENV{'SDRROOT'} . '/crms/t/fixtures/';
  return $fixtures_dir;
}

sub crms {
  my $self = shift;

  if (!defined $self->{crms}) {
    $self->{crms} = CRMS->new;
  }
  return $self->{crms};
}

sub db {
  my $self = shift;

  if (!defined $self->{db}) {
    $self->{db} = CRMS::DB->new->dbh;
  }
  return $self->{db};
}

sub htdb {
  my $self = shift;

  if (!defined $self->{htdb}) {
    $self->{htdb} = CRMS::DB->new(name => 'ht')->dbh;
  }
  return $self->{htdb};
}

1;
