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
use Encode qw(from_to);

my $usage = <<END;
USAGE: $0 [-hnpv] tsv_file1 [tsv_file2...]

Imports the reviews in the argument tab-separated UTF-16 file(s)
as legacy historical reviews.

-h       Print this help message.
-n       Do not update the database.
-p       Run in production.
-v       Be verbose.
END

my %opts;
my $ok = getopts('hnpv', \%opts);

my $help       = $opts{'h'};
my $noop       = $opts{'n'};
my $production = $opts{'p'};
my $verbose    = $opts{'v'};

if ($help || scalar @ARGV < 1 || !$ok)
{
  die $usage;
}

my $file = $ARGV[0];

my $crms = CRMS->new(
    logFile      =>   "$DLXSROOT/prep/c/crms/log_load_hist.txt",
    configFile   =>   'crms.cfg',
    verbose      =>   $verbose,
    root         =>   $DLXSROOT,
    dev          =>   !$production,
);


foreach my $f (@ARGV)
{
  ProcessFile($f);
}

sub ProcessFile
{
  my $f = shift;
  open my $in, "<:raw", $f or die "failed to open $f: $! \n";
  read $in, my $buf, -s $f; # one of many ways to slurp file.
  close $in;
  from_to($buf,'UTF-16','UTF-8');
  $buf =~ s/\s+$//s;
  my @lines = split m/\n+/, $buf;

  # NOTE: The file must be exported from Excel as UTF-16 (no BOM is fine).

  ## This is the format for file 1... 12 columns
  ## 0  Barcode
  ## 1  Author
  ## 2  Title
  ## 3  Year
  ## 4  Original Copyright date, if different
  ## 5  Attribute
  ## 6  Reason
  ## 7  Copyright renewal date?
  ## 8  Copyright renewal number?
  ## 9  Date of check
  ## 10 Checker
  ## 11 Notes   - Note that the format for this is CATEGORY: text
  ## 12 akz comments

  ## This is the format for file 2 ( re-reports )... 19 columns
  ## 0   Barcode
  ## 1   Author
  ## 2   Title
  ## 3   Year
  ## 4   Original Copyright date, if different
  ## 13  Attribute
  ## 14  Reason
  ## 15  Copyright renewal date?
  ## 16  Copyright renewal number?
  ## 18  Date of check
  ## 17  Checker
  ##     Notes   - undef for file 2. ( always )
  ## 12  akz comments

  ## F code format
  ## 11 F=US Docs
  ## 12 Use to record questions or problems with und codes

  my $n = 0;
  my $alt = 0;
  foreach my $line (@lines)
  {
    chomp $line;
    $line =~ s/[\n\r]//g;
    $line =~ s/\t+$//;
    # Split into parts with leading and trailing whitespace trimmed
    my @parts = map {s/^\s+|\s+$//g;$_;} split("\t", $line);
    next if $parts[0] =~ m/^Barcode/i;
    my $nparts = scalar @parts;
    printf "%s\n", join(',',@parts) if $verbose;
    #if ($nparts > 19)
    #{
    #  printf("Error: line %d (%s) had $nparts fields; should be 12 or 19\n", $n+1, $parts[0]);
    #  exit(1);
    #}
    if ($n == 0)
    {
      $alt = 1 if $nparts > 12;
      printf("Doing a rereport? %s\n", ($alt)? 'yes':'no') if $verbose;
    }
    my $j = 0;
    my ( $id, $title, $year, $cDate, $attr, $reason, $renDate, 
         $renNum, $date, $user, $note, $category, $status );
    # $alt indicates file 2 
    $id      = "mdp." . $parts[0];
    $title   = $parts[2];
    $year    = $parts[3];
    $cDate   = $parts[4];
    if ( ! $alt )
    {
      $attr      = $parts[5];
      $reason    = $parts[6];
      $renDate   = $parts[7];
      $renNum    = $parts[8];
      $date      = $parts[9];
      $user      = $parts[10];
      $note      = $parts[11];
      $status    = 1;

      #Remove starting and ending quotes
      if ( $note =~ m/^\".*/ ) { $note =~ s/^\"+(.*)/$1/; }
      if ( $note =~ m/.*?"$/ ) { $note =~ s/(.*?)\"+$/$1/; }
      $note =~ s/\"\"/`/g;

      if ( $title =~ m/^\".*/ ) { $title =~ s/^\"+(.*)/$1/g; }
      if ( $title =~ m/.*?"$/ ) { $title =~ s/(.*?)\"+$/$1/; }

      #Parse out the category.
      if ( $note =~ m/.*?[:.].*/ )
      {
        $category = $note;
        $category =~ s/(.*?)[:.].*/$1/s;
        die "Can't translate $category!" if (uc $category) eq $crms->TranslateCategory( $category );
        $category = $crms->TranslateCategory( $category );
        $note =~ s/.*?[:.]\s*(.*)/$1/s;
      }
      elsif ($note)
      {
        $category = $note;
        $note = undef;
        die "Can't translate $category!" if (uc $category) eq $crms->TranslateCategory( $category );
        $category = $crms->TranslateCategory( $category );
      }
    }
    else
    {
      $attr      = $parts[13];
      $reason    = $parts[14];
      $renDate   = $parts[15];
      $renNum    = $parts[16];
      $date      = $parts[18];
      $user      = $parts[17];
      $note      = $parts[12]; # Expert note
      $status    = 5;
      #Remove starting and ending quotes
      if ( $note =~ m/^\".*/ ) { $note =~ s/^\"(.*)/$1/; }
      if ( $note =~ m/.*"$/ ) { $note =~ s/(.*)\"$/$1/; }
      $note =~ s/\"\"/`/g;
      $category = 'Misc';

      if ( $title =~ m/^\".*/ ) { $title =~ s/^\"(.*)/$1/; }
      if ( $title =~ m/.*"$/ ) { $title =~ s/(.*)\"$/$1/; }

    }
    #date is comming in in this format MM/DD/YYYY, need to change to
    #YYYY/MM/DD and time -- let's use noon just for kicks.
    $date = $crms->ChangeDateFormat( $date ) . ' 12:00:00';
    # Rendate is in the yucky format DD-Mon-YY and we need it in the equally yucky format DDMonYY
    $renDate =~ s/-//g;
    die "Not a valid renewal date: $renDate" unless $crms->IsRenDate($renDate);
    if ( $verbose )
    {
      print "ID:    $id\n";
      print "User:  $user\n";
      print "Date:  $date\n";
      print "Attr:  $attr\n";
      print "Rsn:   $reason\n";
      print "Cat:   $category\n";
      print "RDate: $renDate\n";
      print "R#:    $renNum\n";
      print "Note:  $note\n";
      printf("SubmitHistReview(%s)\n", join ', ', ($id, $user, $date, $attr, $reason, $renNum, $renDate, $note, $category, $status));
    }
    my $rc = $crms->SubmitHistReview($id, $user, $date, $attr, $reason, $renNum, $renDate, $note, $category, $status, ($alt)? 2:0, $noop);
    if ( ! $rc ) 
    {
      my $errors = $crms->GetErrors();
      map { print "Error: $_\n"; } ( @{$errors} );
      die "Failed: $line \n";
    }
    $n++;
  }
  printf "Done with $f: processed %d items\n", $n;
}
