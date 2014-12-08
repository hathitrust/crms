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
use Getopt::Std;

my $usage = <<END;
USAGE: $0 [-hprv] [-x SYS]

Updates the CRMS database 'lag' table with
information about when and on what machine
replication lags occur. With -r flag, instead
reports on these numbers from the last 24 hours.

Currently this is run every 12 minutes via cron on dlps11,
and mails the report (-r flag) once a day.

-h       Print this help message.
-p       Run in production.
-r       Print a report on delays in the last 24 hours.
-v       Be verbose.
-x SYS   Set SYS as the system to execute.
END

my %opts;
my $ok = getopts('hprvx:', \%opts);
my $help       = $opts{'h'};
my $production = $opts{'p'};
my $report     = $opts{'r'};
my $verbose    = $opts{'v'};
my $sys        = $opts{'x'};
$DLPS_DEV = undef if $production;

if ($help || !$ok)
{
  die $usage;
}

my $crms = CRMS->new(
    logFile => "$DLXSROOT/prep/c/crms/lagcron_hist.txt",
    sys     => $sys,
    verbose => $verbose,
    root    => $DLXSROOT,
    dev     => $DLPS_DEV,
);

if ($report)
{
  my $start = $crms->SimpleSqlGet('SELECT DATE_SUB(NOW(), INTERVAL 24 HOUR)');
  my $sql = "SELECT time,client,seconds FROM lag WHERE time>='$start'";
  my $ref = $self->SelectAll($sql);
  if (!scalar @{$ref})
  {
    print "There have been no delays since $start\n";
    exit(0);
  }
  print "Delays since $start\n";
  foreach my $row (@{$ref})
  {
    my ($time,$client,$secs) = @{$row};
    my $status = $secs . ' ' . $crms->Pluralize('second', $secs);
    $status = 'replication disabled' if $secs == 999999;
    printf "$time: $client $status\n", 
  }
}
else
{
  my $sql = "SELECT client,seconds FROM mysqlrep.delay";
  my $ref = $self->SelectAll($sql);
  foreach my $row (@{$ref})
  {
    my $client = $row->[0];
    next if $client =~ /(hefe)|(dlps12)/;
    my $secs = $row->[1];
    print "$client: $secs secs\n" if $verbose;
    if ($secs > 0)
    {
      $sql = "INSERT INTO lag (client,seconds) VALUES ('$client',$secs)";
      print "$sql\n" if $verbose;
      $crms->PrepareSubmitSql($sql);
    }
  }
}

print "Warning: $_\n" for @{$crms->GetErrors()};
