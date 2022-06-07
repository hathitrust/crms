use strict;
use warnings;
use utf8;

use Data::Dumper;
use FindBin;
use Test::More;

use lib "$FindBin::Bin/lib";
use TestHelper;

use Institution;

subtest "Institution::Default" => sub {
  my $default = Institution::Default();
  isa_ok($default, 'Institution', 'Institution::Default returns Institution');
  is('umich', $default->{inst_id}, 'Institution::Default returns umich');
};

subtest "Institution::All" => sub {
  my $all = Institution::All();
  isa_ok($all, 'ARRAY', 'Institution::All returns arrayref');
  ok(scalar @$all, "Institution::All returns multiple objects");
  isa_ok($all->[0], 'Institution', 'Institution::All[0] is Institution');
};

subtest "Institution::Active" => sub {
  my $active = Institution::Active();
  isa_ok($active, 'ARRAY', 'Institution::Active returns arrayref');
  ok(scalar @$active, "Institution::Active returns multiple objects");
  isa_ok($active->[0], 'Institution', 'Institution::Active[0] is Institution');
  foreach my $institution (@$active) {
    is(1, $institution->{enabled}, "$institution->{inst_id} is enabled");
  }
};

subtest "Institution::Find" => sub {
  my $institution = Institution::Find('pitt');
  isa_ok($institution, 'Institution', 'Institution::Find(pitt) finds Institution');
  is('pitt', $institution->{inst_id}, "Institution::Find(0) finds Institution with inst_id 'pitt'");
  is('University of Pittsburgh', $institution->{name}, "Institution::Find(0) finds Institution named 'University of Pittsburgh'");
};

subtest "Institution::FindByEmail" => sub {
  my $institution = Institution::FindByEmail('invalid_uniqname@umich.edu');
  isa_ok($institution, 'Institution', 'Institution::Find(pitt) finds Institution');
  is('umich', $institution->{inst_id}, 'Institution::FindByEmail finds Institution with suffix umich.edu');
};

subtest "Institution::Where" => sub {
  my $institutions = Institution::Where(domain => 'pitt.edu');
  isa_ok($institutions, 'ARRAY', 'Institution::Where returns arrayref');
  is(1, scalar @$institutions, "Institution::Where returns one match for domain 'pitt.edu'");
  is('pitt', $institutions->[0]->{inst_id}, "Institution::Where returns match 'pitt'");
};

subtest "Institution::new" => sub {
  my $institution = Institution->new(name => 'Test Institution');
  isa_ok($institution, 'Institution', 'Institution::New returns an Institution');
  is('Test Institution', $institution->{name}, 'Institution::New returns a Institution with the specified name');
};

subtest "short_name" => sub {
  my $default = Institution::Default();
  is('Michigan', $default->short_name, "University of Michigan default name 'Michigan'");
};

done_testing();
