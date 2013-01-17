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
USAGE: ./loadSCRD.pl [-hnpt] [-x SYS] FILE [FILE...]

Loads a downloaded copy of the Stanford Cpoyright Renewal Database
into the CRMS database "stanford" table.

-h       Print this help message.
-n       Don't actually do anything, just simulate.
-p       Run in production.
-t       Run in training (overrides -p).
-x SYS   Set SYS as the system to execute.
END

my %opts;
getopts('hnptx', \%opts);
my $help       = $opts{'h'};
my $noop       = $opts{'n'};
my $production = $opts{'p'};
my $training   = $opts{'t'};
my $sys        = $opts{'x'};
$DLPS_DEV = undef if $production;
$DLPS_DEV = 'crmstest' if $training;
die $usage if $help or !scalar @ARGV;

my $crms = CRMS->new(
    logFile => "$DLXSROOT/prep/c/crms/stanford_log.txt",
    sys     => $sys,
    verbose => 0,
    root    => $DLXSROOT,
    dev     => $DLPS_DEV
);

foreach my $filename (@ARGV)
{
  #print "Processing $filename\n";
  ProcessFile($filename);
}

sub ProcessFile
{
  my $file = shift;
  open (my $fh, $file) || die "failed to open $file: $@ \n";
  my ($id,$dreg);
  my $n = 0;
  foreach my $line (<$fh>)
  {
    $n++;
    chomp $line;
    $line =~ s/\r+//gs;
    if ($line =~ m/^---/ && $id && $dreg)
    {
      AddRecord($id, $dreg, $file);
      $id = undef;
      $dreg = undef;
      next;
    }
    my ($tag,$val) = split(/\:/, $line, 2);
    $tag =~ s/\s+//gs;
    $val =~ s/\s+//gs;
    #print "Tag <$tag> value <$val>\n";
    if ($tag eq "ID")
    {
      $id = $val;
      $id =~ s/(RE?\d+).*/$1/;
      if ($id !~ m/^RE?\d+$/)
      {
        printf "Bogus ID format: '$val' -- ignoring. ($file) %s\n", ($dreg)? $dreg:'';
        $id = undef;
      }
    }
    if ($tag eq "DREG")
    {
      $dreg = $val;
      $dreg =~ s/(\d+[A-Za-z][A-Za-z][A-Za-z]\d\d).*/$1/;
      if ($dreg !~ m/^\d+[A-Za-z][A-Za-z][A-Za-z]\d\d$/)
      {
        printf "Bogus DREG format: '$val' -- ignoring. ($file) %s\n";
        $dreg = undef;
      }
    }
  }
  close $fh;
}

sub AddRecord
{
  my $id       = shift;
  my $dreg     = shift;
  my $filename = shift;
  
  my $sql = "REPLACE INTO stanford (ID, DREG) VALUES (?,?)";
  if ($noop)
  {
    #print "$filename: $sql\n";
    return;
  }
  $crms->PrepareSubmitSql($sql, $id, $dreg);
}
