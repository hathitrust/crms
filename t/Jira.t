#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use lib "$ENV{SDRROOT}/crms/lib";

use Test::LWP::UserAgent;
use Test::More;

use CRMS::Jira;

my $jira = CRMS::Jira->new;
my $good_endpoint = qr{/rest/api/2/issue/HT-\d+/comment};
my $bad_endpoint = qr{/rest/api/2/issue/HT-\D+/comment};

subtest '#add_comment' => sub {
  my $ua = Test::LWP::UserAgent->new;
  $ua->map_response($good_endpoint, HTTP::Response->new('200', 'OK', ['Content-Type' => 'text/plain'], '(from t/Jira.t)'));
  $ua->map_response($bad_endpoint, HTTP::Response->new('500', 'ERROR', ['Content-Type' => 'text/plain'], '(from t/Jira.t)'));

  subtest 'success' => sub {
    my $err = $jira->add_comment(ticket => 'HT-33', comment => 'this is a comment', user_agent => $ua);
    ok(!defined $err);
  };

  subtest 'failure' => sub {
    my $err = $jira->add_comment(ticket => 'HT-XX', comment => 'this is a comment', user_agent => $ua);
    ok(defined $err);
  };
};

subtest '#browse_url' => sub {
  is($jira->browse_url('HT-000'), 'https://hathitrust.atlassian.net/browse/HT-000');
};

subtest '#request' => sub {
  my $req = $jira->request(method => 'GET', path => 'some/path/to/something');
  isa_ok($req, 'HTTP::Request');
};

done_testing();
