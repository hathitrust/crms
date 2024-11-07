use strict;
use warnings;
use utf8;

use Data::Dumper;
use Test::Exception;
use Test::More;

use lib "$ENV{SDRROOT}/crms/lib";

use CRMS::DB;
use CRMS::Instance;

subtest 'CRMS DB' => sub {
  subtest 'development instance' => sub {
    CRMS::Instance::test_reinitialize;
    my $instance = CRMS::Instance->new();
    my $crms_db = CRMS::DB->new(name => 'crms');
    isa_ok($crms_db, 'CRMS::DB::CRMS');
    is($crms_db->dsn, 'DBI:mysql:database=crms;host=mariadb');
    ok(defined $crms_db->dbh);
  };
  
  subtest 'production instance' => sub {
    CRMS::Instance::test_reinitialize;
    my $instance = CRMS::Instance->new(instance => 'production');
    my $crms_db = CRMS::DB->new(name => 'crms');
    isa_ok($crms_db, 'CRMS::DB::CRMS');
    is($crms_db->dsn, 'DBI:mysql:database=crms;host=mariadb');
    ok(defined $crms_db->dbh);
  };

  subtest 'training instance' => sub {
    CRMS::Instance::test_reinitialize;
    my $instance = CRMS::Instance->new(instance => 'crms_training');
    my $crms_db = CRMS::DB->new(name => 'crms');
    isa_ok($crms_db, 'CRMS::DB::CRMS');
    is($crms_db->dsn, 'DBI:mysql:database=crms_training;host=mariadb');
    # Can't check dbh because we don't have a training DB in Docker
  };
};

subtest 'HT DB' => sub {
  # Unlike the CRMS DB, always the same DSN for any instance
  my $HT_DB_DSN = 'DBI:mysql:database=ht;host=mariadb_ht';

  subtest 'development instance' => sub {
    CRMS::Instance::test_reinitialize;
    my $instance = CRMS::Instance->new;
    my $ht_db = CRMS::DB->new(name => 'ht');
    isa_ok($ht_db, 'CRMS::DB::HT');
    is($ht_db->dsn, $HT_DB_DSN);
    ok(defined $ht_db->dbh);
  };

  subtest 'production instance' => sub {
    CRMS::Instance::test_reinitialize;
    my $instance = CRMS::Instance->new(instance => 'production');
    my $ht_db = CRMS::DB->new(name => 'ht');
    isa_ok($ht_db, 'CRMS::DB::HT');
    is($ht_db->dsn, $HT_DB_DSN);
    ok(defined $ht_db->dbh);
  };

  subtest 'training instance' => sub {
    CRMS::Instance::test_reinitialize;
    my $instance = CRMS::Instance->new(instance => 'crms_training');
    my $ht_db = CRMS::DB->new(name => 'ht');
    isa_ok($ht_db, 'CRMS::DB::HT');
    is($ht_db->dsn, $HT_DB_DSN);
    ok(defined $ht_db->dbh);
  };
};

CRMS::Instance::test_reinitialize;
subtest 'reuse existing connection' => sub {
  my $crms_dbh_1 = CRMS::DB->new->dbh;
  my $crms_dbh_2 = CRMS::DB->new->dbh;
  is_deeply($crms_dbh_1, $crms_dbh_2);
};

subtest 'error handling' => sub {
  subtest 'with error handler' => sub {
    my $error_handled = 0;
    my $db = CRMS::DB->new(error_handler => sub {$error_handled = 'yessiree';} );
    $db->one('SELECT * FROM no_such_table');
    is('yessiree', $error_handled);
    $error_handled = 0;
    $db->submit('UPDATE no_such_table SET blah="blah"');
    is('yessiree', $error_handled);
  };

  subtest 'with built-in error handling' => sub {
    my $db = CRMS::DB->new;
    dies_ok { $db->one('SELECT * FROM no_such_table'); };
    dies_ok { $db->submit('UPDATE no_such_table SET blah="blah"'); };
  };
};

subtest 'submit' => sub {
  subtest 'with noop' => sub {
    my $db = CRMS::DB->new(noop => 1);
    my $count_before = $db->one("SELECT COUNT(*) FROM note");
    $db->submit('INSERT INTO note (note) VALUES ("this is a note")');
    my $count_after = $db->one("SELECT COUNT(*) FROM note");
    is($count_after, $count_before);
  };

  subtest 'without noop' => sub {
    my $db = CRMS::DB->new;
    my $count_before = $db->one("SELECT COUNT(*) FROM note");
    $db->submit('INSERT INTO note (note) VALUES ("this is a note")');
    my $count_after = $db->one("SELECT COUNT(*) FROM note");
    is($count_after, $count_before + 1);
  };
};

subtest 'noop' => sub {
  my $db = CRMS::DB->new(noop => 1);
  my $count_before = $db->one("SELECT COUNT(*) FROM note");
  $db->submit('INSERT INTO note (note) VALUES ("this is a note")');
  my $count_after = $db->one("SELECT COUNT(*) FROM note");
  is($count_after, $count_before);
};

subtest '#info' => sub {
  ok(CRMS::DB->new->info =~ /db info/i);
};

done_testing();
