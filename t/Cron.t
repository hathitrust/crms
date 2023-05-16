#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use Test::Exception;
use Test::More;

use lib "$ENV{SDRROOT}/crms/lib";

use CRMS::DB;

require_ok($ENV{'SDRROOT'}. '/crms/lib/CRMS/Cron.pm');
my $cron = CRMS::Cron->new;
my $db = CRMS::DB->new;
$db->submit('DELETE FROM cron_recipients');
$db->submit('DELETE FROM cron WHERE script=?', $cron->script_name);

subtest 'CRMS::Cron::expand_email' => sub {
  is($cron->expand_email('default'), 'default@umich.edu');
  is($cron->expand_email('default@default.invalid'), 'default@default.invalid');
};

subtest 'CRMS::Cron::script_name' => sub {
  is('Cron.t', $cron->script_name);
};

subtest 'CRMS::Cron::recipients' => sub {
  subtest 'without DB config' => sub {
    subtest 'with override' => sub {
      my $list = ['user1', 'user2@default.invalid'];
      my $expected_list = ['user1@umich.edu', 'user2@default.invalid'];
      my $recipients = $cron->recipients(@$list);
      is_deeply($recipients, $expected_list);
    };

    subtest 'without override' => sub {
      my $recipients = $cron->recipients;
      is_deeply($recipients, []);
    };
  };

  subtest 'with DB config' => sub {
    my $db_recipient = 'user3';
    my $sql = 'INSERT INTO cron (script) VALUES (?)';
    $db->submit($sql, $cron->script_name);
    $sql = 'INSERT INTO cron_recipients (cron_id,email)'.
           ' VALUES ((SELECT MAX(id) FROM cron), ?)';
    $db->submit($sql, $db_recipient);

    subtest 'with override' => sub {
      my $list = ['user1', 'user2@default.invalid'];
      my $expected_list = ['user1@umich.edu', 'user2@default.invalid'];
      my $recipients = $cron->recipients(@$list);
      is_deeply($recipients, $expected_list);
    };

    subtest 'without override' => sub {
      my $recipients = $cron->recipients;
      is_deeply($recipients, [$db_recipient . '@umich.edu']);
    };
    $db->submit('DELETE FROM cron_recipients WHERE email=?', $db_recipient);
    $db->submit('DELETE FROM cron WHERE script=?', $cron->script_name);
  };
};

done_testing();
