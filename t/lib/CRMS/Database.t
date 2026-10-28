use strict;
use warnings;
use utf8;

use Data::Dumper;
use Test::Exception;
use Test::More;

use lib "$ENV{SDRROOT}/crms/lib";

use CRMS::Database;

subtest 'new' => sub {
  subtest 'development instance' => sub {
    my $config = CRMS::Config->new(instance => 'development', reinitialize => 1);
    my $crms_db = CRMS::Database->new;
    isa_ok($crms_db, 'CRMS::Database');
    is($crms_db->dsn, 'DBI:mysql:database=crms;host=mariadb');
    ok(defined $crms_db->dbh);
  };

  subtest 'production instance' => sub {
    my $config = CRMS::Config->new(instance => 'production', reinitialize => 1);
    my $crms_db = CRMS::Database->new;
    isa_ok($crms_db, 'CRMS::Database');
    is($crms_db->dsn, 'DBI:mysql:database=crms;host=mariadb');
    ok(defined $crms_db->dbh);
  };

  subtest 'training instance' => sub {
    my $config = CRMS::Config->new(instance => 'crms_training', reinitialize => 1);
    my $crms_db = CRMS::Database->new;
    isa_ok($crms_db, 'CRMS::Database');
    is($crms_db->dsn, 'DBI:mysql:database=crms_training;host=mariadb');
    # Can't check dbh because we don't have a training DB in Docker
  };
};
# Reset config back to development
my $config = CRMS::Config->new(instance => 'development', reinitialize => 1);

subtest 'reuse existing connection' => sub {
  my $crms_dbh_1 = CRMS::Database->new->dbh;
  my $crms_dbh_2 = CRMS::Database->new->dbh;
  is_deeply($crms_dbh_1, $crms_dbh_2);
};

subtest 'error handling' => sub {
  my $db = CRMS::Database->new;
  dies_ok { $db->one('SELECT * FROM no_such_table'); };
  dies_ok { $db->submit('UPDATE no_such_table SET blah="blah"'); };
};

subtest '#one' => sub {
  my $database = CRMS::Database->new;
  subtest 'with one result' => sub {
    my $sql = 'SELECT id FROM users';
    my $field = $database->one($sql);
    is($field, 'autocrms', 'autocrms row returned');
  };

  subtest 'with no result' => sub {
    my $sql = 'SELECT id FROM users WHERE name=?';
    my $field = $database->one($sql, "no_such_user");
    is($field, undef, 'undef returned');
  };

  subtest 'with unsuccessful query' => sub {
    my $sql = 'SELECT shwoozle FROM users';
    dies_ok { $database->one($sql) } 'raises';
  };
};

subtest '#all' => sub {
  subtest 'with one result' => sub {
    my $sql = 'SELECT id FROM users';
    my $fields = CRMS::Database->new->all($sql);
    is($fields->[0]->{id}, 'autocrms', 'autocrms row returned');
  };

  subtest 'with no result' => sub {
    my $sql = 'SELECT id FROM users WHERE name=?';
    my $fields = CRMS::Database->new->all($sql, "no_such_user");
    is(scalar @$fields, 0, 'no rows returned');
  };

  subtest 'with unsuccessful query' => sub {
    my $sql = 'SELECT no_such_column FROM users';
    dies_ok { CRMS::Database->new->all($sql) } 'raises';
  };
};

subtest '#for' => sub {
  subtest 'with one result' => sub {
    my $sql = 'SELECT id FROM users';
    my $fields = [];
    CRMS::Database->new->for($sql, sub {
      my $row = shift;
      push @$fields, $row->{id};
    });
    is(scalar @$fields, 1, 'one row returned');
    is($fields->[0], 'autocrms', '"autocrms" row returned');
  };

  subtest 'with no result' => sub {
    my $sql = 'SELECT id FROM users WHERE name=?';
    my $fields = [];
    CRMS::Database->new->for($sql, 'shwoozle', sub {
      my $row = shift;
      push @$fields, $row->{id};
    });
    is(scalar @$fields, 0, 'no rows returned');
  };

  subtest 'with unsuccessful query' => sub {
    my $sql = 'SELECT no_such_column FROM users';
    dies_ok {
      CRMS::Database->new->for($sql, sub { my $row = shift; });
    } 'raises';
  };
};

subtest '#submit' => sub {
  subtest 'successful update' => sub {
    my $sql = 'INSERT INTO users (id,name,institution) VALUES ("testuser","Test User",1)';
    CRMS::Database->new->submit($sql);
    $sql = 'SELECT COUNT(*) FROM users WHERE id="testuser"';
    my $count =  CRMS::Database->new->one($sql);
    is($count, 1, 'one row inserted');
    $sql = 'DELETE FROM users WHERE id="testuser"';
    CRMS::Database->new->submit($sql);
  };

  subtest 'with unsuccessful query' => sub {
    my $sql = 'INSERT INTO no_such_table VALUES (1,2,3)';
    dies_ok { CRMS::Database->new->submit($sql) } 'raises';
  };

  subtest 'with noop' => sub {
    my $db = CRMS::Database->new(noop => 1);
    my $count_before = $db->one("SELECT COUNT(*) FROM note");
    $db->submit('INSERT INTO note (note) VALUES ("this is a note")');
    my $count_after = $db->one("SELECT COUNT(*) FROM note");
    is($count_after, $count_before);
  };
};

subtest '#info' => sub {
  ok(CRMS::Database->new->info =~ /db info/i);
};

done_testing();
