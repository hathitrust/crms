#!/l/local/bin/perl

# This script can be run from crontab

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
use Getopt::Long;
use Mail::Sender;

my $usage = <<END;
USAGE: $0 [-hpv] [-m MAIL_ADDR [-m MAIL_ADDR2...]] 

Sends automatic monthly report of institutional stats for INST which can be in
{UM-ERAU,IU,UMN,UW,ALL}. Default is UM-ERAU.

-h       Print this help message.
-m ADDR  Mail the report to ADDR in addition to the supervisor at the institution.
         May be repeated for multiple addresses.
-p       Run in production.
-v       Be verbose.
END

my $help;
my $inst;
my @mails;
my $production;
my $verbose;

Getopt::Long::Configure ('bundling');
die 'Terminating' unless GetOptions('h|?' => \$help,
           'm:s@' => \@mails,
           'p' => \$production,
           'v+' => \$verbose);
$DLPS_DEV = undef if $production;
print "Verbosity $verbose\n" if $verbose;
die "$usage\n\n" if $help;

my $crms = CRMS->new(
    logFile      =>   "$DLXSROOT/prep/c/crms/inst_hist.txt",
    configFile   =>   "$DLXSROOT/bin/c/crms/crms.cfg",
    verbose      =>   $verbose,
    root         =>   $DLXSROOT,
    dev          =>   $DLPS_DEV
);

my $inst = uc $ARGV[0];
$inst = 'UM-ERAU' unless $inst;
my %names = ('UM-ERAU' => 'UM Electronic Access Unit__jaheim@umich.edu__Judy',
             'IU'=>'Indiana University__shmichae@indiana.edu__Sherri',
             'UMN'=>'University of Minnesota__dewey002@umn.edu__Carla',
             'UW'=>'University of Wisconsin__izimmerman@library.wisc.edu__Irene');
my @insts = ($inst);
@insts = keys %names if $inst eq 'ALL';
foreach $inst (@insts)
{
  my $users = $crms->GetUsersWithAffiliation($inst);
  my $in = "('" . (join "','", @{$users}) . "')";
  my ($year,$month) = $crms->GetTheYearMonth();
  if ($month == 1)
  {
    $month = 12;
    $year--;
  }
  else
  {
    $month--;
  }
  $month = '0'.$month if $month =~ m/^\d$/;
  my $date = "$year-$month";
  my $english = $crms->YearMonthToEnglish($date,1);
  my $sql = 'SELECT COUNT(r.id),COUNT(DISTINCT e.id) FROM historicalreviews r INNER JOIN exportdata e ON r.gid=e.gid WHERE ' .
            "r.attr=1 AND e.attr='pd' AND r.validated!=0 AND r.time LIKE '$date%' AND r.user IN $in";
  my $ref = $crms->GetDb()->selectall_arrayref($sql);
  my $rev = $ref->[0]->[0];
  my $det = $ref->[0]->[1];
  $sql = 'SELECT COUNT(r.id) FROM historicalreviews r WHERE ' .
         "r.time LIKE '$date%' AND r.user IN $in";
  my $ref = $crms->GetDb()->selectall_arrayref($sql);
  my $tot = $ref->[0]->[0];
  my ($iname,$mail,$fname) = split '__', $names{$inst};
  my $msg = "Monthly statistics for $iname CRMS Reviewers\n\n" .
            "Total Reviews: $tot\n" .
            "Validated PD Reviews: $rev\n" .
            "Resulting # of volumes made available as full text in HathiTrust: $det\n\n" .
            'Note: This is an automatically generated message from the Copyright Review Management System.';
  my $sender = new Mail::Sender { smtp => 'mail.umdl.umich.edu',
                                  from => $crms->GetSystemVar('adminEmail', undef, ''),
                                  on_errors => 'undef' }
    or die "Error in mailing : $Mail::Sender::Error\n";
  $sender->OpenMultipart({
    to => $mail,
    cc => (join ',', @mails),
    subject => "CRMS Prod: $iname Statistics for $english",
    ctype => 'text/plain',
    encoding => 'quoted-printable'
    }) or die $Mail::Sender::Error,"\n";
  $sender->Body();
  $sender->SendEnc($msg);
  $sender->Close();
}

print "Warning: $_\n" for @{$crms->GetErrors()};
