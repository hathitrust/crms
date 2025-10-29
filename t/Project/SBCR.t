#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use CGI;
use Data::Dumper;
use JSON::XS;
use Test::More;

use lib $ENV{'SDRROOT'} . '/crms/cgi';
use lib $ENV{'SDRROOT'} . '/crms/lib';
use CRMS;
use CRMS::Entitlements;

my $jsonxs = JSON::XS->new->utf8->canonical(1)->pretty(0);
# Will be used multiple times in this test suite.
my $crms = CRMS->new();
my $entitlements = CRMS::Entitlements->new(crms => $crms);

require_ok($ENV{'SDRROOT'}. '/crms/cgi/Project/SBCR.pm');

my $sql = 'SELECT id FROM projects WHERE name="SBCR"';
my $project_id = $crms->SimpleSqlGet($sql);
my $project = SBCR->new(crms => $crms, id => $project_id);
ok(defined $project);

subtest 'PresentationOrder' => sub {
  my $order = $project->PresentationOrder;
  ok(!defined $order, 'does not define a presentation order');
};

subtest 'ReviewPartials' => sub {
  ok(defined $project->ReviewPartials, 'defines a UI ordering');
};

subtest 'ValidateSubmission' => sub {
  subtest 'no rights selected' => sub {
    my $cgi = CGI->new;
    my $err = $project->ValidateSubmission($cgi);
    ok($err =~ m/rights\/reason combination/);
  };

  subtest 'date must be only decimal digits' => sub {
    subtest 'acceptable inputs' => sub {
      foreach my $date ('1234', '-1234') {
        my $cgi = CGI->new;
        $cgi->param('rights', 1);
        $cgi->param('date', $date);
        my $err = $project->ValidateSubmission($cgi);
        ok($err !~ m/date must be only decimal digits/);
      }
    };

    subtest 'unacceptable inputs' => sub {
      foreach my $date ('12345', '-12345', 'c.1950') {
        my $cgi = CGI->new;
        $cgi->param('rights', 1);
        $cgi->param('date', $date);
        my $err = $project->ValidateSubmission($cgi);
        ok($err =~ m/date must be only decimal digits/);
      }
    };

    subtest 'no date submitted' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', 1);
      my $err = $project->ValidateSubmission($cgi);
      ok($err !~ m/date must be only decimal digits/);
    };
  };

  subtest '*/add and */exp must include a numeric year' => sub {
    foreach my $id (keys %{$entitlements->{rights}}) {
      my $rights = $entitlements->{rights}->{$id};
      if ($rights->{reason_name} eq 'add' || $rights->{reason_name} eq 'exp') {
        subtest "$rights->{name} with date" => sub {
          my $cgi = CGI->new;
          $cgi->param('rights', $rights->{id});
          $cgi->param('date', 1957);
          my $err = $project->ValidateSubmission($cgi);
          ok($err !~ m/must include a numeric year/);
        };

        subtest "$rights->{name} without date" => sub {
          my $cgi = CGI->new;
          $cgi->param('rights', $rights->{id});
          my $err = $project->ValidateSubmission($cgi);
          ok($err =~ m/must include a numeric year/);
        };
      } else {
        subtest "$rights->{name} with date" => sub {
          my $cgi = CGI->new;
          $cgi->param('rights', $rights->{id});
          $cgi->param('date', 1957);
          my $err = $project->ValidateSubmission($cgi);
          ok($err !~ m/must include a numeric year/);
        };
      }
    }
  };

  subtest 'ic/ren must include renewal id and renewal date' => sub {
    my $ic_ren_rights_id = $entitlements->rights_by_attribute_reason('ic', 'ren')->{id};
    subtest 'with renewal data' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', $ic_ren_rights_id);
      $cgi->param('renNum', 'R123');
      $cgi->param('renDate', '4Jun23');
      my $err = $project->ValidateSubmission($cgi);
      ok($err !~ m/must include renewal id and renewal date/);
    };

    subtest 'with just renewal id' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', $ic_ren_rights_id);
      $cgi->param('renNum', 'R123');
      my $err = $project->ValidateSubmission($cgi);
      ok($err =~ m/must include renewal id and renewal date/);
    };

    subtest 'without renewal data' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', $ic_ren_rights_id);
      my $err = $project->ValidateSubmission($cgi);
      ok($err =~ m/must include renewal id and renewal date/);
    };
  };

  subtest 'actual publication date' => sub {
    subtest 'single date' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', 1);
      $cgi->param('actual', '9999');
      my $err = $project->ValidateSubmission($cgi);
      ok($err !~ m/YYYY or YYYY-YYYY/);
    };

    subtest 'date range' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', 1);
      $cgi->param('actual', '9990-9999');
      my $err = $project->ValidateSubmission($cgi);
      ok($err !~ m/YYYY or YYYY-YYYY/);
    };

    subtest 'nonsense' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', 1);
      $cgi->param('actual', 'abcde');
      my $err = $project->ValidateSubmission($cgi);
      ok($err =~ m/YYYY or YYYY-YYYY/);
    };
  };
  # End of ValidateSubmission subtest
};

subtest 'ExtractReviewData' => sub {
  subtest 'with lots of data, some of it messy' => sub {
    my $cgi = CGI->new;
    $cgi->param('renNum', ' R123');
    $cgi->param('renDate', ' 26Sep39');
    $cgi->param('date', '1950');
    $cgi->param('pub', 'on');
    $cgi->param('crown', 'on');
    $cgi->param('actual', '1960');
    $cgi->param('approximate', 'on');
    my $extracted = $project->ExtractReviewData($cgi);
    is($extracted->{renNum}, 'R123');
    is($extracted->{renDate}, '26Sep39');
    is($extracted->{date}, '1950');
    is($extracted->{pub}, 1);
    is($extracted->{crown}, 1);
    is($extracted->{actual}, '1960');
    is($extracted->{approximate}, 1);
  };

  subtest 'with very little data' => sub {
    my $cgi = CGI->new;
    my $extracted = $project->ExtractReviewData($cgi);
    is_deeply($extracted, {});
  };
};

subtest 'FormatReviewData' => sub {
  subtest 'with lots of data' => sub {
    my $data = {
      renNum => 'R123',
      renDate => '26Sep39',
      date => '1950',
      pub => 0,
      crown => 1,
      actual => '1960',
      approximate => 1
    };
    my $json = $jsonxs->encode($data);
    my $format = $project->FormatReviewData(1, $json);
    ok($format->{format} =~ /Renewal/);
    ok($format->{format} =~ /ADD/);
    ok($format->{format} !~ /<strong>Pub/);
    ok($format->{format} =~ /Crown/);
    ok($format->{format} =~ /Actual/);
    is($format->{id}, 1);
  };

  subtest 'with a little data' => sub {
    my $data = {
      date => '1960',
      pub => 1
    };
    my $json = $jsonxs->encode($data);
    my $format = $project->FormatReviewData(1, $json);
    ok($format->{format} !~ /Renewal/);
    ok($format->{format} !~ /ADD/);
    ok($format->{format} =~ /<strong>Pub/);
    ok($format->{format} !~ /Crown/);
    ok($format->{format} !~ /Actual/);
    is($format->{id}, 1);
  };
  
  subtest 'with no data' => sub {
    my $data = {};
    my $json = $jsonxs->encode($data);
    my $format = $project->FormatReviewData(1, $json);
    ok($format->{format} !~ /Renewal/);
    ok($format->{format} !~ /ADD/);
    ok($format->{format} !~ /<strong>Pub/);
    ok($format->{format} !~ /Crown/);
    ok($format->{format} !~ /Actual/);
    is($format->{id}, 1);
  };
};

subtest 'extract_parameters' => sub {
  my $cgi = CGI->new;
  $cgi->param('rights', 1);
  $cgi->param('renNum', "  R12345\n");
  my $params = $project->extract_parameters($cgi);
  is($params->{rights}, 1, 'leaves rights unchanged');
  is($params->{renNum}, 'R12345', 'strips whitespace');
};

subtest 'format_renewal_data' => sub {
  subtest 'with no data' => sub {
    ok(length $project->format_renewal_data(undef, undef) == 0);
  };

  subtest 'with only renNum' => sub {
    ok($project->format_renewal_data('R123', undef) =~ m/R123/);
  };

  subtest 'with only renDate' => sub {
    ok($project->format_renewal_data(undef, '1Oct51') =~ m/1Oct51/);
  };

  subtest 'with both renNum and renDate' => sub {
    ok($project->format_renewal_data('R123', '1Oct51') =~ m/R123/);
    ok($project->format_renewal_data('R123', '1Oct51') =~ m/1Oct51/);
  };
};

done_testing();


