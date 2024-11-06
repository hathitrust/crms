#!/usr/bin/perl

use strict;
use warnings;

use Test::Exception;
use Test::More;

use lib $ENV{'SDRROOT'} . '/crms/lib';
use CRMS::Instance;


subtest '::new' => sub {
  # We have to assume the singleton is already set,
  # so we reinit the module before each test and at the end.
  subtest 'development (default)' => sub {
    CRMS::Instance::test_reinitialize;
    my $instance = CRMS::Instance->new();
    is($instance->name, 'development');
  };

  subtest 'production' => sub {
    CRMS::Instance::test_reinitialize;
    my $instance = CRMS::Instance->new(instance => 'production');
    is($instance->name, 'production');
  };

  subtest 'training' => sub {
    CRMS::Instance::test_reinitialize;
    my $instance = CRMS::Instance->new(instance => 'crms_training');
    is($instance->name, 'training');
  };
  # Clean up the mess we've made of the instance singleton.
  CRMS::Instance::test_reinitialize;

  subtest 'same object' => sub {
    my $instance_1 = CRMS::Instance->new();
    my $instance_2 = CRMS::Instance->new();
    is_deeply($instance_1, $instance_2, "the two instances are the same object");
  };
};

done_testing();
