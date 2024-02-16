#!/usr/bin/perl

use strict;
use warnings;

use Test::More;

use lib $ENV{'SDRROOT'} . '/crms/lib';
use CRMS::Field008Formatter;

my $FAKE_008 = '850423s1940    uk a          000 0 eng d';

subtest '::new' => sub {
  my $formatter = CRMS::Field008Formatter->new;
  isa_ok($formatter, 'CRMS::Field008Formatter');
};

subtest '#pad' => sub {
  # Make sure we always get back 40 characters.
  subtest 'with a normal 008' => sub {
    my $formatter = CRMS::Field008Formatter->new;
    is(length($formatter->pad($FAKE_008)), 40);
  };

  subtest 'with a truncated 008' => sub {
    my $formatter = CRMS::Field008Formatter->new;
    is(length($formatter->pad('850423')), 40);
  };

  subtest 'with an undefined 008' => sub {
    my $formatter = CRMS::Field008Formatter->new;
    is(length($formatter->pad()), 40);
  };
};

subtest '#format' => sub {
  # Make sure we get back a string.
  subtest 'with a well-formed 008' => sub {
    my $formatter = CRMS::Field008Formatter->new;
    is(ref $formatter->format($FAKE_008), '');
  };

  subtest 'with a truncated 008' => sub {
    my $formatter = CRMS::Field008Formatter->new;
    is(ref $formatter->format(''), '');
  };
};

done_testing();
