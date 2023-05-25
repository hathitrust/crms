#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use Test::More;

use lib "$ENV{SDRROOT}/crms/lib";
use CRMS::Country;

subtest '.new' => sub {
  isa_ok(CRMS::Country->new, 'CRMS::Country');
};

subtest '#country_data' => sub {
  isa_ok(CRMS::Country->new->country_data, 'HASH');
};

subtest '#from_code' => sub {
  subtest 'short version' => sub {
    is(CRMS::Country->new->from_code('xx'), 'Undetermined [xx]');
    is(CRMS::Country->new->from_code(''), 'Undetermined []');
    is(CRMS::Country->new->from_code(undef), 'Undetermined [undef]');
    is(CRMS::Country->new->from_code('|||'), 'Undetermined [|||]');
    is(CRMS::Country->new->from_code('aca'), 'Australia');
    is(CRMS::Country->new->from_code('|aca|'), 'Australia');
    is(CRMS::Country->new->from_code('xb'), 'Cocos (Keeling) Islands');
    # Guard against borked-up UTF-8 here or in YML data
    is(CRMS::Country->new->from_code('iv'), "Côte d'Ivoire");
  };

  subtest 'long version' => sub {
    is(CRMS::Country->new->from_code('xx', 1), 'Undetermined [xx]');
    is(CRMS::Country->new->from_code('', 1), 'Undetermined []');
    is(CRMS::Country->new->from_code(undef, 1), 'Undetermined [undef]');
    is(CRMS::Country->new->from_code('|||', 1), 'Undetermined [|||]');
    is(CRMS::Country->new->from_code('aca', 1), 'Australia (Australian Capital Territory)');
    is(CRMS::Country->new->from_code('|aca|', 1), 'Australia (Australian Capital Territory)');
    is(CRMS::Country->new->from_code('xb', 1), 'Cocos (Keeling) Islands');
    # Guard against borked-up UTF-8 here or in YML data
    is(CRMS::Country->new->from_code('iv', 1), "Côte d'Ivoire");
  };
};

subtest '#from_name' => sub {
  my $country = CRMS::Country->new;
  my $canada_codes = [qw(abc bcc cn mbc nfc nkc nsc ntc nuc onc pic quc snc xxc ykc)];
  is_deeply($country->from_name('Canada'), $canada_codes);
  is_deeply($country->from_name('Dogpatch and Lower Slobbovia'), []);
};

done_testing();

