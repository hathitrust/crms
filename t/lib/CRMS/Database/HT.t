use strict;
use warnings;
use utf8;

use Data::Dumper;
use Test::Exception;
use Test::More;

use lib "$ENV{SDRROOT}/crms/lib";

use CRMS::Database::HT;

# Unlike the CRMS DB, always the same DSN for any instance
my $HT_DB_DSN = 'DBI:mysql:database=ht;host=mariadb_ht';

subtest 'development instance' => sub {
  my $config = CRMS::Config->new(instance => 'development', reinitialize => 1);
  my $ht_db = CRMS::Database::HT->new;
  isa_ok($ht_db, 'CRMS::Database::HT');
  is($ht_db->dsn, $HT_DB_DSN);
  ok(defined $ht_db->dbh);
};

subtest 'production instance' => sub {
  my $config = CRMS::Config->new(instance => 'production', reinitialize => 1);
  my $ht_db = CRMS::Database::HT->new;
  isa_ok($ht_db, 'CRMS::Database::HT');
  is($ht_db->dsn, $HT_DB_DSN);
  ok(defined $ht_db->dbh);
};

subtest 'training instance' => sub {
  my $config = CRMS::Config->new(instance => 'crms_training', reinitialize => 1);
  my $ht_db = CRMS::Database::HT->new;
  isa_ok($ht_db, 'CRMS::Database::HT');
  is($ht_db->dsn, $HT_DB_DSN);
  ok(defined $ht_db->dbh);
};

done_testing();
