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
use Getopt::Std;

my %opts;
getopts('chpv', \%opts);

my $csv        = $opts{'c'};
my $help       = $opts{'h'};
my $production = $opts{'p'};
my $verbose    = $opts{'v'};


if ($help)
{
  die "USAGE: $0 [-c] [-h] [-p] [-v] [start date] [end date]\n\n";
}

my $crms = CRMS->new(
    logFile      =>   "$DLXSROOT/prep/c/crms/gov_hist.txt",
    configFile   =>   "$DLXSROOT/bin/c/crms/crms.cfg",
    verbose      =>   $verbose,
    root         =>   $DLXSROOT,
    dev          =>   !$production
);

my $dbh = $crms->get('dbh');
my $start = $crms->SimpleSqlGet('SELECT DATE(DATE_SUB(NOW(), INTERVAL 2 DAY))');
my $end = $crms->SimpleSqlGet('SELECT DATE(DATE_SUB(NOW(), INTERVAL 1 DAY))');
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
my $startSQL = " AND time>'$start 00:00:00'";
my $endSQL = " AND time<='$end 00:00:00'";
my $sql = "SELECT id,time FROM und WHERE src='gov' $startSQL $endSQL ORDER BY id";
#print "$sql\n";
my $ref = $dbh->selectall_arrayref($sql);
if ($csv)
{
  print "ID\tTime\tAuthor\tTitle\tPub Date\tPub\n";
}
else
{
  print '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">' .
        '<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en"><head>' .
        "<meta http-equiv='Content-Type' content='text/html; charset=utf-8'/>\n" .
        "<title>Suspected gov docs from $start to $end</title>\n" .
        '</head><body>' .
        '<table border="1">' .
        "<tr><th>#</th><th>ID</th><th>Time</th><th>Author</th><th>Title</th><th>Pub&nbsp;Date</th><th>Pub</th></tr>\n";
}
my $n = 1;
foreach my $row ( @{$ref} )
{
  my $id = $row->[0];
  my $time = $row->[1];
  
  my $sysID = $crms->BarcodeToId($id);
  my $catLink = "http://mirlyn.lib.umich.edu/Record/$sysID/Details#tabs";
  my $record = $crms->GetRecordMetadata($id);
  my $author = $crms->GetMarcDatafieldAuthor($id, $record);
  $author =~ s/&/&amp;/g;
  my $title = $crms->GetRecordTitleBc2Meta($id, $record);
  $title =~ s/&/&amp;/g;
  my $pub = $crms->GetPublDate($id, $record);
  my $xpath  = q{//*[local-name()='datafield' and @tag='260']/*[local-name()='subfield' and @code='a']};
  my $field260a = $record->findvalue( $xpath ) or '';
  $xpath  = q{//*[local-name()='datafield' and @tag='260']/*[local-name()='subfield' and @code='b']};
  my $field260b = $record->findvalue( $xpath ) or '';
  $field260a .= ' ' . $field260b;
  if ($csv)
  {
    $field260a =~ s/\t+/ /g;
    print "$id\t$time\t$author\t$title\t$pub\t$field260a\n";
  }
  else
  {
    $time =~ s/\s+/&nbsp;/g;
    $field260a =~ s/&/&amp;/g;
    print "<tr><td>$n</td><td><a href='$catLink' target='_blank'>$id</a></td><td>$time</td>";
    print "<td>$author</td><td>$title</td><td>$pub</td><td>$field260a</td></tr>\n";
  }
  $n++;
}
if (!$csv)
{
  print "</table></body></html>\n\n";
}

my $r = $crms->GetErrors();
foreach my $w (@{$r})
{
  print "Warning: $w\n";
}

