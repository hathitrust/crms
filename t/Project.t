#!/usr/bin/perl

use strict;
use warnings;

use Test::More;

use lib $ENV{'SDRROOT'} . '/crms/cgi';
use lib $ENV{'SDRROOT'} . '/crms/lib';

use CRMS;
use CRMS::Entitlements;

my $dir = $ENV{'SDRROOT'}. '/crms/cgi/Project';
opendir(DIR, $dir) or die "Can't open $dir\n";
my @files = readdir(DIR);
closedir(DIR);
foreach my $file (sort @files)
{
  next if $file =~ /^\.\.?$/;
  my $path = "$dir/$file";
  require_ok($path);
}

my $crms = CRMS->new;
my $entitlements = CRMS::Entitlements->new(crms => $crms);
# Rights ids used across subtests

my $ic_cdpp_rights_id = $entitlements->rights_by_attribute_reason('ic', 'cdpp')->{id};
my $und_nfi_rights_id = $entitlements->rights_by_attribute_reason('und', 'nfi')->{id};
my $und_ren_rights_id = $entitlements->rights_by_attribute_reason('und', 'ren')->{id};

my $project = Project->new(crms => $crms);
subtest '#queue_order' => sub {
  is($project->queue_order, undef, 'default project has no queue_order');
};

subtest '#PresentationOrder' => sub {
  is($project->PresentationOrder, undef, 'default project has no PresentationOrder');
};

subtest 'ValidateSubmission' => sub {
  subtest 'no rights selected' => sub {
    my $cgi = CGI->new;
    my $err = $project->ValidateSubmission($cgi);
    ok($err =~ m/rights\/reason combination/, 'error displayed');
  };

  subtest 'und/nfi must include note category and note text' => sub {
    subtest 'with category and note' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', $und_nfi_rights_id);
      $cgi->param('category', 'Edition');
      $cgi->param('note', 'This is a note');
      my $err = $project->ValidateSubmission($cgi);
      ok($err !~ m/must include note category and note text/, 'no error');
    };

    subtest 'without category' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', $und_nfi_rights_id);
      # Setting the category explicitly to empty string is needed to avoid
      # "uninitialized value $category" warnings in Project.pm.
      # These can be all removed when that is fixed with a default empty string value.
      $cgi->param('category', '');
      $cgi->param('note', 'This is a note');
      my $err = $project->ValidateSubmission($cgi);
      ok($err =~ m/must include note category and note text/, 'error displayed');
    };

    subtest 'with neither' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', $und_nfi_rights_id);
      $cgi->param('category', '');
      my $err = $project->ValidateSubmission($cgi);
      ok($err =~ m/must include note category and note text/, 'error displayed');
    };
  };
  
  subtest 'ic/ren must include renewal id and renewal date' => sub {
    my $ic_ren_rights_id = $entitlements->rights_by_attribute_reason('ic', 'ren')->{id};
    subtest 'with renewal data' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', $ic_ren_rights_id);
      $cgi->param('renNum', 'R123');
      $cgi->param('renDate', '4Jun23');
      $cgi->param('category', '');
      my $err = $project->ValidateSubmission($cgi);
      ok($err !~ m/must include renewal id and renewal date/, 'no error');
    };

    subtest 'with just renewal id' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', $ic_ren_rights_id);
      $cgi->param('renNum', 'R123');
      $cgi->param('category', '');
      my $err = $project->ValidateSubmission($cgi);
      ok($err =~ m/must include renewal id and renewal date/, 'error displayed');
    };

    subtest 'without renewal data' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', $ic_ren_rights_id);
      $cgi->param('category', '');
      my $err = $project->ValidateSubmission($cgi);
      ok($err =~ m/must include renewal id and renewal date/, 'error displayed');
    };
  };
  
  subtest 'pd/ren should not include renewal info' => sub {
    my $pd_ren_rights_id = $entitlements->rights_by_attribute_reason('pd', 'ren')->{id};
    subtest 'without renewal info' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', $pd_ren_rights_id);
      $cgi->param('category', '');
      my $err = $project->ValidateSubmission($cgi);
      ok($err !~ m/should not include renewal info/, 'no error');
    };

    # FIXME: next two tests show arguably incorrect behavior, the error should be triggered if either
    # renNum or renDate is present. The assumption has been that renDate will always be present
    # if renNum is, and that's maybe not quite true.
    subtest 'with renNum' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', $pd_ren_rights_id);
      $cgi->param('renNum', 'R123');
      $cgi->param('category', '');
      my $err = $project->ValidateSubmission($cgi);
      ok($err !~ m/should not include renewal info/, 'no error');
    };
  
    subtest 'with renDate' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', $pd_ren_rights_id);
      $cgi->param('renDate', '4Jun23');
      $cgi->param('category', '');
      my $err = $project->ValidateSubmission($cgi);
      ok($err !~ m/should not include renewal info/, 'no error');
    };
    
    subtest 'with both' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', $pd_ren_rights_id);
      $cgi->param('renDate', '4Jun23');
      $cgi->param('category', '');
      my $err = $project->ValidateSubmission($cgi);
      ok($err !~ m/should not include renewal info/, 'error displayed');
    };
  };

  subtest 'pd*/cdpp must not include renewal data' => sub {
    foreach my $attr ('pd', 'pdus') {
      my $rights = $entitlements->rights_by_attribute_reason($attr, 'cdpp')->{id};
      subtest "$attr with renewal number" => sub {
        my $cgi = CGI->new;
        $cgi->param('rights', $rights);
        $cgi->param('renNum', 'R123');
        $cgi->param('category', '');
        my $err = $project->ValidateSubmission($cgi);
        ok($err =~ m/must not include renewal info/, 'error displayed');
      };

      subtest "$attr with renewal date" => sub {
        my $cgi = CGI->new;
        $cgi->param('rights', $rights);
        $cgi->param('renDate', '4Jun23');
        $cgi->param('category', '');
        my $err = $project->ValidateSubmission($cgi);
        ok($err =~ m/must not include renewal info/, 'error displayed');
      };

      subtest "$attr without renewal data" => sub {
        my $cgi = CGI->new;
        $cgi->param('rights', $rights);
        $cgi->param('category', '');
        my $err = $project->ValidateSubmission($cgi);
        ok($err !~ m/must not include renewal info/, 'no error');
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
      my $err = $project->ValidateSubmission($cgi);
      ok($err !~ m/must include note category and note text/, 'no error');
    };

    subtest 'with note only' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', $rights);
      $cgi->param('category', '');
      $cgi->param('note', 'This is a note');
      my $err = $project->ValidateSubmission($cgi);
      ok($err =~ m/must include note category and note text/, 'error displayed');
    };

    subtest 'with neither' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', $rights);
      $cgi->param('category', '');
      my $err = $project->ValidateSubmission($cgi);
      ok($err =~ m/must include note category and note text/, 'error displayed');
    };
  };

  # NOTE: this could be merged with the pd/cdpp and pdus/cdpp logic above
  subtest 'ic/cdpp must not include renewal data' => sub {
    subtest 'with renewal number' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', $ic_cdpp_rights_id);
      $cgi->param('renNum', 'R123');
      $cgi->param('category', '');
      my $err = $project->ValidateSubmission($cgi);
      ok($err =~ m/should not include renewal info/, 'error displayed');
    };
    
    subtest 'with renewal date' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', $ic_cdpp_rights_id);
      $cgi->param('renDate', '4Jun23');
      $cgi->param('category', '');
      my $err = $project->ValidateSubmission($cgi);
      ok($err =~ m/should not include renewal info/, 'error displayed');
    };
  };

  # NOTE: this could be merged with the pd/cdpp and pdus/cdpp logic above
  subtest 'ic/cdpp must include note category and note text' => sub {
    subtest 'with both' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', $ic_cdpp_rights_id);
      $cgi->param('category', 'Edition');
      $cgi->param('note', 'This is a note');
      my $err = $project->ValidateSubmission($cgi);
      ok($err !~ m/must include note category and note text/, 'no error');
    };

    subtest 'with note only' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', $ic_cdpp_rights_id);
      $cgi->param('category', '');
      $cgi->param('note', 'This is a note');
      my $err = $project->ValidateSubmission($cgi);
      ok($err =~ m/must include note category and note text/, 'error displayed');
    };

    subtest 'with neither' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', $ic_cdpp_rights_id);
      $cgi->param('category', '');
      my $err = $project->ValidateSubmission($cgi);
      ok($err =~ m/must include note category and note text/, 'error displayed');
    };
  };

  subtest 'und/ren must have note category Inserts/No Renewal' => sub {
    subtest 'with expected category' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', $und_ren_rights_id);
      $cgi->param('category', 'Inserts/No Renewal');
      my $err = $project->ValidateSubmission($cgi);
      ok($err !~ m/mmust have note category Inserts\/No Renewal/, 'no error');
    };

    subtest 'without expected category' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', $und_ren_rights_id);
      $cgi->param('category', 'Edition');
      my $err = $project->ValidateSubmission($cgi);
      ok($err =~ m/must have note category Inserts\/No Renewal/, 'no error');
    };

    subtest 'with no category' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', $und_ren_rights_id);
      $cgi->param('category', '');
      my $err = $project->ValidateSubmission($cgi);
      ok($err =~ m/must have note category/, 'error displayed');
    };
  };

  subtest 'Inserts/No Renewal category is only used with und/ren' => sub {
    subtest 'with expected rights' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', $und_ren_rights_id);
      $cgi->param('category', 'Inserts/No Renewal');
      my $err = $project->ValidateSubmission($cgi);
      ok($err !~ m/must have rights code/, 'no error');
    };

    subtest 'without expected rights' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', $und_nfi_rights_id);
      $cgi->param('category', 'Inserts/No Renewal');
      my $err = $project->ValidateSubmission($cgi);
      ok($err =~ m/must have rights code/, 'error displayed');
    };
  };

  subtest "note optionality" => sub {
    my $note_required = $crms->SimpleSqlGet('SELECT name FROM categories WHERE need_note=1 AND interface=1 AND restricted IS NULL');
    my $note_optional = $crms->SimpleSqlGet('SELECT name FROM categories WHERE need_note=0 AND interface=1 AND restricted IS NULL');
    subtest 'category without required note' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', 1);
      $cgi->param('category', $note_required);
      my $err = $project->ValidateSubmission($cgi);
      ok($err =~ m/must include a note/, 'error displayed');
    };

    subtest 'category with required note' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', 1);
      $cgi->param('category', $note_required);
      $cgi->param('note', 'This is a required note');
      my $err = $project->ValidateSubmission($cgi);
      ok($err !~ m/must include a note/, 'no error');
    };

    subtest 'category without optional note' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', 1);
      $cgi->param('category', $note_optional);
      my $err = $project->ValidateSubmission($cgi);
      ok($err !~ m/must include a note/, 'no error');
    };

    subtest 'category with required note' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', 1);
      $cgi->param('category', $note_optional);
      $cgi->param('note', 'This is an optional note');
      my $err = $project->ValidateSubmission($cgi);
      ok($err !~ m/must include a note/, 'no error');
    };
  };

  subtest 'must include a category if there is a note' => sub {
    subtest 'note with category' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', 1);
      $cgi->param('note', 'This is a note');
      $cgi->param('category', 'Misc');
      my $err = $project->ValidateSubmission($cgi);
      ok($err !~ m/must include a category/, 'no error');
    };

    subtest 'note without category' => sub {
      my $cgi = CGI->new;
      $cgi->param('rights', 1);
      $cgi->param('category', '');
      $cgi->param('note', 'This is a note');
      my $err = $project->ValidateSubmission($cgi);
      ok($err =~ m/must include a category/, 'error displayed');
    };
  };
};

done_testing();

