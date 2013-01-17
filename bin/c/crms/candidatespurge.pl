#!/usr/bin/perl

my $DLXSROOT;
my $DLPS_DEV;
BEGIN 
{ 
  $DLXSROOT = $ENV{'DLXSROOT'};
  $DLPS_DEV = $ENV{'DLPS_DEV'};
  unshift (@INC, $DLXSROOT . '/cgi/c/crms/');
}

use strict;
use CRMS;
use Getopt::Long qw(:config no_ignore_case bundling);
use Encode;

my $usage = <<END;
USAGE: $0 [-acdhpvux] [-s VOL_ID [-s VOL_ID2...]]
          [start_date [end_date]]

Reports on volumes that are no longer eligible for candidacy in the rights database
and, optionally, deletes them from the system.

-a         Report on all volumes, ignoring date range.
-c         Run against candidates.
-d         Delete qualifying volumes unless they're in the queue.
-h         Print this help message.
-p         Run in production.
-s VOL_ID  Report only for HT volume VOL_ID. May be repeated for multiple volumes.
-u         Run against the und table.
-v         Emit debugging information.
-x SYS     Set SYS as the system to execute.
END

my $all;
my $candidates;
my $delete;
my $help;
my $production;
my @singles;
my $und;
my $verbose;
my $sys;

Getopt::Long::Configure ('bundling');
die 'Terminating' unless GetOptions(
           'a'    => \$all,
           'c'    => \$candidates,
           'd'    => \$delete,
           'h|?'  => \$help,
           'p'    => \$production,
           's:s@' => \@singles,
           'u'    => \$und,
           'v+'   => \$verbose,
           'x:s'  => \$sys);
$DLPS_DEV = undef if $production;
die "$usage\n\n" if $help;

my $crms = CRMS->new(
    logFile      =>   $DLXSROOT . '/prep/c/crms/candidatespurge_hist.txt',
    sys          =>   $sys,
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

my $module = 'Candidates_' . $crms->get('sys') . '.pm';
require "$module";
my $clause = Candidates::RightsClause();

CheckTable('candidates', $all, $start, $end, \@singles) if $candidates;
CheckTable('und', $all, $start, $end, \@singles) if $und;

sub CheckTable
{
  my $table   = shift;
  my $all     = shift;
  my $start   = shift;
  my $end     = shift;
  my $singles = shift;
  
  my $sql = "SELECT id FROM $table";
  my @restrict = ();
  push @restrict, 'src!="gov"' if $table eq 'und';
  push @restrict, "(time>'$start 00:00:00' AND time<='$end 23:59:59')" unless $all;
  $sql .= ' WHERE ' . join ' AND ', @restrict if scalar @restrict;
  my @singles = @{$singles};
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
    my ($namespace,$n) = split m/\./, $id, 2;
    print "$id\n" if $verbose >= 2;
    my ($attr,$reason,$src,$usr,$time,$note) = @{$crms->RightsQuery($id,1)->[0]};
    my $rights = "$attr/$reason";
    $sql = "SELECT COUNT(*) FROM rights_current WHERE namespace='$namespace' AND id='$n' AND ($clause)";
    if ($crms->SimpleSqlGetSDR($sql) > 0)
    {
      my @errs = ();
      push @errs, 'in queue' if $crms->SimpleSqlGet("SELECT COUNT(*) FROM queue WHERE id='$id'");
      push @errs, 'in reviews' if $crms->SimpleSqlGet("SELECT COUNT(*) FROM reviews WHERE id='$id'");
      $sql = ($table eq 'und')?"SELECT src FROM und WHERE id='$id'":"SELECT time FROM candidates WHERE id='$id'";
      my $info = $crms->SimpleSqlGet($sql);
      if ($delete && 0 == scalar @errs)
      {
        my $sql = "DELETE FROM $table WHERE id='$id'";
        print "$id ($info): $attr/$reason ($usr) -- deleting\n";
        $crms->PrepareSubmitSql($sql);
      }
      else
      {
        printf "$id ($info): $rights ($usr) -- %s\n", (scalar @errs)? (join '; ', @errs):'can delete';
      }
      $n++ unless scalar @errs;
    }
    elsif ($table ne 'und')
    {
      my $cat = $crms->ShouldVolumeGoInUndTable($id);
      if ($cat)
      {
        print "$id: ($cat) -- filtering\n";
        $crms->Filter($id, $cat) if $delete;
      }
    }
  }
  printf "%s delete $n %s of %d from $table\n", ($delete)?'Did':'Can',
                             $crms->Pluralize('volume', $n),
                             scalar @{$ref};
}

print "Warning: $_\n" for @{$crms->GetErrors()};

