#!/usr/bin/env perl
use strict;
use warnings;
use utf8;

use Data::Dumper;
#use DBI;
use FindBin;
use Term::ANSIColor qw(:constants);

use lib "$FindBin::Bin/../lib";
use Factories;
use TestHelper;

#use lib "$FindBin::Bin/../../lib";
#use User;

$Term::ANSIColor::AUTORESET = 1;

print YELLOW "========== Seeding Database ===============\n";
#my $dbh = DBI->connect("DBI:mysql:database=crms;host=mariadb", 'crms', 'crms',
#  { PrintError => 0, RaiseError => 1, AutoCommit => 1 }) || die "Cannot connect: $DBI::errstr";
#$dbh->{mysql_enable_utf8} = 1;
#$dbh->{mysql_auto_reconnect} = 1;
#$dbh->do('SET NAMES "utf8";');

my $dbh = TestHelper->new->db;

my @sqls = (
  'DELETE FROM projectusers',
  'DELETE FROM licensing',
  'DELETE FROM users WHERE name LIKE "Default%" OR name LIKE "Inactive%"'
);

foreach my $sql (@sqls) {
  my $sth = $dbh->prepare($sql);
  $sth->execute();
}

Factories::User(name => 'Default Reviewer', reviewer => 1);
Factories::User(name => 'Default Advanced Reviewer', reviewer => 1, advanced => 1);
Factories::User(name => 'Default Expert', reviewer => 1, advanced => 1, expert => 1);
Factories::User(name => 'Default Admin', reviewer => 1, advanced => 1, expert => 1, admin => 1);
Factories::User(name => 'Inactive Reviewer', reviewer => 1, active => 0);

print GREEN "========== Done Seeding Database ==========\n";
