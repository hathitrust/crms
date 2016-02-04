#!/usr/bin/perl

use warnings;
my ($DLXSROOT, $DLPS_DEV);
BEGIN
{
  $DLXSROOT = $ENV{'DLXSROOT'};
  $DLPS_DEV = $ENV{'DLPS_DEV'};
  unshift (@INC, $DLXSROOT . '/cgi/c/crms/');
}

use strict;
use CRMS;
use Getopt::Std;
use Test::More;


my %opts;
getopts('rptx:', \%opts);

my $production = $opts{'p'};
my $training = $opts{'t'};
my $sys = $opts{'x'};
my $dev = 'moseshll';
$dev = 0 if $production;
$dev = 'crms-training' if $training;

$sys = 'crms' unless $sys;

my $crms = CRMS->new(
        logFile      =>   "$DLXSROOT/prep/c/crms/log_unittest.txt",
        sys          =>   $sys,
        verbose      =>   1,
        root         =>   $DLXSROOT,
        dev          =>   $dev
		    );


ok($crms->GetViolations('mdp.39015063050051'),                           'violation in date range');
ok($crms->GetViolations('mdp.39015068249401'),                           'violation in foreign pub');
ok($crms->GetViolations('mdp.39015035994030'),                           'violation in FMT');

if ($sys ne 'crmsworld')
{
  isnt($crms->ShouldVolumeBeFiltered('uc1.31822009761909'), 'gov',       'probable Gov Doc 1'); # uncaught
  isnt($crms->ShouldVolumeBeFiltered('uc1.31822009761842'), 'gov',       'probable Gov Doc 2'); # uncaught
  isnt($crms->ShouldVolumeBeFiltered('uc1.31822020641114'), 'gov',       'probable Gov Doc 3'); # uncaught
  isnt($crms->ShouldVolumeBeFiltered('uc1.31822023236219'), 'gov',       'probable Gov Doc 4'); # uncaught
  isnt($crms->ShouldVolumeBeFiltered('uc1.31822009762170'), 'gov',       'probable Gov Doc 5'); # uncaught
  isnt($crms->ShouldVolumeBeFiltered('uc1.31822032663288'), 'gov',       'probable Gov Doc 6'); # uncaught
  isnt($crms->ShouldVolumeBeFiltered('uc1.31822009761610'), 'gov',       'probable Gov Doc 7'); # uncaught
  is($crms->ShouldVolumeBeFiltered('uc1.31822032646135'),   'gov',       'probable Gov Doc 8');
  isnt($crms->ShouldVolumeBeFiltered('uc1.31822009761628'), 'gov',       'probable Gov Doc 9'); # uncaught
  isnt($crms->ShouldVolumeBeFiltered('uc1.31822032663288'), 'gov',       'probable Gov Doc 10'); # uncaught
  is($crms->ShouldVolumeBeFiltered('uc1.b4239360'),         'gov',       'probable Gov Doc 11');
  isnt($crms->ShouldVolumeBeFiltered('uc1.31822009761800'), 'gov',       'probable Gov Doc 12'); # uncaught
  isnt($crms->ShouldVolumeBeFiltered('uc1.31822016490567'), 'gov',       'probable Gov Doc 13'); # uncaught
  is($crms->ShouldVolumeBeFiltered('uc1.b4239650'),         'gov',       'probable Gov Doc 14');
  isnt($crms->ShouldVolumeBeFiltered('uc1.31822009761677'), 'gov',       'probable Gov Doc 15'); # uncaught
  isnt($crms->ShouldVolumeBeFiltered('uc1.31822016490195'), 'gov',       'probable Gov Doc 16'); # uncaught
  isnt($crms->ShouldVolumeBeFiltered('uc1.b4250907'),       'gov',       'probable Gov Doc 17'); # uncaught
  isnt($crms->ShouldVolumeBeFiltered('uc1.31822009265760'), 'gov',       'probable Gov Doc 18'); # uncaught
  isnt($crms->ShouldVolumeBeFiltered('uc1.31822016490500'), 'gov',       'probable Gov Doc 19'); # uncaught
  isnt($crms->ShouldVolumeBeFiltered('uc1.31822020642872'), 'gov',       'probable Gov Doc 20'); # uncaught
}
is($crms->ShouldVolumeBeFiltered('mdp.39015071261104'), 'language',    'language to und');
is($crms->ShouldVolumeBeFiltered('mdp.39015004119445'), 'translation', 'translation to und');

is($crms->TwoWorkingDays('2010-07-28'), '2010-07-30 23:59:59',           '2 WDs from Wed');
is($crms->TwoWorkingDays('2010-07-30'), '2010-08-03 23:59:59',           '2 WDs from Fri');
is($crms->TwoWorkingDays('2011-05-26'), '2011-05-31 23:59:59',           '2 WDs over Memorial 2011');
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

if ($sys ne 'crmsworld')
{
  is($crms->GetInstitutionName($crms->GetUserInstitution('hansone@indiana.edu')),      'Indiana',            'IU affiliation');
  is($crms->GetInstitutionName($crms->GetUserInstitution('aseeger@library.wisc.edu')), 'Wisconsin',          'UW affiliation');
  is($crms->GetInstitutionName($crms->GetUserInstitution('zl2114@columbia.edu')),      'Columbia',           'COL affiliation');
  is(scalar @{ $crms->GetInstitutionUsers(1) }, 8,                         'IU affiliates count');
  is(scalar @{ $crms->GetInstitutionUsers(2) }, 7,                         'UW affiliates count');
  is(scalar @{ $crms->GetInstitutionUsers(4) }, 1,                         'COL affiliates count');
  is($crms->IsReviewCorrect('uc1.b3763822','dfulmer','2009-11-02') ,0,     'Correctness: uc1.b3763822 1');
  is($crms->IsReviewCorrect('uc1.b3763822','cwilcox','2009-11-03') ,1,     'Correctness: uc1.b3763822 2');
  is($crms->IsReviewCorrect('uc1.b3763822','gnichols123','2009-11-04') ,1, 'Correctness: uc1.b3763822 3');
  is($crms->IsReviewCorrect('uc1.b3763822','jaheim123','2009-11-04') ,0,   'Correctness: uc1.b3763822 4');
  is($crms->IsReviewCorrect('uc1.b3763822','annekz','2009-11-09') ,1,      'Correctness: uc1.b3763822 5');
}

if ($sys ne 'crmsworld')
{
  my $record = $crms->GetMetadata('mdp.39015011285692');
  is(scalar @{$crms->GetViolations('mdp.39015011285692',$record,0,0)}, 1,    'Violations: mdp.39015011285692 P0');
  is(scalar @{$crms->GetViolations('mdp.39015011285692',$record,1,0)}, 1,    'Violations: mdp.39015011285692 P1');
  is(scalar @{$crms->GetViolations('mdp.39015011285692',$record,2,0)}, 1,    'Violations: mdp.39015011285692 P2');
  is(scalar @{$crms->GetViolations('mdp.39015011285692',$record,3,0)}, 1,    'Violations: mdp.39015011285692 P3');
  is(scalar @{$crms->GetViolations('mdp.39015011285692',$record,3,1)}, 0,    'Violations: mdp.39015011285692 P3 1');
  is(scalar @{$crms->GetViolations('mdp.39015011285692',$record,4,0)}, 0,    'Violations: mdp.39015011285692 P4');
  is(scalar @{$crms->GetViolations('mdp.39015011285692',$record,4,1)}, 0,    'Violations: mdp.39015011285692 P4 1');
  $record = $crms->GetMetadata('mdp.39015082195432');
  is(scalar @{$crms->GetViolations('mdp.39015082195432',$record,0,0)}, 3,    'Violations: mdp.39015082195432 P0');
  is(scalar @{$crms->GetViolations('mdp.39015082195432',$record,1,0)}, 3,    'Violations: mdp.39015082195432 P1');
  is(scalar @{$crms->GetViolations('mdp.39015082195432',$record,2,0)}, 3,    'Violations: mdp.39015082195432 P2');
  is(scalar @{$crms->GetViolations('mdp.39015082195432',$record,3,0)}, 3,    'Violations: mdp.39015082195432 P3');
  is(scalar @{$crms->GetViolations('mdp.39015082195432',$record,3,1)}, 3,    'Violations: mdp.39015082195432 P3 1');
  is(scalar @{$crms->GetViolations('mdp.39015082195432',$record,4,0)}, 3,    'Violations: mdp.39015082195432 P4');
  is(scalar @{$crms->GetViolations('mdp.39015082195432',$record,4,1)}, 0,    'Violations: mdp.39015082195432 P4 1');
}


if ($sys eq 'crmsworld')
{
  is($crms->ValidateSubmission('inu.39000005773028','moseshll',19,17,undef,undef,undef,undef),
     'Volumes published prior to 1923 are not eligible for icus/gatt. ', 'icus/gatt superadmin <23');
  is($crms->PredictRights('uc1.$b173100','1945'), 4,    'Predict rights: uc1.$b173100 1945 ic/add');
  ok($crms->CanChangeToUser('jblock@princeton.edu','jblock@princeton.edu-expert'), 'user switching');
  ok(!$crms->CanChangeToUser('jblock@princeton.edu','moseshll'), 'user switching');
}
else
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
     $crms->ValidateSubmission('mdp.39015011285692','jaheim123',1,2,undef,undef,'R000','1Jan60'), 'pd/ncn admin >63 +ren');
  ok('' eq
     $crms->ValidateSubmission('mdp.39015011285692','jaheim123',1,2,undef,undef,undef,undef),     'pd/ncn admin >63 -ren');
  ok('' eq
     $crms->ValidateSubmission('uc1.31822009761677','jaheim123',1,2,undef,undef,'R000','1Jan60'), 'pd/ncn admin <63 +ren -note');
  
  ok('' eq
     $crms->ValidateSubmission('uc1.31822009761677','jaheim123',1,2,'blah','Expert Note','R000','1Jan60'), 'pd/ncn admin <63 +ren +note');
  ok('' eq
     $crms->ValidateSubmission('uc1.31822009761677','jaheim123',1,2,'blah','Expert Note',undef,undef),     'pd/ncn admin <63 -ren +note');
  ok('' eq
     $crms->ValidateSubmission('uc1.31822009761677','gnichols',1,2,undef,undef,'R000','1Jan60'), 'pd/ncn expert <63 +ren');
}
my $id = $crms->SimpleSqlGet('SELECT id FROM und WHERE src!="duplicate"');
$crms->Filter($id, 'duplicate');
my $src = $crms->SimpleSqlGet("SELECT src FROM und WHERE id='$id'");
ok($src ne 'duplicate', "Filter($id) preserves src ($src)");
ok('volumes' eq $crms->Pluralize('volume',0), 'pluralize 0');
ok('volume' eq $crms->Pluralize('volume',1), 'pluralize 1');
ok('volumes' eq $crms->Pluralize('volume',2), 'pluralize 2');
is($crms->IsReviewCorrect('chi.22682760','lnachreiner@library.wisc.edu','2010-11-02 14:45:00'), 1, 'status 8 validation 1');
is($crms->IsReviewCorrect('chi.22682760','s-zuri@umn.edu','2010-11-02 14:02:51'), 1,               'status 8 validation 2');
is($crms->IsReviewCorrect('coo.31924002832313','dfulmer','2011-01-13 12:00:37'), 1,                'status 8 validation 3');
is($crms->IsReviewCorrect('coo.31924002832313','s-zuri@umn.edu','2011-01-13 11:13:57'), 1,         'status 8 validation 4');
if ($sys ne 'crmsworld')
{
  is($crms->IsFiltered('mdp.39015027953937','foreign'), 1,                                           'IsFiltered 1');
  is($crms->IsFiltered('mdp.39015027953937','duplicate'), 0,                                         'IsFiltered 2');
  is($crms->IsFiltered('mdp.39015027953937'), 1,                                                     'IsFiltered 3');
}
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

if ($sys eq 'crmsworld')
{
  is($crms->GetCodeFromAttrReason(1,14),1,                                                         'GetCodeFromAttrReason 1');
  is($crms->GetCodeFromAttrReason(1,15),2,                                                         'GetCodeFromAttrReason 2');
  is($crms->GetCodeFromAttrReason(2,14),4,                                                         'GetCodeFromAttrReason 3');
  is($crms->GetCodeFromAttrReason(9,14),3,                                                         'GetCodeFromAttrReason 4');
  is($crms->GetCodeFromAttrReason(19,17),5,                                                        'GetCodeFromAttrReason 5');
  is($crms->GetCodeFromAttrReason(5,8),6,                                                          'GetCodeFromAttrReason 6');
  ok($crms->Sysify('crms') eq 'crms?sys=crmsworld',                                                'Sysify 1');
  ok($crms->Sysify('crms?p=review') eq 'crms?p=review;sys=crmsworld',                              'Sysify 2');
}
else
{
  is($crms->GetCodeFromAttrReason(1,7),1,                                                          'GetCodeFromAttrReason 1');
  is($crms->GetCodeFromAttrReason(1,9),2,                                                          'GetCodeFromAttrReason 2');
  is($crms->GetCodeFromAttrReason(1,2),3,                                                          'GetCodeFromAttrReason 3');
  is($crms->GetCodeFromAttrReason(2,7),4,                                                          'GetCodeFromAttrReason 4');
  is($crms->GetCodeFromAttrReason(2,9),5,                                                          'GetCodeFromAttrReason 5');
  is($crms->GetCodeFromAttrReason(5,8),6,                                                          'GetCodeFromAttrReason 6');
  is($crms->GetCodeFromAttrReason(9,9),7,                                                          'GetCodeFromAttrReason 7');
  is($crms->GetCodeFromAttrReason(1,14),8,                                                         'GetCodeFromAttrReason 8');
  is($crms->GetCodeFromAttrReason(1,15),9,                                                         'GetCodeFromAttrReason 9');
  is($crms->GetCodeFromAttrReason(9,14),11,                                                        'GetCodeFromAttrReason 11');
  is($crms->GetCodeFromAttrReason(2,14),12,                                                        'GetCodeFromAttrReason 12');
  is($crms->SameUser('gnichols','gnichols123'),1,                                                  'SameUser 1');
  is($crms->SameUser('gnichols','moseshll'),0,                                                     'SameUser 2');
  is($crms->SameUser('rose','doc'),0,                                                              'SameUser 3');
}

is($crms->TolerantCompare(undef,undef),1,                                                          'TolerantCompare 1');
is($crms->TolerantCompare('blah',undef),0,                                                         'TolerantCompare 2');
is($crms->TolerantCompare(undef,'blah'),0,                                                         'TolerantCompare 3');
is($crms->TolerantCompare('blah','bleh'),0,                                                        'TolerantCompare 4');
is($crms->TolerantCompare('blah','blah'),1,                                                        'TolerantCompare 5');


done_testing();

my $r = $crms->GetErrors();
foreach my $w (@{$r})
{
  print "Warning: $w\n";
}

