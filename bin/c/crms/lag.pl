#!/l/local/bin/perl

my $DLXSROOT;
my $DLPS_DEV;

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

my $usage = <<END;
USAGE: $0 [-hprv]

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
END

my %opts;
my $ok = getopts('hprv', \%opts);
my $help       = $opts{'h'};
my $production = $opts{'p'};
my $report     = $opts{'r'};
my $verbose    = $opts{'v'};
$DLPS_DEV = undef if $production;

if ($help || !$ok)
{
  die $usage;
}

my $crms = CRMS->new(
    logFile      =>   "$DLXSROOT/prep/c/crms/lagcron_hist.txt",
    configFile   =>   "$DLXSROOT/bin/c/crms/crms.cfg",
    verbose      =>   $verbose,
    root         =>   $DLXSROOT,
    dev          =>   $DLPS_DEV,
);


if ($report)
{
  my $start = $crms->SimpleSqlGet('SELECT DATE_SUB(NOW(), INTERVAL 24 HOUR)');
  my $sql = "SELECT time,client,seconds FROM lag WHERE time>='$start'";
  my $ref = $crms->get('dbh')->selectall_arrayref($sql);
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
  my $dbh = $crms->get('dbh');
  my $ref = $dbh->selectall_arrayref($sql);
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
