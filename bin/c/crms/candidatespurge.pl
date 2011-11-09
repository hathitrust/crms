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
use Getopt::Long qw(:config no_ignore_case bundling);
use Encode;

my $usage = <<END;
USAGE: $0 [-adhpvu] [-s VOL_ID [-s VOL_ID2...]]
          [start_date [end_date]]

Reports on volumes that are no longer ic/bib in the rights database
and, optionally, delete them from the system.

-a         Report on all volumes, ignoring date range.
-d         Delete qualifying volumes from candidates.
-h         Print this help message.
-p         Run in production.
-s VOL_ID  Report only for HT volume VOL_ID. May be repeated for multiple volumes.
-u         Run against the und table instead of candidates.
-v         Emit debugging information.
END

my $all;
my $delete;
my $help;
my $production;
my @singles;
my $und;
my $verbose;

Getopt::Long::Configure ('bundling');
die 'Terminating' unless GetOptions(
           'a'    => \$all,
           'd'    => \$delete,
           'h|?'  => \$help,
           'p'    => \$production,
           's:s@' => \@singles,
           'u'    => \$und,
           'v+'   => \$verbose);
$DLPS_DEV = undef if $production;
die "$usage\n\n" if $help;

my $configFile = "$DLXSROOT/bin/c/crms/crms.cfg";
my $crms = CRMS->new(
    logFile      =>   "$DLXSROOT/prep/c/crms/inherit_hist.txt",
    configFile   =>   $configFile,
    verbose      =>   $verbose,
    root         =>   $DLXSROOT,
    dev          =>   $DLPS_DEV
);

print "Verbosity $verbose\n" if $verbose;
my $dbh = $crms->GetDb();
my $start = $crms->SimpleSqlGet('SELECT DATE(NOW())');
my $end = $start;
if (scalar @ARGV)
{
  $start = $ARGV[0];
  die "Bad date format ($start); should be in the form e.g. 2010-08-29" unless $start =~ m/^\d\d\d\d-\d\d-\d\d$/;
  if (scalar @ARGV > 1)
  {
    $end = $ARGV[1];
    die "Bad date format ($end); should be in the form e.g. 2010-08-29" unless $end =~ m/^\d\d\d\d-\d\d-\d\d$/;
  }
}

my $table = ($und)? 'und':'candidates';
my $sql = "SELECT id FROM $table";
$sql .= " WHERE (time>'$start 00:00:00' AND time<='$end 23:59:59')" unless $all;
if (@singles && scalar @singles)
{
  $sql = sprintf("SELECT id FROM $table WHERE id in ('%s') ORDER BY id", join "','", @singles);
}
print "$sql\n" if $verbose > 1;
my $ref = $dbh->selectall_arrayref($sql);
my $n = 0;
foreach my $row (@{$ref})
{
  my $id = $row->[0];
  my ($attr,$reason,$src,$usr,$time,$note) = @{$crms->RightsQuery($id,1)->[0]};
  my $rights = "$attr/$reason";
  if ($rights ne 'ic/bib' && $rights ne 'pdus/gfv')
  {
    my @errs = ();
    push @errs, 'in queue' if $crms->SimpleSqlGet("SELECT COUNT(*) FROM queue WHERE id='$id'");
    push @errs, 'in reviews' if $crms->SimpleSqlGet("SELECT COUNT(*) FROM reviews WHERE id='$id'");
    my $info = $crms->SimpleSqlGet(($und)?"SELECT src FROM und WHERE id='$id'":"SELECT time FROM candidates WHERE id='$id'");
    printf "$id ($info): $attr/$reason ($usr) -- %s\n", (scalar @errs)? (join '; ', @errs):'can delete' if $verbose;
    next if scalar @errs;
    if ($delete)
    {
      my $sql = "DELETE FROM $table WHERE id='$id'";
      print "$sql\n" if $verbose > 1;
      $crms->PrepareSubmitSql($sql);
    }
    $n++;
  }
}
printf "%s $n %s\n", ($delete)?'Deleted':'Found', $crms->Pluralize('volume', $n);
print "Warning: $_\n" for @{$crms->GetErrors()};

