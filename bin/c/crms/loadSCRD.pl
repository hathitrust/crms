#!/usr/bin/perl

my ($root);
BEGIN 
{ 
  $root = $ENV{'SDRROOT'};
  $root = $ENV{'DLXSROOT'} unless $root and -d $root;
  unshift(@INC, $root. '/crms/cgi');
  unshift(@INC, $root. '/cgi/c/crms');
}

use strict;
use CRMS;
use Getopt::Long qw(:config no_ignore_case bundling);


my $usage = <<END;
USAGE: $0 [-hnptv] [-x SYS] FILE [FILE...]

Loads a downloaded copy of the Stanford Cpoyright Renewal Database
into the CRMS database "stanford" table.

-h       Print this help message.
-n       Don't actually do anything, just simulate.
-p       Run in production.
-t       Run in training (overrides -p).
-v       Emit debugging information.
-x SYS   Set SYS as the system to execute.
END

my $instance;
my ($help, $noop, $production, $training, $verbose, $sys);
Getopt::Long::Configure('bundling');
die 'Terminating' unless GetOptions(
           'h|?'  => \$help,
           'n'    => \$noop,
           'p'    => \$production,
           't'    => \$training,
           'v'    => \$verbose,
           'x:s'  => \$sys);

$instance = 'production' if $production;
$instance = 'crms-training' if $training;
die $usage if $help or !scalar @ARGV;

my $crms = CRMS->new(
    sys      => $sys,
    verbose  => 0,
    instance => $instance
);

foreach my $filename (@ARGV)
{
  #print "Processing $filename\n";
  ProcessFile($filename);
}

sub ProcessFile
{
  my $file = shift;
  open my $in, $file or die "failed to open $file: $! \n";
  read $in, my $buff, -s $file; # one of many ways to slurp file.
  close $in;
  $buff =~ s/\s+$//;
  my @chunks = split m/\n\n|----+/, $buff;
  printf "$file: %s chunks\n", scalar @chunks;
  foreach my $chunk (@chunks)
  {
    chomp $chunk;
    my $id = undef;
    my $dreg = undef;
    foreach my $line (split m/[\r\n]+/, $chunk)
    {
      $line =~ s/\r+//gs;
      my ($tag,$val) = split(/\:/, $line, 2);
      $tag =~ s/\s+//gs;
      $val =~ s/\s+//gs;
      print "Tag <$tag> value <$val>\n" if $verbose > 1;
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
      elsif ($tag eq "DREG")
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
    print "ID: $id, DREG: $dreg\n" if $verbose > 1;
    AddRecord($id, $dreg, $file) if defined $id and defined $dreg;
  }
}

sub AddRecord
{
  my $id       = shift;
  my $dreg     = shift;
  my $filename = shift;

  my $sql = "REPLACE INTO stanford (ID, DREG) VALUES (?,?)";
  print "$filename: $sql ($id, $dreg)\n" if $verbose;
  $crms->PrepareSubmitSql($sql, $id, $dreg) unless $noop;
}
