use strict;
use warnings;
use utf8;

use Data::Dumper;
use Test::Exception;
use Test::More;

use lib "$ENV{SDRROOT}/crms/lib";

use CRMS::DB;

subtest 'CRMS DB' => sub {
  subtest 'development instance' => sub {
    my $crms_db = CRMS::DB->new(name => 'crms', instance => '');
    is($crms_db->dsn, 'DBI:mysql:database=crms;host=mariadb');
    ok(defined $crms_db->dbh);
  };
  
  subtest 'production instance' => sub {
    my $crms_db = CRMS::DB->new(name => 'crms', instance => 'production');
    is($crms_db->dsn, 'DBI:mysql:database=crms;host=mysql-sdr');
  };

  subtest 'training instance' => sub {
    my $crms_training_db = CRMS::DB->new(name => 'crms', instance => 'crms-training');
    is($crms_training_db->dsn, 'DBI:mysql:database=crms_training;host=mysql-sdr');

    subtest 'with CRMS_INSTANCE' => sub {
      my $save_instance = $ENV{CRMS_INSTANCE};
      $ENV{CRMS_INSTANCE} = 'crms-training';
      my $crms_db = CRMS::DB->new;
      is($crms_db->dsn, 'DBI:mysql:database=crms_training;host=mysql-sdr');
      $ENV{CRMS_INSTANCE} = $save_instance;
    };
  };
};

subtest 'HT DB' => sub {
  # Unlike the CRMS DB, always the same DSN for any instance
  my $HT_DB_DSN = 'DBI:mysql:database=ht;host=mariadb_ht';

  subtest 'production connection' => sub {
    my $ht_db = CRMS::DB->new(name => 'ht', instance => 'production');
    is($ht_db->dsn, $HT_DB_DSN);
    ok(defined $ht_db->dbh);
  };

  subtest 'training connection' => sub {
    my $ht_db = CRMS::DB->new(name => 'ht', instance => 'crms-training');
    is($ht_db->dsn, $HT_DB_DSN);
  };

  subtest 'development connection' => sub {
    my $ht_db = CRMS::DB->new(name => 'ht', instance => 'development');
    is($ht_db->dsn, $HT_DB_DSN);
  };
};


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
