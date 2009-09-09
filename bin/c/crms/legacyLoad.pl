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

my %opts;
getopts('af:hnv', \%opts);

my $help       = $opts{'h'};
my $verbose    = $opts{'v'};
my $file       = $opts{'f'};
my $noop       = $opts{'n'};

#For testing.
#This is what's needed from file1
#$file = qq{/l1/dev/blancoj/bin/c/crms/historical_data2/2007-12report_cleaned_v2.txt};

#These two are what's needed for file2
$file = qq{/l1/dev/blancoj/bin/c/crms/historical_data2/2007-12re-report_cleaned_v3.txt};
$alt = 1;

if ( $help || ! $file ) { die "USAGE: $0 -f csv_file [-h] [-n] [-v]\n\n"; }


my $crms = CRMS->new(
    logFile      =>   "$DLXSROOT/prep/c/crms/log_load_hist.txt",
    configFile   =>   'crms.cfg',
    verbose      =>   $verbose,
    root         =>   $DLXSROOT,
    dev          =>   $DLPS_DEV,
);

open my $fh, $file or die "failed to open $file: $@ \n";


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
my $line = (<$fh>);
my @parts = split("\t", $line);

foreach my $line ( <$fh> )
{
  chomp $line;
  my @parts     = split("\t", $line);
  my $nparts = scalar @parts;
  if ($nparts != 12 && $nparts != 19) die "Line " . $n+1 . "had $nparts fields; should be 12 or 19\n";
  my $alt = ($nparts == 19) if $n == 0;
  
  my ( $id, $title, $year, $cDate, $attr, $reason, $renDate, 
       $renNum, $date, $user, $note, $eNote, $category, $status );
  next if $parts[0] =~ m/^Barcode/i;
  # $alt indicates file 2 
  if ( ! $alt )
  {
    $id        = "mdp." . $parts[0];
    $title     = $parts[2];
    $year      = $parts[3];
    $cDate     = $parts[4];
    $attr      = $parts[5];
    $reason    = $parts[6];
    $renDate   = $parts[7];
    $renNum    = $parts[8];
    $date      = $parts[9];
    $user      = $parts[10];
    $note      = $parts[11];
    $status    = 1;

    #Remove starting and ending quotes
    if ( $note =~ m/^\".*/ ) { $note =~ s/^\"(.*)/$1/; }
    if ( $note =~ m/.*"$/ ) { $note =~ s/(.*)\"$/$1/; }

    if ( $title =~ m/^\".*/ ) { $title =~ s/^\"(.*)/$1/; }
    if ( $title =~ m/.*"$/ ) { $title =~ s/(.*)\"$/$1/; }
    #Parse out the category.
    if ( $note =~ m/.*?\:.*/ )
    {
	    $category = $note;
	    $category =~ s/(.*?)\:.*/$1/s; 
	    $category = $crms->TranslateCategory( $category );
	    $note =~ s/.*?\:(.*)/$1/s; 
      if ( $note =~ m/^ +.*/ ) { $note =~ s/^ +(.*)/$1/; }
    }
    $eNote     = $parts[12];
  }
  else
  {
    $id        = "mdp." . $parts[0];
    $title     = $parts[2];
    $year      = $parts[3];
    $cDate     = $parts[4];
    $attr      = $parts[13];
    $reason    = $parts[14];
    $renDate   = $parts[15];
    $renNum    = $parts[16];
    $date      = $parts[18];
    $user      = $parts[17];
    $note      = undef;
    $eNote     = $parts[12];
    $status    = 5;

    #Remove starting and ending quotes
    if ( $eNote =~ m/^\".*/ ) { $eNote =~ s/^\"(.*)/$1/; }
    if ( $eNote =~ m/.*"$/ ) { $eNote =~ s/(.*)\"$/$1/; }

    if ( $title =~ m/^\".*/ ) { $title =~ s/^\"(.*)/$1/; }
    if ( $title =~ m/.*"$/ ) { $title =~ s/(.*)\"$/$1/; }

  }

  if ( $alt ) { undef $note; }  ## this is the F flag, not used

  ## if ( scalar @parts > 14 ) { die "ERROR:$line \n"; }

  if ( $verbose )
  { 
    print qq{$id, $user, $attr, $reason, $cDate, $renNum, $renDate, $note, $eNote, $category, $status, $title } . "\n"; 
  }

  if ( $id =~ m/\d/ )
  {
	  #date is comming in in this format MM/DD/YYYY, need to change to 
	  #YYYY/MM/DD
	  $date =  $crms->ChangeDateFormat( $date );
	  my $rc = $crms->SubmitHistReview( $id, $user, $date, $attr, $reason, $cDate, $renNum, $renDate, $note, $eNote, $category, $status, $title, $noop );
	  if ( ! $rc ) 
	  {
	    my $errors = $crms->GetErrors();
	    map { print "$_\n"; } ( @{$errors} );
	    die "Failed: $line \n";
	  }
  }
  $n++;
}
close $fh;

printf "Done: processed %d items\n", $n if $verbose;
