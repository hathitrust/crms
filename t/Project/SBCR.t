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
# Grab the most frequently used rights ids
my $ic_ren_rights_id = $entitlements->rights_by_attribute_reason('ic', 'ren')->{id};
my $pd_ren_rights_id = $entitlements->rights_by_attribute_reason('pd', 'ren')->{id};
my $ic_cdpp_rights_id = $entitlements->rights_by_attribute_reason('ic', 'cdpp')->{id};
my $und_nfi_rights_id = $entitlements->rights_by_attribute_reason('und', 'nfi')->{id};
my $und_ren_rights_id = $entitlements->rights_by_attribute_reason('und', 'ren')->{id};

require_ok($ENV{'SDRROOT'}. '/crms/cgi/Project/SBCR.pm');

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

  subtest 'date must be only decimal digits' => sub {
    subtest 'acceptable inputs' => sub {
      foreach my $date ('1234', '-1234') {
        my $cgi = CGI->new;
        $cgi->param('rights', 1);
        $cgi->param('date', $date);
        my $err = $proj->ValidateSubmission($cgi);
        ok($err !~ m/date must be only decimal digits/);
      }
    };

    subtest 'unacceptable inputs' => sub {
      foreach my $date ('12345', '-12345', 'c.1950') {
        my $cgi = CGI->new;
        $cgi->param('rights', 1);
        $cgi->param('date', $date);
        my $err = $proj->ValidateSubmission($cgi);
        ok($err =~ m/date must be only decimal digits/);
      }
    };

    subtest 'no date submitted' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', 1);
      my $err = $proj->ValidateSubmission($cgi);
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
          my $err = $proj->ValidateSubmission($cgi);
          ok($err !~ m/must include a numeric year/);
        };

        subtest "$rights->{name} without date" => sub {
          my $cgi = CGI->new;
          $cgi->param('rights', $rights->{id});
          #$cgi->param('date', 1957);
          my $err = $proj->ValidateSubmission($cgi);
          ok($err =~ m/must include a numeric year/);
        };
      } else {
        subtest "$rights->{name} with date" => sub {
          my $cgi = CGI->new;
          $cgi->param('rights', $rights->{id});
          $cgi->param('date', 1957);
          my $err = $proj->ValidateSubmission($cgi);
          ok($err !~ m/must include a numeric year/);
        };
      }
    }
  };

  subtest 'renewal ... has expired: volume is pd' => sub {
    subtest 'ic/ren with nonexpired renewal' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', $ic_ren_rights_id);
      $cgi->param('renNum', 'R123');
      $cgi->param('renDate', '4Jun63');
      my $err = $proj->ValidateSubmission($cgi);
      ok($err !~ m/renewal .*? has expired: volume is pd/);
    };

    subtest 'ic/ren with expired renewal date' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', $ic_ren_rights_id);
      $cgi->param('renNum', 'R123');
      $cgi->param('renDate', '4Jun23');
      my $err = $proj->ValidateSubmission($cgi);
      ok($err =~ m/renewal .*? has expired: volume is pd/);
    };
    
    subtest 'ic/ren with unparseable renewal date' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', $ic_ren_rights_id);
      $cgi->param('renNum', 'R123');
      $cgi->param('renDate', 'unparseable');
      my $err = $proj->ValidateSubmission($cgi);
      ok($err !~ m/renewal .*? has expired: volume is pd/);
    };

    subtest 'ic/ren with no renewal date' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', $ic_ren_rights_id);
      $cgi->param('renNum', 'R123');
      my $err = $proj->ValidateSubmission($cgi);
      ok($err !~ m/renewal .*? has expired: volume is pd/);
    };

    subtest 'not ic/ren' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', $pd_ren_rights_id);
      $cgi->param('renNum', 'R123');
      $cgi->param('renDate', '4Jun23');
      my $err = $proj->ValidateSubmission($cgi);
      ok($err !~ m/renewal .*? has expired: volume is pd/);
    };
  };

  subtest 'ic/ren must include renewal id and renewal date' => sub {
    my $cgi = CGI->new;
    $cgi->param('rights', $ic_ren_rights_id);
    my $err = $proj->ValidateSubmission($cgi);
    ok($err =~ m/must include renewal id and renewal date/);
  };

  subtest 'pd/ren should not include renewal info' => sub {
    subtest 'without renewal info' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', $pd_ren_rights_id);
      my $err = $proj->ValidateSubmission($cgi);
      ok($err !~ m/should not include renewal info/);
    };

    subtest 'with renNum' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', $pd_ren_rights_id);
      $cgi->param('renNum', 'R123');
      my $err = $proj->ValidateSubmission($cgi);
      ok($err =~ m/should not include renewal info/);
    };

    subtest 'with renDate' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', $pd_ren_rights_id);
      $cgi->param('renDate', '4Jun23');
      my $err = $proj->ValidateSubmission($cgi);
      ok($err =~ m/should not include renewal info/);
    };
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
      my $rights = $entitlements->rights_by_attribute_reason($attr, 'cdpp')->{id};
      subtest "$attr with renewal number" => sub {
        my $cgi = CGI->new;
        $cgi->param('rights', $rights);
        $cgi->param('renNum', 'R123');
        my $err = $proj->ValidateSubmission($cgi);
        ok($err =~ m/must not include renewal info/);
      };

      subtest "$attr with renewal date" => sub {
        my $cgi = CGI->new;
        $cgi->param('rights', $rights);
        $cgi->param('renDate', '4Jun23');
        my $err = $proj->ValidateSubmission($cgi);
        ok($err =~ m/must not include renewal info/);
      };

      subtest "$attr without renewal data" => sub {
        my $cgi = CGI->new;
        $cgi->param('rights', $rights);
        my $err = $proj->ValidateSubmission($cgi);
        ok($err !~ m/must not include renewal info/);
      };
    }
  };

  subtest 'pd/cdpp must include note category and note text' => sub {
    my $rights = $entitlements->rights_by_attribute_reason('pd', 'cdpp')->{id};
    subtest 'with both' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', $rights);
      $cgi->param('category', 'Edition');
      $cgi->param('note', 'This is a note');
      my $err = $proj->ValidateSubmission($cgi);
      ok($err !~ m/must include note category and note text/);
    };

    subtest 'with note only' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', $rights);
      $cgi->param('note', 'This is a note');
      my $err = $proj->ValidateSubmission($cgi);
      ok($err =~ m/must include note category and note text/);
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
    subtest 'with renewal number' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', $ic_cdpp_rights_id);
      $cgi->param('renNum', 'R123');
      my $err = $proj->ValidateSubmission($cgi);
      ok($err =~ m/must not include renewal info/);
    };
    
    subtest 'with renewal date' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', $ic_cdpp_rights_id);
      $cgi->param('renDate', '4Jun23');
      my $err = $proj->ValidateSubmission($cgi);
      ok($err =~ m/must not include renewal info/);
    };
  };

  # NOTE: this could be merged with the pd/cdpp and pdus/cdpp logic above
  subtest 'ic/cdpp must include note category and note text' => sub {
    subtest 'with both' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', $ic_cdpp_rights_id);
      $cgi->param('category', 'Edition');
      $cgi->param('note', 'This is a note');
      my $err = $proj->ValidateSubmission($cgi);
      ok($err !~ m/must include note category and note text/);
    };

    subtest 'with note only' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', $ic_cdpp_rights_id);
      $cgi->param('note', 'This is a note');
      my $err = $proj->ValidateSubmission($cgi);
      ok($err =~ m/must include note category and note text/);
    };

    subtest 'with neither' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', $ic_cdpp_rights_id);
      my $err = $proj->ValidateSubmission($cgi);
      ok($err =~ m/must include note category and note text/);
    };
  };

  subtest 'und/nfi must include note category' => sub {
    subtest 'with category' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', $und_nfi_rights_id);
      $cgi->param('category', 'Edition');
      my $err = $proj->ValidateSubmission($cgi);
      ok($err !~ m/must include note category/);
    };

    subtest 'without category' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', $und_nfi_rights_id);
      my $err = $proj->ValidateSubmission($cgi);
      ok($err =~ m/must include note category/);
    };
  };

  subtest 'und/ren must have note category Inserts/No Renewal' => sub {
    subtest 'with expected category' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', $und_ren_rights_id);
      $cgi->param('category', 'Inserts/No Renewal');
      my $err = $proj->ValidateSubmission($cgi);
      ok($err !~ m/mmust have note category Inserts\/No Renewal/);
    };

    subtest 'without expected category' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', $und_ren_rights_id);
      $cgi->param('category', 'Edition');
      my $err = $proj->ValidateSubmission($cgi);
      ok($err =~ m/must have note category Inserts\/No Renewal/);
    };

    subtest 'with no category' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', $und_ren_rights_id);
      my $err = $proj->ValidateSubmission($cgi);
      ok($err =~ m/must have note category /);
    };
  };
  
  subtest 'Inserts/No Renewal category is only used with und/ren' => sub {
    subtest 'with expected rights' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', $und_ren_rights_id);
      $cgi->param('category', 'Inserts/No Renewal');
      my $err = $proj->ValidateSubmission($cgi);
      ok($err !~ m/must have rights code/);
    };

    subtest 'without expected rights' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', $und_nfi_rights_id);
      $cgi->param('category', 'Inserts/No Renewal');
      my $err = $proj->ValidateSubmission($cgi);
      ok($err =~ m/must have rights code/);
    };
  };

  subtest "note optionality" => sub {
    my $note_required = $crms->SimpleSqlGet('SELECT name FROM categories WHERE need_note=1 AND interface=1 AND restricted IS NULL');
    my $note_optional = $crms->SimpleSqlGet('SELECT name FROM categories WHERE need_note=0 AND interface=1 AND restricted IS NULL');
    subtest 'category without required note' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', 1);
      $cgi->param('category', $note_required);
      my $err = $proj->ValidateSubmission($cgi);
      ok($err =~ m/requires a note/);
    };

    subtest 'category with required note' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', 1);
      $cgi->param('category', $note_required);
      $cgi->param('note', 'This is a required note');
      my $err = $proj->ValidateSubmission($cgi);
      ok($err !~ m/requires a note/);
    };

    subtest 'category without optional note' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', 1);
      $cgi->param('category', $note_optional);
      my $err = $proj->ValidateSubmission($cgi);
      ok($err !~ m/requires a note/);
    };

    subtest 'category with required note' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', 1);
      $cgi->param('category', $note_optional);
      $cgi->param('note', 'This is an optional note');
      my $err = $proj->ValidateSubmission($cgi);
      ok($err !~ m/requires a note/);
    };
  };

  subtest 'must include a category if there is a note' => sub {
    subtest 'note with category' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', 1);
      $cgi->param('note', 'This is a note');
      $cgi->param('category', 'Misc');
      my $err = $proj->ValidateSubmission($cgi);
      ok($err !~ m/must include a category/);
    };

    subtest 'note without category' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', 1);
      $cgi->param('note', 'This is a note');
      my $err = $proj->ValidateSubmission($cgi);
      ok($err =~ m/must include a category/);
    };
  };
  
  subtest 'Not Government category requires und/NFI' => sub {
    subtest 'Not Government category with und/nfi' => sub {
      my $rights = $entitlements->rights_by_attribute_reason('und', 'nfi')->{id};
      my $cgi = CGI->new;
      $cgi->param('rights', $rights);
      $cgi->param('category', 'Not Government');
      my $err = $proj->ValidateSubmission($cgi);
      ok($err !~ m/Not Government category requires/);
    };

    subtest 'Not Government category without und/nfi' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', $ic_ren_rights_id);
      $cgi->param('category', 'Not Government');
      my $err = $proj->ValidateSubmission($cgi);
      ok($err =~ m/Not Government category requires/);
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
    my $format = $proj->FormatReviewData(1, $json);
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
    my $format = $proj->FormatReviewData(1, $json);
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
    my $format = $proj->FormatReviewData(1, $json);
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
  my $params = $proj->extract_parameters($cgi);
  is($params->{rights}, 1, 'leaves rights unchanged');
  is($params->{renNum}, 'R12345', 'strips whitespace');
};

subtest 'format_renewal_data' => sub {
  subtest 'with no data' => sub {
    ok(length $proj->format_renewal_data(undef, undef) == 0);
  };

  subtest 'with only renNum' => sub {
    ok($proj->format_renewal_data('R123', undef) =~ m/R123/);
  };

  subtest 'with only renDate' => sub {
    ok($proj->format_renewal_data(undef, '1Oct51') =~ m/1Oct51/);
  };

  subtest 'with both renNum and renDate' => sub {
    ok($proj->format_renewal_data('R123', '1Oct51') =~ m/R123/);
    ok($proj->format_renewal_data('R123', '1Oct51') =~ m/1Oct51/);
  };
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


