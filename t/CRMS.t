use strict;
use warnings;
use Data::Dumper;
#use Data::Faker::Internet;
use FindBin;
use Test::Exception;
use Test::More;

use lib "$FindBin::Bin/lib";
use TestHelper;
use Factories;

use User;

my $crms = TestHelper::CRMS;
$crms->set('die_on_error', 1);
ok(defined $crms);

test_Version();
test_Instance();
test_WebPath();
test_FSPath();
test_BuildURL();
test_get();
test_set();
test_DbInfo();
test_GetCandidatesSize();
done_testing();

sub test_Version {
  ok($crms->Version =~ m/^\d+\.\d+(\.\d+)?$/);
}

sub test_Instance {
  my $test_crms = CRMS->new(instance => 'production');
  is($test_crms->Instance(), 'production');
  $test_crms = CRMS->new(instance => 'crms-training');
  is($test_crms->Instance(), 'training');
  $test_crms = CRMS->new();
  is($test_crms->Instance(), 'dev');
  $test_crms = CRMS->new(instance => 'some_random_garbage');
  is($test_crms->Instance(), 'dev');
}

sub test_WebPath {
  is('/crms/prep/test.txt', $crms->WebPath('prep', 'test.txt'));
  dies_ok { $crms->WebPath('blah', 'test.txt') } 'Dies on nonexistent directory type';
}

sub test_FSPath {
  is('/htapps/babel/crms/prep/test.txt', $crms->FSPath('prep', 'test.txt'));
  dies_ok { $crms->FSPath('blah', 'test.txt') } 'Dies on nonexistent directory type';
}

sub test_BuildURL {
  is('crms?p=test', $crms->BuildURL('test'));
  is('crms?p=test&param1=value1', $crms->BuildURL('test', 'param1', 'value1'));
  is('crms?p=test&param1=value1&param2=value2', $crms->BuildURL('test', 'param1', 'value1', 'param2', 'value2'));
  is('crms?p=test&param1=', $crms->BuildURL('test', 'param1'));
  is('crms?p=test&param1=&param2=value2', $crms->BuildURL('test', 'param1', undef, 'param2', 'value2'));
  is('crms?param1=value1', $crms->BuildURL('', 'param1', 'value1'));
}

sub test_get {
  $crms->set('test_get_key', 'test_get_value');
  is('test_get_value', $crms->get('test_get_key'));
  ok(!defined $crms->get('some_mostly_impossible_test_get_key'));
}

sub test_set {
  $crms->set('test_set_key', 'test_set_value');
  is('test_set_value', $crms->{test_set_key});
}

sub test_DbInfo {
  is($crms->DbInfo(), 'Instance <blank> Location DEV Connection DBI:mysql:database=crms;host=mariadb as crms');
}

sub test_GetCandidatesSize {
  $crms->PrepareSubmitSql('DELETE FROM projects');
  $crms->PrepareSubmitSql('DELETE FROM candidates');
  $crms->PrepareSubmitSql('INSERT INTO projects (id,name) VALUES (1,"Core")');
  $crms->PrepareSubmitSql('INSERT INTO candidates (id,project) VALUES (?,1)', "mdp.$_") for (1 .. 5);
  is($crms->GetCandidatesSize(), 5);
  $crms->PrepareSubmitSql('DELETE FROM candidates');
  $crms->PrepareSubmitSql('DELETE FROM projects');
}

