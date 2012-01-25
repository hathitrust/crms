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
    printf "%s (%d parts)\n", join(',',@parts), $nparts if $verbose;
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
        die "Can't translate $category!" if (uc $category) eq TranslateCategory($category);
        $category = TranslateCategory($category);
        $note =~ s/.*?[:.]\s*(.*)/$1/s;
      }
      elsif ($note)
      {
        $category = $note;
        $note = undef;
        die "Can't translate $category!" if (uc $category) eq TranslateCategory($category);
        $category = TranslateCategory($category);
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
    #YYYY-MM-DD and time -- let's use noon just for kicks.
    $date = ChangeDateFormat( $date ) . ' 12:00:00';
    die "Not a valid date: $date" unless $date =~ m/^\d\d\d\d-\d\d-\d\d\s\d\d:\d\d:\d\d$/;
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
    my $rc = $crms->SubmitHistReview($id, $user, $date, $attr, $reason, $renNum, $renDate, $note, $category, $status, ($alt)? 2:0, 1, 'legacy', undef, $noop);
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

sub ChangeDateFormat
{
  my $date = shift;

  my ($month, $day, $year) = split '/', $date;
  $year  = "20$year" if $year < 100;
  $month = "0$month" if $month < 10;
  $day   = "0$day" if $day < 10;
  $date = join '-', ($year, $month, $day);
  return $date;
}


## ----------------------------------------------------------------------------
##  Function:   submit historical review  (from excel SS)
##  Parameters: Lots of them -- last one does the sanity checks but no db updates
##  Return:     1 || 0
## ----------------------------------------------------------------------------
sub SubmitHistReview
{
  my ($id, $user, $time, $attr, $reason, $renNum, $renDate, $note, $category, $status, $expert, $legacy, $source, $gid, $noop) = @_;

  $id = lc $id;
  $legacy = ($legacy)? 1:0;
  $gid = 'NULL' unless $gid;
  ## change attr and reason back to numbers
  $attr = $crms->GetRightsNum( $attr ) unless $attr =~ m/^\d+$/;
  $reason = $crms->GetReasonNum( $reason ) unless $reason =~ m/^\d+$/;
  # ValidateAttrReasonCombo sets error internally on fail.
  if ( ! $crms->ValidateAttrReasonCombo( $attr, $reason ) ) { return 0; }
  if ($status != 9)
  {
    my $err = ValidateSubmissionHistorical($attr, $reason, $note, $category, $renNum, $renDate);
    if ($err) { $crms->SetError($err); return 0; }
  }
  ## do some sort of check for expert submissions
  if (!$noop)
  {
    my $dbh = $crms->GetDb();
    $note = $dbh->quote($note);
    ## all good, INSERT
    my $sql = 'REPLACE INTO historicalreviews (id, user, time, attr, reason, renNum, renDate, note, legacy, category, status, expert, source, gid) ' .
           "VALUES('$id', '$user', '$time', '$attr', '$reason', '$renNum', '$renDate', $note, $legacy, '$category', $status, $expert, '$source', $gid)";
    $crms->PrepareSubmitSql( $sql );
    #Now load this info into the bibdata and system table.
    $crms->UpdateMetadata($id, 'bibdata', 1 );
    # Update status on status 1 item
    if ($status == 5)
    {
      $sql = "UPDATE historicalreviews SET status=$status WHERE id='$id' AND legacy=1 AND gid IS NULL";
      $crms->PrepareSubmitSql( $sql );
    }
    # Update validation on all items with this id
    $sql = "SELECT user,time,validated FROM historicalreviews WHERE id='$id'";
    my $ref = $dbh->selectall_arrayref($sql);
    foreach my $row (@{$ref})
    {
      $user = $row->[0];
      $time = $row->[1];
      my $val  = $row->[2];
      my $val2 = $crms->IsReviewCorrect($id, $user, $time);
      if ($val != $val2)
      {
        $sql = "UPDATE historicalreviews SET validated=$val2 WHERE id='$id' AND user='$user' AND time='$time'";
        $crms->PrepareSubmitSql( $sql );
      }
    }
  }
  return 1;
}

sub TranslateCategory
{
  my $category = uc shift;

  if    ( $category eq 'COLLECTION' ) { return 'Insert(s)'; }
  elsif ( $category =~ m/LANG.*/ ) { return 'Language'; }
  elsif ( $category =~ m/MISC.*/ ) { return 'Misc'; }
  elsif ( $category eq 'MISSING' ) { return 'Missing'; }
  elsif ( $category eq 'DATE' ) { return 'Date'; }
  elsif ( $category =~ m/REPRINT.*/ ) { return 'Reprint'; }
  elsif ( $category eq 'SERIES' ) { return 'Periodical'; }
  elsif ( $category eq 'TRANS' ) { return 'Translation'; }
  elsif ( $category =~ m/^WRONG.+/ ) { return 'Wrong Record'; }
  elsif ( $category =~ m,FOREIGN PUB.*, ) { return 'Foreign Pub'; }
  elsif ( $category eq 'DISS' ) { return 'Dissertation/Thesis'; }
  elsif ( $category eq 'EDITION' ) { return 'Edition'; }
  elsif ( $category eq 'NOT CLASS A' ) { return 'Not Class A'; }
  elsif ( $category eq 'PERIODICAL' ) { return 'Periodical'; }
  elsif ( $category =~ /INSERT.*/ ) { return 'Insert(s)'; }
  else  { return $category };
}

# Returns an error message, or an empty string if no error.
# Relaxes constraints on ic/ren needing renewal id and date
sub ValidateSubmissionHistorical
{
  my ($attr, $reason, $note, $category, $renNum, $renDate) = @_;
  my $errorMsg = '';

  my $noteError = 0;

  if ( ( ! $attr ) || ( ! $reason ) )
  {
    $errorMsg .= 'rights/reason required.';
  }

  ## und/nfi
  if ( $attr == 5 && $reason == 8 && ( ( ! $note ) || ( ! $category ) )  )
  {
      $errorMsg .= 'und/nfi must include note category and note text.';
      $noteError = 1;
  }

  ## pd/ren should not have a ren number or date
  #if ( $attr == 1 && $reason == 7 &&  ( ( $renNum ) || ( $renDate ) )  )
  #{
  #    $errorMsg .= 'pd/ren should not include renewal info.';
  #}

  ## pd/ncn requires a ren number
  if (  $attr == 1 && $reason == 2 && ( ( $renNum ) || ( $renDate ) ) )
  {
      $errorMsg .= 'pd/ncn should not include renewal info.';
  }

  ## pd/cdpp requires a ren number
  if (  $attr == 1 && $reason == 9 && ( ( $renNum ) || ( $renDate )  ) )
  {
      $errorMsg .= 'pd/cdpp should not include renewal info.';
  }

  #if ( $attr == 1 && $reason == 9 && ( ( ! $note ) || ( ! $category )  )  )
  #{
  #    $errorMsg .= 'pd/cdpp must include note category and note text.';
  #    $noteError = 1;
  #}

  ## ic/cdpp requires a ren number
  if (  $attr == 2 && $reason == 9 && ( ( $renNum ) || ( $renDate ) ) )
  {
      $errorMsg .= 'ic/cdpp should not include renewal info.';
  }

  if ( $attr == 2 && $reason == 9 && ( ( ! $note )  || ( ! $category ) )  )
  {
      $errorMsg .= 'ic/cdpp must include note category and note text.';
      $noteError = 1;
  }

  if ( $noteError == 0 )
  {
    if ( ( $category )  && ( ! $note ) )
    {
      if ($category ne 'Expert Accepted')
      {
        $errorMsg .= 'must include a note if there is a category.';
      }
    }
    elsif ( ( $note ) && ( ! $category ) )
    {
      $errorMsg .= 'must include a category if there is a note.';
    }
  }

  ## pdus/cdpp requires a note and a 'Foreign' or 'Translation' category, and must not have a ren number
  if ($attr == 9 && $reason == 9)
  {
    if (( $renNum ) || ( $renDate ))
    {
      $errorMsg .= 'rights/reason conflicts with renewal info.';
    }
    if (( !$note ) || ( !$category ))
    {
      $errorMsg .= 'note category/note text required.';
    }
    if ($category ne 'Foreign Pub' && $category ne 'Translation')
    {
      $errorMsg .= 'pdus/cdpp requires note category "Foreign Pub" or "Translation".';
    }
  }
  return $errorMsg;
}
