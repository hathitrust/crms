#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use CGI;
use Test::More;

use lib "$ENV{SDRROOT}/crms/cgi";
use CRMS;

require_ok "$ENV{SDRROOT}/crms/cgi/Project/PublicationDate.pm";

my $crms = CRMS->new();
my $sql = 'SELECT id FROM projects WHERE name="Publication Date"';
my $project_id = $crms->SimpleSqlGet($sql);
my $proj = PublicationDate->new(crms => $crms, id => $project_id);
isa_ok($proj, 'PublicationDate');

subtest '#ValidateSubmission' => sub {
  subtest 'bogus country of publication' => sub {
    my $cgi = CGI->new;
    $cgi->param('rights', 1);
    $cgi->param('date', '1950');
    $cgi->param('country', 'bogus_country_code');
    my $err = $proj->ValidateSubmission($cgi);
    ok($err =~ /Country of Publication/i);
  };
};

subtest '#FormatReviewData' => sub {
  my $json = '{"country":"fr","date":"1987"}';
  my $fmt = $proj->FormatReviewData('htid', $json)->{format};
  ok($fmt =~ /France/);
};

done_testing();


