#!/l/local/bin/perl

my $DLXSROOT;
my $DLPS_DEV;
BEGIN 
{ 
    $DLXSROOT = $ENV{'DLXSROOT'}; 
    $DLPS_DEV = $ENV{'DLPS_DEV'}; 
    unshift ( @INC, $ENV{'DLXSROOT'} . "/cgi/c/crms/" );
}

use strict;
use CRMS;
use Getopt::Std;
use Term::ANSIColor qw(:constants);

$Term::ANSIColor::AUTORESET = 1;



my $finalStats = <<END;
CRMS Project Cumulative
Categories	Grand Total	2010
All PD	93	93
pd/ren	53	53
pd/ncn	40	40
pd/cdpp	0	0
pdus/cdpp	0	0
All IC	2	2
ic/ren	2	2
ic/cdpp	0	0
All UND/NFI	6	6
Total	101	101
Status 4	60	60
Status 5	36	36
Status 6	5	5
END

my $data = <<END;
mdp.39015064503116 cwilcox 1
mdp.39015064504643 sgueva 1
mdp.39015064521340 esaran 1
mdp.39015064535944 gnichols 1
mdp.39015064537056 cwilcox 1
mdp.39015064540944 esaran 1
mdp.39015064543161 cwilcox 1
mdp.39015065132402 cwilcox 1
mdp.39015065134051 esaran 1
mdp.39015065246095 sgueva 1
mdp.39015065274550 esaran 1
mdp.39015065294897 sgueva 1
mdp.39015065311360 esaran 1
mdp.39015065322946 esaran 1
mdp.39015065378260 cwilcox 1
mdp.39015065432463 dfulmer 1
mdp.39015065432505 dfulmer 1
mdp.39015065432711 esaran 1
mdp.39015065452750 esaran 1
mdp.39015065498217 cwilcox 1
mdp.39015065510052 sgueva 1
mdp.39015065510235 gnichols 1
mdp.39015065510284 gnichols 1
mdp.39015065511563 sgueva 1
mdp.39015065512181 sgueva 1
mdp.39015065512322 sgueva 1
mdp.39015065512413 sgueva 1
mdp.39015065516968 dmcw 1
mdp.39015065528336 sgueva 1
mdp.39015065528617 sgueva 1
mdp.39015065530274 sgueva 1
mdp.39015065530282 sgueva 1
mdp.39015065530290 sgueva 1
mdp.39015065531579 sgueva 1
mdp.39015065644430 sgueva 1
mdp.39015065646955 cwilcox 1
mdp.39015065654256 sgueva 1
mdp.39015065655576 sgueva 1
mdp.39015065660857 sgueva 1
mdp.39015065661939 sgueva 1
mdp.39015065668397 sgueva 1
mdp.39015065671086 dfulmer 1
mdp.39015065676309 sgueva 1
mdp.39015065683149 sgueva 1
mdp.39015065683610 sgueva 1
mdp.39015065692769 sgueva 1
mdp.39015065692850 esaran 1
mdp.39015065704713 sgueva 1
mdp.39015065705009 gnichols 1
mdp.39015065709746 sgueva 1
mdp.39015065724687 sgueva 1
mdp.39015065728688 sgueva 1
mdp.39015065730494 gnichols 1
mdp.39015065734439 dfulmer 1
mdp.39015065736251 dfulmer 1
mdp.39015065750450 dfulmer 1
mdp.39015065759022 dfulmer 1
mdp.39015065772751 esaran 1
mdp.39015065808027 dmcw 1
mdp.39015065809306 sgueva 1
mdp.39015065897574 sgueva 1
mdp.39015065904917 cwilcox 1
mdp.39015066475594 dfulmer 1
mdp.39015066496830 esaran 1
mdp.39015066500508 sgueva 1
mdp.39015066624472 sgueva 1
mdp.39015066904940 sgueva 1
mdp.39015066904957 sgueva 1
mdp.39015066905145 sgueva 1
mdp.39015066905376 sgueva 1
mdp.39015066927321 dfulmer 1
mdp.39015066986129 cwilcox 1
mdp.39015067139389 esaran 1
mdp.39015067162431 sgueva 1
mdp.39015067163215 esaran 1
mdp.39015067163801 sgueva 1
mdp.39015067225733 sgueva 1
mdp.39015067225741 sgueva 1
mdp.39015067255524 sgueva 1
mdp.39015067263346 sgueva 1
mdp.39015067265010 sgueva 1
mdp.39015067266315 sgueva 1
mdp.39015067266323 sgueva 1
mdp.39015067266331 sgueva 1
mdp.39015067266349 sgueva 1
mdp.39015067284144 sgueva 1
mdp.39015067308836 sgueva 1
mdp.39015067308844 sgueva 1
mdp.39015067308984 sgueva 1
mdp.39015067308992 sgueva 1
mdp.39015067309008 sgueva 1
mdp.39015067309057 sgueva 1
mdp.39015067331705 sgueva 1
mdp.39015067331713 sgueva 1
mdp.39015065661939 annekz 1
mdp.39015024910328 annekz 1
mdp.39015024912613 annekz 1
mdp.39015010885039 annekz 1
mdp.39015065683149 annekz 1
mdp.39015023082301 annekz 1
inu.32000009454499 annekz 1
mdp.39015071455961 gnichols123 1
mdp.39015001587149 annekz 1
mdp.39015001587149 cwilcox 1
mdp.39015001587149 dfulmer 0
uc1.b3480039 doc 1
uc1.b3480039 gnichols123 1
uc1.b3480039 rose 1
mdp.39015001455685 annekz 1
mdp.39015001455685 cwilcox 1
mdp.39015001455685 dfulmer 2
uc1.b3146845 annekz 1
uc1.b3146845 cwilcox 0
uc1.b3146845 dfulmer 1
mdp.39015002586306 annekz 1
mdp.39015002586306 cwilcox 1
mdp.39015002586306 dfulmer 0
mdp.39015002835653 annekz 1
mdp.39015002835653 cwilcox 1
mdp.39015002835653 dfulmer 0
uc1.b3496576 doc 0
uc1.b3496576 gnichols123 1
uc1.b3496576 rose 0
uc1.b3843865 doc 0
uc1.b3843865 gnichols123 1
uc1.b3843865 rose 0
mdp.39015002153669 annekz 1
mdp.39015002153669 cwilcox 1
mdp.39015002153669 dfulmer 0
mdp.39015001871287 annekz 1
mdp.39015001871287 cwilcox 1
mdp.39015001871287 dfulmer 0
wu.89081503401 doc 0
wu.89081503401 gnichols123 1
wu.89081503401 rose 0
mdp.39015081950209 annekz 1
mdp.39015081950209 cwilcox 0
mdp.39015081950209 dfulmer 1
mdp.39015004084136 annekz 1
mdp.39015004084136 cwilcox 1
mdp.39015004084136 dfulmer 0
mdp.39015002012329 gnichols123 1
mdp.39015084474140 annekz 1
mdp.39015084474140 cwilcox 0
mdp.39015084474140 dfulmer 1
wu.89081504193 doc 0
wu.89081504193 gnichols123 1
wu.89081504193 rose 0
uc1.b18463 annekz 1
uc1.b18463 cwilcox 0
uc1.b18463 dfulmer 1
mdp.39015002280678 annekz 1
mdp.39015002280678 cwilcox 1
mdp.39015002280678 dfulmer 0
mdp.39015002565029 annekz 1
mdp.39015002565029 cwilcox 1
mdp.39015002565029 dfulmer 0
mdp.39015084863839 annekz 1
mdp.39015084863839 cwilcox 0
mdp.39015084863839 dfulmer 1
mdp.39015008845565 annekz 1
mdp.39015008845565 dfulmer 1
mdp.39015008845565 rereport02 0
mdp.39015003998922 annekz 1
mdp.39015003998922 dfulmer 1
mdp.39015003998922 rereport02 0
mdp.39015010300286 annekz 1
mdp.39015010300286 dfulmer 1
mdp.39015010300286 rereport02 0
mdp.39015010432923 annekz 1
mdp.39015010432923 dfulmer 1
mdp.39015010432923 rereport02 0
mdp.39015008834296 annekz 1
mdp.39015008834296 dfulmer 1
mdp.39015008834296 rereport02 0
mdp.39015003397927 annekz 1
mdp.39015003397927 dfulmer 1
mdp.39015003397927 rereport02 0
mdp.39015009284699 annekz 1
mdp.39015009284699 dfulmer 1
mdp.39015009284699 rereport02 0
mdp.39015002946385 annekz 1
mdp.39015002946385 dfulmer 1
mdp.39015002946385 rereport02 0
mdp.39015002370248 annekz 1
mdp.39015002370248 dfulmer 1
mdp.39015002370248 rereport02 0
mdp.39015005411536 annekz 1
mdp.39015005411536 dfulmer 1
mdp.39015005411536 rereport02 0
wu.89086255353 annekz 1
inu.32000003495613 cwilcox 1
inu.32000003495613 dfulmer 1
mdp.39015056952164 cwilcox 1
mdp.39015056952164 doc 1
inu.32000002913582 cwilcox 1
inu.32000002913582 dfulmer 1
inu.30000093904526 cwilcox 1
inu.30000093904526 dfulmer 1
mdp.39015039837557 cwilcox 1
mdp.39015039837557 dfulmer 1
mdp.39015079843242 cwilcox 1
mdp.39015079843242 doc 1
inu.30000083470769 cwilcox 1
inu.30000083470769 dfulmer 1
mdp.39015045987669 cwilcox 1
mdp.39015045987669 dfulmer 1
mdp.39015005024750 cwilcox 1
mdp.39015005024750 dfulmer 1
mdp.39015054057214 cwilcox 1
mdp.39015054057214 dfulmer 1
mdp.39015008655618 cwilcox 1
mdp.39015008655618 dfulmer 1
mdp.39015043592511 cwilcox 1
mdp.39015043592511 dfulmer 1
mdp.39015064064036 cwilcox 1
mdp.39015064064036 doc 1
mdp.39015049881074 cwilcox 1
mdp.39015049881074 dfulmer 1
inu.30000081677589 cwilcox 1
inu.30000081677589 dfulmer 1
mdp.39015036889858 cwilcox 1
mdp.39015036889858 dfulmer 1
mdp.39015027559288 cwilcox 1
mdp.39015027559288 dfulmer 1
mdp.39015069451147 cwilcox 1
mdp.39015069451147 doc 1
mdp.39015011352450 cwilcox 1
mdp.39015011352450 dfulmer 1
mdp.39015031324406 cwilcox 1
mdp.39015031324406 dfulmer 1
mdp.39015068215824 cwilcox 1
mdp.39015068215824 doc 1
mdp.39015056668489 cwilcox 1
mdp.39015056668489 dfulmer 1
mdp.39015004919166 cwilcox 1
mdp.39015004919166 dfulmer 1
mdp.39015009005185 cwilcox 1
mdp.39015009005185 dfulmer 1
mdp.39015062745982 dfulmer 1
mdp.39015062745982 rereport02 1
mdp.39015036839309 dfulmer 1
mdp.39015036839309 rereport02 1
mdp.39015030435047 dfulmer 1
mdp.39015030435047 rereport02 1
mdp.39015031929212 dfulmer 1
mdp.39015031929212 rereport02 1
mdp.39015062922789 dfulmer 1
mdp.39015062922789 rereport02 1
mdp.39015059749112 dfulmer 1
mdp.39015059749112 rereport02 1
mdp.39015011953240 dfulmer 1
mdp.39015011953240 rereport02 1
mdp.39015059771884 dfulmer 1
mdp.39015059771884 rereport02 1
mdp.39015024037080 dfulmer 1
mdp.39015024037080 rereport02 1
mdp.39015058422356 dfulmer 1
mdp.39015058422356 rereport02 1
mdp.39015026830979 dfulmer 1
mdp.39015026830979 rereport02 1
mdp.39015030621992 dfulmer 1
mdp.39015030621992 rereport02 1
mdp.39015058431860 dfulmer 1
mdp.39015058431860 rereport02 1
mdp.39015059740202 dfulmer 1
mdp.39015059740202 rereport02 1
mdp.39015041295489 dfulmer 1
mdp.39015041295489 rereport02 1
mdp.39015063038650 dfulmer 1
mdp.39015063038650 rereport02 1
mdp.39015027781684 dfulmer 1
mdp.39015027781684 rereport02 1
mdp.39015058623508 dfulmer 1
mdp.39015058623508 rereport02 1
mdp.39015062314441 dfulmer 1
mdp.39015062314441 rereport02 1
mdp.39015038826973 dfulmer 1
mdp.39015038826973 rereport02 1
mdp.39015030344827 dfulmer 1
mdp.39015030344827 rereport02 1
mdp.39015033916126 cwilcox 1
mdp.39015033916126 dfulmer 1
mdp.39015031930475 dfulmer 1
mdp.39015031930475 rereport02 1
mdp.39015062382596 dfulmer 1
mdp.39015062382596 rereport02 1
mdp.39015030021169 dfulmer 1
mdp.39015030021169 rereport02 1
mdp.39015020470293 dfulmer 1
mdp.39015020470293 rereport02 1
mdp.39015030430121 dfulmer 1
mdp.39015030430121 rereport02 1
mdp.39015049200705 dfulmer 1
mdp.39015049200705 rereport02 1
mdp.39015035853194 dfulmer 1
mdp.39015035853194 rereport02 1
mdp.39015028121955 dfulmer 1
mdp.39015028121955 rereport02 1
mdp.39015014507233 dfulmer 1
mdp.39015014507233 rereport02 1
mdp.39015062190254 dfulmer 1
mdp.39015062190254 rereport02 1
mdp.39015062201077 dfulmer 1
mdp.39015062201077 rereport02 1
mdp.39015015211736 dfulmer 1
mdp.39015015211736 rereport02 1
mdp.39015059457542 dfulmer 1
mdp.39015059457542 rereport02 1
mdp.39015026741838 dfulmer 1
mdp.39015026741838 rereport02 1
mdp.39015028137043 dfulmer 1
mdp.39015028137043 rereport02 1
mdp.39015041300180 dfulmer 1
mdp.39015041300180 rereport02 1
mdp.39015059721749 dfulmer 1
mdp.39015059721749 rereport02 1
mdp.39015059888506 dfulmer 1
mdp.39015059888506 rereport02 1
mdp.39015021107282 dfulmer 1
mdp.39015021107282 rereport02 1
END


my %opts;
getopts('dhv12345', \%opts);

my $load     = $opts{'d'};
my $help     = $opts{'h'};
my $verbose  = $opts{'v'};
my $phase1   = $opts{'1'};
my $phase2   = $opts{'2'};
my $phase3   = $opts{'3'};
my $phase4   = $opts{'4'};
my $phase5   = $opts{'5'};

if ( $help )
{
  die "USAGE: $0 [-d] [-h] [-v] [-1] [-2] [-3] [-4] [-5]\n\n";
}

my $logfile = "$DLXSROOT/prep/c/crms/tester_log.txt";
unlink $logfile if -f $logfile;
my $crms = CRMS->new(
        logFile      =>   $logfile,
        configFile   =>   "$DLXSROOT/bin/c/crms/crms.cfg",
        verbose      =>   0,
        root         =>   $DLXSROOT,
        dev          =>   1,
		    );

$phase2 = 1 if $phase1 and ($phase3 or $phase4 or $phase5);
$phase3 = 1 if $phase2 and ($phase4 or $phase5);
$phase4 = 1 if $phase3 and $phase5;

$_ = `hostname`;
chomp;
if ('clamato.umdl.umich.edu' ne $_)
{
  Complain("I refuse to run anywhere but on clamato. You're on $_.");
  exit(1);
}

if ($load)
{
  print "Loading test database.\n";
  `mysql -u moseshll -p crms < db_test.sql`;
  # To keep from importing vast numbers of items in overnight processing. Bumps date.
  $crms->PrepareSubmitSql('INSERT INTO candidatesrecord (addedamount) VALUES (1)');
}

if ($phase1)
{
  print "Beginning phase 1 (initial reviews)\n";
  my $sql = "SELECT id,priority FROM queue ORDER BY priority DESC, id ASC";
  my $r = $crms->get('dbh')->selectall_arrayref($sql);
  my $n0 = 0;
  my $n1 = 0;
  my $q = 1;
  my $eq = 1;
  foreach my $row (@{$r})
  {
    my $id = $row->[0];
    my $priority = $row->[1];
    print "$id ($priority)\n" if $verbose;
    # annekz reviews 3 priority 4 items as pd/ren (1/7)
    if ($priority == 4)
    {
      $crms->SubmitReview($id, 'annekz', 1, 7, undef, undef, undef, 1, undef, undef, undef, $eq);
      $eq = 0;
    }
    # gnichols123 reviews 2 priority 3 items as ic/ren (2/7)
    elsif ($priority == 3)
    {
      $crms->SubmitReview($id, 'gnichols123', 2, 7, undef, undef, undef, 1, undef, undef);
    }
    # All 50 rereport02 items are pd/ncn (1/2)
    # dfulmer reviews the first 10 as conflicts (ic/ren [1/7]) and the remaining 40 agreeing
    elsif ($priority == 1)
    {
      my $reason = ($n1 < 10)? 7:2;
      $crms->SubmitReview($id, 'dfulmer', 1, $reason, undef, undef, undef, 0, undef, undef);
      $n1++;
    }
    # All priority 0 items are reviewed by cwilcox and (if a second review) dfulmer
    # First 5 priority 0 are matching und/nfi (5/8)
    # Next 5 are single review pd/ren (1/7) by cwilcox
    # Next 10 are pd/ren vs ic/ren
    # Next 20 are pd/ren in agreement
    # Next 10 are one und/nfi vs pd/ren
    else
    {
      if ($n0 < 5) # 5 ps 4
      {
        $crms->SubmitReview($id, 'cwilcox', 5, 8, undef, undef, undef, 0, undef, undef);
        $crms->SubmitReview($id, 'dfulmer', 5, 8, undef, undef, undef, 0, undef, undef);
      }
      elsif ($n0 < 10) # 5 ps 1
      {
        $crms->SubmitReview($id, 'cwilcox', 1, 7, undef, undef, undef, 0, undef, undef);
      }
      elsif ($n0 < 20) # 1 ps 1, 9 ps 2
      {
        $crms->SubmitReview($id, 'cwilcox', 1, 7, undef, undef, undef, 0, undef, undef, undef, $q);
        $crms->SubmitReview($id, 'dfulmer', 2, 7, undef, undef, undef, 0, undef, undef);
        $q = undef;
      }
      elsif ($n0 < 35) # 15 ps 4
      {
        $crms->SubmitReview($id, 'cwilcox', 1, 7, undef, undef, undef, 0, undef, undef);
        $crms->SubmitReview($id, 'dfulmer', 1, 7, undef, undef, undef, 0, undef, undef);
      }
      elsif ($n0 < 40) # 5 ps 4
      {
        $crms->SubmitReview($id, 'cwilcox', 1, 7, undef, undef, undef, 0, undef, undef);
        $crms->SubmitReview($id, 'doc', 1, 7, undef, undef, undef, 0, undef, undef);
      }
      elsif ($n0 < 45) # 5 ps 2
      {
        $crms->SubmitReview($id, 'cwilcox', 5, 8, undef, undef, undef, 0, undef, undef);
        $crms->SubmitReview($id, 'dfulmer', 1, 7, undef, undef, undef, 0, undef, undef);
      }
      else # 5 ps 3
      {
        $crms->SubmitReview($id, 'rose', 1, 7, undef, undef, undef, 0, undef, undef);
        $crms->SubmitReview($id, 'doc', 1, 7, undef, undef, undef, 0, undef, undef);
      }
      $n0++;
    }
  }
  my $r = $crms->GetErrors();
  foreach my $w (@{$r})
  {
    print "Warning: $w\n";
  }
  # At the end of phase 1, here are the pending status breakdowns:
  # Stat | Count
  # 0    | 0 (everything should get reviewed)
  # 1    | 6 (priority 0 single reviews)
  # 2    | 24 (10 priority 1, 14 priority 0)
  # 3    | 5 (priority 0)
  # 4    | 65 (40 priority 1, 20 priority 0)
  # 5    | 5 (priority 3/4 items)
  # 6    | 0 (not yet!)
  my %stati = (0=>0,1=>6,2=>24,3=>5,4=>65,5=>5,6=>0);
  foreach my $status (sort keys %stati)
  {
    my $sql = "SELECT COUNT(*) FROM queue WHERE pending_status=$status";
    print "$sql\n" if $verbose;
    my $count = $crms->SimpleSqlGet($sql);
    my $should = $stati{$status};
    Complain("Pending status $status has $count, should have $should in queue") unless $count == $should;
  }
  VerifySQL('SELECT COUNT(*) FROM queue WHERE status>0',5,'Wrong number of queue nonzero status items.');
  VerifySQL('SELECT COUNT(*) FROM queue WHERE status=0',100,'Wrong number of queue status zero items.');
  VerifySQL('SELECT COUNT(*) FROM queue',105,'Wrong number of items in queue.');
  VerifySQL('SELECT COUNT(*) FROM reviews',200,'Wrong number of items in reviews.');
  Verify($crms->GetTotalAwaitingReview(),0,'Wrong number awaiting review');
  Verify($crms->GetTotalNonLegacyReviewCount(),0,'Wrong number of CRMS historical reviews');
  Verify($crms->GetTotalLegacyReviewCount(),100,'Wrong number of legacy reviews');
  Verify($crms->GetTotalHistoricalReviewCount(),100,'Wrong number of historical reviews');
  $crms->SanityCheckDB();
  my $r = $crms->GetErrors();
  foreach my $w (@{$r})
  {
    print "Warning: $w\n";
  }
  print "Phase 1 complete\n";
}


if ($phase2)
{
  print "Beginning phase 2 (review processing)\n";
  $crms->ProcessReviews();
  # At the end of phase 2, here are the status breakdowns:
  # Stat | Count
  # 0    | 6 (5 priority 0 single reviews and one hold)
  # 2    | 29 (10 priority 1, 19 priority 0)
  # 3    | 5 (priority 0)
  # 4    | 60 (40 priority 1, 20 priority 0)
  # 5    | 5 (priority 3/4 items)
  # 6    | 0 (not yet!)
  my %stati = (0=>6,1=>0,2=>24,3=>5,4=>65,5=>5,6=>0);
  foreach my $status (sort keys %stati)
  {
    my $sql = "SELECT COUNT(id) FROM queue WHERE status=$status";
    my $count = $crms->SimpleSqlGet($sql);
    my $should = $stati{$status};
    Complain("Status $status has $count, should have $should in queue") unless $count == $should;
  }
  VerifySQL('SELECT COUNT(*) FROM queue WHERE status>0',99,'Wrong number of queue nonzero status items.');
  VerifySQL('SELECT COUNT(*) FROM queue WHERE status=0',6,'Wrong number of queue status zero items.');
  VerifySQL('SELECT COUNT(*) FROM queue',105,'Wrong number of items in queue.');
  VerifySQL('SELECT COUNT(*) FROM reviews WHERE hold IS NOT NULL',2,'Wrong number of held reviews.');
  VerifySQL('SELECT COUNT(*) FROM reviews',200,'Wrong number of items in reviews.');
  Verify($crms->GetTotalAwaitingReview(),0,'Wrong number awaiting review');
  Verify($crms->GetTotalNonLegacyReviewCount(),0,'Wrong number of CRMS historical reviews');
  Verify($crms->GetTotalLegacyReviewCount(),100,'Wrong number of legacy reviews');
  Verify($crms->GetTotalHistoricalReviewCount(),100,'Wrong number of historical reviews');
  $crms->SanityCheckDB();
  my $r = $crms->GetErrors();
  foreach my $w (@{$r})
  {
    Complain("Warning: $w");
  }
  print "Phase 2 complete\n";
}

if ($phase3)
{
  print "Beginning phase 3 (conflict and provisional reviews)\n";
  my $sql = "SELECT id FROM queue WHERE status=2 ORDER BY id ASC";
  my $r = $crms->get('dbh')->selectall_arrayref($sql);
  my $swiss = 1;
  foreach my $row (@{$r})
  {
    my $id = $row->[0];
    $crms->SubmitReview($id, 'annekz', 1, 7, undef, undef, undef, 1, undef, undef, $swiss);
    $swiss = 0;
  }
  $sql = "SELECT id FROM queue WHERE status=3 ORDER BY id ASC";
  my $r = $crms->get('dbh')->selectall_arrayref($sql);
  my $clone = 1;
  foreach my $row (@{$r})
  {
    my $id = $row->[0];
    if ($clone)
    {
      $crms->CloneReview($id, 'gnichols123');
    }
    else
    {
      $crms->SubmitReview($id, 'gnichols123', 5, 8, undef, undef, undef, 1, undef, undef);
    }
    $clone = undef;
  }
  # At the end of phase 3, here are the status breakdowns:
  # Stat | Count
  # 0    | 6 (5 priority 0 single reviews and a hold)
  # 4    | 65 (45 priority 1, 20 priority 0)
  # 5    | 33 (5 priority 3/4 items, 28 priority 0)
  # 6    | 1 from the cloned review
  my %stati = (0=>6,4=>65,5=>33,6=>1);
  foreach my $status (sort keys %stati)
  {
    my $sql = "SELECT COUNT(*) FROM queue WHERE status=$status";
    my $count = $crms->SimpleSqlGet($sql);
    my $should = $stati{$status};
    Complain("Status $status has $count, should have $should in queue") unless $count == $should;
  }
  VerifySQL('SELECT COUNT(*) FROM queue WHERE status>0',99,'Wrong number of queue nonzero status items.');
  VerifySQL('SELECT COUNT(*) FROM queue WHERE status=0',6,'Wrong number of queue status zero items.');
  VerifySQL('SELECT COUNT(*) FROM queue',105,'Wrong number of items in queue.');
  VerifySQL('SELECT COUNT(*) FROM reviews',229,'Wrong number of items in reviews.');
  Verify($crms->GetTotalAwaitingReview(),0,'Wrong number awaiting review');
  Verify($crms->GetTotalNonLegacyReviewCount(),0,'Wrong number of CRMS historical reviews');
  Verify($crms->GetTotalLegacyReviewCount(),100,'Wrong number of legacy reviews');
  Verify($crms->GetTotalHistoricalReviewCount(),100,'Wrong number of historical reviews');
  $crms->SanityCheckDB();
  my $r = $crms->GetErrors();
  foreach my $w (@{$r})
  {
    Complain("Warning: $w");
  }
  print "Phase 3 complete\n";
}

if ($phase4)
{
  print "Beginning phase 4 (queue update and monthly stats update)\n";
  system('./updateQueue.pl -cq') == 0 or die "updateQueue.pl failed: $?";
  system('./monthlyStats.pl') == 0 or die "monthlyStats.pl failed: $?";
  my $sql = 'SELECT COUNT(*) FROM queue';
  my $count = $crms->SimpleSqlGet($sql);
  my $should = 7;
  Complain("Queue has $count, should have $should") unless $count == $should;
  my %stati = (0=>6);
  foreach my $status (sort keys %stati)
  {
    $sql = "SELECT COUNT(*) FROM queue WHERE status=$status";
    $count = $crms->SimpleSqlGet($sql);
    $should = $stati{$status};
    Complain("Status $status has $count, should have $should in queue") unless $count == $should;
  }
  %stati = (4=>130,5=>96,6=>3);
  foreach my $status (sort keys %stati)
  {
    $sql = "SELECT COUNT(*) FROM historicalreviews WHERE status=$status";
    $count = $crms->SimpleSqlGet($sql);
    $should = $stati{$status};
    Complain("Status $status has $count, should have $should in historical") unless $count == $should;
  }
  VerifySQL('SELECT COUNT(*) FROM queue WHERE status>0',1,'Wrong number of queue nonzero status items.');
  VerifySQL('SELECT COUNT(*) FROM queue WHERE status=0',6,'Wrong number of queue status zero items.');
  VerifySQL('SELECT COUNT(*) FROM queue',7,'Wrong number of items in queue');
  VerifySQL('SELECT COUNT(*) FROM reviews',8,'Wrong number of items in reviews');
  Verify($crms->GetTotalAwaitingReview(),0,'Wrong number awaiting review');
  Verify($crms->GetTotalNonLegacyReviewCount(),221,'Wrong number of CRMS historical reviews');
  Verify($crms->GetTotalLegacyReviewCount(),100,'Wrong number of legacy reviews');
  Verify($crms->GetTotalHistoricalReviewCount(),321,'Wrong number of historical reviews');
  VerifySQL('SELECT COUNT(*) FROM historicalreviews WHERE validated=1 AND legacy=0 AND user="cwilcox"',34,'Wrong number of validated reviews for cwilcox');
  VerifySQL('SELECT COUNT(*) FROM historicalreviews WHERE legacy=0 AND user="cwilcox"',39,'Wrong number of historical reviews for cwilcox');
  VerifySQL('SELECT COUNT(*) FROM historicalreviews WHERE validated=1 AND legacy=0 AND user="dfulmer"',75,'Wrong number of validated reviews for dfulmer');
  VerifySQL('SELECT COUNT(*) FROM historicalreviews WHERE validated=2 AND legacy=0 AND user="dfulmer"',1,'Wrong number of swiss validations for dfulmer');
  VerifySQL('SELECT COUNT(*) FROM historicalreviews WHERE legacy=0 AND user="dfulmer"',84,'Wrong number of historical reviews for dfulmer');
  $crms->SanityCheckDB();
  my $r = $crms->GetErrors();
  foreach my $w (@{$r})
  {
    print "Warning: $w\n" unless $w =~ m/questionable/i;
  }
  my @lines = split "\n", $data;
  foreach my $line (@lines)
  {
    my ($id,$user,$val) = split ' ', $line;
    my $sql = "SELECT validated FROM historicalreviews WHERE user='$user' AND id='$id'";
    my $dbval = $crms->SimpleSqlGet($sql);
    Verify($dbval,$val,"Wrong validation for $user: $id");
  }
  print "Phase 4 complete\n";
}

if ($phase5)
{
  print "Beginning phase 5 (miscellaneous tests)\n";
  my $id = 'wu.89081504193';
  my $result = $crms->AddItemToQueueOrSetItemActive($id,2);
  Verify(substr($result,0,1),0,"AddItemToQueueOrSetItemActive returned $result");
  $crms->SubmitReview($id, 'annekz', 1, 7, undef, undef, undef, 1, undef, undef);
  system('./updateQueue.pl') == 0 or die "updateQueue.pl failed: $?";
  system('./monthlyStats.pl') == 0 or die "monthlyStats.pl failed: $?";
  VerifySQL("SELECT COUNT(id) FROM und WHERE src='dissertation'",5,"Wrong und count for theses");
  VerifySQL("SELECT COUNT(id) FROM und WHERE src='translation'",7,"Wrong und count for translations");
  VerifySQL("SELECT COUNT(id) FROM und WHERE src='foreign'",2,"Wrong und count for foreign pubs");
  my %valid = ('annekz'=>1,'gnichols123'=>0,'rose'=>1,'doc'=>1);
  foreach my $user (keys %valid)
  {
    VerifySQL("SELECT validated FROM historicalreviews WHERE id='$id' AND user='$user'",$valid{$user},"Wrong validation for $user: $id");
  }
  my @unds = (
# theses: 5/10 detected
'uc1.b195517',
'uc1.b50667',
'uc1.b54721',
'uc1.b184716',
'uc1.b50734',
'uc1.b185423',
'uc1.b3508360',
'mdp.39015018634736',
'mdp.39015028711136',
'uc1.b50741',
# translations: 7/10 detected
'mdp.39015009791065',
'uc1.b598359',
'uc1.b3140728',
'uc1.b537045',
'mdp.39015019996290',
'uc1.b3758654',
'inu.32000001196858',
'mdp.39015027602708',
'mdp.39015003708909',
'mdp.39015051388794',
# foreign: 2/9 detected
'uc1.b3148827',
'uc1.b512888',
'uc1.b3439351',
'mdp.39015074910343',
'wu.89080453830',
'mdp.39015008800891',
'uc1.b537834',
'mdp.39015071135993',
'uc1.b163247');
  foreach $id (@unds)
  {
    my $result = $crms->AddItemToCandidates( $id, $crms->GetTodaysDate(), 0, 0 );
    Verify($result,1,"AddItemToCandidates failed for $result");
  }
  my $stats = $crms->CreateExportData("\t", 1, 1);
  Verify($stats,$finalStats,'Final stats mismatch');
  print "Phase 5 complete\n";
}

sub VerifySQL
{
  my $sql = shift;
  my $target = shift;
  my $msg = shift;
  
  my $count = $crms->SimpleSqlGet($sql);
  Complain("$msg (Wanted $target got $count)") if ($count != $target && $count ne $target)
}

sub Verify
{
  my $count = shift;
  my $target = shift;
  my $msg = shift;
  
  Complain("$msg (Wanted $target got $count)") if ($count != $target && $count ne $target)
}

sub Complain
{
  my $complaint = shift;
  
  print RED, "$complaint\n", RESET;
  #exit(1);
}

