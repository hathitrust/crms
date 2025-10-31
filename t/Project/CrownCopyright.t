#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use CGI;
use Test::More;

use lib $ENV{'SDRROOT'} . '/crms/cgi';
use lib $ENV{'SDRROOT'} . '/crms/lib';
use CRMS;
use CRMS::Entitlements;

my $crms = CRMS->new();
my $entitlements = CRMS::Entitlements->new(crms => $crms);

require_ok($ENV{'SDRROOT'}. '/crms/cgi/Project/CrownCopyright.pm');

my $sql = 'SELECT id FROM projects WHERE name="Crown Copyright"';
my $project_id = $crms->SimpleSqlGet($sql);
my $project = CrownCopyright->new(crms => $crms, id => $project_id);
ok(defined $project);

subtest 'ValidateSubmission' => sub {
  subtest 'no rights selected' => sub {
    my $cgi = CGI->new;
    my $err = $project->ValidateSubmission($cgi);
    ok($err =~ m/rights\/reason combination/);
  };

  subtest 'Not Government category requires und/NFI' => sub {
    subtest 'Not Government category with und/nfi' => sub {
      my $rights = $entitlements->rights_by_attribute_reason('und', 'nfi')->{id};
      my $cgi = CGI->new;
      $cgi->param('rights', $rights);
      # Setting the date explicitly to empty string is needed to avoid
      # "uninitialized value $date" warnings in CrownCopyright.pm.
      # These can be all removed when that is fixed with a default empty string value.
      $cgi->param('date', '');
      $cgi->param('category', 'Not Government');
      my $err = $project->ValidateSubmission($cgi);
      ok($err !~ m/Not Government category requires/);
    };

    subtest 'Not Government category without und/nfi' => sub {
      my $rights = $entitlements->rights_by_attribute_reason('ic', 'ren')->{id};
      my $cgi = CGI->new;
      $cgi->param('rights', $rights);
      $cgi->param('date', '');
      $cgi->param('category', 'Not Government');
      my $err = $project->ValidateSubmission($cgi);
      ok($err =~ m/Not Government category requires/);
    };
  };
};

done_testing();
