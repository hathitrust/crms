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

require_ok($ENV{'SDRROOT'}. '/crms/cgi/Project/SBCR.pm');

my $crms = CRMS->new();
# TODO: Project::for_name would be a much nicer way to do this.
my $sql = 'SELECT id FROM projects WHERE name="SBCR"';
my $project_id = $crms->SimpleSqlGet($sql);
my $proj = SBCR->new(crms => $crms, id => $project_id);
ok(defined $proj);

subtest 'SBCR::PresentationOrder' => sub {
  my $order = $proj->PresentationOrder;
  ok(!defined $order, 'does not define a presentation order');
};

subtest 'SBCR::ReviewPartials' => sub {
  ok(defined $proj->ReviewPartials, 'defines a UI ordering');
};

subtest 'SBCR::ValidateSubmission' => sub {
  subtest 'no rights selected' => sub {
    my $cgi = CGI->new;
    my $err = $proj->ValidateSubmission($cgi);
    ok($err =~ m/rights\/reason combination/);
  };

  subtest 'ADD/pub date with too many digits' => sub {
    my $cgi = CGI->new;
    $cgi->param('rights', 1);
    $cgi->param('date', '12345');
    my $err = $proj->ValidateSubmission($cgi);
    ok($err =~ m/decimal digits/);
  };

  subtest 'pd/add with no date' => sub {
    my $cgi = CGI->new;
    my $rights = CRMS::Entitlements->new(crms => $crms)->rights_by_attribute_reason('pd', 'add')->{id};
    $cgi->param('rights', $rights);
    my $err = $proj->ValidateSubmission($cgi);
    ok($err =~ m/numeric year/);
  };

  subtest 'pd/exp with no date' => sub {
    my $cgi = CGI->new;
    my $rights = CRMS::Entitlements->new(crms => $crms)->rights_by_attribute_reason('pd', 'exp')->{id};
    $cgi->param('rights', $rights);
    my $err = $proj->ValidateSubmission($cgi);
    ok($err =~ m/numeric year/);
  };

  subtest 'ic/ren with expired renewal' => sub {
    my $cgi = CGI->new;
    my $rights = CRMS::Entitlements->new(crms => $crms)->rights_by_attribute_reason('ic', 'ren')->{id};
    $cgi->param('rights', $rights);
    $cgi->param('renNum', 'R123');
    $cgi->param('renDate', '4Jun23');
    my $err = $proj->ValidateSubmission($cgi);
    ok($err =~ m/expired/);
  };

  subtest 'ic/ren with no renewal data' => sub {
    my $cgi = CGI->new;
    my $rights = CRMS::Entitlements->new(crms => $crms)->rights_by_attribute_reason('ic', 'ren')->{id};
    $cgi->param('rights', $rights);
    my $err = $proj->ValidateSubmission($cgi);
    ok($err =~ m/renewal id/);
  };

  subtest 'pd/ren with renewal data' => sub {
    my $cgi = CGI->new;
    my $rights = CRMS::Entitlements->new(crms => $crms)->rights_by_attribute_reason('pd', 'ren')->{id};
    $cgi->param('rights', $rights);
    $cgi->param('renNum', 'R123');
    $cgi->param('renDate', '4Jun23');
    my $err = $proj->ValidateSubmission($cgi);
    ok($err =~ m/should not include renewal info/);
  };

  subtest 'actual publication date' => sub {
    subtest 'single date' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', 1);
      $cgi->param('actual', '9999');
      my $err = $proj->ValidateSubmission($cgi);
      ok($err !~ m/YYYY or YYYY-YYYY/);
    };

    subtest 'date range' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', 1);
      $cgi->param('actual', '9990-9999');
      my $err = $proj->ValidateSubmission($cgi);
      ok($err !~ m/YYYY or YYYY-YYYY/);
    };

    subtest 'nonsense' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', 1);
      $cgi->param('actual', 'abcde');
      my $err = $proj->ValidateSubmission($cgi);
      ok($err =~ m/YYYY or YYYY-YYYY/);
    };
  };
  
  subtest 'pd*/cdpp must not include renewal data' => sub {
    foreach my $attr ('pd', 'pdus') {
      subtest $attr => sub {
        my $cgi = CGI->new;
        my $rights = CRMS::Entitlements->new(crms => $crms)->rights_by_attribute_reason($attr, 'cdpp')->{id};
        $cgi->param('rights', $rights);
        $cgi->param('renNum', 'R123');
        $cgi->param('renDate', '4Jun23');
        my $err = $proj->ValidateSubmission($cgi);
        ok($err =~ m/must not include renewal info/);
      };
    }
  };

  subtest 'pd/cdpp must include note category and note text' => sub {
    my $rights = CRMS::Entitlements->new(crms => $crms)->rights_by_attribute_reason('pd', 'cdpp')->{id};
    subtest 'with both' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', $rights);
      $cgi->param('category', 'Edition');
      $cgi->param('note', 'This is a note');
      my $err = $proj->ValidateSubmission($cgi);
      ok($err !~ m/must include note category and note text/);
    };

    subtest 'with neither' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', $rights);
      my $err = $proj->ValidateSubmission($cgi);
      ok($err =~ m/must include note category and note text/);
    };
  };

  # NOTE: this could be merged with the pd/cdpp and pdus/cdpp logic above
  subtest 'ic/cdpp must not include renewal data' => sub {
    my $cgi = CGI->new;
    my $rights = CRMS::Entitlements->new(crms => $crms)->rights_by_attribute_reason('ic', 'cdpp')->{id};
    $cgi->param('rights', $rights);
    $cgi->param('renNum', 'R123');
    $cgi->param('renDate', '4Jun23');
    my $err = $proj->ValidateSubmission($cgi);
    ok($err =~ m/must not include renewal info/);
  };

  # NOTE: this could be merged with the pd/cdpp and pdus/cdpp logic above
  subtest 'ic/cdpp must include note category and note text' => sub {
    my $rights = CRMS::Entitlements->new(crms => $crms)->rights_by_attribute_reason('ic', 'cdpp')->{id};
    subtest 'with both' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', $rights);
      $cgi->param('category', 'Edition');
      $cgi->param('note', 'This is a note');
      my $err = $proj->ValidateSubmission($cgi);
      ok($err !~ m/must include note category and note text/);
    };

    subtest 'with neither' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', $rights);
      my $err = $proj->ValidateSubmission($cgi);
      ok($err =~ m/must include note category and note text/);
    };
  };

  subtest 'und/nfi must include note category' => sub {
    my $rights = CRMS::Entitlements->new(crms => $crms)->rights_by_attribute_reason('und', 'nfi')->{id};
    subtest 'with category' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', $rights);
      $cgi->param('category', 'Edition');
      my $err = $proj->ValidateSubmission($cgi);
      ok($err !~ m/must include note category/);
    };

    subtest 'without category' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', $rights);
      my $err = $proj->ValidateSubmission($cgi);
      ok($err =~ m/must include note category/);
    };
  };

  subtest 'und/ren must have note category Inserts/No Renewal' => sub {
    my $rights = CRMS::Entitlements->new(crms => $crms)->rights_by_attribute_reason('und', 'ren')->{id};
    subtest 'with expected category' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', $rights);
      $cgi->param('category', 'Inserts/No Renewal');
      my $err = $proj->ValidateSubmission($cgi);
      ok($err !~ m/must have note category/);
    };

    subtest 'without expected category' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', $rights);
      $cgi->param('category', 'Edition');
      my $err = $proj->ValidateSubmission($cgi);
      ok($err =~ m/must have note category /);
    };

    subtest 'with no category' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', $rights);
      my $err = $proj->ValidateSubmission($cgi);
      ok($err =~ m/must have note category /);
    };
  };

  # FIXME: MORE TESTS NEEDED HERE
  


  subtest 'category without required note' => sub {
    my $cgi = CGI->new;
    $cgi->param('rights', 1);
    $cgi->param('category', 'Misc');
    my $err = $proj->ValidateSubmission($cgi);
    ok($err =~ m/requires a note/);
  };
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
    my $extracted = $proj->ExtractReviewData($cgi);
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
    my $extracted = $proj->ExtractReviewData($cgi);
    is_deeply($extracted, {});
  };
};

subtest 'FormatReviewData' => sub {
  my $data = {
    renNum => 'R123',
    renDate => '26Sep39',
    date => '1950',
    pub => 1,
    crown => 1,
    actual => '1960',
    approximate => 1
  };
  my $json = $jsonxs->encode($data);
  my $format = $proj->FormatReviewData(1, $json);
  ok($format->{format} =~ /renewal/i);
  ok($format->{format} =~ /pub/i);
  ok($format->{format} =~ /crown/i);
  ok($format->{format} =~ /actual/i);
  is($format->{id}, 1);
};

subtest 'extract_parameters' => sub {
  my $cgi = CGI->new;
  $cgi->param('rights', 1);
  $cgi->param('renNum', "  R12345\n");
  my $params = $proj->extract_parameters($cgi);
  is($params->{rights}, 1, 'leaves rights unchanged');
  is($params->{renNum}, 'R12345', 'strips whitespace');
};

subtest 'renewal_date_to_year' => sub {
  subtest 'with a well-formed renewal date' => sub {
    my $year = $proj->renewal_date_to_year('21Sep51');
    is($year, '1951', 'extracts year');
  };

  subtest 'with a nonsense renewal date' => sub {
    my $year = $proj->renewal_date_to_year('abcde');
    is($year, '', 'returns empty string');
  };
};

done_testing();


