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
getopts('pt', \%opts);

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

is($crms->GetUserAffiliation('hansone@indiana.edu'), 'IU',               'IU affiliation');
is($crms->GetUserAffiliation('aseeger@library.wisc.edu'), 'UW',          'UW affiliation');
is(scalar @{ $crms->GetUsersWithAffiliation('IU') }, 4,                  'IU affiliates count');
is(scalar @{ $crms->GetUsersWithAffiliation('UW') }, 5,                  'UW affiliates count');

is($crms->IsReviewCorrect('uc1.b3763822','dfulmer','2009-11-02') ,0,     'Correctness: uc1.b3763822 1');
is($crms->IsReviewCorrect('uc1.b3763822','cwilcox','2009-11-03') ,1,     'Correctness: uc1.b3763822 2');
is($crms->IsReviewCorrect('uc1.b3763822','gnichols123','2009-11-04') ,1, 'Correctness: uc1.b3763822 3');
is($crms->IsReviewCorrect('uc1.b3763822','jaheim123','2009-11-04') ,0,   'Correctness: uc1.b3763822 4');
is($crms->IsReviewCorrect('uc1.b3763822','annekz','2009-11-09') ,1,      'Correctness: uc1.b3763822 5');

my $sql = "SELECT ID,DREG FROM stanford";
my $ref = $crms->get('dbh')->selectall_arrayref($sql);
foreach my $row (@{$ref})
{
  my $id = $row->[0];
  my $dreg = $row->[1];
  ok(('' eq $crms->CheckRenDate($dreg)),                                 "CheckRenDate($id)");
}

done_testing();

my $r = $crms->GetErrors();
foreach my $w (@{$r})
{
  print "Warning: $w\n";
}

