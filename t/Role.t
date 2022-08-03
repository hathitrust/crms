use strict;
use warnings;
use utf8;

use Data::Dumper;
use FindBin;
use Test::More;

use lib "$FindBin::Bin/lib";
use TestHelper;

use CRMS::Role;

subtest "CRMS::Role::All" => sub {
  my $all = CRMS::Role::All();
  isa_ok($all, 'ARRAY', 'CRMS::Role::All returns arrayref');
  is(2, scalar @$all, "CRMS::Role::All returns two roles");
  isa_ok($all->[0], 'CRMS::Role', 'Role::All[0] is CRMS::Role');
  isa_ok($all->[1], 'CRMS::Role', 'Role::All[1] is CRMS::Role');
};

subtest "CRMS::Role::Find" => sub {
  my $role = CRMS::Role::Find(1);
  isa_ok($role, 'CRMS::Role', 'CRMS::Role::Find(1) finds Role');
  is(1, $role->{id}, "CRMS::Role::Find(1) finds Role with id=0");
  is('Reviewer', $role->{name}, "CRMS::Role::Find(0) finds CRMS::Role named 'Reviewer'");
};

subtest "CRMS::Role::Where" => sub {
  my $roles = CRMS::Role::Where(name => 'Expert');
  isa_ok($roles, 'ARRAY', 'CRMS::Role::Where returns arrayref');
  is(1, scalar @$roles, "CRMS::Role::Where returns one match for 'Expert'");
  is('Expert', $roles->[0]->{name}, "CRMS::Role::Where returns match named 'Expert'");
};

subtest "CRMS::Role::new" => sub {
  my $role = CRMS::Role->new(name => 'Test Role');
  isa_ok($role, 'CRMS::Role', 'Role::New returns a Role');
  is('Test Role', $role->{name}, 'CRMS::Role::New returns a CRMS::Role with the specified name');
};

done_testing();
