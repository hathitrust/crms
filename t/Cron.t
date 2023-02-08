#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use Data::Dumper;
use Test::Exception;
use Test::More;

use lib "$ENV{SDRROOT}/crms/cgi";
use lib "$ENV{SDRROOT}/crms/lib";

use CRMS;

require_ok($ENV{'SDRROOT'}. '/crms/lib/CRMS/Cron.pm');
my $crms = CRMS->new;
my $cron = CRMS::Cron->new('crms' => $crms);

subtest 'CRMS::Cron::new' => sub {
  subtest 'requires CRMS object' => sub {
    throws_ok { CRMS::Cron->new; } qr/needs CRMS instance/i;
  };
};

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
    $crms->PrepareSubmitSql($sql, $cron->script_name);
    $sql = 'INSERT INTO cron_recipients (cron_id,email)'.
           ' VALUES ((SELECT MAX(id) FROM cron), ?)';
    $crms->PrepareSubmitSql($sql, $db_recipient);
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
    $crms->PrepareSubmitSql('DELETE FROM cron_recipients WHERE email=?', $db_recipient);
    $crms->PrepareSubmitSql('DELETE FROM cron WHERE script=?', $cron->script_name);
  };
};

done_testing();
