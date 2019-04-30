#!/usr/bin/perl

BEGIN 
{
  unshift(@INC, $ENV{'SDRROOT'}. '/crms/cgi');
}

use strict;
use warnings;
use CRMS;
use Test::More;
use Getopt::Long qw(:config no_ignore_case bundling);
use Data::Dumper;

my $usage = <<END;
USAGE: $0 [-ach]

Unit tests specified systems.

-a         Run all tests. Overrides all other flags.
-c         Test candidacy.
-h         Print this help message.
-p         Test projects.
-r         Test reviews.
END

my $all;
my $candidacy;
my $help;
my $projects;
my $reviews;

Getopt::Long::Configure ('bundling');
die 'Terminating' unless GetOptions(
           'a'    => \$all,
           'c'    => \$candidacy,
           'h|?'  => \$help,
           'p'    => \$projects,
           'r'    => \$reviews,
);
die "$usage\n\n" if $help;

if ($all)
{
  $candidacy = 1;
  $projects = 1;
  $reviews = 1;
}
my $crms = CRMS->new();
### === Projects === ###
if ($projects)
{
  my $projs = $crms->Projects();
  isa_ok($projs, 'HASH', 'Projects()');
  foreach my $projid (sort keys %{$projs})
  {
    my $proj = $projs->{$projid};
    isa_ok($proj, 'HASH', "Project $projid");
    can_ok($proj, 'id');
    is($projid, $proj->id, "Project $projid ids agree");
    can_ok($proj, 'name');
    my $projname = $proj->name;
    can_ok($proj, 'tests');
    my $tests = $proj->tests;
    isa_ok($tests, 'ARRAY', "Project $projname ($projid) tests");
    foreach my $htid (@$tests)
    {
      my $record = $crms->GetMetadata($htid);
      ok(defined $record, "$projname $htid metadata defined");
      my $res = $proj->EvaluateCandidacy($htid, $record, 'ic', 'bib');
      ok(defined $res, "$projname EvaluateCandidacy($htid) result defined");
      isa_ok($res, 'HASH', "$projname EvaluateCandidacy($htid)");
      ok(defined $res->{'status'}, "$projname EvaluateCandidacy($htid) project defined");
      is($res->{'status'}, 'yes', "$projname EvaluateCandidacy($htid) YES");
    }
  }
}

### === Candidacy Checks === ###
if ($candidacy)
{
  # return {'status' => 'filter', 'msg' => 'no meta'} unless defined $record;
  my $res = $crms->EvaluateCandidacy('NONEXISTENT');
  ok(defined $res, "EvaluateCandidacy(NONEXISTENT) defined");
  isa_ok($res, 'HASH', "EvaluateCandidacy(NONEXISTENT)");
  ok(defined $res->{'status'}, 'EvaluateCandidacy(NONEXISTENT) status defined');
  ok(defined $res->{'msg'}, 'EvaluateCandidacy(NONEXISTENT) msg defined');
  is($res->{'status'}, 'filter', 'EvaluateCandidacy(NONEXISTENT) status "filter"');
  is($res->{'msg'}, 'no meta', 'EvaluateCandidacy(NONEXISTENT) msg "no meta"');
}

if ($reviews)
{
  #$crms->set('debugSql', 1);
  ### ============= Status 2 ============= ###
  my $sql = 'DELETE FROM queue WHERE id="coo.31924054065317"';
  $crms->PrepareSubmitSql($sql);
  $sql = 'INSERT INTO queue (id,project) VALUES ("coo.31924054065317",5)';
  $crms->PrepareSubmitSql($sql);
  $sql = 'DELETE FROM reviews WHERE id="coo.31924054065317"';
  $crms->PrepareSubmitSql($sql);
  my $cgi = CGI->new();
  $cgi->param('rights', 17); # 9/2 - pd/ncn
  $cgi->param('start', $crms->GetNow());
  my $res = $crms->SubmitReviewCGI('coo.31924054065317', 'jap232@psu.edu', $cgi);
  ok(!defined $res, 'SubmitReviewCGI(coo.31924054065317, jap232@psu.edu)');
  is($crms->GetStatus('coo.31924054065317'), 0, 'coo.31924054065317 single review S0');
  $cgi = CGI->new();
  $cgi->param('rights', 6); # 5/8 - und/nfi
  $cgi->param('start', $crms->GetNow());
  $cgi->param('note', 'Hold for question');
  $cgi->param('hold', 1);
  $res = $crms->SubmitReviewCGI('coo.31924054065317', 'mah94@cornell.edu', $cgi);
  ok(defined $res, 'SubmitReviewCGI(coo.31924054065317, mah94@cornell.edu) fails w/o category');
  is($crms->GetStatus('coo.31924054065317'), 0, 'coo.31924054065317 single review still S0');
  $cgi->param('category', 'Edition/Reprint');
  $res = $crms->SubmitReviewCGI('coo.31924054065317', 'mah94@cornell.edu', $cgi);
  ok(!defined $res, 'SubmitReviewCGI(coo.31924054065317, mah94@cornell.edu) succeeds w/ category');
  $sql = 'SELECT COUNT(*) FROM reviews WHERE id=? AND user=?';
  is($crms->SimpleSqlGet($sql, 'coo.31924054065317', 'mah94@cornell.edu'), 1, 'mah94@cornell.edu und in DB');
  is($crms->SimpleSqlGet('SELECT pending_status FROM queue WHERE id="coo.31924054065317"'), 2, 'coo.31924054065317 PS2');
  my $data = $crms->CalcStatus('coo.31924054065317');
  ok(defined $data->{'hold'}, 'coo.31924054065317 held for mah94@cornell.edu');
  $cgi->param('hold', 0);
  $res = $crms->SubmitReviewCGI('coo.31924054065317', 'mah94@cornell.edu', $cgi);
  ok(!defined $res, 'SubmitReviewCGI(coo.31924054065317, mah94@cornell.edu) succeeds unholding');
  $data = $crms->CalcStatus('coo.31924054065317');
  ok(!defined $data->{'hold'}, 'coo.31924054065317 no longer held for mah94@cornell.edu');
  is($data->{'status'}, 2, 'coo.31924054065317 status 2');
  ### ============= Status 3 ============= ###
  $sql = 'UPDATE queue SET status=0,pending_status=0 WHERE id="coo.31924054065317"';
  $crms->PrepareSubmitSql($sql);
  $sql = 'UPDATE users SET advanced=0 WHERE id IN ("jap232@psu.edu","mah94@cornell.edu")';
  $crms->PrepareSubmitSql($sql);
  $sql = 'UPDATE reviews SET attr=5,reason=8 WHERE id="coo.31924054065317"';
  $crms->PrepareSubmitSql($sql);
  $data = $crms->CalcStatus('coo.31924054065317');
  is($data->{'status'}, 3, 'coo.31924054065317 status 3');
  ### ============= Status 4 ============= ###
  $sql = 'UPDATE users SET advanced=1 WHERE id IN ("jap232@psu.edu","mah94@cornell.edu")';
  $crms->PrepareSubmitSql($sql);
  $data = $crms->CalcStatus('coo.31924054065317');
  is($data->{'status'}, 4, 'coo.31924054065317 status 4');
  ### ============= Status 8 ============= ###
  $sql = 'SELECT id FROM reviewdata LIMIT 2';
  my $ref = $crms->SelectAll($sql);
  my $did1 = $ref->[0]->[0];
  my $did2 = $ref->[0]->[1];
  $sql = 'UPDATE reviews SET attr=2,reason=7,data=? WHERE id="coo.31924054065317" AND user="jap232@psu.edu"';
  $crms->PrepareSubmitSql($sql, $did1);
  $sql = 'UPDATE reviews SET attr=2,reason=7,data=? WHERE id="coo.31924054065317" AND user="mah94@cornell.edu"';
  $crms->PrepareSubmitSql($sql, $did1);
  $data = $crms->CalcStatus('coo.31924054065317');
  is($data->{'status'}, 4, 'coo.31924054065317 status 4');
  $sql = 'UPDATE reviews SET attr=2,reason=7,data=? WHERE id="coo.31924054065317" AND user="jap232@psu.edu"';
  $crms->PrepareSubmitSql($sql, $did1);
  $sql = 'UPDATE reviews SET attr=2,reason=7,data=? WHERE id="coo.31924054065317" AND user="mah94@cornell.edu"';
  $crms->PrepareSubmitSql($sql, $did2);
  $data = $crms->CalcStatus('coo.31924054065317');
  is($data->{'status'}, 8, 'coo.31924054065317 status 8 part 1');
  $sql = 'UPDATE reviews SET attr=2,reason=17,data=? WHERE id="coo.31924054065317" AND user="mah94@cornell.edu"';
  $crms->PrepareSubmitSql($sql, $did1);
  $data = $crms->CalcStatus('coo.31924054065317');
  is($data->{'status'}, 8, 'coo.31924054065317 status 8 part 2');
  ### ============= Status 8 und/crms ============= ###
  $sql = 'UPDATE reviews SET attr=5,reason=8 WHERE id="coo.31924054065317" AND user="mah94@cornell.edu"';
  $crms->PrepareSubmitSql($sql);
  $data = $crms->CalcStatus('coo.31924054065317');
  is($data->{'status'}, 8, 'coo.31924054065317 status 8 und/crms');
  is($data->{'category'}, 'Attr Default', 'coo.31924054065317 status 8 Attr Default');
}

if (0)
{
  is($crms->WasYesterdayWorkingDay('2011-05-30'), 0,                       'WD: Memorial 2011');
  is($crms->WasYesterdayWorkingDay('2011-05-29'), 0,                       'WD: Memorial 2011 - 1');
  is($crms->WasYesterdayWorkingDay('2011-05-31'), 0,                       'WD: Memorial 2011 + 1');
  is($crms->IsWorkingDay('2011-07-04'), 0,                                 'WD: Independence 2011');
  is($crms->IsWorkingDay('2011-07-03'), 0,                                 'WD: Independence 2011 - 1');
  is($crms->IsWorkingDay('2011-07-05'), 1,                                 'WD: Independence 2011 + 1');
  is($crms->IsWorkingDay('2011-09-05'), 0,                                 'WD: Labor 2011');
  is($crms->IsWorkingDay('2011-09-04'), 0,                                 'WD: Labor 2011 - 1');
  is($crms->IsWorkingDay('2011-09-06'), 1,                                 'WD: Labor 2011 + 1');
  is($crms->IsWorkingDay('2011-11-24'), 0,                                 'WD: Thanksgiving 2011');
  is($crms->IsWorkingDay('2011-11-23'), 1,                                 'WD: Thanksgiving 2011 - 1');
  is($crms->IsWorkingDay('2011-11-25'), 0,                                 'WD: Thanksgiving 2011 + 1');
  is($crms->IsWorkingDay('2011-12-26'), 0,                                 'WD: Christmas 2011');
  is($crms->IsWorkingDay('2011-12-25'), 0,                                 'WD: Christmas 2011 - 1');
  is($crms->IsWorkingDay('2011-12-27'), 0,                                 'WD: Season 1 2011');
  is($crms->IsWorkingDay('2011-12-28'), 0,                                 'WD: Season 2 2011');
  is($crms->IsWorkingDay('2011-12-29'), 0,                                 'WD: Season 3 2011');
  is($crms->IsWorkingDay('2011-12-30'), 0,                                 'WD: Season 4 2011');
  is($crms->IsWorkingDay('2012-01-02'), 0,                                 'WD: NY 2012');
  is($crms->IsWorkingDay('2012-01-01'), 0,                                 'WD: NY 2012 - 1');
  is($crms->IsWorkingDay('2012-01-03'), 1,                                 'WD: NY 2012 + 1');
  is($crms->IsWorkingDay('2012-01-04'), 1,                                 'WD: NY 2012 + 2');
  is($crms->IsWorkingDay('2011-06-24'), 1,                                 'WD: a Saturday');
  is($crms->IsWorkingDay('2011-06-25'), 0,                                 'WD: a Saturday');
  is($crms->IsWorkingDay('2011-06-26'), 0,                                 'WD: a Sunday');
  is($crms->IsWorkingDay('2011-06-27'), 1,                                 'WD: a Monday');
}

if (0)
{
  is($crms->GetInstitutionName($crms->GetUserProperty('hansone@indiana.edu', 'institution')),      'Indiana',            'IU affiliation');
  is($crms->GetInstitutionName($crms->GetUserProperty('aseeger@library.wisc.edu', 'institution')), 'Wisconsin',          'UW affiliation');
  is($crms->GetInstitutionName($crms->GetUserProperty('zl2114@columbia.edu', 'institution')),      'Columbia',           'COL affiliation');
  is(scalar @{ $crms->GetInstitutionUsers(3) }, 8,                         'IU affiliates count');
  is(scalar @{ $crms->GetInstitutionUsers(5) }, 7,                         'UW affiliates count');
  is(scalar @{ $crms->GetInstitutionUsers(9) }, 1,                         'COL affiliates count');
  is($crms->IsReviewCorrect('uc1.b3763822','dfulmer','2009-11-02') ,0,     'Correctness: uc1.b3763822 1');
  is($crms->IsReviewCorrect('uc1.b3763822','cwilcox','2009-11-03') ,1,     'Correctness: uc1.b3763822 2');
  is($crms->IsReviewCorrect('uc1.b3763822','gnichols123','2009-11-04') ,1, 'Correctness: uc1.b3763822 3');
  is($crms->IsReviewCorrect('uc1.b3763822','jaheim123','2009-11-04') ,0,   'Correctness: uc1.b3763822 4');
  is($crms->IsReviewCorrect('uc1.b3763822','annekz','2009-11-09') ,1,      'Correctness: uc1.b3763822 5');
}

if (0)
{
  is($crms->ValidateSubmission('inu.39000005773028','moseshll',19,17,undef,undef,undef,undef),
     'Volumes published prior to 1923 are not eligible for icus/gatt. ', 'icus/gatt superadmin <23');
  is($crms->PredictRights('uc1.b3122005 ','1958'), 4,    'Predict rights: uc1.b3122005 1958 ic/add');
  ok($crms->CanChangeToUser('jblock@princeton.edu','jblock@princeton.edu-expert'), 'user switching');
  ok(!$crms->CanChangeToUser('jblock@princeton.edu','moseshll'), 'user switching');
}
if (0)
{
  ok('Renewal no longer required for works published after 1963. ' eq
     $crms->ValidateSubmission('mdp.39015011285692','moseshll',1,2,undef,undef,'R000','1Jan60'), 'pd/ncn superadmin >63 +ren');
  ok('' eq
     $crms->ValidateSubmission('mdp.39015011285692','moseshll',1,2,undef,undef,undef,undef),     'pd/ncn superadmin >63 -ren');
  ok('' eq
     $crms->ValidateSubmission('uc1.31822009761677','moseshll',1,2,undef,undef,'R000','1Jan60'), 'pd/ncn superadmin <63 +ren');
  ok('' eq
     $crms->ValidateSubmission('uc1.31822009761677','moseshll',1,2,undef,undef,undef,undef),     'pd/ncn superadmin <63 -ren');
  ok('Renewal no longer required for works published after 1963. ' eq
     $crms->ValidateSubmission('mdp.39015011285692','gnichols123',1,2,undef,undef,'R000','1Jan60'), 'pd/ncn admin >63 +ren');
  ok('' eq
     $crms->ValidateSubmission('mdp.39015011285692','gnichols123',1,2,undef,undef,undef,undef),     'pd/ncn admin >63 -ren');
  ok('' eq
     $crms->ValidateSubmission('uc1.31822009761677','gnichols123',1,2,undef,undef,'R000','1Jan60'), 'pd/ncn admin <63 +ren -note');
  
  ok('' eq
     $crms->ValidateSubmission('uc1.31822009761677','gnichols123',1,2,'blah','Expert Note','R000','1Jan60'), 'pd/ncn admin <63 +ren +note');
  ok('' eq
     $crms->ValidateSubmission('uc1.31822009761677','gnichols123',1,2,'blah','Expert Note',undef,undef),     'pd/ncn admin <63 -ren +note');
  ok('' eq
     $crms->ValidateSubmission('uc1.31822009761677','gnichols',1,2,undef,undef,'R000','1Jan60'), 'pd/ncn expert <63 +ren');
}

if (0)
{
  $crms->PrepareSubmitSql('INSERT INTO systemvars (name,value) VALUES ("blah", "1")');
  $crms->PrepareSubmitSql('INSERT INTO systemvars (name,value) VALUES ("bleh", "2")');
  is($crms->GetSystemVar('blah'), 1,                                                                 'GetSystemVar 1');
  is($crms->GetSystemVar('bleh'), 2,                                                                 'GetSystemVar 2');
  is($crms->GetSystemVar('bleh', undef, '$_<2'), undef,                                              'GetSystemVar 3');
  ok(defined $crms->GetSystemVar('priority1Frequency'),                                              'GetSystemVar 4');
  is($crms->GetSystemVar('spam'), undef,                                                             'GetSystemVar 5');
  $crms->PrepareSubmitSql('DELETE FROM systemvars WHERE name="blah" OR name="bleh"');

  $crms->PrepareSubmitSql('INSERT INTO systemvars (name,value) VALUES ("spam", "1.0")');
  is($crms->GetSystemVar('spam', undef, '$_>=0.0 and $_<1.0'), undef,                                'GetSystemVar 6');
  is($crms->GetSystemVar('spam', .25, '$_>=0.0 and $_<1.0'), .25,                                    'GetSystemVar 7');
  is($crms->GetSystemVar('span', undef, '$_>=0.0 and $_<1.0'), undef,                                'GetSystemVar 8');
  is($crms->GetSystemVar('span', .25, '$_>=0.0 and $_<1.0'), .25,                                    'GetSystemVar 9');
  $crms->PrepareSubmitSql('DELETE FROM systemvars WHERE name="blah" OR name="bleh" OR name="spam"');
  is($crms->TranslateAttr(1),'pd',                                                                   'TranslateAttr 1');
  is($crms->TranslateAttr(2),'ic',                                                                   'TranslateAttr 2');
  is($crms->TranslateAttr(3),'op',                                                                   'TranslateAttr 3');
  is($crms->TranslateAttr(4),'orph',                                                                 'TranslateAttr 4');
  is($crms->TranslateAttr(5),'und',                                                                  'TranslateAttr 5');
  is($crms->TranslateAttr(6),'umall',                                                                'TranslateAttr 6');
  is($crms->TranslateAttr(7),'ic-world',                                                             'TranslateAttr 7');
  is($crms->TranslateAttr(8),'nobody',                                                               'TranslateAttr 8');
  is($crms->TranslateAttr(9),'pdus',                                                                 'TranslateAttr 9');
  is($crms->TranslateAttr(10),'cc-by-3.0',                                                           'TranslateAttr 10');
  is($crms->TranslateAttr(11),'cc-by-nd-3.0',                                                        'TranslateAttr 11');
  is($crms->TranslateAttr(12),'cc-by-nc-nd-3.0',                                                     'TranslateAttr 12');
  is($crms->TranslateAttr(13),'cc-by-nc-3.0',                                                        'TranslateAttr 13');
  is($crms->TranslateAttr(14),'cc-by-nc-sa-3.0',                                                     'TranslateAttr 14');
  is($crms->TranslateAttr(15),'cc-by-sa-3.0',                                                        'TranslateAttr 15');
  is($crms->TranslateAttr(16),'orphcand',                                                            'TranslateAttr 16');
  is($crms->TranslateAttr(17),'cc-zero',                                                             'TranslateAttr 17');
  is($crms->TranslateAttr(18),'und-world',                                                           'TranslateAttr 18');
  is($crms->TranslateAttr(19),'icus',                                                                'TranslateAttr 19');

  is($crms->TranslateAttr('pd'),1,                                                                   'TranslateAttr 1a');
  is($crms->TranslateAttr('ic'),2,                                                                   'TranslateAttr 2a');
  is($crms->TranslateAttr('op'),3,                                                                   'TranslateAttr 3a');
  is($crms->TranslateAttr('orph'),4,                                                                 'TranslateAttr 4a');
  is($crms->TranslateAttr('und'),5,                                                                  'TranslateAttr 5a');
  is($crms->TranslateAttr('umall'),6,                                                                'TranslateAttr 6a');
  is($crms->TranslateAttr('ic-world'),7,                                                             'TranslateAttr 7a');
  is($crms->TranslateAttr('nobody'),8,                                                               'TranslateAttr 8a');
  is($crms->TranslateAttr('pdus'),9,                                                                 'TranslateAttr 9a');
  is($crms->TranslateAttr('cc-by-3.0'),10,                                                           'TranslateAttr 10a');
  is($crms->TranslateAttr('cc-by-nd-3.0'),11,                                                        'TranslateAttr 11a');
  is($crms->TranslateAttr('cc-by-nc-nd-3.0'),12,                                                     'TranslateAttr 12a');
  is($crms->TranslateAttr('cc-by-nc-3.0'),13,                                                        'TranslateAttr 13a');
  is($crms->TranslateAttr('cc-by-nc-sa-3.0'),14,                                                     'TranslateAttr 14a');
  is($crms->TranslateAttr('cc-by-sa-3.0'),15,                                                        'TranslateAttr 15a');
  is($crms->TranslateAttr('orphcand'),16,                                                            'TranslateAttr 16a');
  is($crms->TranslateAttr('cc-zero'),17,                                                             'TranslateAttr 17a');
  is($crms->TranslateAttr('und-world'),18,                                                           'TranslateAttr 18a');
  is($crms->TranslateAttr('icus'),19,                                                                'TranslateAttr 19a');

  is($crms->TranslateReason(1),'bib',                                                                'TranslateReason 1');
  is($crms->TranslateReason(2),'ncn',                                                                'TranslateReason 2');
  is($crms->TranslateReason(3),'con',                                                                'TranslateReason 3');
  is($crms->TranslateReason(4),'ddd',                                                                'TranslateReason 4');
  is($crms->TranslateReason(5),'man',                                                                'TranslateReason 5');
  is($crms->TranslateReason(6),'pvt',                                                                'TranslateReason 6');
  is($crms->TranslateReason(7),'ren',                                                                'TranslateReason 7');
  is($crms->TranslateReason(8),'nfi',                                                                'TranslateReason 8');
  is($crms->TranslateReason(9),'cdpp',                                                               'TranslateReason 9');
  is($crms->TranslateReason(10),'ipma',                                                              'TranslateReason 10');
  is($crms->TranslateReason(11),'unp',                                                               'TranslateReason 11');
  is($crms->TranslateReason(12),'gfv',                                                               'TranslateReason 12');
  is($crms->TranslateReason(13),'crms',                                                              'TranslateReason 13');
  is($crms->TranslateReason(14),'add',                                                               'TranslateReason 14');
  is($crms->TranslateReason(15),'exp',                                                               'TranslateReason 15');
  is($crms->TranslateReason(16),'del',                                                               'TranslateReason 16');
  is($crms->TranslateReason(17),'gatt',                                                              'TranslateReason 17');

  is($crms->TranslateReason('bib'),1,                                                                'TranslateReason 1a');
  is($crms->TranslateReason('ncn'),2,                                                                'TranslateReason 2a');
  is($crms->TranslateReason('con'),3,                                                                'TranslateReason 3a');
  is($crms->TranslateReason('ddd'),4,                                                                'TranslateReason 4a');
  is($crms->TranslateReason('man'),5,                                                                'TranslateReason 5a');
  is($crms->TranslateReason('pvt'),6,                                                                'TranslateReason 6a');
  is($crms->TranslateReason('ren'),7,                                                                'TranslateReason 7a');
  is($crms->TranslateReason('nfi'),8,                                                                'TranslateReason 8a');
  is($crms->TranslateReason('cdpp'),9,                                                               'TranslateReason 9a');
  is($crms->TranslateReason('ipma'),10,                                                              'TranslateReason 10a');
  is($crms->TranslateReason('unp'),11,                                                               'TranslateReason 11a');
  is($crms->TranslateReason('gfv'),12,                                                               'TranslateReason 12a');
  is($crms->TranslateReason('crms'),13,                                                              'TranslateReason 13a');
  is($crms->TranslateReason('add'),14,                                                               'TranslateReason 14a');
  is($crms->TranslateReason('exp'),15,                                                               'TranslateReason 15a');
  is($crms->TranslateReason('del'),16,                                                               'TranslateReason 16a');
  is($crms->TranslateReason('gatt'),17,                                                              'TranslateReason 17a');
}

if (0)
{
  is($crms->AccessChange('pd','pd'),0,                                                               'AccessChange 1');
  is($crms->AccessChange('pd','pdus'),1,                                                             'AccessChange 2');
  is($crms->AccessChange('pd','ic'),1,                                                               'AccessChange 3');
  is($crms->AccessChange('pd','und'),1,                                                              'AccessChange 4');
  is($crms->AccessChange('pd','icus'),1,                                                             'AccessChange 5');
  is($crms->AccessChange('pdus','pdus'),0,                                                           'AccessChange 6');
  is($crms->AccessChange('pdus','ic'),1,                                                             'AccessChange 7');
  is($crms->AccessChange('pdus','und'),1,                                                            'AccessChange 8');
  is($crms->AccessChange('pdus','icus'),1,                                                           'AccessChange 9');
  is($crms->AccessChange('ic','ic'),0,                                                               'AccessChange 10');
  is($crms->AccessChange('ic','und'),0,                                                              'AccessChange 11');
  is($crms->AccessChange('ic','icus'),1,                                                             'AccessChange 12');
  is($crms->AccessChange('und','icus'),1,                                                            'AccessChange 13');
}

done_testing();

my $r = $crms->GetErrors();
foreach my $w (@{$r})
{
  print "Warning: $w\n";
}

