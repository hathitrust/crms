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
USAGE: ./loadSCRD.pl [-hnpt] FILE [FILE...]

Loads a downloaded copy of the Stanford Cpoyright Renewal Database
into the CRMS database "stanford" table..

-h       Print this help message.
-n       Don't actually do anything, just simulate.
-p       Run in production.
-t       Run in training (overrides -p).
END


my %opts;
getopts('hnpt', \%opts);
my $help = $opts{'h'};
my $noop = $opts{'n'};
my $production = $opts{'p'};
my $training = $opts{'t'};
my $dev = 'moseshll';
$dev = 0 if $production;
$dev = 'crmstest' if $training;
die $usage if $help;

my $crms = CRMS->new(
    logFile      =>   "$DLXSROOT/prep/c/crms/stanford_log.txt",
    configFile   =>   "$DLXSROOT/bin/c/crms/crms.cfg",
    verbose      =>   0,
    root         =>   $DLXSROOT,
    dev          =>   $dev
);

my $filename;
foreach $filename (@ARGV)
{
  print "Processing $filename\n";
  processFile( $filename );
}

sub processFile
{
  my $file = shift;
  open (my $fh, $file) || die "failed to open $file: $@ \n";
  my ($id,$dreg);
  foreach my $line ( <$fh> )
  {
    chomp $line;
    if ( $line =~ m/^---/ && $id && $dreg)
    {
      addRecord($id, $dreg);
      next;
    }
    my ($tag,$val) = split(/\:/, $line, 2);
    $tag =~ s/\s+//gs;
    $val =~ s/^ //g;
    $val =~ s/"//g;
    $val =~ s/\s+//gs;
    #print "Tag <$tag> value <$val>\n";
    if ($tag eq "ID")
    {
      $id = $val;
      $id =~ s/(RE?\d+).*/$1/;
      if ($id !~ m/^RE?\d+$/)
      {
        print "Bogus ID format: '$val' -- ignoring.\n";
        $id = undef;
      }
    }
    if ($tag eq "DREG")
    {
      $dreg = $val;
      $dreg =~ s/(\d+[A-Za-z][A-Za-z][A-Za-z]\d\d).*/$1/;
      if ($dreg !~ m/^\d+[A-Za-z][A-Za-z][A-Za-z]\d\d$/)
      {
        print "Bogus DREG format: '$val' -- ignoring.\n";
        $dreg = undef;
      }
    }
  }
  close $fh;
}

sub addRecord
{
  my $id = shift;
  my $dreg = shift;
  
  my $sql = "REPLACE INTO stanford (ID, DREG) VALUES ('$id', '$dreg')";
  if ($noop)
  {
    print "$filename $sql\n";
    return;
  }
  $crms->PrepareSubmitSql($sql);
}
