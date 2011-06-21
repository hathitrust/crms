#!../../../bin/symlinks/perl

use warnings;
my ($DLXSROOT, $DLPS_DEV);
BEGIN 
{ 
  $DLXSROOT = $ENV{'DLXSROOT'}; 
  $DLPS_DEV = $ENV{'DLPS_DEV'}; 

  my $toinclude = qq{$DLXSROOT/cgi/c/crms};
  unshift( @INC, $toinclude );
}

use strict;
use CRMS;
use Getopt::Std;
use Test::More;


my %opts;
getopts('rpt', \%opts);

my $renDate = $opts{'d'};
my $production = $opts{'p'};
my $training = $opts{'t'};
my $dev = 'moseshll';
$dev = 0 if $production;
$dev = 'crmstest' if $training;

my $crms = CRMS->new(
        logFile      =>   "$DLXSROOT/prep/c/crms/log_unittest.txt",
        configFile   =>   "$DLXSROOT/bin/c/crms/crms.cfg",
        verbose      =>   1,
        root         =>   $DLXSROOT,
        dev          =>   $dev
		    );


ok($crms->GetViolations('mdp.39015063050051'),                           'violation in date range');
ok($crms->GetViolations('mdp.39015068249401'),                           'violation in foreign pub');
ok($crms->GetViolations('mdp.39015035994030'),                           'violation in FMT');

isnt($crms->ShouldVolumeGoInUndTable('uc1.31822009761909'), 'gov',       'probable Gov Doc 1'); # uncaught
isnt($crms->ShouldVolumeGoInUndTable('uc1.31822009761842'), 'gov',       'probable Gov Doc 2'); # uncaught
isnt($crms->ShouldVolumeGoInUndTable('uc1.31822020641114'), 'gov',       'probable Gov Doc 3'); # uncaught
isnt($crms->ShouldVolumeGoInUndTable('uc1.31822023236219'), 'gov',       'probable Gov Doc 4'); # uncaught
isnt($crms->ShouldVolumeGoInUndTable('uc1.31822009762170'), 'gov',       'probable Gov Doc 5'); # uncaught
isnt($crms->ShouldVolumeGoInUndTable('uc1.31822032663288'), 'gov',       'probable Gov Doc 6'); # uncaught
isnt($crms->ShouldVolumeGoInUndTable('uc1.31822009761610'), 'gov',       'probable Gov Doc 7'); # uncaught
is($crms->ShouldVolumeGoInUndTable('uc1.31822032646135'),   'gov',       'probable Gov Doc 8');
isnt($crms->ShouldVolumeGoInUndTable('uc1.31822009761628'), 'gov',       'probable Gov Doc 9'); # uncaught
isnt($crms->ShouldVolumeGoInUndTable('uc1.31822032663288'), 'gov',       'probable Gov Doc 10'); # uncaught
is($crms->ShouldVolumeGoInUndTable('uc1.b4239360'),         'gov',       'probable Gov Doc 11');
isnt($crms->ShouldVolumeGoInUndTable('uc1.31822009761800'), 'gov',       'probable Gov Doc 12'); # uncaught
isnt($crms->ShouldVolumeGoInUndTable('uc1.31822016490567'), 'gov',       'probable Gov Doc 13'); # uncaught
is($crms->ShouldVolumeGoInUndTable('uc1.b4239650'),         'gov',       'probable Gov Doc 14');
isnt($crms->ShouldVolumeGoInUndTable('uc1.31822009761677'), 'gov',       'probable Gov Doc 15'); # uncaught
isnt($crms->ShouldVolumeGoInUndTable('uc1.31822016490195'), 'gov',       'probable Gov Doc 16'); # uncaught
isnt($crms->ShouldVolumeGoInUndTable('uc1.b4250907'),       'gov',       'probable Gov Doc 17'); # uncaught
isnt($crms->ShouldVolumeGoInUndTable('uc1.31822009265760'), 'gov',       'probable Gov Doc 18'); # uncaught
isnt($crms->ShouldVolumeGoInUndTable('uc1.31822016490500'), 'gov',       'probable Gov Doc 19'); # uncaught
isnt($crms->ShouldVolumeGoInUndTable('uc1.31822020642872'), 'gov',       'probable Gov Doc 20'); # uncaught

is($crms->ShouldVolumeGoInUndTable('mdp.39015028088733'), 'language',    'language to und');
is($crms->ShouldVolumeGoInUndTable('uc1.b22139'), 'dissertation',        'dissertation to und');
is($crms->ShouldVolumeGoInUndTable('mdp.39015004119445'), 'translation', 'translation to und');
is($crms->ShouldVolumeGoInUndTable('uc1.b79381'), 'foreign',             'foreign to und');

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

is($crms->GetUserAffiliation('hansone@indiana.edu'), 'IU',               'IU affiliation');
is($crms->GetUserAffiliation('aseeger@library.wisc.edu'), 'UW',          'UW affiliation');
is(scalar @{ $crms->GetUsersWithAffiliation('IU') }, 6,                  'IU affiliates count');
is(scalar @{ $crms->GetUsersWithAffiliation('UW') }, 5,                  'UW affiliates count');

is($crms->IsReviewCorrect('uc1.b3763822','dfulmer','2009-11-02') ,0,     'Correctness: uc1.b3763822 1');
is($crms->IsReviewCorrect('uc1.b3763822','cwilcox','2009-11-03') ,1,     'Correctness: uc1.b3763822 2');
is($crms->IsReviewCorrect('uc1.b3763822','gnichols123','2009-11-04') ,1, 'Correctness: uc1.b3763822 3');
is($crms->IsReviewCorrect('uc1.b3763822','jaheim123','2009-11-04') ,0,   'Correctness: uc1.b3763822 4');
is($crms->IsReviewCorrect('uc1.b3763822','annekz','2009-11-09') ,1,      'Correctness: uc1.b3763822 5');

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

ok('Renewal no longer required for works published after 1963. ' eq
   $crms->ValidateSubmission2('mdp.39015011285692','annekz',1,2,undef,undef,'R000','1Jan60'), 'pd/ncn superadmin >63 +ren');
ok('' eq
   $crms->ValidateSubmission2('mdp.39015011285692','annekz',1,2,undef,undef,undef,undef),     'pd/ncn superadmin >63 -ren');
ok('' eq
   $crms->ValidateSubmission2('uc1.31822009761677','annekz',1,2,undef,undef,'R000','1Jan60'), 'pd/ncn superadmin <63 +ren');
ok('' eq
   $crms->ValidateSubmission2('uc1.31822009761677','annekz',1,2,undef,undef,undef,undef),     'pd/ncn superadmin <63 -ren');

ok('Renewal no longer required for works published after 1963. ' eq
   $crms->ValidateSubmission2('mdp.39015011285692','gnichols123',1,2,undef,undef,'R000','1Jan60'), 'pd/ncn admin >63 +ren');
ok('' eq
   $crms->ValidateSubmission2('mdp.39015011285692','gnichols123',1,2,undef,undef,undef,undef),     'pd/ncn admin >63 -ren');
ok('' eq
   $crms->ValidateSubmission2('uc1.31822009761677','gnichols123',1,2,undef,undef,'R000','1Jan60'), 'pd/ncn admin <63 +ren -note');
ok('pd/ncn must include either renewal id and renewal date, or note category "Expert Note". ' eq
   $crms->ValidateSubmission2('uc1.31822009761677','gnichols123',1,2,undef,undef,undef,undef),     'pd/ncn admin <63 -ren -note');
ok('' eq
   $crms->ValidateSubmission2('uc1.31822009761677','gnichols123',1,2,'blah','Expert Note','R000','1Jan60'), 'pd/ncn admin <63 +ren +note');
ok('' eq
   $crms->ValidateSubmission2('uc1.31822009761677','gnichols123',1,2,'blah','Expert Note',undef,undef),     'pd/ncn admin <63 -ren +note');

ok('' eq
   $crms->ValidateSubmission2('uc1.31822009761677','dmcw123',1,2,undef,undef,'R000','1Jan60'), 'pd/ncn expert <63 +ren');
ok('pd/ncn must include renewal id and renewal date. ' eq
   $crms->ValidateSubmission2('uc1.31822009761677','dmcw123',1,2,undef,undef,undef,undef),     'pd/ncn expert <63 -ren');
my $id = $crms->SimpleSqlGet('SELECT id FROM und WHERE src!="duplicate"');
$crms->Filter($id, 'duplicate');
my $src = $crms->SimpleSqlGet("SELECT src FROM und WHERE id='$id'");
ok($src ne 'duplicate', "Filter($id) preserves src ($src)");
ok('volumes' eq $crms->Pluralize('volume',0), 'pluralize 0');
ok('volume' eq $crms->Pluralize('volume',1), 'pluralize 1');
ok('volumes' eq $crms->Pluralize('volume',2), 'pluralize 2');
is($crms->IsReviewCorrect('chi.22682760','lnachreiner@library.wisc.edu','2010-11-02 14:45:00'), 1, 'status 8 validation 1');
is($crms->IsReviewCorrect('chi.22682760','s-zuri@umn.edu','2010-11-02 14:02:51'), 1, 'status 8 validation 2');
is($crms->IsReviewCorrect('coo.31924002832313','dfulmer','2011-01-13 12:00:37'), 1, 'status 8 validation 3');
is($crms->IsReviewCorrect('coo.31924002832313','s-zuri@umn.edu','2011-01-13 11:13:57'), 1, 'status 8 validation 4');
is($crms->IsFiltered('mdp.39015027953937','foreign'), 1, 'IsFiltered 1');
is($crms->IsFiltered('mdp.39015027953937','duplicate'), 0, 'IsFiltered 2');
is($crms->IsFiltered('mdp.39015027953937'), 1, 'IsFiltered 3');
my %data = ();
$crms->DuplicateVolumesFromCandidates('mdp.39015005203321','000623956',\%data);
ok($data{'inherit'}, 'mdp.39015005203321 inherits');
ok($data{'inherit'}->{'uc1.$b467316'}, 'mdp.39015005203321 inherits from uc1.$b467316');

if ($renDate)
{
  my $sql = "SELECT ID,DREG FROM stanford";
  my $ref = $crms->get('dbh')->selectall_arrayref($sql);
  foreach my $row (@{$ref})
  {
    $id = $row->[0];
    my $dreg = $row->[1];
    ok(('' eq $crms->CheckRenDate($dreg)),                                 "CheckRenDate($id)");
  }
}


done_testing();

my $r = $crms->GetErrors();
foreach my $w (@{$r})
{
  print "Warning: $w\n";
}

