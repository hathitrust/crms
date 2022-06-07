use strict;
use warnings;
use utf8;

use Data::Dumper;
use FindBin;
use Test::More;

use lib "$FindBin::Bin/lib";
use TestHelper;

use CRMS::DB;

test_docker_connection();
test_production_connection();

sub test_docker_connection {
  my $crms_db_dev = CRMS::DB->new(name => 'crms');
  ok(defined $crms_db_dev);
  is($crms_db_dev->dsn, 'DBI:mysql:database=crms;host=mariadb');
  ok(defined $crms_db_dev->dbh);

  my $crms_db_production = CRMS::DB->new(name => 'crms', instance => 'production');
  ok(defined $crms_db_production);
  is($crms_db_production->dsn, 'DBI:mysql:database=crms;host=mariadb');

  my $ht_rights_db = CRMS::DB->new(name => 'ht');
  ok(defined $ht_rights_db);
  is($ht_rights_db->dsn, 'DBI:mysql:database=ht;host=mariadb_ht');
  ok(defined $ht_rights_db->dbh);
}

sub test_production_connection {
  my $save_host = $ENV{CRMS_SQL_HOST};
  my $save_host_ht = $ENV{CRMS_SQL_HOST_HT};
  delete $ENV{CRMS_SQL_HOST};
  delete $ENV{CRMS_SQL_HOST_HT};

  my $crms_db_dev = CRMS::DB->new();
  ok(defined $crms_db_dev);
  is($crms_db_dev->dsn, 'DBI:mysql:database=crms;host=mysql-htdev');

  my $crms_db_production = CRMS::DB->new(name => 'crms', instance => 'production');
  ok(defined $crms_db_production);
  is($crms_db_production->dsn, 'DBI:mysql:database=crms;host=mysql-sdr');

  my $ht_rights_db = CRMS::DB->new(name => 'ht_rights');
  ok(defined $ht_rights_db);
  is($ht_rights_db->dsn, 'DBI:mysql:database=ht;host=mysql-sdr');

  my $ht_repository_db = CRMS::DB->new(name => 'ht_repository');
  ok(defined $ht_repository_db);
  is($ht_repository_db->dsn, 'DBI:mysql:database=ht;host=mysql-sdr');
  ok(ref $ht_repository_db->credentials eq 'HASH');

  $ENV{CRMS_SQL_HOST} = $save_host;
  $ENV{CRMS_SQL_HOST_HT} = $save_host_ht;
}

done_testing();
