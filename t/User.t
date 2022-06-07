use strict;
use warnings;
use utf8;

#BEGIN { unshift(@INC, $ENV{'SDRROOT'}. '/crms/cgi'); }

use Data::Dumper;
use FindBin;
use Scalar::Util;
use Test::Exception;
use Test::More;

use lib "$FindBin::Bin/lib";
use Factories;
use TestHelper;

#use CRMS;
use User;


my $crms = TestHelper->new->crms;

test_All();
test_Find();
test_Where();
test_new();
test_save();
test_update();
test_normalize();
test_validate();
test_is_reviewer();
test_is_advanced();
test_is_expert();
test_is_at_least_expert();
test_is_admin();
test_privilege_level();
test_commitment();
test_normalize();
done_testing();

sub setup {
  #my $before = $crms->SimpleSqlGet('SELECT COUNT(*) FROM users');
  #$crms->PrepareSubmitSql('DELETE FROM users');
  #my $after = $crms->SimpleSqlGet('SELECT COUNT(*) FROM users');
  #print STDERR "User.t::setup before $before after $after\n";
}

sub test_All {
  setup();
  my $user1 = Factories::User;
  $user1->save;
  my $all_users = User::All;
  isa_ok($all_users, 'ARRAY', 'User:All returns arrayref');
  ok(scalar @$all_users > 1, 'User::All returns multiple Users');
}

sub test_Find {
  setup();
  my $user = Factories::User;
  my $user_id = $user->{id};
  $user = User::Find($user_id);
  ok(defined $user, 'User::Find retrieves User by id');
  $user = User::Find(999999);
  ok(!defined $user, 'User::Find returns undef when asked for nonexistent User');
}

sub test_Where {
  setup();
  
  my $result = User::Where(admin => 1);
  ok(scalar @$result > 0);
  is($result->[0]->{admin}, 1);
  $result = User::Where;
  ok(scalar @$result > 0);
}

sub test_new {
  setup();
  my $user = User->new(email => 'test_new_email', name => 'test_new_name');
  isa_ok($user, 'User', 'User::New returns a User');
  ok(!$user->is_persisted, 'New User is not persisted');
}

sub test_save {
  setup();
  my $user = Factories::User;
  is($user->is_persisted, 1, 'New User is persisted after save');
  my $user_id = $user->{id};
  ok(Scalar::Util::looks_like_number($user_id), 'Saved User gets numeric id');
  $user->destroy;
}

sub test_update {
  setup();
  my $user = Factories::User;
  $user->{note} = 'a note';
  $user->save;
  is($user->is_persisted, 1, 'New User is persisted after update');
  ok('a note' eq $crms->SimpleSqlGet('SELECT note FROM users WHERE id=?', $user->{id}),
    'Updated field is written to database');
}

sub test_normalize {
  setup();
  my $user = Factories::User(note => ' a note ', commitment => ' 85% ');
  my $note = $crms->SimpleSqlGet('SELECT note FROM users WHERE id=?', $user->{id});
  my $commitment = $crms->SimpleSqlGet('SELECT commitment FROM users WHERE id=?', $user->{id});
  is($note, 'a note', 'Normalized note field');
  is($commitment, '0.8500', 'Normalized note field');
  my $user1 = Factories::User(note => '');
  ok(!defined $user1->{note}, 'blank note set to undef');
  ok(!defined $crms->SimpleSqlGet('SELECT note FROM users WHERE id=?', $user1->{id}),
    'blank note set to NULL');
}

sub test_validate {
  setup();
  my $user = Factories::User();
  $user->{email} = undef;
  my $errs = $user->errors;
  ok(defined $errs && scalar @$errs && $errs->[0] =~ m/email must be defined/);
  my $user2 = Factories::User();
  $user2->{project} = 10000;
  dies_ok { $user2->save; } 'Dies on foreign key violation';
}

sub test_is_reviewer {
  setup();
  my $user1 = Factories::User(reviewer => 0);
  my $user2 = Factories::User(reviewer => 1);
  ok(!$user1->is_reviewer);
  ok($user2->is_reviewer);
}

sub test_is_advanced{
  setup();
  my $user1 = Factories::User(advanced => 0);
  my $user2 = Factories::User(advanced => 1);
  ok(!$user1->is_advanced);
  ok($user2->is_advanced);
}

sub test_is_expert {
  setup();
  my $user1 = Factories::User(expert => 0);
  my $user2 = Factories::User(expert => 1);
  ok(!$user1->is_expert);
  ok($user2->is_expert);
}

sub test_is_at_least_expert {
  setup();
  my $user1 = Factories::User(expert => 0);
  my $user2 = Factories::User(expert => 1, admin => 0);
  my $user3 = Factories::User(expert => 1, admin => 1);
  my $user4 = Factories::User(expert => 0, admin => 1);
  ok(!$user1->is_at_least_expert);
  ok($user2->is_at_least_expert);
  ok($user3->is_at_least_expert);
  ok($user4->is_at_least_expert);
}

sub test_is_admin {
  setup();
  my $user1 = Factories::User(admin => 0);
  my $user2 = Factories::User(admin => 1);
  ok(!$user1->is_admin);
  ok($user2->is_admin);
}

sub test_privilege_level {
  setup();
  my $user1 = Factories::User(reviewer => 1);
  my $user2 = Factories::User(reviewer => 1, advanced => 1);
  my $user3 = Factories::User(expert => 1);
  my $user4 = Factories::User(admin => 1);
  my $user5 = Factories::User(reviewer => 1, advanced => 1, expert => 1, admin => 1);
  is($user1->privilege_level, 1);
  is($user2->privilege_level, 3);
  is($user3->privilege_level, 4);
  is($user4->privilege_level, 8);
  is($user5->privilege_level, 15);
}

sub test_commitment {
  setup();
  my $user1 = Factories::User(commitment => '50%');
  cmp_ok($user1->{commitment}, '==', 0.5);
  my $user2 = Factories::User(commitment => '.5');
  cmp_ok($user2->{commitment}, '==', 0.5);
  my $user3 = Factories::User(commitment => 'xyz');
  my $errs = $user3->errors;
  ok(defined $errs && scalar @$errs && $errs->[0] =~ m/commitment/);
}

