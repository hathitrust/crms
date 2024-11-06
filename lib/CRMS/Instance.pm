package CRMS::Instance;

use strict;
use warnings;
use utf8;

my $singleton_instance;

# This is only to be used in tests
sub test_reinitialize {
  $singleton_instance = undef;
}

sub new {
  my ($class, %args) = @_;
  if (defined $singleton_instance) {
    return $singleton_instance;
  }
  my $self = bless {}, $class;
  $self->{name} = translate_instance_name($args{instance});
  $singleton_instance = $self;
  return $self;
}

sub name {
  my $self = shift;

  return $self->{name};
}

# Translate CRMS_INSTANCE value into canonical non-empty string.
sub translate_instance_name {
  my $inst = shift || $ENV{CRMS_INSTANCE} || '';

  return 'production' if $inst eq 'production';
  return 'training' if $inst eq 'crms-training' || $inst eq 'crms_training' || $inst eq 'training';
  return 'development';
}

1;
