#!/usr/bin/perl

use strict;
use warnings;

use Test::More;

use lib $ENV{'SDRROOT'} . '/crms/lib';
use CRMS::NewYear;

my $new_year = CRMS::NewYear->new;

subtest 'new' => sub {
  isa_ok($new_year, 'CRMS::NewYear');
};

# Note: here we are testing all 59 attested attr/reason combinations attested in rights_current
# at time of writing. Some of these are a little head scratchy.
subtest 'are_rights_in_scope' => sub {
  subtest 'with in-scope rights combinations' => sub {
    my $in_scope = [
      'ic/add',
      'ic/bib',
      'ic/cdpp',
      'ic/crms',
      'ic/ipma',
      'icus/gatt',
      'icus/ren',
      'op/ipma',
      'pdus/add',
      'pdus/bib',
      'pdus/cdpp',
      'pdus/crms',
      'pdus/gfv',
      'pdus/ncn',
      'pdus/ren',
      'pdus/ncn',
      'und/bib',
      'und/crms',
      'und/ipma',
      'und/nfi',
      'und/ren',
    ];
    foreach my $rights (@$in_scope) {
      my ($attribute, $reason) = split('/', $rights);
      ok($new_year->are_rights_in_scope($attribute, $reason), "$rights is in scope");
    }
  };

  subtest 'with out-of-scope rights combinations' => sub {
    my $out_of_scope = [
      'cc-by-3.0/con',
      'cc-by-3.0/man',
      'cc-by-4.0/con',
      'cc-by-4.0/man',
      'cc-by-nc-3.0/con',
      'cc-by-nc-3.0/man',
      'cc-by-nc-4.0/con',
      'cc-by-nc-4.0/man',
      'cc-by-nc-nd-3.0/con',
      'cc-by-nc-nd-4.0/con',
      'cc-by-nc-nd-4.0/man',
      'cc-by-nc-sa-3.0/con',
      'cc-by-nc-sa-4.0/con',
      'cc-by-nd-3.0/con',
      'cc-by-nd-4.0/con',
      'cc-by-sa-3.0/con',
      'cc-by-sa-4.0/con',
      'cc-zero/con',
      'ic-world/con',
      'ic-world/man',
      'nobody/del',
      'nobody/man',
      'nobody/pvt',
      'pd/add',
      'pd/bib',
      'pd/cdpp',
      'pd/con',
      'pd/crms',
      'pd/exp',
      'pd/man',
      'pd/ncn',
      'pd/ren',
      'pdus/man',
      'pd-pvt/pvt',
      'supp/supp',
      'und-world/con',
    ];
    foreach my $rights (@$out_of_scope) {
      my ($attribute, $reason) = split('/', $rights);
      ok(!$new_year->are_rights_in_scope($attribute, $reason), "$rights is out of scope");
    }
  };
};

done_testing();
