#!/usr/bin/perl

use strict;
use warnings;

use Test::Exception;
use Test::More;

use lib $ENV{'SDRROOT'} . '/crms/cgi';
use lib $ENV{'SDRROOT'} . '/crms/lib';
use CRMS;
use CRMS::Entitlements;

my $crms = CRMS->new;

subtest '::new' => sub {
  my $rights = CRMS::Entitlements->new(crms => $crms);
  isa_ok($rights, 'CRMS::Entitlements');
  
  subtest 'Missing CRMS' => sub {
    dies_ok { CRMS::Entitlements->new; };
  };
};

subtest 'rights_by_id' => sub {
  my $rights = CRMS::Entitlements->new(crms => $crms)->rights_by_id(5);
  is($rights->{id}, 5);
};

subtest 'rights_by_attribute_reason' => sub {
  subtest 'with ids' => sub {
    my $rights = CRMS::Entitlements->new(crms => $crms)->rights_by_attribute_reason(2, 7);
    is($rights->{attribute_name}, 'ic');
    is($rights->{reason_name}, 'ren');
    is($rights->{name}, 'ic/ren');
  };
  
  subtest 'with names' => sub {
    my $rights = CRMS::Entitlements->new(crms => $crms)->rights_by_attribute_reason('ic', 'ren');
    is($rights->{attribute_name}, 'ic');
    is($rights->{reason_name}, 'ren');
    is($rights->{name}, 'ic/ren');
  };
};

subtest 'attribute_by_id' => sub {
  my $attr = CRMS::Entitlements->new(crms => $crms)->attribute_by_id(1);
  is($attr->{name}, 'pd', 'attribute 1 is named "pd"');
};

subtest 'attribute_by_name' => sub {
  my $attr = CRMS::Entitlements->new(crms => $crms)->attribute_by_name('pd');
  is($attr->{id}, 1, 'attribute "pd" is id=1');
};

subtest 'reason_by_id' => sub {
  my $reason = CRMS::Entitlements->new(crms => $crms)->reason_by_id(1);
  is($reason->{name}, 'bib', 'reason 1 is named "bib"');
};

subtest 'reason_by_name' => sub {
  my $reason = CRMS::Entitlements->new(crms => $crms)->reason_by_name('bib');
  is($reason->{id}, 1, 'reason "bib" is id=1');
};

done_testing();
