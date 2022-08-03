use strict;
use warnings;
use Data::Dumper;
#use Data::Faker::Internet;
use FindBin;
#use Test::Exception;
use Test::More;

use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../lib";
use TestHelper;
use Factories;

use CRMS::Session;

#my $crms = TestHelper::CRMS;

# Write access via mdp-admin user should only be used for seeding the database.
my $dbh = DBI->connect("DBI:mysql:database=ht;host=mariadb_ht", 'mdp-admin', 'mdp-admin',
  { PrintError => 0, RaiseError => 1, AutoCommit => 1 }) || die "Cannot connect: $DBI::errstr";
$dbh->{mysql_enable_utf8} = 1;
$dbh->{mysql_auto_reconnect} = 1;
$dbh->do('SET NAMES "utf8";');

my @sqls = (
  'DELETE FROM ht_users WHERE userid IN ("uniqname_1","opaque_shib_id_2","user_3@example.com","user_4_userid@example.com")',
  'DELETE FROM ht_users WHERE userid IN ("ht_user_no_mfa","ht_user_mfa")',
  'DELETE FROM ht_institutions WHERE inst_id IN ("test_inst_id","test_inst_id_2")',
  # For SetupUser tests
  'INSERT INTO ht_users (userid,email) VALUES ("uniqname_1","user_1@example.com")',
  'INSERT INTO ht_users (userid,email) VALUES ("opaque_shib_id_2","user_2@example.com")',
  'INSERT INTO ht_users (userid,email) VALUES ("user_3@example.com","user_3@example.com")',
  'INSERT INTO ht_users (userid,email) VALUES ("user_4_userid@example.com","user_4_email@example.com")',
  # For NeedStepupAuth tests
  'INSERT INTO ht_users (userid,email) VALUES ("ht_user_no_mfa","ht_user_no_mfa@example.com")',
  'INSERT INTO ht_users (userid,email,mfa) VALUES ("ht_user_mfa","ht_user_mfa@example.com",1)',
  'INSERT INTO ht_institutions (name,template,domain,us,enabled,inst_id,shib_authncontext_class,entityID)'.
    ' VALUES ("test_name","test_template","test_domain",1,1,"test_inst_id","test_shib_authncontext_class","test_entityID")',
  'INSERT INTO ht_institutions (name,template,domain,us,enabled,inst_id,shib_authncontext_class,entityID)'.
    ' VALUES ("test_name_2","test_template_2","test_domain_2",1,1,"test_inst_id_2","test_shib_authncontext_class_2","test_entityID_2")'
);

foreach my $sql (@sqls) {
  my $sth = $dbh->prepare($sql);
  $sth->execute();
}

subtest "ENV{X-Remote-User} -> uniqname" => sub {
  my $user = Factories::User(email => 'uniqname_1');
  my $session = CRMS::Session->new(env => {'X-Remote-User' => 'uniqname_1'});
  is($session->{remote_user}, $user->{id});
  $user->destroy;
};

subtest "ENV{X-Remote-User} -> HT opaque Shib ID" => sub {
  my $user = Factories::User(email => 'user_2@example.com');
  my $session = CRMS::Session->new(env => {'X-Remote-User' => 'opaque_shib_id_2'});
  is($session->{remote_user}, $user->{id});
  $user->destroy;
};

subtest "ENV{X-Shib-mail} -> ht_users.email" => sub {
  my $user = Factories::User(email => 'user_3@example.com');
  my $session = CRMS::Session->new(env => {'X-Shib-mail' => 'user_3@example.com'});
  is($session->{remote_user}, $user->{id});
  $user->destroy;
};

subtest "Weird situation X-Shib-mail -> ht_users.userid and ht_users.email -> crms.users.email" => sub {
  my $user = Factories::User(email => 'user_4_email@example.com');
  my $session = CRMS::Session->new(env => {'X-Shib-mail' => 'user_4_userid@example.com'});
  is($session->{remote_user}, $user->{id});
  $user->destroy;
};

subtest "test NeedStepUpAuth" => sub {
  my $session = CRMS::Session->new(env => {});
  is($session->NeedStepUpAuth('ht_user_no_mfa'), 0);
  my $env = {'X-Shib-AuthnContext-Class' => 'test_shib_authncontext_class',
    'X-Shib-Identity-Provider' => 'test_entityID'};
  $session = CRMS::Session->new(env => $env);
  is($session->NeedStepUpAuth('ht_user_mfa'), 0);
  $env = {'X-Shib-AuthnContext-Class' => 'test_shib_authncontext_class',
    'X-Shib-Identity-Provider' => 'test_entityID_2'};
  $session = CRMS::Session->new(env => $env);
  is($session->NeedStepUpAuth('ht_user_mfa'), 1);
};

subtest "SetAlias" => sub {
  subtest "SetAlias without an alias has no effect" => sub {
    my $user = Factories::User(email => 'uniqname_1');
    my $session = CRMS::Session->new(env => {'X-Remote-User' => 'uniqname_1'});
    $session->SetAlias;
    ok(!defined $session->{alias_user_id});
    $user->destroy;
  };

  subtest "SetAlias with an existing user sets alias_user_id" => sub {
    my $user = Factories::User(email => 'uniqname_1');
    my $user2 = Factories::User();
    my $session = CRMS::Session->new(env => {'X-Remote-User' => 'uniqname_1'});
    $session->SetAlias($user2->{id});
    is($session->{alias_user_id}, $user2->{id});
    $user->destroy;
    $user2->destroy;
  };

  subtest "SetAlias with an existing alias drops alias_user_id" => sub {
    my $user = Factories::User(email => 'uniqname_1');
    my $user2 = Factories::User();
    my $session = CRMS::Session->new(env => {'X-Remote-User' => 'uniqname_1'});
    $session->SetAlias($user2->{id});
    $session->SetAlias();
    ok(!defined $session->{alias_user_id});
    $user->destroy;
    $user2->destroy;
  };

  subtest "SetAlias with an same user does not set alias_user_id" => sub {
    my $user = Factories::User(email => 'uniqname_1');
    my $session = CRMS::Session->new(env => {'X-Remote-User' => 'uniqname_1'});
    $session->SetAlias($user->{id});
    ok(!defined $session->{alias_user_id});
    $user->destroy;
  };
};

teardown();

sub teardown {
  my @sqls = (
    'DELETE FROM ht_users WHERE userid IN ("uniqname_1","opaque_shib_id_2","user_3@example.com","user_4_userid@example.com")',
    'DELETE FROM ht_users WHERE userid IN ("ht_user_no_mfa","ht_user_mfa")',
    'DELETE FROM ht_institutions WHERE inst_id IN ("test_inst_id","test_inst_id_2")'
  );

  foreach my $sql (@sqls) {
    my $sth = $dbh->prepare($sql);
    $sth->execute();
  }
}

done_testing();



