package CRMS;

## ----------------------------------------------------------------------------
## Object of shared code for the CRMS DB CGI and BIN scripts
##
## ----------------------------------------------------------------------------

#BEGIN
#{
#  unshift( @INC, $ENV{'DLXSROOT'} . '/lib' );
#}
#use App::Debug::DUtils;
#BEGIN
#{
#  if ($ENV{'DLPS_DEV'})
#  {
#    App::Debug::DUtils::setup_DebugScreen();
#  }
#}
use strict;
use LWP::UserAgent;
use XML::LibXML;
use Encode;
use Date::Calc qw(:all);
use POSIX qw(strftime);
use DBI qw(:sql_types);
use List::Util;

binmode(STDOUT, ":utf8"); #prints characters in utf8

## ----------------------------------------------------------------------------
##  Function:   new() for object
##  Parameters: %hash with a bunch of args
##  Return:     ref to object
## ----------------------------------------------------------------------------
sub new
{
    my ($class, %args) = @_;
    my $self = bless {}, $class;

    if ( ! $args{'logFile'} )    { return "missing log file"; }
    if ( ! $args{'configFile'} ) { return "missing configFile"; }

    $self->set( 'logFile', $args{'logFile'} );

    my $errors = [];
    $self->set( 'errors', $errors );
    
    require $args{'configFile'};
    
    $self->set( 'bc2metaUrl',  $CRMSGlobals::bc2metaUrl );
    $self->set( 'oaiBaseUrl',  $CRMSGlobals::oaiBaseUrl );
    $self->set( 'verbose',     $args{'verbose'});
    $self->set( 'parser',      XML::LibXML->new() );
    $self->set( 'barcodeID',   {} );
 
    $self->set( 'root',        $args{'root'} );
    $self->set( 'dev',         $args{'dev'} );
    $self->set( 'user',        $args{'user'} );

    $self->set( 'dbh',         $self->ConnectToDb() );
    $self->set( 'dbhP',        $self->ConnectToDbForTesting() );

    $self->set( 'sdr_dbh',     $self->ConnectToSdrDb() );

    $self;
}

sub get
{
    my $self = shift;
    my $key  = shift;
    return $self->{$key};
}

sub set
{
    my $self = shift;
    my $key  = shift;
    my $val  = shift;
    $self->{$key} = $val;
}

## ----------------------------------------------------------------------------
##  Function:   connect to the mysql DB
##  Parameters: nothing
##  Return:     ref to DBI
## ----------------------------------------------------------------------------
sub ConnectToDb
{
    my $self      = shift;
    my $db_user   = $CRMSGlobals::mysqlUser;
    my $db_passwd = $CRMSGlobals::mysqlPasswd;
    my $db_server = $CRMSGlobals::mysqlServerDev;
    
    if ( ! $self->get( 'dev' ) ) { $db_server = $CRMSGlobals::mysqlServer; }

    if ($self->get('verbose')) { $self->Logit( "DBI:mysql:crms:$db_server, $db_user, [passwd]" ); }

    my $dbh = DBI->connect( "DBI:mysql:crms:$db_server", $db_user, $db_passwd,
              { RaiseError => 1, AutoCommit => 1 } ) || die "Cannot connect: $DBI::errstr";
    $dbh->{mysql_enable_utf8} = 1;
    $dbh->{mysql_auto_reconnect} = 1;
    my $sql = qq{SET NAMES 'utf8';};
    $dbh->do($sql);
    
    return $dbh;
}

sub ConnectToDbForTesting
{
    my $self      = shift;
    my $db_user   = $CRMSGlobals::mysqlUser;
    my $db_passwd = $CRMSGlobals::mysqlPasswd;
    my $db_server = $CRMSGlobals::mysqlServerDev;

    $db_server = $CRMSGlobals::mysqlServer;

    my $dbh = DBI->connect( "DBI:mysql:crms:$db_server", $db_user, $db_passwd,
              { RaiseError => 1, AutoCommit => 1 } ) || die "Cannot connect: $DBI::errstr";
    $dbh->{mysql_enable_utf8} = 1;
    $dbh->{mysql_auto_reconnect} = 1;
    my $sql = qq{SET NAMES 'utf8';};
    $dbh->do($sql);
    
    return $dbh;
}

## ----------------------------------------------------------------------------
##  Function:   connect to the development mysql DB
##  Parameters: nothing
##  Return:     ref to DBI
## ----------------------------------------------------------------------------
sub ConnectToSdrDb
{
    my $self      = shift;
    my $db_user   = $CRMSGlobals::mysqlMdpUser;
    my $db_passwd = $CRMSGlobals::mysqlMdpPasswd;
    my $db_server = $CRMSGlobals::mysqlMdpServerDev;

    if ( ! $self->get( 'dev' ) ) { $db_server = $CRMSGlobals::mysqlMdpServer; }

    if ($self->get('verbose')) { $self->Logit( "DBI:mysql:mdp:$db_server, $db_user, [passwd]" ); }

    my $sdr_dbh = DBI->connect( "DBI:mysql:mdp:$db_server", $db_user, $db_passwd,
              { RaiseError => 1, AutoCommit => 1 } );
    if ($sdr_dbh)
    {
      $sdr_dbh->{mysql_auto_reconnect} = 1;
    }
    else
    {
      $self->SetError($DBI::errstr);
    }

    return $sdr_dbh;
}

sub PrepareSubmitSql
{
    my $self = shift;
    my $sql  = shift;

    my $sth = $self->get( 'dbh' )->prepare( $sql );
    eval { $sth->execute(); };
    if ($@) { $self->Logit("sql failed ($sql): " . $sth->errstr); }
    return 1;
}


sub PrepareSubmitSqlForTesting
{
    my $self = shift;
    my $sql  = shift;

    my $sth = $self->get( 'dbhP' )->prepare( $sql );
    eval { $sth->execute(); };
    return 1;
}

sub SimpleSqlGet
{
    my $self = shift;
    my $sql  = shift;

    my $ref = $self->get('dbh')->selectall_arrayref( $sql );
    return $ref->[0]->[0];
}

sub SimpleSqlGetForTesting
{
    my $self = shift;
    my $sql  = shift;

    my $ref = $self->get('dbhP')->selectall_arrayref( $sql );
    return $ref->[0]->[0];
}


sub GetCandidatesTime
{
  my $self = shift;

  my $sql = qq{select max(time) from candidates};
  my $time = $self->SimpleSqlGet( $sql );

  return $time;
  
}


sub GetCandidatesSize
{
  my $self = shift;

  my $sql = qq{select count(*) from candidates};
  my $size = $self->SimpleSqlGet( $sql );

  return $size;
  
}


sub MoveToProdDBCandidates
{
  my $self = shift;

    my $sql = qq{select id, time, pub_date, title, author from candidates};

    my $ref = $self->get('dbh')->selectall_arrayref( $sql );

    ## design note: if these were in the same DB we could just INSERT
    ## into the new table, not SELECT then INSERT
    my $count = 0;
    my $inqueue;
    foreach my $row ( @{$ref} )
    {
      my $id       = $row->[0];
      my $time     = $row->[1];
      my $pub_date = $row->[2];
      my $title    = $row->[3];
      $title =~ s,\',\\',gs;
      my $author   = $row->[4];
      $author =~ s,\',\\',gs;

      my $sql = qq{insert into candidates values ('$id', '$time', '$pub_date', '$title', '$author')};

      $self->PrepareSubmitSqlForTesting( $sql );
    }
}


sub DeDup
{
  my $self = shift;

  my $sql = qq{select distinct id from duplicates};

  my $ref = $self->get('dbh')->selectall_arrayref( $sql );

  ## design note: if these were in the same DB we could just INSERT
  ## into the new table, not SELECT then INSERT
  my $count = 0;
  my $msg;
  foreach my $row ( @{$ref} )
  {
    my $id = $row->[0];

    my $sql = qq{ SELECT count(*) from candidates where id="mdp.$id"};
    my $incan = $self->SimpleSqlGet( $sql );

    if ( $incan == 1 )
    {
      my $sql = qq{ DELETE FROM candidates WHERE id = "mdp.$id" };
      $self->PrepareSubmitSql( $sql );

      $count = $count + 1;
    }
    else
    {
      $msg .= qq{$id\n};
    }
  }
  print $count;
}



sub DeDupProd
{

  my $self = shift;

    my $sql = qq{select distinct id from duplicates};

    my $ref = $self->get('dbhP')->selectall_arrayref( $sql );

    ## design note: if these were in the same DB we could just INSERT
    ## into the new table, not SELECT then INSERT
    my $count = 0;
    my $msg;
    foreach my $row ( @{$ref} )
    {
      my $id = $row->[0];

      my $sql = qq{ SELECT count(*) from candidates where id="mdp.$id"};
      my $incan = $self->SimpleSqlGetForTesting( $sql );
      
      if ( $incan == 1 )
      {
        my $sql = qq{ DELETE FROM candidates WHERE id = "mdp.$id" };
        $self->PrepareSubmitSqlForTesting( $sql );

        $count = $count + 1;
      }
      else
      {
        $msg .= qq{$id\n};
      }
    }

  print $count;
}


sub LoadNewItemsInCandidates
{
    my $self = shift;

    my $start = $self->GetCandidatesTime();
    my $start_size = $self->GetCandidatesSize();

    print "Before load, the max timestamp in the candidates table $start, and the size is $start_size\n";

    my $sql = qq{SELECT CONCAT(namespace, '.', id) AS id, MAX(time) AS time, attr, reason FROM rights WHERE time > '$start' GROUP BY id ORDER BY time ASC};

    my $ref = $self->get('sdr_dbh')->selectall_arrayref( $sql );

    if ($self->get('verbose')) { print "found: " .  scalar( @{$ref} ) . ": $sql\n"; }

    ## design note: if these were in the same DB we could just INSERT
    ## into the new table, not SELECT then INSERT
    my $inqueue;
    foreach my $row ( @{$ref} )
    {
      my $id     = $row->[0];
      my $time   = $row->[1];
      my $attr   = $row->[2];
      my $reason = $row->[3];

      if ( ( $attr == 2 ) && ( $reason == 1 ) )
      {
        my $lang = $self->GetPubLanguage($id);
        if ('eng' ne $lang && '###' ne $lang && 'zxx' ne $lang && 'mul' ne $lang && 'sgn' ne $lang && 'und' ne $lang)
        {
          print "Skipping non-English language $id: $lang\n";
        }
        else
        {
          $self->AddItemToCandidates( $id, $time, 0, 0 );
        }
      }
    }

    my $end_size = $self->GetCandidatesSize();
    my $diff = $end_size - $start_size;
    
    my $r = $self->GetErrors();
    if ( defined $r )
    {
      printf "There were %d errors%s\n", scalar @{$r}, (scalar @{$r})? ':':'.';
      map {print "  $_\n";} @{$r};
    }
    
    print "After load, the cadidate has $end_size rows. Added $diff\n\n";
    
    #Record the update to the queue
    my $sql = qq{INSERT INTO candidatesrecord ( addedamount ) values ( $diff )};
    $self->PrepareSubmitSql( $sql );

    return 1;
}


sub LoadNewItems
{
    my $self = shift;

    my $queuesize = $self->GetQueueSize();
    print "Before load, the queue has $queuesize volumes.\n";
    if ($queuesize < $CRMSGlobals::queueSize)
    {
      my $y = 1923 + int(rand(40));
      my $limitcount = $CRMSGlobals::queueSize - $queuesize;
      return unless $limitcount > 0;
      
      my $count = 0;
      while (1)
      {
        my $sql = 'SELECT id, time, pub_date, title, author FROM candidates WHERE id NOT IN (SELECT DISTINCT id FROM queue) ' .
                  'AND id NOT IN (SELECT DISTINCT id FROM reviews) AND id NOT IN (SELECT DISTINCT id FROM historicalreviews) ' .
                  'AND id NOT IN (SELECT DISTINCT id FROM queue) ORDER BY pub_date ASC, time DESC';
        my $ref = $self->get('dbh')->selectall_arrayref( $sql );
        my $row = $ref->[0];
        foreach my $row (@{$ref})
        {
          my $pub_date = $row->[2];
          next if $pub_date ne "$y-01-01";
          my $id = $row->[0];
          my $time = $row->[1];
          my $title = $row->[3];
          my $author = $row->[4];
          my $lang = $self->GetPubLanguage($id);
          if ('eng' ne $lang && '###' ne $lang && '|||' ne $lang && 'zxx' ne $lang && 'mul' ne $lang && 'sgn' ne $lang && 'und' ne $lang)
          {
            print "Skip non-English $id: '$lang'\n";
            next;
          }
          $self->AddItemToQueue( $id, $pub_date, $title, $author );
          printf "Added to queue: $id published %s\n", substr($pub_date, 0, 4);
          $count++;
          last if $count >= $limitcount;
          $y++;
          $y = 1923 if $y > 1963;
        }
        last if $count >= $limitcount;
      }
      #Record the update to the queue
      my $sql = "INSERT INTO $CRMSGlobals::queuerecordTable (itemcount, source) VALUES ($count, 'RIGHTSDB')";
      $self->PrepareSubmitSql( $sql );
    }
}


## ----------------------------------------------------------------------------
##  Function:   get the latest time from the queue
##  Parameters: NOTHING
##  Return:     date
## ----------------------------------------------------------------------------
sub GetUpdateTime
{
    my $self = shift;
    my $dbh  = $self->get( 'dbh' );

    my $sql = qq{SELECT MAX(time) FROM $CRMSGlobals::queueTable LIMIT 1};
    my @ref = $dbh->selectrow_array( $sql );
    return $ref[0] || '2000-01-01';
}

sub AddItemToCandidates
{
    my $self     = shift;
    my $id       = shift;
    my $time     = shift;

    my $record = $self->GetRecordMetadata($id);

    ## pub date between 1923 and 1963
    my $pub = $self->GetPublDate( $id, $record );
    ## confirm date range and add check

    #Only care about volumes between 1923 and 1963
    if ( ( $pub >= '1923' ) && ( $pub <= '1963' ) )
    {

      ## no gov docs
      if ( $self->IsGovDoc( $id, $record ) ) { $self->Logit( "skip fed doc: $id" ); return 0; }
      
      #check 008 field postion 17 = "u" - this would indicate a us publication.
      if ( ! $self->IsUSPub( $id, $record ) ) { $self->Logit( "skip not us doc: $id" ); return 0; }

      #check FMT.
      if ( ! $self->IsFormatBK( $id, $record ) ) { $self->Logit( "skip not fmt bk: $id" ); return 0; }

      my $au = $self->GetMarcDatafieldAuthor( $id );
      $au = $self->get('dbh')->quote($au);
      $self->SetError("UTF-8 check failed for quoted author: $au") unless utf8::is_utf8($au);
      
      my $title = $self->GetRecordTitleBc2Meta( $id );
      $title = $self->get('dbh')->quote($title);
      $self->SetError("UTF-8 check failed for quoted author: $title") unless utf8::is_utf8($title);
      
      my $sql = "REPLACE INTO candidates (id, time, pub_date, title, author) VALUES ('$id', '$time', '$pub-01-01', $title, $au)";

      $self->PrepareSubmitSql( $sql );
      
      return 1;
    }
    return 0;
}

# Plain vanilla code for adding an item with status 0, priority 0
# Expects the pub_date to be already in 19XX-01-01 format.
# Returns 1 if item was added, 0 if not added because it was already in the queue.
sub AddItemToQueue
{
    my $self     = shift;
    my $id       = shift;
    my $pub_date = shift;
    my $title    = shift;
    my $author   = shift;
    
    if ( ! $self->IsItemInQueue( $id ) )
    {
      # queue table has priority and status default to 0, time to current timestamp.
      my $sql = "INSERT INTO $CRMSGlobals::queueTable (id) VALUES ('$id')";
      $self->PrepareSubmitSql( $sql );

      $self->UpdateTitle( $id, $title );
      $self->UpdatePubDate( $id, $pub_date );
      $self->UpdateAuthor( $id, $author );
    }
    return 1;
}

# Returns a status code (0=Add, 1=Error, 2=Skip, 3=Modify) followed by optional text.
sub AddItemToQueueOrSetItemActive
{
  my $self     = shift;
  my $id       = shift;
  my $priority = shift;
  my $override = shift;
  my $stat = 0;
  my @msgs = ();
  
  $priority = 4 if $override;
  ## give the existing item higher or lower priority
  if ( $self->IsItemInQueue( $id ) )
  {
    my $oldpri = $self->GetItemPriority($id);
    my $sql = "SELECT COUNT(*) FROM $CRMSGlobals::reviewsTable WHERE id='$id'";
    my $count = $self->SimpleSqlGet($sql);
    if ($oldpri == $priority)
    {
      push @msgs, 'already in queue with the same priority';
      $stat = 2;
    }
    else
    {
      $sql = "UPDATE $CRMSGlobals::queueTable SET priority=$priority,time=NOW() WHERE id='$id'";
      $self->PrepareSubmitSql( $sql );
      push @msgs, "changed priority from $oldpri to $priority";
      if ($count)
      {
        $sql = "UPDATE $CRMSGlobals::reviewsTable SET priority=$priority,time=NOW() WHERE id='$id'";
        $self->PrepareSubmitSql( $sql );
      }
      $stat = 3;
    }
    push @msgs, "already has a <a href='?p=adminReviews&amp;search1=Identifier&amp;search1value=$id' target='_blank'>review</a>" if $count;
  }
  else
  {
    my $record =  $self->GetRecordMetadata($id);
    if ($record eq '')
    {
      push @msgs, 'item was not found in Mirlyn';
      $stat = 1;
    }
    else
    {
      my $pub = $self->GetPublDate( $id, $record );
      my $v = $self->GetViolations($id, $pub);
      push @msgs, $v if $v;
      if ($v && !$override)
      {
        $stat = 1;
      }
      else
      {
        my $sql = "INSERT INTO $CRMSGlobals::queueTable (id, pub_date, priority) VALUES ('$id', '$pub-01-01', $priority)";
        $self->PrepareSubmitSql( $sql );
        
        $self->UpdateTitle( $id );
        $self->UpdatePubDate( $id, $pub );
        $self->UpdateAuthor ( $id );
        
        my $sql = "INSERT INTO $CRMSGlobals::queuerecordTable (itemcount, source) VALUES (1, 'ADMINUI')";
        $self->PrepareSubmitSql( $sql );
      }
    }
  }
  return $stat . join '; ', @msgs;
}

# Returns a 4-char string in the format 'dgub' (hey, it's Tibetan!) where the fields stand for
# date, govt, us, book. For each constraint, it is capitalized if the constraint is violated.
# Returns 0 if record can't be found.
sub GetViolations
{
  my $self     = shift;
  my $id       = shift;
  my $pub      = shift;
  
  my $record =  $self->GetRecordMetadata($id);
  return 'not found in Mirlyn' if $record eq '';
  $pub = $self->GetPublDate( $id, $record ) unless $pub;
  my @errs = ();
  push @errs, 'not in range 1923-1963' if ($pub < '1923' || $pub > '1963');
  push @errs, 'gov doc' if $self->IsGovDoc( $id, $record );
  push @errs, 'foreign pub' unless $self->IsUSPub( $id, $record );
  push @errs, 'non-BK format' unless $self->IsFormatBK( $id, $record );
  return join('; ', @errs);
}

# Used by the script loadIDs.pl to add and/or bump priority on a volume
sub GiveItemsInQueuePriority
{
  my $self     = shift;
  my $id       = shift;
  my $time     = shift;
  my $status   = shift;
  my $priority = shift;

  ## skip if $id has been reviewed
  #if ( $self->IsItemInReviews( $id ) ) { return; }

  my $record =  $self->GetRecordMetadata($id);

  ## pub date between 1923 and 1963
  my $pub = $self->GetPublDate( $id, $record );
  ## confirm date range and add check

  #Only care about volumes between 1923 and 1963
  if ( ( $pub >= '1923' ) && ( $pub <= '1963' ) )
  {
    ## no gov docs
    if ( $self->IsGovDoc( $id, $record ) ) { $self->Logit( "skip fed doc: $id" ); return 0; }

    #check 008 field postion 17 = "u" - this would indicate a us publication.
    if ( ! $self->IsUSPub( $id, $record ) ) { $self->Logit( "skip not us doc: $id" ); return 0; }

    #check FMT.
    if ( ! $self->IsFormatBK( $id, $record ) ) { $self->Logit( "skip not fmt bk: $id" ); return 0; }

    my $sql = qq{ SELECT count(*) from $CRMSGlobals::queueTable where id="$id"};
    my $count = $self->SimpleSqlGet( $sql );
    if ( $count == 1 )
    {
        $sql = qq{ UPDATE $CRMSGlobals::queueTable SET priority = 1 WHERE id = "$id" };
        $self->PrepareSubmitSql( $sql );
    }
    else
    {
      $sql = "INSERT INTO $CRMSGlobals::queueTable (id, time, status, pub_date, priority) VALUES ('$id', '$time', $status, '$pub-01-01', $priority)";

      $self->PrepareSubmitSql( $sql );

      $self->UpdateTitle( $id );
      $self->UpdatePubDate( $id, $pub );
      $self->UpdateAuthor( $id );

      # Accumulate counts for items added at the 'same time'.
      # Otherwise queuerecord will have a zillion kabillion single-item entries when importing
      # e.g. 2007 reviews for reprocessing.
      # We see if there is another ADMINSCRIPT entry for the current time; if so increment.
      # If not, add a new one.
      $sql = qq{SELECT itemcount FROM $CRMSGlobals::queuerecordTable WHERE time='$time' AND source='ADMINSCRIPT' LIMIT 1};
      
      my $itemcount = $self->SimpleSqlGet($sql);
      if ($itemcount)
      {
        $itemcount++;
        $sql = qq{UPDATE $CRMSGlobals::queuerecordTable SET itemcount=$itemcount WHERE time='$time' AND source='ADMINSCRIPT' LIMIT 1};
      }
      else
      {
        $sql = qq{INSERT INTO $CRMSGlobals::queuerecordTable (time, itemcount, source) values ('$time', 1, 'ADMINSCRIPT')};
      }
      
      $self->PrepareSubmitSql( $sql );
    }
  }
  return 1;
}

sub IsItemInQueue
{
    my $self = shift;
    my $bar  = shift;

    my $sql = qq{SELECT id FROM $CRMSGlobals::queueTable WHERE id = '$bar'};
    my $id = $self->SimpleSqlGet( $sql );

    if ($id) { return 1; }
    return 0;
}

sub TranslateCategory
{
    my $self     = shift;
    my $category = shift;

    if    ( $category eq 'COLLECTION' ) { return 'Collection'; }
    elsif ( $category eq 'LANG' ) { return 'Language'; }
    elsif ( $category eq 'MISC' ) { return 'Misc'; }
    elsif ( $category eq 'MISSING' ) { return 'Missing'; }
    elsif ( $category eq 'DATE' ) { return 'Date'; }
    elsif ( $category eq 'REPRINT FROM' ) { return 'Reprint'; }
    elsif ( $category eq 'SERIES' ) { return 'Series/Serial'; }
    elsif ( $category eq 'TRANS' ) { return 'Translation'; }
    elsif ( $category eq 'WRONGREC' ) { return 'Wrong Record'; }
    elsif ( $category =~ m,FOREIGN PUB.*, ) { return 'Foreign Pub'; }
    elsif ( $category eq 'DISS' ) { return 'Dissertation/Thesis'; }
    else  { return $category };
}

# Valid for DB reviews/historicalreviews
sub IsValidCategory
{
  my $self = shift;
  my $cat = shift;
  
  my %cats = ('Collection' => 1, 'Language' => 1, 'Misc' => 1, 'Missing' => 1, 'Date' => 1, 'Reprint' => 1,
              'Series/Serial' => 1, 'Translation' => 1, 'Wrong Record' => 1, 'Foreign Pub' => 1, 'Dissertation/Thesis' => 1);
  return exists $cats{$cat};
}

sub IsItemInReviews
{
    my $self = shift;
    my $bar  = shift;

    my $sql = qq{SELECT id FROM $CRMSGlobals::reviewsTable WHERE id = '$bar'};
    my $id = $self->SimpleSqlGet( $sql );

    if ($id) { return 1; }
    return 0;
}


## ----------------------------------------------------------------------------
##  Function:   submit review
##  Parameters: id, user, attr, reason, note, stanford ren. number
##  Return:     1 || 0
## ----------------------------------------------------------------------------
sub SubmitReview
{
    my $self = shift;
    my ($id, $user, $attr, $reason, $copyDate, $note, $renNum, $exp, $renDate, $category) = @_;

    if ( ! $self->CheckForId( $id ) )                         { $self->Logit("id check failed");          return 0; }
    if ( ! $self->CheckReviewer( $user, $exp ) )              { $self->Logit("reviewer check failed");    return 0; }
    if ( ! $self->ValidateAttr( $attr ) )                     { $self->Logit("attr check failed");        return 0; }
    if ( ! $self->ValidateReason( $reason ) )                 { $self->Logit("reason check failed");      return 0; }
    if ( ! $self->ValidateAttrReasonCombo( $attr, $reason ) ) { $self->Logit("attr/reason check failed"); return 0; }

    #remove any blanks from renNum
    $renNum =~ s/\s+//gs;
    
    # Javascript code inserts the string 'searching...' into the review text box.
    # This in once case got submitted as the renDate in production
    $renDate = '' if $renDate eq 'searching...';

    ## do some sort of check for expert submissions

    $note = $self->get('dbh')->quote($note);
    
    my $priority = $self->GetItemPriority( $id );
    
    my @fieldList = ('id', 'user', 'attr', 'reason', 'renNum', 'renDate', 'category', 'priority');
    my @valueList = ($id,  $user,  $attr,  $reason,  $renNum,  $renDate, $category, $priority);

    if ($exp)      { push(@fieldList, 'expert');   push(@valueList, $exp); }
    if ($copyDate) { push(@fieldList, 'copyDate'); push(@valueList, $copyDate); }
    if ($note)     { push(@fieldList, 'note'); }
    
    my $sql = "REPLACE INTO $CRMSGlobals::reviewsTable (" . join(', ', @fieldList) .
              ") VALUES('" . join("', '", @valueList) . sprintf("'%s)", ($note)? ", $note":'');

    if ( $self->get('verbose') ) { $self->Logit( $sql ); }

    $self->PrepareSubmitSql( $sql );

    if ( $exp )
    {
      my $sql = qq{ UPDATE $CRMSGlobals::queueTable SET expcnt=1 WHERE id="$id" };
      $self->PrepareSubmitSql( $sql );
      my $qstatus = $self->SimpleSqlGet("SELECT status FROM queue WHERE id='$id'");
      # FIXME: need to check all other review of this group and see if all are und/nfi
      my $status = ($attr == 5 && $reason == 8 && $qstatus == 3)? 6:5;
      #We have decided to register the expert decision right away.
      $self->RegisterStatus($id, $status);
    }

    $self->EndTimer( $id, $user );
    $self->UnlockItem( $id, $user );

    return 1;
}

sub GetItemPriority
{
  my $self = shift;
  my $id = shift;
  
  my $sql = qq{ SELECT priority FROM $CRMSGlobals::queueTable WHERE id='$id' LIMIT 1 };
  return $self->SimpleSqlGet( $sql );
}


sub GetOtherReview
{
    my $self = shift;
    my $id   = shift;
    my $user = shift;


    my $sql = qq{SELECT id, user, attr, reason, renNum, renDate FROM $CRMSGlobals::reviewsTable WHERE id="$id" and user != "$user"};

    my $ref = $self->get( 'dbh' )->selectall_arrayref( $sql );


    foreach my $row ( @{$ref} )
    {
        my $id      = $row->[0];
        my $user    = $row->[1];
        my $attr    = $row->[2];
        my $reason  = $row->[3];
        my $renNum  = $row->[4];
        my $renDate = $row->[5];

        return ( $user, $attr, $reason, $renNum, $renDate );
   }

}

sub ProcessReviews
{
  my $self = shift;

  my $sql = "SELECT id, user, attr, reason, renNum, renDate FROM $CRMSGlobals::reviewsTable " .
            "WHERE id IN ( SELECT id FROM $CRMSGlobals::queueTable WHERE status=0) GROUP BY id HAVING count(*) >= 2";

  my $ref = $self->get( 'dbh' )->selectall_arrayref( $sql );

  foreach my $row ( @{$ref} )
  {
    my $id      = $row->[0];
    my $user    = $row->[1];
    my $attr    = $row->[2];
    my $reason  = $row->[3];
    my $renNum  = $row->[4];
    my $renDate = $row->[5];
    
    my ( $other_user, $other_attr, $other_reason, $other_renNum, $other_renDate ) = $self->GetOtherReview( $id, $user );

    if ( ( $attr == $other_attr ) && ( $reason == $other_reason ) )
    {
      #If both und/nfi them status is 3
      if ( ( $attr == 5 ) && ( $reason == 8 ) )
      {
         $self->RegisterStatus( $id, 3 );
      }
      else #Mark as 4 - two that agree
      {
        #If they are ic/ren then the renewal date and id must match
        if ( ( $attr == 2 ) && ( $reason == 7 ) )
        {
          $renNum =~ s/\s+//gs;
          $other_renNum =~ s/\s+//gs;
          if ( ( $renNum eq $other_renNum ) && ( $renDate eq $other_renDate ) )
          {
            #Mark as 4
            $self->RegisterStatus( $id, 4 );
          }
          else
          {
            #Mark as 2
            $self->RegisterStatus( $id, 2 );
          }
        }
        else #all other cases mark as 4
        {
          $self->RegisterStatus( $id, 4 );
        }
      }
    }
    else #Mark as 2 - two that disagree
    {
      $self->RegisterStatus( $id, 2 );
    }
  }
  my $sql = qq{ INSERT INTO processstatus VALUES ( )};
  $self->PrepareSubmitSql( $sql );
}


## ----------------------------------------------------------------------------
##  Function:   submit historical review  (from excel SS)
##  Parameters: Lots of them -- last one does the sanity checks but no db updates
##  Return:     1 || 0
## ----------------------------------------------------------------------------
sub SubmitHistReview
{
    my $self = shift;
    my ($id, $user, $date, $attr, $reason, $cDate, $renNum, $renDate, $note, $category, $status, $expert, $noop) = @_;

    ## change attr and reason back to numbers
    $attr = $self->GetRightsNum( $attr );
    $reason = $self->GetReasonNum( $reason );

    #if ( ! $self->ValidateAttr( $attr ) )                     { $self->Logit("attr check failed");        return 0; }
    #if ( ! $self->ValidateReason( $reason ) )                 { $self->Logit("reason check failed");      return 0; }
    if ( ! $self->ValidateAttrReasonCombo( $attr, $reason ) ) { $self->setError("attr/reason check failed"); return 0; }
    
    ## do some sort of check for expert submissions

    if (!$noop)
    {
      $note = $self->get('dbh')->quote($note);
      
      ## all good, INSERT
      my $sql = qq{REPLACE INTO $CRMSGlobals::historicalreviewsTable (id, user, time, attr, reason, copyDate, renNum, renDate, note, legacy, category, status, expert) } .
                qq{VALUES('$id', '$user', '$date', '$attr', '$reason', '$cDate', '$renNum', '$renDate', $note, 1, '$category', $status, $expert) };

      $self->PrepareSubmitSql( $sql );

      #Now load this info into the bibdata table.
      $self->UpdateTitle( $id );
      $self->UpdatePubDate( $id );
      $self->UpdateAuthor( $id );
      
      # Update status on status 1 item
      if ($status == 5)
      {
        $sql = qq{UPDATE $CRMSGlobals::historicalreviewsTable SET status=$status WHERE id='$id'};
        $self->PrepareSubmitSql( $sql );
      }
    }
    return 1;
}

## ----------------------------------------------------------------------------
##  Function:   submit a new active review  (single pd review from rights DB)
##  Parameters: Lots of them -- last one does the sanity checks but no db updates
##  Return:     1 || 0
## ----------------------------------------------------------------------------
sub SubmitActiveReview
{
    my $self = shift;
    my ($id, $user, $date, $attr, $reason, $noop) = @_;

    ## change attr and reason back to numbers
    $attr = $self->GetRightsNum( $attr );
    
    if (!$attr) { $self->SetError( "bad attr: $attr" ); return 0; }
    $reason = $self->GetReasonNum( $reason );
    if (!$reason) { $self->SetError( "bad reason: $reason" ); return 0; }
    if ( ! $self->ValidateAttrReasonCombo( $attr, $reason ) ) { $self->Logit("bad attr/reason $attr/$reason"); return 0; }
    if ( ! $self->ValidateUser( $user ) )                     { $self->Logit("user $user does not exist");     return 0; }
    ## do some sort of check for expert submissions

    if (!$noop)
    {
      ## all good, INSERT
      my $sql = qq{REPLACE INTO $CRMSGlobals::reviewsTable (id, user, time, attr, reason, legacy, priority) } .
                qq{VALUES('$id', '$user', '$date', '$attr', '$reason', 1, 1) };

      $self->PrepareSubmitSql( $sql );

      #Now load this info into the bibdata table.
      $self->UpdateTitle( $id );
      $self->UpdatePubDate( $id );
      $self->UpdateAuthor( $id );
    }
    return 1;
}

sub ValidateUser
{
  my $self = shift;
  my $user = shift;
  my $sql = "SELECT count(*) FROM users WHERE id='$user'";
  return 1 if $self->SimpleSqlGet($sql) > 0;
  $self->SetError( "user does not exist: $user" );
  return 0;
}

sub ClearQueueAndExport
{
    my $self = shift;

    my $eCount = 0;
    my $dCount = 0;
    my $export = [];

    ## get items > 2, clear these
    my $expert = $self->GetExpertRevItems();
    foreach my $row ( @{$expert} )
    {
        my $id = $row->[0];
        push( @{$export}, $id );
        $eCount++;
    }

    ## get items = 2 and see if they agree
    my $double = $self->GetDoubleRevItemsInAgreement();
    foreach my $row ( @{$double} )
    {
        my $id = $row->[0];
        push( @{$export}, $id );
        $dCount++;
    }

    $self->ExportReviews( $export );
    
    ## report back
    $self->Logit( "expert reviewed items removed from queue ($eCount)" );
    $self->Logit( "double reviewed items removed from queue ($dCount)" );

    return ("twice reviewed removed: $dCount, expert reviewed reemoved: $eCount");
}

## ----------------------------------------------------------------------------
##  Function:   create a tab file of reviews to be loaded into the rights table
##              barcode | attr | reason | user | null
##              mdp.123 | ic   | ren    | crms | null
##  Parameters: A reference to a list of barcodes
##  Return:     1 || 0
## ----------------------------------------------------------------------------
sub ExportReviews
{
    my $self = shift;
    my $list = shift;

    my $user = "crms";
    my $time = $self->GetTodaysDate();
    my ( $fh, $file ) = $self->GetExportFh();
    my $user = "crms";
    my $src = "null";
    my $count = 0;

    foreach my $barcode ( @{$list} )
    {
      #The routine GetFinalAttrReason may need to change - jose
      my ($attr,$reason) = $self->GetFinalAttrReason($barcode);

      print $fh "$barcode\t$attr\t$reason\t$user\t$src\n";

      my $sql = qq{ INSERT INTO  exportdata (time, id, attr, reason, user ) VALUES ('$time', '$barcode', '$attr', '$reason', '$user' )};
      $self->PrepareSubmitSql( $sql );

      my $sql = qq{ INSERT INTO  exportdataBckup (time, id, attr, reason, user ) VALUES ('$time', '$barcode', '$attr', '$reason', '$user' )};
      $self->PrepareSubmitSql( $sql );

      $self->MoveFromReviewsToHistoricalReviews($barcode); ## DEBUG
      $self->RemoveFromQueue($barcode); ## DEBUG

      $count++;
    }
    close $fh;

    my $sql = qq{ INSERT INTO  $CRMSGlobals::exportrecordTable (itemcount) VALUES ( $count )};
    $self->PrepareSubmitSql( $sql );

    eval { $self->EmailReport ( $count, $file ); };
    $self->SetError("EmailReport() failed: $@") if $@;
}

sub EmailReport
{
  my $self    = shift;
  my $count   = shift;
  my $file    = shift;

  my $subject = sprintf('%s%d volumes exported to rights db', ($self->get('dev'))? 'CRMS Dev: ':'', $count);

  use Mail::Sender;
  my $sender = new Mail::Sender
    {smtp => 'mail.umdl.umich.edu',
     from => $CRMSGlobals::exportEmailFrom};
  $sender->MailFile({to => $CRMSGlobals::exportEmailTo,
           subject => $subject,
           msg => "See attachment.",
           file => $file});
  $sender->Close;
}

sub GetNumberExportedFromCandidates
{
  my $self = shift;

  my $sql = qq{ SELECT count(DISTINCT id) FROM historicalreviews WHERE legacy=0 AND id IN (SELECT id FROM candidates)};
  my $count = $self->SimpleSqlGet( $sql );

  if ($count) { return $count; }
  return 0;
}

sub GetNumberExportedNotFromCandidates
{
  my $self = shift;

  my $sql = qq{ SELECT count(DISTINCT id) FROM historicalreviews WHERE legacy=0 AND id NOT IN (SELECT id FROM candidates)};
  my $count = $self->SimpleSqlGet( $sql );

  if ($count) { return $count; }
  return 0;
}

sub GetExportFh
{
    my $self = shift;
    my $date = $self->GetTodaysDate();
    $date    =~ s/:/_/g;
    $date    =~ s/ /_/g;
 
    my $out = $self->get('root') . "/prep/c/crms/crms_" . $date . ".rights";

    if ( -f $out ) { die "file already exists: $out \n"; }

    open ( my $fh, ">", $out ) || die "failed to open exported file ($out): $! \n";

    return ( $fh, $out );
}

sub RemoveFromQueue
{
    my $self = shift;
    my $id   = shift;

    $self->Logit( "remove $id from queue" );

    my $sql = qq{ DELETE FROM $CRMSGlobals::queueTable WHERE id = "$id" };
    $self->PrepareSubmitSql( $sql );

    return 1;
}


sub PrepareForTesting
{
    my $self = shift;

    my $sql = qq{ DELETE FROM $CRMSGlobals::queueTable};
    $self->PrepareSubmitSql( $sql );

    my $sql = qq{ DELETE FROM bibdata where id not in ( select id from historicalreviews where legacy = 1)};
    $self->PrepareSubmitSql( $sql );

    my $sql = qq{ DELETE FROM candidatesrecord};
    $self->PrepareSubmitSql( $sql );

    my $sql = qq{ DELETE FROM exportrecord};
    $self->PrepareSubmitSql( $sql );

    my $sql = qq{ DELETE FROM reviews};
    $self->PrepareSubmitSql( $sql );

    my $sql = qq{ DELETE FROM processstatus};
    $self->PrepareSubmitSql( $sql );

    my $sql = qq{ DELETE FROM userstats};
    $self->PrepareSubmitSql( $sql );

    my $sql = qq{ DELETE FROM queuerecord};
    $self->PrepareSubmitSql( $sql );

    my $sql = qq{ DELETE FROM timer};
    $self->PrepareSubmitSql( $sql );

    my $sql = qq{ DELETE FROM historicalreviews where legacy=0};
    $self->PrepareSubmitSql( $sql );

    return 1;
}


sub MoveFromReviewsToHistoricalReviews
{
    my $self = shift;
    my $id   = shift;

    my $status = $self->GetStatus ( $id );

    $self->Logit( "store $id in historicalreviews" );

    my $sql = qq{INSERT into $CRMSGlobals::historicalreviewsTable (id, time, user, attr, reason, note, renNum, expert, duration, legacy, expertNote, renDate, copyDate, category, priority) select id, time, user, attr, reason, note, renNum, expert, duration, legacy, expertNote, renDate, copyDate, category, priority from reviews where id='$id'};
    $self->PrepareSubmitSql( $sql );

    $sql = qq{ UPDATE $CRMSGlobals::historicalreviewsTable set status=$status WHERE id = "$id" };
    $self->PrepareSubmitSql( $sql );


    $self->Logit( "remove $id from reviews" );

    $sql = qq{ DELETE FROM $CRMSGlobals::reviewsTable WHERE id = "$id" };
    $self->PrepareSubmitSql( $sql );
    
    # Update correctness/validation
    $sql = "SELECT user,time FROM historicalreviews WHERE id='$id'";
    my $ref = $self->get( 'dbh' )->selectall_arrayref( $sql );
    foreach my $row ( @{$ref} )
    {
      my $user = $row->[0];
      my $time = $row->[1];
      if (!$self->IsReviewCorrect($id, $user, $time))
      {
        $sql = "UPDATE historicalreviews SET validated=0 WHERE id='$id' AND user='$user' AND time='$time'";
        $self->PrepareSubmitSql( $sql );
      }
    }
    return 1;
}


sub GetFinalAttrReason
{
    my $self = shift;
    my $id   = shift;

    ## order by expert so that if there is an expert review, return that one
    my $sql = qq{SELECT attr, reason FROM $CRMSGlobals::reviewsTable WHERE id = "$id" } .
              qq{ORDER BY expert DESC, time DESC LIMIT 1};
    my $ref = $self->get( 'dbh' )->selectall_arrayref( $sql );

    if ( ! $ref->[0]->[0] )
    {
        $self->Logit( "$id not found in review table" );
    }

    my $attr   = $self->GetRightsName( $ref->[0]->[0] );
    my $reason = $self->GetReasonName( $ref->[0]->[1] );
    return ($attr, $reason);
}

sub GetExpertRevItems
{
    my $self = shift;
    my $sql  = qq{SELECT id FROM $CRMSGlobals::queueTable WHERE status=5 OR status=6};
    my $ref  = $self->get( 'dbh' )->selectall_arrayref( $sql );

    return $ref;
}

sub GetDoubleRevItemsInAgreement
{
    my $self = shift;
    my $sql  = qq{SELECT id FROM $CRMSGlobals::queueTable WHERE status=4 };
    my $ref  = $self->get( 'dbh' )->selectall_arrayref( $sql );

    return $ref;
}


sub RegisterStatus
{
    my $self   = shift;
    my $id     = shift;
    my $status = shift;

    my $sql = qq{UPDATE $CRMSGlobals::queueTable SET status = $status WHERE id = "$id"};

    $self->PrepareSubmitSql( $sql );
}

sub GetYesterday
{
  my $self = shift;
  
  my $yd = $self->SimpleSqlGet('SELECT DATE_SUB(NOW(), INTERVAL 1 DAY)');
  return substr($yd, 0, 10);
}


sub ConvertToSearchTerm
{
    my $self           = shift;
    my $search         = shift;
    my $page           = shift;

    my $new_search = $search;
    if    ( $search eq 'Identifier' )
    {
      $new_search = ($page eq 'queue')? 'q.id':'r.id';
    }
    elsif ( $search eq 'UserId' ) { $new_search = 'r.user'; }
    elsif ( $search eq 'Status' )
    {
      if ( $page eq 'adminHistoricalReviews' ) { $new_search = 'r.status'; }
      else { $new_search = 'q.status'; }
    }
    elsif ( $search eq 'Attribute' ) { $new_search = 'r.attr'; }
    elsif ( $search eq 'Reason' ) { $new_search = 'r.reason'; }
    elsif ( $search eq 'NoteCategory' ) { $new_search = 'r.category'; }
    elsif ( $search eq 'Legacy' ) { $new_search = 'r.legacy'; }
    elsif ( $search eq 'Title' ) { $new_search = 'b.title'; }
    elsif ( $search eq 'Author' ) { $new_search = 'b.author'; }
    elsif ( $search eq 'Priority' )
    {
      if ( $page eq 'queue' ) { $new_search = 'q.priority'; }
      else { $new_search = 'r.priority'; }
    }
    elsif ( $search eq 'Validated' ) { $new_search = 'r.validated'; }
    elsif ( $search eq 'PubDate' ) { $new_search = 'YEAR(b.pub_date)'; }
    elsif ( $search eq 'Locked' ) { $new_search = 'q.locked'; }
    elsif ( $search eq 'ExpertCount' ) { $new_search = 'q.expcnt'; }
    elsif ( $search eq 'Reviews' )
    {
      $new_search = '(SELECT COUNT(*) FROM reviews r WHERE r.id=q.id)';
    }
    return $new_search;
}

sub CreateSQL
{
    my $self               = shift;
    my $order              = shift;
    my $direction          = shift;

    my $search1            = shift;
    my $search1value       = shift;
    my $op1                = shift;

    my $search2            = shift;
    my $search2value       = shift;

    my $startDate          = shift;
    my $endDate            = shift;
    my $offset             = shift;
    my $pagesize           = shift;
    my $type               = shift;
    my $limit              = shift;

    $search1 = $self->ConvertToSearchTerm( $search1, $type );
    $search2 = $self->ConvertToSearchTerm( $search2, $type );

    if ( ! $offset ) { $offset = 0; }

    if ( ( $type eq 'userReviews' ) || ( $type eq 'editReviews' ) )
    {
      if ( ! $order || $order eq "time" ) { $order = "time"; }
    }
    else
    {
      if ( ! $order || $order eq "id" ) { $order = "id"; }
    }

    if ( ! $direction )
    {
      $direction = 'DESC';
    }

    my $sql;
    if ( $type eq 'adminReviews' )
    {
      $sql = qq{ SELECT r.id, r.time, r.duration, r.user, r.attr, r.reason, r.note, r.renNum, r.expert, r.copyDate, r.expertNote, r.category, r.legacy, r.renDate, r.priority, q.status, b.title, b.author FROM $CRMSGlobals::reviewsTable r, $CRMSGlobals::queueTable q, bibdata b WHERE q.id = r.id AND q.id = b.id };
    }
    elsif ( $type eq 'expert' )
    {
      $sql = qq{ SELECT r.id, r.time, r.duration, r.user, r.attr, r.reason, r.note, r.renNum, r.expert, r.copyDate, r.expertNote, r.category, r.legacy, r.renDate, r.priority, q.status, b.title, b.author FROM $CRMSGlobals::reviewsTable r, $CRMSGlobals::queueTable q, bibdata b WHERE q.id = r.id AND q.id = b.id  AND ( q.status = 2 ) };
    }
    elsif ( $type eq 'adminHistoricalReviews' )
    {
      $sql = qq{ SELECT r.id, r.time, r.duration, r.user, r.attr, r.reason, r.note, r.renNum, r.expert, r.copyDate, r.expertNote, r.category, r.legacy, r.renDate, r.priority, r.status, b.title, b.author, YEAR(b.pub_date), r.validated FROM $CRMSGlobals::historicalreviewsTable r, bibdata b  WHERE r.id = b.id };
    }
    elsif ( $type eq 'undReviews' )
    {
      $sql = qq{ SELECT r.id, r.time, r.duration, r.user, r.attr, r.reason, r.note, r.renNum, r.expert, r.copyDate, r.expertNote, r.category, r.legacy, r.renDate, r.priority, q.status, b.title, b.author FROM $CRMSGlobals::reviewsTable r, $CRMSGlobals::queueTable q, bibdata b WHERE q.id = b.id  AND q.id = r.id AND q.status = 3 };
    }
    elsif ( $type eq 'userReviews' )
    {
      my $user = $self->get( "user" );
      $sql = qq{ SELECT r.id, r.time, r.duration, r.user, r.attr, r.reason, r.note, r.renNum, r.expert, r.copyDate, r.expertNote, r.category, r.legacy, r.renDate, r.priority, q.status, b.title, b.author FROM $CRMSGlobals::reviewsTable r, $CRMSGlobals::queueTable q, bibdata b WHERE q.id = r.id AND q.id = b.id AND r.user = '$user' AND q.status > 0 };
    }
    elsif ( $type eq 'editReviews' )
    {
      my $user = $self->get( "user" );
      my $yesterday = $self->GetYesterday();
      $sql = qq{ SELECT r.id, r.time, r.duration, r.user, r.attr, r.reason, r.note, r.renNum, r.expert, r.copyDate, r.expertNote, r.category, r.legacy, r.renDate, r.priority, q.status, b.title, b.author FROM $CRMSGlobals::reviewsTable r, $CRMSGlobals::queueTable q, bibdata b WHERE q.id = r.id AND q.id = b.id AND r.user = '$user' AND r.time >= "$yesterday" };
    }

    my ( $search1term, $search2term );
    if ( $search1value =~ m/.*\*.*/ )
    {
      $search1value =~ s/\*/%/gs;
      $search1term = qq{$search1 LIKE '$search1value'};
    }
    else
    {
      $search1term = qq{$search1 = '$search1value'};
    }
    if ( $search2value =~ m/.*\*.*/ )
    {
      $search2value =~ s/\*/%/gs;
      $search2term = qq{$search2 LIKE '$search2value'};
    }
    else
    {
      $search2term = qq{$search2 = '$search2value'};
    }
    if ( $search1value =~ m/([<>!]=?)\s*(\d+)\s*/ )
    {
      $search1term = "$search1 $1 $2";
    }
    if ( $search2value =~ m/([<>!]=?)\s*(\d+)\s*/ )
    {
      $search2term = "$search2 $1 $2";
    }
    
    if ( ( $search1value ne '' ) && ( $search2value ne '' ) )
    {
      { $sql .= qq{ AND ( $search1term  $op1  $search2term ) };   }
    }
    elsif ( $search1value ne '' )
    {
      { $sql .= qq{ AND $search1term  };   }
    }
    elsif (  $search2value ne '' )
    {
      { $sql .= qq{ AND $search2term  };   }
    }

    if ( $startDate ) { $sql .= qq{ AND r.time >= "$startDate 00:00:00" }; }
    if ( $endDate ) { $sql .= qq{ AND r.time <= "$endDate 23:59:59" }; }

    my $limit_section = '';
    if ( $limit )
    {
      $limit_section = qq{LIMIT $offset, $pagesize};
    }
    if ( $order eq 'status' )
    {
      if ( $type eq 'adminHistoricalReviews' )
      {
        $sql .= qq{ ORDER BY r.$order $direction $limit_section };
      }
      else
      {
        $sql .= qq{ ORDER BY q.$order $direction $limit_section };
      }
    }
    elsif ($order eq 'title' || $order eq 'author' || $order eq 'pub_date')
    {
       $sql .= qq{ ORDER BY b.$order $direction $limit_section };
    }
    else
    {
       $sql .= qq{ ORDER BY r.$order $direction $limit_section };
    }
    
    return $sql;
}


sub SearchAndDownload
{
    my $self               = shift;
    my $order              = shift;
    my $direction          = shift;

    my $search1            = shift;
    my $search1value       = shift;
    my $op1                = shift;

    my $search2            = shift;
    my $search2value       = shift;

    my $startDate          = shift;
    my $endDate            = shift;
    my $offset             = shift;

    my $type               = shift;
    my $limit              = 0;

    my $isadmin = $self->IsUserAdmin();
    my $sql =  $self->CreateSQL( $order, $direction, $search1, $search1value, $op1, $search2, $search2value, $startDate, $endDate, $offset, undef, $type, $limit );
    
    my $ref = $self->get( 'dbh' )->selectall_arrayref( $sql );

    my $buffer;
    if ( scalar @{$ref} != 0 )
    {
      if ( $type eq 'userReviews')
      {
        $buffer .= qq{id\ttitle\tauthor\ttime\tattr\treason\tcategory\tnote};
      }
      elsif ( $type eq 'editReviews' )
      {
        $buffer .= qq{id\ttitle\tauthor\ttime\tattr\treason\tcategory\tnote};
      }
      elsif ( $type eq 'undReviews' )
      {
        $buffer .= qq{id\ttitle\tauthor\ttime\tstatus\tuser\tattr\treason\tcategory\tnote}
      }
      elsif ( $type eq 'expert' )
      {
        $buffer .= qq{id\ttitle\tauthor\ttime\tstatus\tuser\tattr\treason\tcategory\tnote};
      }
      elsif ( $type eq 'adminReviews' )
      {
        $buffer .= qq{id\ttitle\tauthor\ttime\tstatus\tuser\tattr\treason\tcategory\tnote};
      }
      elsif ( $type eq 'adminHistoricalReviews' )
      {
        $buffer .= qq{id\ttitle\tauthor\tpub date\ttime\tstatus\tlegacy\tuser\tattr\treason\tcategory\tnote\tvalidated};
      }
    }
    $buffer .= sprintf("%s\n", ($self->IsUserAdmin())? "\tpriority":'');
    
    foreach my $row ( @{$ref} )
    {
        $row->[1] =~ s,(.*) .*,$1,;
        
        my $id         = $row->[0];
        my $time       = $row->[1];
        my $duration   = $row->[2];
        my $user       = $row->[3];
        my $attr       = $self->GetRightsName($row->[4]);
        my $reason     = $self->GetReasonName($row->[5]);
        my $note       = $row->[6];
        $note =~ s,\n, ,gs;
        $note =~ s,\r, ,gs;
        $note =~ s,\t, ,gs;
        my $renNum     = $row->[7];
        my $expert     = $row->[8];
        my $copyDate   = $row->[9];
        my $expertNote = $row->[10];
        $expertNote =~ s,\n, ,gs;
        $expertNote =~ s,\r, ,gs;
        $expertNote =~ s,\t, ,gs;
        my $category   = $row->[11];
        my $legacy     = $row->[12];
        my $renDate    = $row->[13];
        my $priority   = $row->[14];
        my $status     = $row->[15];
        my $title      = $row->[16];
        my $author     = $row->[17];
        
        if ( $type eq 'userReviews')
        {
          #for reviews
          #id, title, author, review date, attr, reason, category, note.
          $buffer .= qq{$id\t$title\t$author\t$time\t$attr\t$reason\t$category\t$note};
        }
        elsif ( $type eq 'editReviews' )
        {
          #for editRevies
          #id, title, author, review date, attr, reason, category, note.
          $buffer .= qq{$id\t$title\t$author\t$time\t$attr\t$reason\t$category\t$note};
        }
        elsif ( $type eq 'undReviews' )
        {
          #for und/nif
          #id, title, author, review date, status, user, attr, reason, category, note.
          $buffer .= qq{$id\t$title\t$author\t$time\t$status\t$user\t$attr\t$reason\t$category\t$note}
        }
        elsif ( $type eq 'expert' )
        {
          #for expert
          #id, title, author, review date, status, user, attr, reason, category, note.
          $buffer .= qq{$id\t$title\t$author\t$time\t$status\t$user\t$attr\t$reason\t$category\t$note};
        }
        elsif ( $type eq 'adminReviews' )
        {
          #for adminReviews
          #id, title, author, review date, status, user, attr, reason, category, note.
          $buffer .= qq{$id\t$title\t$author\t$time\t$status\t$user\t$attr\t$reason\t$category\t$note};
        }
        elsif ( $type eq 'adminHistoricalReviews' )
        {
          my $pubdate = $row->[18];
          $pubdate = '?' unless $pubdate;
          my $validated = $row->[19];
          #id, title, author, review date, status, user, attr, reason, category, note, validated
          $buffer .= qq{$id\t$title\t$author\t$pubdate\t$time\t$status\t$legacy\t$user\t$attr\t$reason\t$category\t$note\t$validated};
        }
        $buffer .= sprintf("%s\n", ($self->IsUserAdmin())? "\t$priority":'');
      }

      $self->DownloadSpreadSheet( $buffer );

    if ( $buffer ) { return 1; }
    else { return 0; }
}

sub SearchAndDownloadQueue
{
  my $self = shift;
  my $order = shift;
  my $dir = shift;
  my $search1 = shift;
  my $search1Value = shift;
  my $op1 = shift;
  my $search2 = shift;
  my $search2Value = shift;
  my $startDate = shift;
  my $endDate = shift;
  my $offset = shift;
  my $pagesize = shift;
  my $download = shift;
  
  my $buffer = $self->GetQueueRef($order, $dir, $search1, $search1Value, $op1, $search2, $search2Value, $startDate, $endDate, $offset, $pagesize, 1);
  $self->DownloadSpreadSheet( $buffer );
  if ( $buffer ) { return 1; }
  else { return 0; }
}

sub GetReviewsRef
{
    my $self               = shift;
    my $order              = shift;
    my $dir                = shift;

    my $search1            = shift;
    my $search1Value       = shift;
    my $op1                = shift;

    my $search2            = shift;
    my $search2Value       = shift;

    my $startDate          = shift;
    my $endDate            = shift;
    my $offset             = shift;
    my $pagesize           = shift;
    my $page               = shift;

    my $limit              = 1;
    $pagesize = 20 unless $pagesize > 0;
    $offset = 0 unless $offset > 0;
    my $totalReviews = $self->GetReviewsCount($search1, $search1Value, $op1, $search2, $search2Value, $startDate, $endDate, $page, 0);
    my $totalVolumes = $self->GetReviewsCount($search1, $search1Value, $op1, $search2, $search2Value, $startDate, $endDate, $page, 1);
    $offset = $totalReviews-($totalReviews % $pagesize) if $offset >= $totalReviews;
    #print("GetReviewsRef('$order','$dir','$search1','$search1Value','$op1','$search2','$search2Value','$startDate','$endDate','$offset','$pagesize','$page');<br/>\n");
    my $sql =  $self->CreateSQL( $order, $dir, $search1, $search1Value, $op1, $search2, $search2Value, $startDate, $endDate, $offset, $pagesize, $page, $limit );
    #print "$sql<br/>\n";
    my $ref = $self->get( 'dbh' )->selectall_arrayref( $sql );

    my $return = [];
    foreach my $row ( @{$ref} )
    {
        my $date = $row->[1];
        $date =~ s/(.*) .*/$1/;
        my $item = {id         => $row->[0],
                    time       => $row->[1],
                    date       => $date,
                    duration   => $row->[2],
                    user       => $row->[3],
                    attr       => $self->GetRightsName($row->[4]),
                    reason     => $self->GetReasonName($row->[5]),
                    note       => $row->[6],
                    renNum     => $row->[7],
                    expert     => $row->[8],
                    copyDate   => $row->[9],
                    expertNote => $row->[10],
                    category   => $row->[11],
                    legacy     => $row->[12],
                    renDate    => $row->[13],
                    priority   => $row->[14],
                    status     => $row->[15],
                    title      => $row->[16],
                    author     => $row->[17]
                   };
        my $pubdate = $row->[18];
        $pubdate = '?' unless $pubdate;
        ${$item}{'pubdate'} = $pubdate if $page eq 'adminHistoricalReviews';
        ${$item}{'validated'} = $row->[19] if $page eq 'adminHistoricalReviews';
        push( @{$return}, $item );
    }
    my $n = POSIX::ceil($offset/$pagesize+1);
    my $of = POSIX::ceil($totalReviews/$pagesize);
    $n = 0 if $of == 0;
    my $data = {'rows' => $return,
                'reviews' => $totalReviews,
                'volumes' => $totalVolumes,
                'page' => $n,
                'of' => $of
               };
  return $data;
}


sub GetVolumesRef
{
  my $self = shift;
  my $order = shift;
  my $dir = shift;
  my $search1 = shift;
  my $search1Value = shift;
  my $op1 = shift;
  my $search2 = shift;
  my $search2Value = shift;
  my $startDate = shift;
  my $endDate = shift;
  my $offset = shift;
  my $pagesize = shift;
  my $page = shift;
  #print("GetVolumesRef('$order','$dir','$search1','$search1Value','$op1','$search2','$search2Value','$startDate','$endDate','$offset','$pagesize','$page');<br/>\n");
  
  $pagesize = 20 unless $pagesize > 0;
  $offset = 0 unless $offset > 0;
  if (!$order)
  {
    $order = 'id';
    $order = 'time' if $page eq 'userReviews' or $page eq 'editReviews';
  }
  $offset = 0 unless $offset;
  $search1 = $self->ConvertToSearchTerm( $search1, $page );
  $search2 = $self->ConvertToSearchTerm( $search2, $page );
  if ($order eq 'author' || $order eq 'title' || $order eq 'pub_date') { $order = 'b.' . $order; }
  elsif ($order eq 'status' && $page ne 'adminHistoricalReviews') { $order = 'q.' . $order; }
  else { $order = 'r.' . $order; }
  $search1 = 'r.id' unless $search1;
  my $order2 = ($dir eq 'ASC')? 'max':'min';
  my @rest = ('r.id=b.id');
  my $table = 'reviews';
  my $doQ = '';
  my $status = 'r.status';
  if ($page eq 'adminHistoricalReviews')
  {
    $table = 'historicalreviews';
  }
  else
  {
    push @rest, 'r.id=q.id';
    $doQ = ', queue q';
    $status = 'q.status';
  }
  if ($page eq 'undReviews')
  {
    push @rest, 'q.status=3';
  }
  elsif ($page eq 'expert')
  {
    push @rest, 'q.status=2';
  }
  my $tester1 = '=';
  my $tester2 = '=';
  if ( $search1Value =~ m/.*\*.*/ )
  {
    $search1Value =~ s/\*/%/gs;
    $tester1 = ' LIKE ';
  }
  if ( $search2Value =~ m/.*\*.*/ )
  {
    $search2Value =~ s/\*/%/gs;
    $tester2 = ' LIKE ';
  }
  if ( $search1Value =~ m/([<>!]=?)\s*(\d+)\s*/ )
  {
    $search1Value = $2;
    $tester1 = $1;
  }
  if ( $search2Value =~ m/([<>!]=?)\s*(\d+)\s*/ )
  {
    $search2Value = $2;
    $tester2 = $1;
  }
  push @rest, "r.time >= '$startDate'" if $startDate;
  push @rest, "r.time <= '$endDate'" if $endDate;
  push @rest, "$search1 $tester1 '$search1Value'" if $search1Value ne '';
  push @rest, "$search2 $tester2 '$search2Value'" if $search2Value ne '';
  my $restrict = join(' AND ', @rest);
  my $sql = "SELECT COUNT(r2.id) FROM $table r2 WHERE r2.id IN (SELECT r.id FROM $table r, bibdata b$doQ WHERE $restrict)";
  #print "$sql<br/>\n";
  my $totalReviews = $self->SimpleSqlGet($sql);
  $sql = "SELECT COUNT(DISTINCT r.id) FROM $table r, bibdata b$doQ WHERE $restrict";
  #print "$sql<br/>\n";
  my $totalVolumes = $self->SimpleSqlGet($sql);
  $offset = $totalVolumes-($totalVolumes % $pagesize) if $offset >= $totalVolumes;
  $sql = 'SELECT id FROM ' .
         "(SELECT r.id as id,count(r.id) AS cnt, $order2($order) AS ord FROM $table r, bibdata b$doQ WHERE $restrict GROUP BY r.id) " .
         "AS derived WHERE cnt>0 ORDER BY ord $dir LIMIT $offset, $pagesize";
  #print "$sql<br/>\n";
  my $ref = $self->get( 'dbh' )->selectall_arrayref( $sql );
  my $return = ();
  foreach my $row ( @{$ref} )
  {
    my $id = $row->[0];
    my $qrest = ($doQ)? ' AND r.id=q.id':'';
    $sql = "SELECT r.id, r.time, r.duration, r.user, r.attr, r.reason, r.note, r.renNum, r.expert, r.copyDate, r.expertNote, " .
           "r.category, r.legacy, r.renDate, r.priority, $status, b.title, b.author" .
           (($page eq 'adminHistoricalReviews')? ', YEAR(b.pub_date) ':' ') .
           (($page eq 'adminHistoricalReviews')? ', r.validated ':' ') .
           "FROM $table r, bibdata b$doQ ";
    $sql .= "WHERE r.id='$id' AND r.id=b.id $qrest ORDER BY $order $dir";
    #print "$sql<br/>\n";
    my $ref2 = $self->get( 'dbh' )->selectall_arrayref( $sql );
    foreach my $row ( @{$ref2} )
    {
      my $date = $row->[1];
      $date =~ s/(.*) .*/$1/;
      my $item = {id         => $row->[0],
                  time       => $row->[1],
                  date       => $date,
                  duration   => $row->[2],
                  user       => $row->[3],
                  attr       => $self->GetRightsName($row->[4]),
                  reason     => $self->GetReasonName($row->[5]),
                  note       => $row->[6],
                  renNum     => $row->[7],
                  expert     => $row->[8],
                  copyDate   => $row->[9],
                  expertNote => $row->[10],
                  category   => $row->[11],
                  legacy     => $row->[12],
                  renDate    => $row->[13],
                  priority   => $row->[14],
                  status     => $row->[15],
                  title      => $row->[16],
                  author     => $row->[17]
                 };
      my $pubdate = $row->[18];
      $pubdate = '?' unless $pubdate;
      ${$item}{'pubdate'} = $pubdate if $page eq 'adminHistoricalReviews';
      ${$item}{'validated'} = $row->[19] if $page eq 'adminHistoricalReviews';
      push( @{$return}, $item );
    }
  }
  my $n = POSIX::ceil($offset/$pagesize+1);
  my $of = POSIX::ceil($totalVolumes/$pagesize);
  $n = 0 if $of == 0;
  my $data = {'rows' => $return,
              'reviews' => $totalReviews,
              'volumes' => $totalVolumes,
              'page' => $n,
              'of' => $of
             };
  return $data;
}

sub GetQueueRef
{
  my $self = shift;
  my $order = shift;
  my $dir = shift;
  my $search1 = shift;
  my $search1Value = shift;
  my $op1 = shift;
  my $search2 = shift;
  my $search2Value = shift;
  my $startDate = shift;
  my $endDate = shift;
  my $offset = shift;
  my $pagesize = shift;
  my $download = shift;
  #print("GetQueueRef('$order','$dir','$search1','$search1Value','$op1','$search2','$search2Value','$startDate','$endDate','$offset','$pagesize','$download');<br/>\n");
  
  $pagesize = 20 unless $pagesize > 0;
  $offset = 0 unless $offset > 0;
  $order = 'id' unless $order;
  $offset = 0 unless $offset;
  $search1 = $self->ConvertToSearchTerm( $search1, 'queue' );
  $search2 = $self->ConvertToSearchTerm( $search2, 'queue' );
  if ($order eq 'author' || $order eq 'title' || $order eq 'pub_date') { $order = 'b.' . $order; }
  elsif ($order eq 'reviews') { $order = '(SELECT COUNT(*) FROM reviews r WHERE r.id=q.id)'; }
  else { $order = 'q.' . $order; }
  my @rest = ('q.id=b.id');
  my $tester1 = '=';
  my $tester2 = '=';
  if ( $search1Value =~ m/.*\*.*/ )
  {
    $search1Value =~ s/\*/%/gs;
    $tester1 = ' LIKE ';
  }
  if ( $search2Value =~ m/.*\*.*/ )
  {
    $search2Value =~ s/\*/%/gs;
    $tester2 = ' LIKE ';
  }
  if ( $search1Value =~ m/([<>!]=?)\s*(\d+)\s*/ )
  {
    $search1Value = $2;
    $tester1 = $1;
  }
  if ( $search2Value =~ m/([<>!]=?)\s*(\d+)\s*/ )
  {
    $search2Value = $2;
    $tester2 = $1;
  }
  push @rest, "q.time >= '$startDate'" if $startDate;
  push @rest, "q.time <= '$endDate'" if $endDate;
  push @rest, "$search1 $tester1 '$search1Value'" if $search1Value ne '';
  push @rest, "$search2 $tester2 '$search2Value'" if $search2Value ne '';
  my $restrict = ((scalar @rest)? 'WHERE ':'') . join(' AND ', @rest);
  my $sql = "SELECT COUNT(q.id) FROM queue q, bibdata b $restrict\n";
  #print "$sql<br/>\n";
  my $totalVolumes = $self->SimpleSqlGet($sql);
  $offset = $totalVolumes-($totalVolumes % $pagesize) if $offset >= $totalVolumes;
  my $limit = ($download)? '':"LIMIT $offset, $pagesize";
  my $return = ();
  $sql = 'SELECT q.id, q.time, q.status, q.locked, YEAR(b.pub_date), q.priority, q.expcnt, b.title, b.author ' .
         "FROM queue q, bibdata b $restrict ORDER BY $order $dir $limit";
  #print "$sql<br/>\n";
  my $ref = $self->get( 'dbh' )->selectall_arrayref( $sql );
  my $data = join "\t", ('ID','Title','Author','Pub Date','Date Added','Status','Locked','Priority','Reviews','Expert Reviews');
  foreach my $row ( @{$ref} )
  {
    my $id = $row->[0];
    my $date = $row->[1];
    $date =~ s/(.*) .*/$1/;
    my $pubdate = $row->[4];
    $pubdate = '?' unless $pubdate;
    $sql = "SELECT COUNT(*) FROM reviews WHERE id='$id'";
    #print "$sql<br/>\n";
    my $reviews = $self->SimpleSqlGet($sql);
    my $item = {id         => $id,
                time       => $row->[1],
                date       => $date,
                status     => $row->[2],
                locked     => $row->[3],
                pubdate    => $pubdate,
                priority   => $row->[5],
                expcnt     => $row->[6],
                title      => $row->[7],
                author     => $row->[8],
                reviews    => $reviews
               };
    push( @{$return}, $item );
    $data .= sprintf("\n$id\t%s\t%s\t%s\t$date\t%s\t%s\t%s\t$reviews\t%s",
                     $row->[7], $row->[8], $row->[4], $row->[2], $row->[3], $row->[5], $row->[6]);
  }
  if (!$download)
  {
    my $n = POSIX::ceil($offset/$pagesize+1);
    my $of = POSIX::ceil($totalVolumes/$pagesize);
    $n = 0 if $of == 0;
    $data = {'rows' => $return,
             'volumes' => $totalVolumes,
             'page' => $n,
             'of' => $of
            };
  }
  return $data;
}

sub GetReviewsCount
{
    my $self           = shift;
    my $search1        = shift;
    my $search1value   = shift;
    my $op1            = shift;
    my $search2        = shift;
    my $search2value   = shift;
    my $startDate      = shift;
    my $endDate        = shift;
    my $page           = shift;
    my $volumes        = shift;

    my $countExpression = qq{*};
    if ( $volumes )
    {
      $countExpression = qq{distinct r.id};
    }

    $search1 = $self->ConvertToSearchTerm( $search1, $page );
    $search2 = $self->ConvertToSearchTerm( $search2, $page );


    my $sql;
    if ( $page eq 'adminReviews' )
    {
      $sql = qq{ SELECT count($countExpression) FROM $CRMSGlobals::reviewsTable r, $CRMSGlobals::queueTable q, bibdata b WHERE q.id = r.id AND q.id = b.id };
    }
    elsif ( $page eq 'expert' ) # Conflicts
    {
      $sql = qq{ SELECT count($countExpression) FROM $CRMSGlobals::reviewsTable r, $CRMSGlobals::queueTable q, bibdata b WHERE q.id = r.id AND q.id = b.id  AND ( q.status = 2 ) };
    }
    elsif ( $page eq 'adminHistoricalReviews' )
    {
      $sql = qq{ SELECT count($countExpression) FROM $CRMSGlobals::historicalreviewsTable r, bibdata b  WHERE r.id = b.id };
    }
    elsif ( $page eq 'undReviews' )
    {
      $sql = qq{ SELECT count($countExpression) FROM $CRMSGlobals::reviewsTable r, $CRMSGlobals::queueTable q, bibdata b WHERE q.id = b.id  AND q.id = r.id AND q.status = 3 };
    }
    elsif ( $page eq 'userReviews' )
    {
      my $user = $self->get( "user" );
      $sql = qq{ SELECT count($countExpression) FROM $CRMSGlobals::reviewsTable r, $CRMSGlobals::queueTable q, bibdata b WHERE q.id = r.id AND q.id = b.id AND r.user = '$user' AND q.status > 0 };
    }
    elsif ( $page eq 'editReviews' )
    {
      my $user = $self->get( "user" );
      my $yesterday = $self->GetYesterday();
      $sql = qq{ SELECT count($countExpression) FROM $CRMSGlobals::reviewsTable r, $CRMSGlobals::queueTable q, bibdata b WHERE q.id = r.id AND q.id = b.id AND r.user = '$user' AND r.time >= "$yesterday" };
    }
    
    my ( $search1term, $search2term );
    if ( $search1value =~ m,.*\*.*, )
    {
      $search1value =~ s,\*,%,gs;
      $search1term = qq{$search1 LIKE '$search1value'};
    }
    else
    {
      $search1term = qq{$search1 = '$search1value'};
    }
    if ( $search2value =~ m,.*\*.*, )
    {
      $search2value =~ s,\*,%,gs;
      $search2term = qq{$search2 LIKE '$search2value'};
    }
    else
    {
      $search2term = qq{$search2 = '$search2value'};
    }
    if ( $search1value =~ m/([<>!]=?)\s*(\d+)\s*/ )
    {
      $search1term = "$search1 $1 $2";
    }
    if ( $search2value =~ m/([<>!]=?)\s*(\d+)\s*/ )
    {
      $search2term = "$search2 $1 $2";
    }
    if ( ( $search1value ne '' ) && ( $search2value ne '' ) )
    {
      { $sql .= qq{ AND ( $search1term  $op1  $search2term ) };   }
    }
    elsif ( $search1value ne '' )
    {
      { $sql .= qq{ AND $search1term  };   }
    }
    elsif (  $search2value ne '' )
    {
      { $sql .= qq{ AND $search2term  };   }
    }

    if ( $startDate ) { $sql .= qq{ AND r.time >= "$startDate 00:00:00" }; }
    if ( $endDate ) { $sql .= qq{ AND r.time <= "$endDate 23:59:59" }; }
    #print "$sql<br/>\n";
    return $self->SimpleSqlGet( $sql );
}


sub LinkToStanford
{
    my $self = shift;
    my $q    = shift;

    my $url = 'http://collections.stanford.edu/copyrightrenewals/bin/search/simple/process?query=';

    return qq{<a href="$url$q">$q</a>};
}

sub LinkToPT
{
    my $self = shift;
    my $id   = shift;
    my $ti   = $self->GetTitle( $id );
    
    my $url = 'https://babel.hathitrust.org/cgi/pt?attr=1&amp;id=';
    #This url was used for testing.
    #my $url = '/cgi/m/mdp/pt?skin=crms;attr=1;id=';

    return qq{<a href="$url$id" target="_blank">$ti</a>};
}

sub LinkToReview
{
    my $self = shift;
    my $id   = shift;
    my $ti   = $self->GetTitle( $id );
    
    ## my $url = 'http://babel.hathitrust.org/cgi/pt?attr=1&id=';
    my $url = qq{/cgi/c/crms/crms?p=review;barcode=$id;editing=1};

    return qq{<a href="$url" target="_blank">$ti</a>};
}

sub DetailInfo
{
    my $self   = shift;
    my $id     = shift;
    my $user   = shift;
    my $page   = shift;
    
    my $url = qq{/cgi/c/crms/crms?p=detailInfo&amp;id=$id&amp;user=$user&amp;page=$page};

    return qq{<a href="$url" target="_blank">$id</a>};
}

sub DetailInfoForReview
{
    my $self   = shift;
    my $id     = shift;
    my $user   = shift;
    my $page   = shift;
    
    my $url = qq{/cgi/c/crms/crms?p=detailInfoForReview&amp;id=$id&amp;user=$user&amp;page=$page};

    return qq{<a href="$url" target="_blank">$id</a>};
}


sub GetStatus
{
    my $self = shift;
    my $id   = shift;

    my $sql = qq{ SELECT status FROM $CRMSGlobals::queueTable WHERE id = "$id"};
    my $str = $self->SimpleSqlGet( $sql );

    return $str;

}

sub GetLegacyStatus
{
    my $self = shift;
    my $id   = shift;

    my $sql = qq{ SELECT status FROM $CRMSGlobals::historicalreviewsTable WHERE id = "$id"};
    my $str = $self->SimpleSqlGet( $sql );

    return $str;

}

sub ItemWasReviewedByOtherUser
{
    my $self   = shift;
    my $id     = shift;
    my $user   = shift;

    my $sql = qq{ SELECT id FROM $CRMSGlobals::reviewsTable WHERE user != "$user" AND id = "$id"};
    my $found = $self->SimpleSqlGet( $sql );

    if ($found) { return 1; }
    return 0;

}

sub UsersAgreeOnReview
{
    my $self = shift;
    my $id   = shift;

    ##Agree is when the attr and reason match.

    my $sql = qq{ SELECT id, attr, reason FROM $CRMSGlobals::reviewsTable where id = '$id' Group by id, attr, reason having count(*) = 2};
    my $found = $self->SimpleSqlGet( $sql );

    if ($found) { return 1; }
    return 0;

}

sub GetAttrReasonFromOtherUser
{
    my $self   = shift;
    my $id     = shift;
    my $name   = shift;

    my $sql = qq{SELECT attr, reason FROM $CRMSGlobals::reviewsTable WHERE id = "$id" and user != '$name'};
    my $ref = $self->get( 'dbh' )->selectall_arrayref( $sql );

    if ( ! $ref->[0]->[0] )
    {
        $self->Logit( "$id not found in review table" );
    }

    my $attr = $self->GetRightsName( $ref->[0]->[0] );
    my $reason = $self->GetReasonName( $ref->[0]->[1] );
    return ($attr, $reason);
}


sub ValidateAttrReasonCombo
{
    my $self    = shift;
    my $attr    = shift;
    my $reason  = shift;
    
    my $code = $self->GetCodeFromAttrReason($attr,$reason);
    $self->SetError( "bad attr/reason: $attr/$reason" ) unless $code;
    return $code;
}

sub GetAttrReasonCom
{
    my $self = shift;
    my $in   = shift;
 
    my %codes = (1 => 'pd/ncn', 2 => 'pd/ren',  3 => 'pd/cdpp',
                 4 => 'ic/ren', 5 => 'ic/cdpp', 6 => 'und/nfi',
                 7 => 'pdus/cdpp');

    my %str   = ('pd/ncn' => 1, 'pd/ren'  => 2, 'pd/cdpp' => 3,
                 'ic/ren' => 4, 'ic/cdpp' => 5, 'und/nfi' => 6,
                 'pdus/cdpp' => 7);

    if ( $in =~ m/\d/ ) { return $codes{$in}; }
    else                { return $str{$in};   }
}

sub GetAttrReasonFromCode
{
    my $self = shift;
    my $code = shift;

    if    ( $code eq '1' ) { return (1,2); }
    elsif ( $code eq '2' ) { return (1,7); }
    elsif ( $code eq '3' ) { return (1,9); }
    elsif ( $code eq '4' ) { return (2,7); }
    elsif ( $code eq '5' ) { return (2,9); }
    elsif ( $code eq '6' ) { return (5,8); }
    elsif ( $code eq '7' ) { return (9,9); }
}

sub GetCodeFromAttrReason
{
    my $self = shift;
    my $attr = shift;
    my $reason = shift;

    if ($attr == 1 and $reason == 2) { return 1; }
    if ($attr == 1 and $reason == 7) { return 2; }
    if ($attr == 1 and $reason == 9) { return 3; }
    if ($attr == 2 and $reason == 7) { return 4; }
    if ($attr == 2 and $reason == 9) { return 5; }
    if ($attr == 5 and $reason == 8) { return 6; }
    if ($attr == 9 and $reason == 9) { return 7; }
}

sub GetReviewComment
{
    my $self = shift;
    my $id   = shift;
    my $user = shift;

    my $sql = qq{ SELECT note FROM $CRMSGlobals::reviewsTable WHERE id = "$id" AND user = "$user"};
    #my $ref = $self->get( 'dbh' )->selectall_arrayref( $sql );
    my $str = $self->SimpleSqlGet( $sql );

    return $str;

}

sub GetReviewCategory
{
    my $self = shift;
    my $id   = shift;
    my $user = shift;

    my $sql = qq{ SELECT category FROM $CRMSGlobals::reviewsTable WHERE id = "$id" AND user = "$user"};
    #my $ref = $self->get( 'dbh' )->selectall_arrayref( $sql );
    my $str = $self->SimpleSqlGet( $sql );

    return $str;
}


sub GetAttrReasonCode
{
    my $self = shift;
    my $id   = shift;
    my $user = shift;

    my $sql = qq{ SELECT attr, reason FROM $CRMSGlobals::reviewsTable WHERE id = "$id" AND user = "$user"};
    my $ref = $self->get( 'dbh' )->selectall_arrayref( $sql );

    my $rights = $self->GetRightsName( $ref->[0]->[0] );
    my $reason = $self->GetReasonName( $ref->[0]->[1] );

    return $self->GetAttrReasonCom( "$rights/$reason" );
}

sub CheckForId
{
    my $self = shift;
    my $id   = shift;
    my $dbh  = $self->get( 'dbh' );

    ## just make sure the ID is in the queue
    my $sql = qq{SELECT id FROM $CRMSGlobals::queueTable WHERE id = '$id'};
    my @rows = $dbh->selectrow_array( $sql );
    
    return scalar( @rows );
}

sub CheckReviewer
{
    my $self = shift;
    my $user = shift;
    my $exp  = shift;
    my $dbh  = $self->get( 'dbh' );

    my $sql = qq{SELECT type FROM $CRMSGlobals::usersTable WHERE id = '$user'};
    my $rows = $dbh->selectall_arrayref( $sql );

    if ( $exp )
    {
        foreach ( @{$rows} ) { if ($_->[0] == 2) { return 1; } }
    }
    else
    {
        foreach ( @{$rows} ) { if ($_->[0] == 1 || $_->[0] == 2) { return 1; } }
    }
    return 0;
}

sub GetUserName
{
    my $self = shift;
    my $user = shift;

    if ( ! $user ) { $user = $self->get( "user" ); }

    my $sql = qq{SELECT name FROM $CRMSGlobals::usersTable WHERE id = '$user' LIMIT 1};
    my $name = $self->SimpleSqlGet( $sql );

    if ( $name ne '' ) { return $name; }

    return 0;
}


sub GetAliasUserName
{
    my $self = shift;
    my $user = shift;

    if ( ! $user ) { $user = $self->get( "user" ); }

    my $sql = qq{SELECT alias FROM $CRMSGlobals::usersTable WHERE id = '$user' LIMIT 1};
    my $name = $self->SimpleSqlGet( $sql );

    if ( $name ne '' ) { return $name; }

    return 0;
}

sub ChangeAliasUserName
{
    my $self = shift;
    my $user = shift;
    my $new_user = shift;

    if ( ! $user ) { $user = $self->get( "user" ); }

    my $sql = qq{UPDATE $CRMSGlobals::usersTable set alias = '$new_user' WHERE id = '$user'};
    $self->PrepareSubmitSql( $sql );


}

sub ChangeDateFormat
{
    my $self = shift;
    my $date = shift;
    
    #go from MM/DD/YYYY to YYYY-MM-DD
    my ($month, $day, $year) = split '/', $date;
    
    $year  = qq{20$year} if $year < 100;
    $month = qq{0$month} if $month < 10;
    $day   = qq{0$day} if $day < 10;

    $date = join '-', ($year, $month, $day);

    return $date;
}

sub IsUserReviewer
{
    my $self = shift;
    my $user = shift;

    if ( ! $user ) { $user = $self->get( "user" ); }

    my $sql = qq{ SELECT name FROM $CRMSGlobals::usersTable WHERE id = '$user' AND type = 1 };
    my $name = $self->SimpleSqlGet( $sql );

    if ($name) { return 1; }

    return 0;
}

sub IsUserExpert
{
    my $self = shift;
    my $user = shift;

    if ( ! $user ) { $user = $self->get( "user" ); }

    my $sql = qq{ SELECT name FROM $CRMSGlobals::usersTable WHERE id = '$user' AND type = 2 };
    my $name = $self->SimpleSqlGet( $sql );

    if ($name) { return 1; }

    return 0;
}

sub IsUserAdmin
{
    my $self = shift;
    my $user = shift;

    if ( ! $user ) { $user = $self->get( "user" ); }
    
    my $sql = qq{ SELECT name FROM $CRMSGlobals::usersTable WHERE id = '$user' AND type = 3 };
    my $name = $self->SimpleSqlGet( $sql );
    
    if ( $name ) { return 1; }
    
    return 0;
}

sub GetUserData
{
    my $self = shift;
    my $id   = shift;
    my $dbh  = $self->get( 'dbh' );

    my $sql = qq{SELECT id, name, type FROM $CRMSGlobals::usersTable };
    if ( $id ne '' ) { $sql .= qq{ WHERE id = "$id"; } }

    my $ref = $dbh->selectall_arrayref( $sql );

    my %userTypes;
    foreach my $r ( @{$ref} ) { push @{$userTypes{$r->[0]}}, $r->[2]; }

    my $return;
    foreach my $r ( @{$ref} )
    {
       $return->{$r->[0]} = {'name'  => $r->[1],
                             'id'    => $r->[0],
                             'types' => $userTypes{$r->[0]}};
    }

    return $return;
}

sub GetRange
{
  my $self = shift;
 
  my $sql = qq{ SELECT max( time ) from reviews};
  my $reviews_max = $self->SimpleSqlGet( $sql );

  $sql = qq{ SELECT min( time ) from reviews};
  my $reviews_min = $self->SimpleSqlGet( $sql );

  $sql = qq{ SELECT max( time ) from historicalreviews where legacy=0};
  my $historicalreviews_max = $self->SimpleSqlGet( $sql );

  $sql = qq{ SELECT min( time ) from historicalreviews where legacy=0};
  my $historicalreviews_min = $self->SimpleSqlGet( $sql );

  my $max = $reviews_max;
  if ( $historicalreviews_max ge $reviews_max ) { $max = $historicalreviews_max; }

  my $min = $reviews_min;
  if ( $historicalreviews_min lt $reviews_min ) { $min = $historicalreviews_min; }
  
  my $max_year = $max;
  $max_year =~ s,(.*?)\-.*,$1,;

  my $max_month = $max;
  $max_month =~ s,.*?\-(.*?)\-.*,$1,;

  my $min_year = $min;
  $min_year =~ s,(.*?)\-.*,$1,;

  my $min_month = $min;
  $min_month =~ s,.*?\-(.*?)\-.*,$1,;
  
  return ( $max_year, $max_month, $min_year, $min_month );

}


sub GetTheYearMonth
{

   my $self = shift;

   my $newtime = scalar localtime(time());
   my $year = substr($newtime, 20, 4);

    my %months = (
                  "Jan" => "01",
                  "Feb" => "02",
                  "Mar" => "03",
                  "Apr" => "04",
                  "May" => "05",
                  "Jun" => "06",
                  "Jul" => "07",
                  "Aug" => "08",
                  "Sep" => "09",
                  "Oct" => "10",
                  "Nov" => "11",
                  "Dec" => "12",
                 );
   my $month = $months{substr ($newtime,4, 3)};

   return ( $year, $month );
}

# Convert a yearmonth-type string, e.g. '2009-08' to English: 'August 2009'
# Pass 1 as a second parameter to leave it long, otherwise truncates to 3-char abbreviation
sub YearMonthToEnglish
{
  my $self = shift;
  my $yearmonth = shift;
  my $long = shift;
  my %months = (  '01' => 'January',
                  '02' => 'February',
                  '03' => 'March',
                  '04' => 'April',
                  '05' => 'May',
                  '06' => 'June',
                  '07' => 'July',
                  '08' => 'August',
                  '09' => 'September',
                  '10' => 'October',
                  '11' => 'November',
                  '12' => 'December'
                );
  my ($year, $month) = split('-', $yearmonth);
  $month = $months{$month};
  return (($long)? $month:substr($month,0,3)).' '.$year;
}

# Returns a pair of date strings e.g. ('2009-01','2009-12') for the current year.
sub GetYear
{
  my $self = shift;
  my $ym = shift;
  my @range = $self->GetAllMonthsInYear($ym);
  return ($range[0], $range[-1]);
}

# Returns an array of date strings e.g. ('2009-01'...'2009-12') for the (current if no param) year.
sub GetAllMonthsInYear
{
  my $self = shift;
  my $ym = shift;
  my ( $year, $month );
  if ($ym) { ($year, $month) = split('-', $ym); }
  else { ($year, $month) = $self->GetTheYearMonth(); }
  my $start = ($year eq '2009')? 7:1;
  return map sprintf("$year-%.2d", $_), ($start..12)
}

# Returns an array of date strings e.g. ('2009-01','2010-01') with start month of all years for which we have data.
sub GetAllYears
{
  my $self = shift;
  
  # FIXME: use the GetRange function
  my $min = $self->SimpleSqlGet("SELECT MIN(time) FROM $CRMSGlobals::historicalreviewsTable WHERE legacy=0 AND user NOT LIKE 'rereport%'");
  my $max = $self->SimpleSqlGet("SELECT MAX(time) FROM $CRMSGlobals::historicalreviewsTable WHERE legacy=0");
  $min = substr($min,0,4);
  $max = substr($max,0,4);
  return ($min..$max);
}


sub CreateExportData
{
  my $self = shift;
  my $delimiter = shift;
  my $cumulative = shift;
  my $doCurrentMonth = shift;
  my $doPercent = shift;
  my $dbh = $self->get( 'dbh' );
  my $now = join('-', $self->GetTheYearMonth());
  my @statdates = ($cumulative)? $self->GetAllYears() : $self->GetAllMonthsInYear();
  my $y1 = substr($statdates[0],0,4);
  my $y2 = substr($statdates[-1],0,4);
  my $range = ($y1 eq $y2)? "$y1":"$y1-$y2";
  my $label = ($cumulative)? "CRMS&nbsp;Project&nbsp;Cumulative" : "Cumulative $range";
  my $report = sprintf("$label\nCategories%sGrand Total", $delimiter);
  my %stats = ();
  my @usedates = ();
  foreach my $date (@statdates)
  {
    last if $date gt $now;
    last if $date eq $now and !$doCurrentMonth;
    push @usedates, $date;
    $report .= "$delimiter$date";
    my %cats = ('pd/ren' => 0, 'pd/ncn' => 0, 'pd/cdpp' => 0, 'pdus/cdpp' => 0, 'ic/ren' => 0, 'ic/cdpp' => 0,
                'All PD' => 0, 'All IC' => 0, 'All UND/NFI' => 0,
                'Status 4' => 0, 'Status 6' => 0, 'Status 6' => 0);
    my $mintime = $date . '-01 00:00:00';
    my $maxtime = $date . '-31 23:59:59';
    my $sql = qq{SELECT attr,reason,status FROM $CRMSGlobals::historicalreviewsTable h1 WHERE } .
              qq{ time=(SELECT max(h2.time) FROM $CRMSGlobals::historicalreviewsTable h2 WHERE h1.id=h2.id) AND } .
              qq{ (status=4 OR status=5 OR status=6) AND legacy=0 AND time >= '$mintime' AND time <= '$maxtime'};
    my $rows = $dbh->selectall_arrayref( $sql );
    foreach my $row ( @{$rows} )
    {
      my $attr = int($row->[0]);
      my $reason = int($row->[1]);
      my $status = int($row->[2]);
      my $code = $self->GetCodeFromAttrReason($attr, $reason);
      my $cat = $self->GetAttrReasonCom($code);
      $cat = 'All UND/NFI' if $cat eq 'und/nfi';
      if (exists $cats{$cat} or $cat eq 'All UND/NFI')
      {
        $cats{$cat}++;
        my $allkey = 'All ' . uc substr($cat,0,2);
        $cats{$allkey}++ if exists $cats{$allkey};
      }
      $cat = 'Status '.$status;
      $cats{$cat}++;
    }
    for my $cat (keys %cats)
    {
      $stats{$cat}{$date} = $cats{$cat};
    }
  }
  $report .= "\n";
  my @titles = ('All PD', 'pd/ren', 'pd/ncn', 'pd/cdpp', 'pdus/cdpp', 'All IC', 'ic/ren', 'ic/cdpp', 'All UND/NFI', 'Total',
                'Status 4', 'Status 5', 'Status 6');
  my %monthTotals = ();
  my %catTotals = ('All PD' => 0, 'All IC' => 0, 'All UND/NFI' => 0);
  my $gt = 0;
  foreach my $date (@usedates)
  {
    my $monthTotal = $stats{'All PD'}{$date} + $stats{'All IC'}{$date} + $stats{'All UND/NFI'}{$date};
    $catTotals{'All PD'} += $stats{'All PD'}{$date};
    $catTotals{'All IC'} += $stats{'All IC'}{$date};
    $catTotals{'All UND/NFI'} += $stats{'All UND/NFI'}{$date};
    $monthTotals{$date} = $monthTotal;
    $gt += $monthTotal;
  }
  foreach my $title (@titles)
  {
    $report .= $title;
    my $total = 0;
    foreach my $date (@usedates)
    {
      my $n = 0;
      if ($title eq 'Total') { $n = $monthTotals{$date}; }
      else { $n = $stats{$title}{$date}; }
      $total += $n;
    }
    my $of = $gt;
    if ($title ne 'Total' && $doPercent)
    {
      my $pct = eval { 100.0*$total/$of; };
      $pct = 0.0 unless $pct;
      $total = sprintf("$total:%.1f", $pct);
    }
    $report .= $delimiter . $total;
    foreach my $date (@usedates)
    {
      my $n = 0;
      $of = $monthTotals{$date};
      if ($title eq 'Total') { $n = $monthTotals{$date}; }
      else
      {
        $n = $stats{$title}{$date};
        $n = 0 if !$n;
        if ($doPercent)
        {
          my $pct = eval { 100.0*$n/$of; };
          $pct = 0.0 unless $pct;
          $n = sprintf("$n:%.1f", $pct);
        }
      }
      $n = 0 if !$n;
      $report .= $delimiter . $n;
    }
    $report .= "\n";
  }
  return $report;
}

# Type arg is 0 for Monthly Breakdown, 1 for Total Determinations, 2 for cumulative (pie)
sub CreateExportGraph
{
  my $self = shift;
  my $type = int shift;
  
  return $self->CreateExportStatusGraph() if $type == 3;
  my $data = $self->CreateExportData(',', $type == 2, $type == 2);
  my @lines = split m/\n/, $data;
  my $title = shift @lines;
  $title .= '*' if $type == 2;
  $title =~ s/Cumulative/Monthly Breakdown/ if $type == 0;
  $title =~ s/Cumulative/Monthly Totals/ if $type == 1;
  my @dates = split(',', shift @lines);
  # Shift off the Categories and GT headers
  shift @dates; shift @dates;
  # Now the data is just the categories and numbers...
  my @titles = ($type == 1)? ('Total'):('All PD','All IC','All UND/NFI');
  my %titleh = ('All PD' => $lines[0],'All IC' => $lines[5],'All UND/NFI' => $lines[8],'Total' => $lines[9]);
  my @elements = ();
  my %colors = ('All PD' => '#22BB00', 'All IC' => '#FF2200', 'All UND/NFI' => '#0088FF', 'Total' => '#FFFF00');
  my %totals = ('All PD' => 0, 'All IC' => 0, 'All UND/NFI' => 0);
  my $ceiling = 100;
  my @totalline = split ',',$titleh{'Total'};
  shift @totalline;
  my $gt = shift @totalline;
  foreach my $title (@titles)
  {
    # Extract the total,n1,n2... data
    my @line = split(',',$titleh{$title});
    shift @line;
    my $total = int(shift @line);
    $totals{$title} = $total;
    foreach my $n (@line) { $ceiling = int($n) if int($n) > $ceiling && $type == 1; }
    my $color = $colors{$title};
    $title = 'Monthly Totals' if $type == 1;
    my $attrs = sprintf('"dot-style":{"type":"solid-dot","dot-size":3,"colour":"%s"},"text":"%s","colour":"%s","on-show":{"type":"pop-up","cascade":1,"delay":0.2}',
                        $color, $title, $color);
    my @vals = @line;
    if ($type == 0)
    {
      for (my $i = 0; $i < scalar @line; $i++)
      {
        my $pct = 0.0;
        eval { $pct = 100.0*$line[$i]/$totalline[$i]; };
        $line[$i] = $pct;
      }
      @vals = map(sprintf('{"value":%.1f,"tip":"%.1f%%"}', $_, $_),@line);
    }
    push @elements, sprintf('{"type":"line","values":[%s],%s}', join(',',@vals), $attrs);
  }
  # Round ceil up to nearest hundred
  $ceiling = 100 * POSIX::ceil($ceiling/100.0) if $type == 1;
  my $report = sprintf('{"bg_colour":"#000000","title":{"text":"%s","style":"{color:#FFFFFF;font-family:Helvetica;font-size:15px;font-weight:bold;text-align:center;}"},"elements":[',$title);
  if ($type == 2)
  {
    my @colorlist = ($colors{'All PD'}, $colors{'All IC'}, $colors{'All UND/NFI'});
    my @vals = ();
    map(push(@vals,sprintf('{"value":%s,"label":"%s\n%.1f%%"}', $totals{$_}, $_, 100.0*$totals{$_}/$gt)),@titles);
    $report .= sprintf('{"type":"pie","start-angle":35,"animate":[{"type":"fade"}],"gradient-fill":true,"colours":["%s"],"values":[%s]}]',
                       join('","',@colorlist),join(',',@vals));
  }
  else
  {
    @dates = map $self->YearMonthToEnglish($_), @dates;
    $report .= sprintf('%s]',join ',', @elements);
    $report .= sprintf(',"y_axis":{"max":%d,"steps":%d,"colour":"#888888","grid-colour":"#888888"%s}',
                       $ceiling, $ceiling/10,
                       ($type == 0)? ',"labels":{"text":"#val#%","colour":"#FFFFFF"}':',"labels":{"colour":"#FFFFFF"}');
    $report .= sprintf(',"x_axis":{"colour":"#888888","grid-colour":"#888888","labels":{"labels":["%s"],"rotate":40,"colour":"#FFFFFF"}}',
                       join('","',@dates));
  }
  $report .= '}';
  return $report;
}


sub CreateExportStatusReport
{
  my $self = shift;
  my @titles = ('4','5','6');
  my ($y,$m) = $self->GetTheYearMonth();
  my @dates = $self->GetWorkingDaysInRange();
  my $report = sprintf("<h2>Final&nbsp;Determinations&nbsp;Breakdown&nbsp;%s</h2><br/>\n", $self->YearMonthToEnglish("$y-$m"));
  $report .= "<table class='exportStats'>\n";
  $report .= "<tr><th/><th colspan='3'><span class='major'>Totals</span></th><th colspan='3'><span class='total'>Percentages</span></th></tr>\n";
  $report .= "<tr><th>Date</th><th>Status&nbsp;4</th><th>Status&nbsp;5</th><th>Status&nbsp;6</th><th>Status&nbsp;4</th><th>Status&nbsp;5</th><th>Status&nbsp;6</th></tr>\n";
  foreach my $date (@dates)
  {
    my ($y,$m,$d) = split '-', $date;
    my @line = (0,0,0,0,0,0);
    my $sql = "SELECT COUNT(DISTINCT id) FROM historicalreviews WHERE time>'$date 00:00:00' AND time<'$date 23:59:59';";
    my $total = $self->SimpleSqlGet($sql);
    for (my $i=0; $i < 3; $i++)
    {
      my $title = $titles[$i];
      $sql = "SELECT COUNT(DISTINCT id) FROM $CRMSGlobals::historicalreviewsTable h1 WHERE " .
             "status=$title AND legacy=0 AND time>'$date 00:00:00' AND time<'$date 23:59:59' AND " .
             "time=(SELECT MAX(h2.time) FROM $CRMSGlobals::historicalreviewsTable h2 WHERE h1.id=h2.id)";
      my $count = $self->SimpleSqlGet($sql);
      $line[$i] = $count;
      my $pct = 0.0;
      eval {$pct = 100.0*$count/$total;};
      $line[$i+3] = sprintf('%.1f%%', $pct);
    }
    $report .= sprintf('<tr><th>%s-%s</th>', $m, $d);
    for (my $i=0; $i < 6; $i++)
    {
      $report .= sprintf("<td class='%s'%s>%s</td>", ($i<3)? 'major':'total',($i==2)?' style="border-right:double 6px black"':'', $line[$i]);
    }
    $report .= "</tr>\n";
  }
  $report .= "</table>\n";
  return $report;
}


sub CreateExportStatusGraph
{
  my $self  = shift;
  
  my $report = '';
  my @dates = $self->GetAllMonthsInYear();
  my $title = 'Final Determinations by Expert Effort';
  my @titles = ('4','5','6');
  my @elements = ();
  my %colors = ('4' => '#22BB00', '5' => '#FF2200', '6' => '#0088FF');
  my $ceiling = 0;
  foreach my $title (@titles)
  {
    my @line = ();
    my $color = $colors{$title};
    my $attrs = sprintf('"dot-style":{"type":"solid-dot","dot-size":3,"colour":"%s"},"text":"Status %s","colour":"%s","on-show":{"type":"pop-up","cascade":1,"delay":0.2}',
                        $color, $title, $color);
    foreach my $date (@dates)
    {
      my $sql = "SELECT COUNT(DISTINCT id) FROM $CRMSGlobals::historicalreviewsTable h1 WHERE " .
                "status=$title AND legacy=0 AND time>'$date-01 00:00:00' AND time<'$date-31 23:59:59' AND " .
                "time=(SELECT MAX(h2.time) FROM $CRMSGlobals::historicalreviewsTable h2 WHERE h1.id=h2.id)";
      my $count = $self->SimpleSqlGet($sql);
      push @line, $count;
      $ceiling = $count if $count > $ceiling;
    }
    my @vals = map(sprintf('{"value":%d}', $_),@line);
    push @elements, sprintf('{"type":"line","values":[%s],%s}', join(',',@vals), $attrs);
  }
  # Round ceil up to nearest hundred
  $ceiling = 100 * POSIX::ceil($ceiling/100.0);
  my $report = sprintf('{"bg_colour":"#000000","title":{"text":"%s","style":"{color:#FFFFFF;font-family:Helvetica;font-size:15px;font-weight:bold;text-align:center;}"},"elements":[',$title);
  $report .= sprintf('%s]',join ',', @elements);
  $report .= sprintf(',"y_axis":{"max":%d,"colour":"#888888","grid-colour":"#888888","labels":{"colour":"#FFFFFF"}}',$ceiling);
  $report .= sprintf(',"x_axis":{"colour":"#888888","grid-colour":"#888888","labels":{"labels":["%s"],"rotate":40,"colour":"#FFFFFF"}}',
                     join('","',map {$self->YearMonthToEnglish($_)} @dates));
  $report .= '}';
  return $report;
}

sub GetWorkingDaysInRange
{
  my $self  = shift;
  my $start = shift;
  my $end   = shift;
  
  my ($y,$m,$d) = Today();
  my $today = join '-', ($y,sprintf('%02d',$m),sprintf('%02d',$d));
  if (!$start || !$end)
  {
    $start = join '-', ($y,$m,'01');
    $end = join '-', ($y,$m,Days_in_Month($y, $m));
  }
  my @days = ();
  while ($start le $end)
  {
    my ($y,$m,$d) = split '-', $start;
    my $dow = Day_of_Week($y, $m, $d);
    push @days, $start if $dow <= 5;
    $start = $self->SimpleSqlGet("SELECT DATE_ADD('$start', INTERVAL 1 DAY)");
    last if $start gt $today;
  }
  return @days;
}

# Create an HTML table for the whole year's exports, month by month.
# If cumulative, columns are years, not months.
sub CreateExportReport
{
  my $self = shift;
  my $cumulative = shift;
  my $dbh = $self->get( 'dbh' );
  my $data = $self->CreateExportData(',', $cumulative, 1, 1);
  my @lines = split m/\n/, $data;
  my $nbsps = '&nbsp;&nbsp;&nbsp;&nbsp;';
  my $dllink = sprintf(qq{$nbsps<a target="_blank" href="/cgi/c/crms/getExportStats?type=text&amp;c=%d">Download</a>}, $cumulative);
  my $title = shift @lines;
  $title .= '*' if $cumulative;
  my $report = sprintf("<h3>%s$dllink</h3>\n<table class='exportStats'>\n<tr>\n", $title);
  foreach my $th (split ',', shift @lines)
  {
    $th = $self->YearMonthToEnglish($th) if $th =~ m/^\d.*/;
    $th =~ s/\s/&nbsp;/g;
    $report .= sprintf("<th%s>$th</th>\n", ($th ne 'Categories')? ' style="text-align:center;"':'');
  }
  $report .= "</tr>\n";
  my %majors = ('All PD' => 1, 'All IC' => 1, 'All UND/NFI' => 1);
  foreach my $line (@lines)
  {
    $report .= '<tr>';
    my @items = split(',', $line);
    my $i = 0;
    $title = shift @items;
    my $major = exists $majors{$title};
    $title =~ s/\s/&nbsp;/g;
    my $padding = ($major)? '':$nbsps;
    $report .= sprintf("<th%s><span%s>%s$title</span></th>",
      ($title eq 'Total')? ' style="text-align:right;"':'',
      ($major)? ' class="major"':(($title =~ m/Status.+/)? ' class="minor"':''),
      ($major)? '':$nbsps);
    foreach my $item (@items)
    {
      my ($n,$pct) = split ':', $item;
      $n =~ s/\s/&nbsp;/g;
      $report .= sprintf("<td%s>%s%s$n%s%s</td>",
                         ($major)? ' class="major"':($title eq 'Total')? ' style="text-align:center;"':(($title =~ m/Status.+/)? ' class="minor"':''),
                         ($major)? '':$nbsps,
                         ($title eq 'Total')? '<b>':'',
                         ($title eq 'Total')? '</b>':'',
                         ($pct)? "&nbsp;($pct%)":'');
      $i++;
    }
    $report .= "</tr>\n";
  }
  $report .= "</table>\n";
  return $report;
}

sub CreateStatsData
{
  my $self = shift;
  my $user = shift;
  my $cumulative = shift;
  my $dbh = $self->get( 'dbh' );
  my $now = join('-', $self->GetTheYearMonth());
  my @statdates = ($cumulative)? $self->GetAllYears() : $self->GetAllMonthsInYear();
  my $y1 = substr($statdates[0],0,4);
  my $y2 = substr($statdates[-1],0,4);
  my $range = ($y1 eq $y2)? "$y1":"$y1-$y2";
  my $username = ($user eq 'all')? 'All Users':$self->GetUserName($user);
  my $label = "$username: " . (($cumulative)? "CRMS&nbsp;Project&nbsp;Cumulative":"Cumulative $range");
  my $report = "$label\nCategories,Grand Total";
  my %stats = ();
  my @usedates = ();
  my $earliest = '';
  my $latest = '';
  my @titles = ('All PD', 'pd/ren', 'pd/ncn', 'pd/cdpp', 'pdus/cdpp', 'All IC', 'ic/ren', 'ic/cdpp', 'All UND/NFI',
                '__TOT__', '__TOTNE__', '__VAL__', '__MVAL__',
                'Time Reviewing (mins)', 'Time per Review (mins)','Reviews per Hour', 'Outlier Reviews');
  foreach my $date (@statdates)
  {
    last if $date gt $now;
    push @usedates, $date;
    $report .= ",$date";
    my $mintime = $date . (($cumulative)? '-01':'');
    my $maxtime = $date . (($cumulative)? '-12':'');
    $earliest = $mintime if $earliest eq '' or $mintime lt $earliest;
    $latest = $maxtime if $latest eq '' or $maxtime gt $latest;
    my $sql = qq{SELECT SUM(total_pd_ren) + SUM(total_pd_cnn) + SUM(total_pd_cdpp) + SUM(total_pdus_cdpp),
                 SUM(total_pd_ren), SUM(total_pd_cnn), SUM(total_pd_cdpp), SUM(total_pdus_cdpp),
                 SUM(total_ic_ren) + SUM(total_ic_cdpp),
                 SUM(total_ic_ren), SUM(total_ic_cdpp), SUM(total_und_nfi), SUM(total_reviews), 1,1,1, SUM(total_time),
                 SUM(total_time)/(SUM(total_reviews)-SUM(total_outliers)),
                 (SUM(total_reviews)-SUM(total_outliers))/SUM(total_time)*60.0, SUM(total_outliers)
                 FROM userstats WHERE monthyear >= '$mintime' AND monthyear <= '$maxtime'};
    $sql .= " AND user='$user'" if $user ne 'all';
    #print "$sql<br/>\n";
    my $rows = $dbh->selectall_arrayref( $sql );
    foreach my $row ( @{$rows} )
    {
      my $i = 0;
      foreach my $title (@titles)
      {
        $stats{$title}{$date} = $row->[$i];
        $i++;
      }
    }
    my ($ok,$oktot) = $self->CountCorrectReviews($user, $mintime . '-01 00:00:00', $maxtime . '-31 23:59:59');
    $stats{'__VAL__'}{$date} = $ok;
    $stats{'__TOTNE__'}{$date} = $oktot;
    $stats{'__MVAL__'}{$date} = $self->GetMedianCorrect($mintime . '-01 00:00:00', $maxtime . '-31 23:59:59');
  }
  $report .= "\n";
  my %totals;
  #my %totals = ('All PD' => 0, 'pd/ren' => 0, 'pd/ncn' => 0, 'pd/cdpp' => 0, 'pdus/cdpp' => 0,
  #              'All IC' => 0, 'ic/ren' => 0, 'ic/cdpp' => 0, 'All UND/NFI' => 0, 'Total' => 0,
  #              'Time Reviewing (mins)' => 0, 'Time per Review (mins)' => 0,
  #              'Reviews per Hour' => 0, 'Outlier Reviews' => 0, 'Validated Reviews' => 0);
  my $sql = qq{SELECT SUM(total_pd_ren) + SUM(total_pd_cnn) + SUM(total_pd_cdpp) + SUM(total_pdus_cdpp),
               SUM(total_pd_ren), SUM(total_pd_cnn), SUM(total_pd_cdpp), SUM(total_pdus_cdpp),
               SUM(total_ic_ren) + SUM(total_ic_cdpp),
               SUM(total_ic_ren), SUM(total_ic_cdpp), SUM(total_und_nfi), SUM(total_reviews), 1,1,1, SUM(total_time),
               SUM(total_time)/(SUM(total_reviews)-SUM(total_outliers)),
               (SUM(total_reviews)-SUM(total_outliers))/SUM(total_time)*60.0, SUM(total_outliers)
               FROM userstats WHERE monthyear >= '$earliest' AND monthyear <= '$latest'};
  $sql .= " AND user='$user'" if $user ne 'all';
  my $rows = $dbh->selectall_arrayref( $sql );
  foreach my $row ( @{$rows} )
  {
    my $i = 0;
    foreach my $title (@titles)
    {
      $totals{$title} = $row->[$i];
      $i++;
    }
  }
  my ($ok,$oktot) = $self->CountCorrectReviews($user, $earliest . '-01 00:00:00', $latest . '-31 23:59:59');
  $totals{'__VAL__'} = $ok;
  $totals{'__TOTNE__'} = $oktot;
  $totals{'__MVAL__'} = $self->GetMedianCorrect($earliest . '-01 00:00:00', $latest . '-31 23:59:59');
  my %majors = ('All PD' => 1, 'All IC' => 1, 'All UND/NFI' => 1);
  my %minors = ('Time Reviewing (mins)' => 1, 'Time per Review (mins)' => 1,
                'Reviews per Hour' => 1, 'Outlier Reviews' => 1);
  foreach my $title (@titles)
  {
    $report .= $title;
    my $of = $totals{'__TOT__'};
    $of = $totals{'__TOTNE__'} if $title eq '__VAL__';
    my $n = $totals{$title};
    $n = 0 unless $n;
    if ($title eq '__MVAL__')
    {
      $n = sprintf('%.1f%%', $n);
    }
    elsif ($title ne '__TOT__' && !exists $minors{$title})
    {
      my $pct = eval { 100.0*$n/$of; };
      $pct = 0.0 unless $pct;
      $n = sprintf("$n:%.1f", $pct);
    }
    else
    {
      $n = sprintf('%.1f', $n) if $n =~ m/^\d*\.\d+$/i;
    }
    $report .= ',' . $n;
    foreach my $date (@usedates)
    {
      $n = $stats{$title}{$date};
      $n = 0 if !$n;
      if ($title eq '__MVAL__')
      {
        $n = sprintf('%.1f%%', $n);
      }
      elsif ($title ne '__TOT__' && !exists $minors{$title})
      {
        $of = $stats{'__TOT__'}{$date};
        $of = $stats{'__TOTNE__'}{$date} if $title eq '__VAL__';
        my $pct = eval { 100.0*$n/$of; };
        $pct = 0.0 unless $pct;
        $n = sprintf("$n:%.1f", $pct);
      }
      else
      {
        $n = sprintf('%.1f', $n) if $n =~ m/^\d*\.\d+$/i;
      }
      $n = 0 if !$n;
      $report .= ',' . $n;
      #print "$user $title $n $of\n";
    }
    $report .= "\n";
  }
  return $report;
}

sub CreateStatsReport
{
  my $self = shift;
  my $user = shift;
  my $cumulative = shift;
  my $suppressBreakdown = shift;
  my $data = $self->CreateStatsData($user, $cumulative);
  my @lines = split m/\n/, $data;
  my $report = sprintf("<h3>%s</h3>\n<table class='exportStats'>\n<tr>\n", shift @lines);
  my $nbsps = '&nbsp;&nbsp;&nbsp;&nbsp;';
  foreach my $th (split ',', shift @lines)
  {
    $th = $self->YearMonthToEnglish($th) if $th =~ m/^\d.*/;
    $th =~ s/\s/&nbsp;/g;
    $report .= sprintf("<th%s>$th</th>\n", ($th ne 'Categories')? ' style="text-align:center;"':'');
  }
  $report .= "</tr>\n";
  my %majors = ('All PD' => 1, 'All IC' => 1, 'All UND/NFI' => 1);
  my %minors = ('Time Reviewing (mins)' => 1, 'Time per Review (mins)' => 1, 'Average Time per Review (mins)' => 1,
                'Reviews per Hour' => 1, 'Average Reviews per Hour' => 1, 'Outlier Reviews' => 1);
  my $exp = $self->IsUserExpert($user);
  foreach my $line (@lines)
  {
    my @items = split(',', $line);
    my $title = shift @items;
    next if $title eq '__VAL__'  and ($exp);
    next if $title eq '__MVAL__' and ($exp);
    next if $title eq '__TOTNE__' and ($user ne 'all' and !$cumulative);
    next if ($cumulative or $user eq 'all' or $suppressBreakdown) and !exists $majors{$title} and !exists $minors{$title} and $title !~ m/__.+?__/;
    my $class = (exists $majors{$title})? 'major':(exists $minors{$title})? 'minor':'';
    $class = 'total' if $title =~ m/__.+?__/;
    $report .= '<tr>';
    $title =~ s/\s/&nbsp;/g;
    my $padding = ($class eq 'major' || $class eq 'minor' || $class eq 'total')? '':$nbsps;
    $report .= sprintf("<th%s><span%s>%s$title</span></th>",
                       ($title =~ m/__.+?__/)? ' style="text-align:right;"':'',
                       ($class)? " class='$class'":'',
                       $padding);
    foreach my $item (@items)
    {
      my ($n,$pct) = split ':', $item;
      $n =~ s/\s/&nbsp;/g;
      $report .= sprintf("<td%s%s>%s%s%s</td>",
                         ($class)? " class='$class'":'',
                         ($title =~ m/__.+?__/ || $class eq 'minor')? ' style="text-align:center;"':'',
                         $padding,
                         ($title eq '__TOT__')? "<b>$n</b>":$n,
                         ($pct)? "&nbsp;($pct%)":'');
    }
    $report .= "</tr>\n";
  }
  $report .= "</table>\n";
  $report =~ s/__TOT__/All&nbsp;Reviews*/;
  $report =~ s/__TOTNE__/Non-Expert&nbsp;Reviews/;
  my $vtitle = 'Validated&nbsp;Reviews&nbsp;&amp;&nbsp;Rate';
  $report =~ s/__VAL__/$vtitle/;
  my $mvtitle = 'Median&nbsp;Validation&nbsp;Rate';
  $report =~ s/__MVAL__/$mvtitle/;
  return $report;
}


sub UpdateStats
{
    my $self = shift;

    my $dbh = $self->get( 'dbh' );

    my $sql = qq{DELETE from userstats};
    $self->PrepareSubmitSql( $sql );

    my @users = map {$_->[0]} @{$dbh->selectall_arrayref( "SELECT distinct id FROM users" )};

    my ( $max_year, $max_month, $min_year, $min_month ) = $self->GetRange();

    my $go = 1;
    my $max_date = qq{$max_year-$max_month};
    while ( $go )
    {
      my $statDate = qq{$min_year-$min_month};
      
      foreach my $user ( @users )
      {
        $self->GetMonthStats( $user, $statDate );
      }

      $min_month = $min_month + 1;
      if ( $min_month == 13 )
      {
        $min_month = 1;
        $min_year = $min_year + 1;
      }

      if ( $min_month < 10 )
      {
        $min_month = qq{0$min_month};
      }

      my $new_test_date = qq{$min_year-$min_month};
      if ( $new_test_date gt $max_date )
      {
        $go = 0;
      }
    }
}


sub GetMonthStats
{
  my $self = shift;
  my $user = shift;
  my $start_date = shift;

  my $dbh = $self->get( 'dbh' );

  my $sql = qq{ SELECT count(*) FROM historicalreviews WHERE user='$user' and legacy=0 and time like '$start_date%'};
  my $total_reviews_toreport = $self->SimpleSqlGet( $sql );

  #pd/ren
  $sql = qq{ SELECT count(*) FROM historicalreviews WHERE user='$user' and legacy=0 and attr=1 and reason=7 and time like '$start_date%'};
  my $total_pd_ren = $self->SimpleSqlGet( $sql );

  #pd/ncn
  $sql = qq{ SELECT count(*) FROM historicalreviews WHERE user='$user' and legacy=0 and attr=1 and reason=2 and time like '$start_date%'};
  my $total_pd_cnn = $self->SimpleSqlGet( $sql );

  #pd/cdpp
  $sql = qq{ SELECT count(*) FROM historicalreviews WHERE user='$user' and legacy=0 and attr=1 and reason=9 and time like '$start_date%'};
  my $total_pd_cdpp = $self->SimpleSqlGet( $sql );

  #ic/ren
  $sql = qq{ SELECT count(*) FROM historicalreviews WHERE user='$user' and legacy=0 and attr=2 and reason=7 and time like '$start_date%'};
  my $total_ic_ren = $self->SimpleSqlGet( $sql );

  #ic/cdpp
  $sql = qq{ SELECT count(*) FROM historicalreviews WHERE user='$user' and legacy=0 and attr=2 and reason=9 and time like '$start_date%'};
  my $total_ic_cdpp = $self->SimpleSqlGet( $sql );

  #pdus/cdpp
  $sql = qq{ SELECT count(*) FROM historicalreviews WHERE user='$user' and legacy=0 and attr=9 and reason=9 and time like '$start_date%'};
  my $total_pdus_cdpp = $self->SimpleSqlGet( $sql );

  #und/nfi
  $sql = qq{ SELECT count(*) FROM historicalreviews WHERE user='$user' and legacy=0 and attr=5 and reason=8 and time like '$start_date%'};
  my $total_und_nfi = $self->SimpleSqlGet( $sql );

  my $total_time = 0;
  
  #time reviewing ( in minutes ) - not including outliers
  $sql = qq{ SELECT duration FROM historicalreviews WHERE user='$user' and legacy=0 and time like '$start_date%' and duration <= '00:05:00'};
  my $rows = $dbh->selectall_arrayref( $sql );

  foreach my $row ( @{$rows} )
  {
    my $duration = $row->[0];
    #convert to minutes:
    my $min = $duration;
    $min =~ s,.*?:(.*?):.*,$1,;
    
    my $sec = $duration;
    $sec =~ s,.*?:.*?:(.*),$1,;
    $sec += (60*$min);
    $total_time += $sec;
  }

  $total_time = $total_time/60;

  #total outliers
  $sql = qq{ SELECT count(*) FROM historicalreviews WHERE user='$user' and legacy=0 and time like '$start_date%' and duration > '00:05:00'};
  my $total_outliers = $self->SimpleSqlGet( $sql );

  my $time_per_review = 0;
  if ( $total_reviews_toreport - $total_outliers > 0)
  {  $time_per_review = ($total_time/($total_reviews_toreport - $total_outliers));}
  
  my $reviews_per_hour = 0;
  if ( $time_per_review > 0 )
  { $reviews_per_hour = (60/$time_per_review);}

  my $year = $start_date;
  $year =~ s,(.*)\-.*,$1,;
  my $month = $start_date;
  $month =~ s,.*\-(.*),$1,;
  my $sql = qq{ INSERT INTO userstats (user, month, year, monthyear, total_reviews, total_pd_ren, total_pd_cnn, total_pd_cdpp, total_pdus_cdpp, total_ic_ren, total_ic_cdpp, total_und_nfi, total_time, time_per_review, reviews_per_hour, total_outliers) VALUES ('$user', '$month', '$year', '$start_date', $total_reviews_toreport, $total_pd_ren, $total_pd_cnn, $total_pd_cdpp, $total_pdus_cdpp, $total_ic_ren, $total_ic_cdpp, $total_und_nfi, $total_time, $time_per_review, $reviews_per_hour, $total_outliers )};
  
  $self->PrepareSubmitSql( $sql );
}


sub GetUserTypes
{
    my $self = shift;
    my $name = shift;

    my $sql = qq{SELECT type FROM $CRMSGlobals::usersTable WHERE id = "$name"};
    my $ref = $self->get( 'dbh' )->selectall_arrayref( $sql );

    my @return;
    foreach ( @{$ref} ) { push (@return, $_->[0]); }
    return @return;
}

sub AddUser
{
    my $self = shift;
    my $args = shift;

    my $dSql = qq|DELETE FROM $CRMSGlobals::usersTable WHERE id = "$args->{'id'}"|;
    $self->PrepareSubmitSql( $dSql );

    if ( $args->{'delete'} ) { return 1; }  ## stop at deleting

    my $sql = qq|REPLACE INTO $CRMSGlobals::usersTable SET id = "$args->{'id'}" | .
              qq|, name = "$args->{'name'}"|;

    if ( $args->{'reviewer'} )
    {
        $self->PrepareSubmitSql( $sql . qq{, type = 1} );
    }
    if ( $args->{'expert'} )
    {
        $self->PrepareSubmitSql( $sql . qq{, type = 2} );
    }
    if ( $args->{'admin'} )
    {
        $self->PrepareSubmitSql( $sql . qq{, type = 3} );
    }

    return 1;
}

sub CheckRenDate
{
  my $self = shift;
  my $renNum = shift;
  my $renDate = shift;

  my $errorMsg = '';

  if ( $renDate )
  {
    if ( $renDate =~ /^\d{1,2}[A-Za-z]{3}\d{2}$/ )
    {
      $renDate =~ s,\w{5}(.*),$1,;
      $renDate = qq{19$renDate};

      if ( $renDate < 1950 )
      {
        $errorMsg .= "The Ren Date you have entered ($renDate) is before 1950; we should not be recording them.";
      }
      if ( ( $renDate >= 1950 )  && ( $renDate <= 1953 ) )
      {
        if ( ( $renNum =~ m,^R\w{5}$, ) || ( $renNum =~ m,^R\w{6}$, ))
        {}
        else
        {
          $errorMsg .= 'Ren number format is not correct for item in  1950 - 1953 range.';
        }
      }
      if ( $renDate >= 1978 )
      {
        if ( $renNum =~ m,^RE\w{6}$, )
        {}
        else
        {
          $errorMsg .= 'Ren Number format is not correct for item with Ren Date >= 1978.';
        }
      }
    }
    else
    {
      $errorMsg .= 'Ren Date is not of the right format, for example 17Dec73.';
    }
  }
  return $errorMsg;
}


sub HasItemBeenReviewedByTwoReviewers
{
  my $self = shift;
  my $id   = shift;
  my $user = shift;

  my $msg = '0';
  if ( $self->IsUserExpert( $user ) )
  {
    if ($self->HasItemBeenReviewedByAnotherExpert($id,$user) && $self->GetItemPriority($id) == 0)
    {
      $msg = 'This volume does not need to be reviewed. An expert has already reviewed it. Please Cancel.';
    }
  }
  else
  {
    my $sql = qq{ SELECT count(*) FROM $CRMSGlobals::reviewsTable WHERE id ='$id' AND user != '$user'};
    my $count = $self->SimpleSqlGet( $sql );
    if ($count >= 2 )
    {
      $msg = 'This volume does not need to be reviewed. Two reviewers or an expert have already reviewed it. Please Cancel.';
    }
    $sql = qq{ SELECT count(*) FROM $CRMSGlobals::queueTable WHERE id ='$id' AND status!=0 };
    $count = $self->SimpleSqlGet( $sql );
    if ($count >= 1 ) { $msg = 'This item has been processed already. Please Cancel.'; }
  }
  return $msg;
}


sub ValidateSubmission2
{
    my $self = shift;
    my ($attr, $reason, $note, $category, $renNum, $renDate, $user) = @_;
    my $errorMsg = '';

    my $noteError = 0;

    ## check user
    if ( ! $self->IsUserReviewer( $user ) )
    {
        $errorMsg .= qq{Not a reviewer.  };
    }

    if ( ( ! $attr ) || ( ! $reason ) )
    {
      $errorMsg .= 'rights/reason designation required.';
    }


    ## und/nfi
    if ( $attr == 5 && $reason == 8 && ( ( ! $note ) || ( ! $category ) )  )
    {
        $errorMsg .= 'und/nfi must include note category and note text.';
        $noteError = 1;
    }

    ## ic/ren requires a ren number
    if ( $attr == 2 && $reason == 7 && ( ( ! $renNum ) || ( ! $renDate ) )  )
    {
        $errorMsg .= 'ic/ren must include renewal id and renewal date.';
    }
    elsif ( $attr == 2 && $reason == 7 )
    {
        $renDate =~ s,.*[A-Za-z](.*),$1,;
        $renDate = '19' . $renDate;

        if ( $renDate < 1950 )
        {
           $errorMsg .= "renewal has expired; volume is pd. date entered is $renDate";
        }
    }

    ## pd/ren requires a ren number
    if ( $attr == 1 && $reason == 7 &&  ( ( $renNum ) || ( $renDate ) )  )
    {
        $errorMsg .= 'pd/ren should not include renewal info.';
    }

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

    if ( $attr == 1 && $reason == 9 && ( ( ! $note ) || ( ! $category )  )  )
    {
        $errorMsg .= 'pd/cdpp must include note category and note text.';
        $noteError = 1;
    }

    ## ic/cdpp requires a ren number
    if (  $attr == 2 && $reason == 9 && ( ( $renNum ) || ( $renDate ) ) )
    {
        $errorMsg .= qq{ic/cdpp should not include renewal info.  };
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
        $errorMsg .= 'must include a note if there is a category.';
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


sub ValidateAttr
{
    my $self    = shift;
    my $attr    = shift;
    
    my $sdr_dbh = $self->get( 'sdr_dbh' );

    my $rows = $sdr_dbh->selectall_arrayref( "SELECT id FROM attributes" );
    
    foreach my $row ( @{$rows} )
    {
        if ( $row->[0] eq $attr ) { return 1; }
    }
    $self->SetError( "bad attr: $attr" );
    return 0;
}

sub ValidateReason
{
    my $self    = shift;
    my $reason  = shift;
    my $sdr_dbh = $self->get( 'sdr_dbh' );
    
    my $rows = $sdr_dbh->selectall_arrayref( "SELECT id FROM reasons" );
    
    foreach my $row ( @{$rows} )
    {
        if ( $row->[0] eq $reason ) { return 1; }
    }
    $self->SetError( "bad reason: $reason" );
    return 0;
}

sub GetCopyrightPage
{
    my $self = shift;
    my $id   = shift;

    ## this is a place holder.  The HT API should be able to do this soon.

    return "7";
}

sub IsGovDoc
{
    my $self    = shift;
    my $barcode = shift;
    my $record  = shift;

    if ( ! $record ) { $self->Logit( "failed in IsGovDoc: $barcode" ); }

    my $xpath   = q{//*[local-name()='controlfield' and @tag='008']};
    my $leader  = $record->findvalue( $xpath );
    my $doc     = substr($leader, 28, 1);
 
    if ( $doc eq "f" ) { return 1; }

    return 0;
}

sub IsUSPub
{
    my $self    = shift;
    my $barcode = shift;
    my $record  = shift;

    if ( ! $record ) { $self->Logit( "failed in IsUSPub: $barcode" ); }

    my $xpath   = q{//*[local-name()='controlfield' and @tag='008']};
    my $leader  = $record->findvalue( $xpath );
    my $doc     = substr($leader, 17, 1);
 
    if ( $doc eq "u" ) { return 1; }

    return 0;
}


sub IsFormatBK
{
    my $self    = shift;
    my $barcode = shift;
    my $record  = shift;

    if ( ! $record ) { $self->Logit( "failed in IsFormatBK: $barcode" ); }

    my $xpath   = q{//*[local-name()='controlfield' and @tag='FMT']};
    my $leader  = $record->findvalue( $xpath );
    my $doc     = $leader;
 
    if ( $doc eq "BK" ) { return 1; }

    return 0;
}

## ----------------------------------------------------------------------------
##  Function:   get the publ date (260|c)for a specific vol.
##  Parameters: barcode
##  Return:     date string
## ----------------------------------------------------------------------------
sub GetPublDate
{
    my $self    = shift;
    my $barcode = shift;
    my $record  = shift;

    if ( ! $record )
    {
      $record = $self->GetRecordMetadata($barcode);
    }

    if ( ! $record ) { return 0; }

    ## my $xpath = q{//*[local-name()='oai_marc']/*[local-name()='fixfield' and @id='008']};
    my $xpath   = q{//*[local-name()='controlfield' and @tag='008']};
    my $leader  = $record->findvalue( $xpath );
    my $pubDateType = substr($leader, 6, 1);
    my $pubDate = substr($leader, 7, 4);
    # On questionable pub date, try date 2 field.
    if ($pubDateType eq 'q' && ($pubDate eq '||||' || $pubDate eq '####' || $pubDate eq '^^^^'))
    {
      $pubDate = substr($leader, 11, 4);
    }
    return $pubDate;
}

sub GetPubLanguage
{
    my $self    = shift;
    my $barcode = shift;
    my $record  = shift;

    if ( ! $record )
    {
      $record = $self->GetRecordMetadata($barcode);
    }

    if ( ! $record ) { return 0; }

    ## my $xpath = q{//*[local-name()='oai_marc']/*[local-name()='fixfield' and @id='008']};
    my $xpath   = q{//*[local-name()='controlfield' and @tag='008']};
    my $leader  = $record->findvalue( $xpath );
    return substr($leader, 35, 3);
}

sub GetMarcFixfield
{
    my $self    = shift;
    my $barcode = shift;
    my $field   = shift;

    my $record = $self->GetRecordMetadata($barcode);
    if ( ! $record ) { $self->Logit( "failed in GetMarcFixfield: $barcode" ); }

    my $xpath = qq{//*[local-name()='oai_marc']/*[local-name()='fixfield' and \@id='$field']};
    return $record->findvalue( $xpath );
}

sub GetMarcVarfield
{
    my $self    = shift;
    my $barcode = shift;
    my $field   = shift;
    my $label   = shift;
    
    my $record = $self->GetRecordMetadata($barcode);
    if ( ! $record ) { $self->Logit( "failed in GetMarcVarfield: $barcode" ); }

    my $xpath = qq{//*[local-name()='oai_marc']/*[local-name()='varfield' and \@id='$field']} .
                qq{/*[local-name()='subfield' and \@label='$label']};

    return $record->findvalue( $xpath );
}

sub GetMarcControlfield
{
    my $self    = shift;
    my $barcode = shift;
    my $field   = shift;
    
    my $record = $self->GetRecordMetadata($barcode);
    if ( ! $record ) { $self->Logit( "failed in GetMarcControlfield: $barcode" ); }

    my $xpath = qq{//*[local-name()='controlfield' and \@tag='$field']};
    return $record->findvalue( $xpath );
}

sub GetMarcDatafield
{
    my $self    = shift;
    my $barcode = shift;
    my $field   = shift;
    my $code    = shift;

    my $record = $self->GetRecordMetadata($barcode);
    if ( ! $record ) { $self->Logit( "failed in GetMarcDatafield: $barcode" ); }

    my $xpath = qq{//*[local-name()='datafield' and \@tag='$field']} .
                qq{/*[local-name()='subfield'  and \@code='$code']};

    my $data;
    eval{ $data = $record->findvalue( $xpath ); };
    if ($@) { $self->Logit( "failed to parse metadata: $@" ); }
    
    return $data
}

sub GetMarcDatafieldAuthor
{
    my $self    = shift;
    my $barcode = shift;

    #After talking to Tim, the author info is in the 1XX field
    #Margrte told me that the only 1xx fields are: 100, 110, 111, 130. 700, 710
    
    my $record = $self->GetRecordMetadata($barcode);
    if ( ! $record ) { $self->Logit( "failed in GetMarcDatafieldAuthor: $barcode" ); }

    my $data;

    my $xpath = qq{//*[local-name()='datafield' and \@tag='100']};
    eval{ $data .= $record->findvalue( $xpath ); };
    if ($@) { $self->Logit( "failed to parse metadata: $@" ); }

    my $xpath = qq{//*[local-name()='datafield' and \@tag='110']};
    eval{ $data .= $record->findvalue( $xpath ); };
    if ($@) { $self->Logit( "failed to parse metadata: $@" ); }

    my $xpath = qq{//*[local-name()='datafield' and \@tag='111']};
    eval{ $data .= $record->findvalue( $xpath ); };
    if ($@) { $self->Logit( "failed to parse metadata: $@" ); }

    my $xpath = qq{//*[local-name()='datafield' and \@tag='130']};
    eval{ $data .= $record->findvalue( $xpath ); };
    if ($@) { $self->Logit( "failed to parse metadata: $@" ); }

    my $xpath = qq{//*[local-name()='datafield' and \@tag='700']};
    eval{ $data .= $record->findvalue( $xpath ); };
    if ($@) { $self->Logit( "failed to parse metadata: $@" ); }

    my $xpath = qq{//*[local-name()='datafield' and \@tag='710']};
    eval{ $data .= $record->findvalue( $xpath ); };
    if ($@) { $self->Logit( "failed to parse metadata: $@" ); }

   
    $data =~ s,\n,,gs;

    return $data
}

sub GetEncTitle
{
    my $self = shift;
    my $bar  = shift;

    my $ti = $self->GetTitle( $bar );

    #good for the title
    $ti =~ s,(.*\w).*,$1,;

    $ti =~ s,\',\\\',g; ## escape '
    return $ti;
}

sub GetTitle
{
    my $self = shift;
    my $id   = shift;

    my $sql = qq{ SELECT title FROM bibdata WHERE id="$id" };
    my $ti = $self->SimpleSqlGet( $sql );

    if ( $ti eq '' ) { $ti = $self->UpdateTitle($id); }

    #good for the title
    $ti =~ s,(.*\w).*,$1,;

    return $ti;
}

sub GetPubDate
{
    my $self = shift;
    my $id   = shift;

    my $sql = qq{ SELECT YEAR(pub_date) FROM bibdata WHERE id="$id" };
    my $date = $self->SimpleSqlGet( $sql );
    $date = 'unknown' unless $date;
    return $date;
}

sub UpdateTitle
{
  my $self  = shift;
  my $id    = shift;
  my $title = shift;
  
  if ($id eq '')
  {
    $self->SetError("Trying to update title for empty volume id!\n");
    $self->Logit("$0: trying to update title for empty volume id!\n");
  }
  if ( ! $title )
  {
    ## my $ti = $self->GetMarcDatafield( $id, "245", "a");
    $title = $self->GetRecordTitleBc2Meta( $id );
  }
  if ($self->Mojibake($title))
  {
    $self->Logit("$0: Mojibake title <<$title>> for $id!\n");
  }
  my $tiq = $self->get('dbh')->quote( $title );
  if ($self->Mojibake($tiq))
  {
    $self->Logit("$0: Mojibake quoted title <<$tiq>> for $id!\n");
  }
  my $sql = qq{ SELECT count(*) FROM bibdata WHERE id="$id"};
  my $count = $self->SimpleSqlGet( $sql );
  $sql = qq{ UPDATE bibdata SET title=$tiq WHERE id="$id"};
  if (!$count)
  {
    $sql = qq{ INSERT INTO bibdata (id, title, pub_date) VALUES ( "$id", $tiq, '')};
  }
  $self->PrepareSubmitSql( $sql );
  return $title;
}

sub UpdateCandidatesTitle
{
  my $self = shift;
  my $id   = shift;
  
  my $title = $self->GetRecordTitleBc2Meta( $id );
  my $tiq = $self->get('dbh')->quote( $title );
  my $sql = qq{ UPDATE candidates SET title=$tiq WHERE id="$id"};
  $self->PrepareSubmitSql( $sql );
}

sub UpdatePubDate
{
  my $self = shift;
  my $id   = shift;
  my $date = shift;

  if ($id eq '')
  {
    $self->SetError("Trying to update pub date for empty volume id!\n");
    $self->Logit("$0: trying to update pub date for empty volume id!\n");
  }
  $date = $self->GetPublDate($id) unless $date;
  my $sql = qq{ SELECT count(*) FROM bibdata WHERE id="$id"};
  my $count = $self->SimpleSqlGet( $sql );
  $sql = "UPDATE bibdata SET pub_date='$date-01-01' WHERE id='$id'";
  if (!$count)
  {
    $sql = "INSERT INTO bibdata (id, title, pub_date) VALUES ('$id', '', '$date-01-01')";
  }
  $self->PrepareSubmitSql( $sql );
  return $date;
}

sub UpdateCandidatesPubDate
{
  my $self = shift;
  my $id   = shift;

  my $date = $self->GetPublDate($id);
  my $sql = "UPDATE candidates SET pub_date='$date-01-01' WHERE id='$id'";
  $self->PrepareSubmitSql( $sql );
}

sub UpdateAuthor
{
  my $self   = shift;
  my $id     = shift;
  my $author = shift;

  if ($id eq '')
  {
    $self->SetError("Trying to update author for empty volume id!\n");
    $self->Logit("$0: trying to update author for empty volume id!\n");
  }
  if ( !$author )
  {
    $author = $self->GetMarcDatafieldAuthor( $id );
  }
  if ($self->Mojibake($author))
  {
    $self->Logit("$0: Mojibake author <<$author>> for $id!\n");
  }
  my $aiq = $self->get('dbh')->quote( $author );
  if ($self->Mojibake($aiq))
  {
    $self->Logit("$0: Mojibake quoted author <<$aiq>> for $id!\n");
  }
  my $sql = qq{ SELECT count(*) FROM bibdata where id="$id"};
  my $count = $self->SimpleSqlGet( $sql );
  my $sql = qq{ UPDATE bibdata SET author=$aiq where id="$id"};
  if (!$count )
  {
    $sql = qq{ INSERT INTO bibdata (id, title, pub_date, author) VALUES ( "$id", '', '', $aiq ) };
  }
  $self->PrepareSubmitSql( $sql );
  return $author;
}

sub UpdateCandidatesAuthor
{
  my $self = shift;
  my $id   = shift;

  my $author = $self->GetMarcDatafieldAuthor( $id );
  my $aiq = $self->get('dbh')->quote( $author );
  my $sql = qq{ UPDATE candidates SET author=$aiq WHERE id="$id"};
  $self->PrepareSubmitSql( $sql );
}


## use for now because the API is slow...
sub GetRecordTitleBc2Meta
{
    my $self = shift;
    my $id   = shift;
    
    $id = lc $id;

    my $parser = $self->get( 'parser' );
    my $url    = $self->get( 'bc2metaUrl' ) . '?id=' . $id;
    my $ua     = LWP::UserAgent->new;

    $ua->timeout( 1000 );
    my $req = HTTP::Request->new( GET => $url );
    my $res = $ua->request( $req );

    if ( ! $res->is_success ) { $self->Logit( "$url failed: ".$res->message() ); return; }

    my $source;
    eval { $source = $parser->parse_string( $res->content() ); };
    if ($@) { $self->Logit( "failed to parse response:$@" ); return; }

    my $errorCode = $source->findvalue( "//*[name()='error']" );
    if ( $errorCode ne '' )
    {
        $self->Logit( "$url \nfailed to get MARC for $id: $errorCode " . $res->content() );
        return;
    }

    my ($title) = $source->findvalue( '/present/record/metadata/oai_marc/varfield[@id="245"]/subfield[@label="a"]' );

    return $title;
}

sub GetEncAuthor
{
    my $self = shift;
    my $bar  = shift;

    my $au = $self->GetMarcDatafieldAuthor( $bar );

    $au =~ s,\',\\\',g; ## escape '
    $au =~ s,\",\\\",g; ## escape "
    return $au;
}

sub GetEncAuthorForReview
{
    my $self = shift;
    my $bar  = shift;

    my $au = $self->GetAuthorForReview($bar);
    $au =~ s/\'/\\\'/g; ## escape '
    return $au;
}

sub GetAuthorForReview
{
    my $self = shift;
    my $bar  = shift;

    my $au = $self->GetMarcDatafield( $bar, 100, 'a');
    if ( ! $au )
    {
      $au = $self->GetMarcDatafield( $bar, 110, 'a');
    }
    if ( ! $au )
    {
      $au = $self->GetMarcDatafield( $bar, 111, 'a');
    }
    if ( ! $au )
    {
      $au = $self->GetMarcDatafield( $bar, 130, 'a');
    }
    if ( ! $au )
    {
      $au = $self->GetMarcDatafield( $bar, 700, 'a');
    }
    if ( ! $au )
    {
      $au = $self->GetMarcDatafield( $bar, 710, 'a');
    }

    $au =~ s,(.*[A-Za-z]).*,$1,;

    return $au;
}

sub MetadataURL
{
  my $self = shift;
  my $id   = shift;
  
  return $self->get( 'bc2metaUrl' ) .'?id=' . $id . '&schema=marcxml';
}

## ----------------------------------------------------------------------------
##  Function:   get the metadata record (MARC21)
##  Parameters: barcode
##  Return:     XML::LibXML record doc
## ----------------------------------------------------------------------------
sub GetRecordMetadata
{
    my $self       = shift;
    my $barcode    = shift;
    my $parser     = $self->get( 'parser' );
    
    if ( ! $barcode ) { $self->Logit( "no barcode given: $barcode" ); return 0; }
    $barcode = lc $barcode;
    my ($ns,$bar) = split(/\./, $barcode);

    ## get from object if we have it
    if ( $self->get( $barcode ) ne '' ) { return $self->get( $barcode ); }

    #my $sysId = $self->BarcodeToId( $barcode );
    #my $url = "http://mirlyn-aleph.lib.umich.edu/cgi-bin/api/marc.xml/uid/$sysId";
    #my $url = "http://mirlyn-aleph.lib.umich.edu/cgi-bin/api_josh/marc.xml/itemid/$bar";
    my $url = $self->MetadataURL($barcode);
    
    my $ua = LWP::UserAgent->new;

    if ($self->get("verbose")) { $self->Logit( "GET: $url" ); }
    $ua->timeout( 1000 );
    my $req = HTTP::Request->new( GET => $url );
    my $res = $ua->request( $req );

    if ( ! $res->is_success ) { $self->Logit( "$url failed: ".$res->message() ); return; }

    my $source;
    eval {
      my $content = Encode::decode('utf8', $res->content());
      $source = $parser->parse_string( $content );
    };
    if ($@) { $self->SetError( "failed to parse ($url):$@" ); return; }

    my $errorCode = $source->findvalue( "//*[name()='error']" );
    if ( $errorCode ne '' )
    {
        $self->Logit( "$url \nfailed to get MARC for $barcode: $errorCode " . $res->content() );
        return;
    }

    #my ($record) = $source->findnodes( "//record" );
    my ($record) = $source->findnodes( "." );
    $self->set( $barcode, $record );

    return $record;
}

## ----------------------------------------------------------------------------
##  Function:   get the mirlyn ID for a given barcode
##  Parameters: barcode
##  Return:     ID
## ----------------------------------------------------------------------------
sub BarcodeToId
{
    my $self       = shift;
    my $barcode    = shift;
    my $bc2metaUrl = $self->get( 'bc2metaUrl' );
    my $barcodeID  = $self->get( 'barcodeID' );

    ## check the cache first
    if ( $barcodeID->{$barcode} ne '' ) { return $barcodeID->{$barcode}; }

    my $url = $bc2metaUrl . "?id=$barcode" . "&no_meta=1";
    
    my $ua = LWP::UserAgent->new;
    $ua->timeout( 1000 );
    my $req = HTTP::Request->new( GET => $url );
    my $res = $ua->request( $req );

    if ( ! $res->is_success ) { $self->Logit( "$url failed: ".$res->message() ); return; }

    $res->content =~ m,<doc_number>\s*(\d+)\s*</doc_number>,s;
    
    my $id = $1;
    if ( $id eq '' ) { return; }  ## error or not found
    #$id = "MIU01-" . $id;

    $barcodeID->{$barcode} = $id;   ## put into cache
    return $id;
}

sub GetPriority
{
  my $self = shift;
  my $bar = shift;
  
  my $sql = qq{SELECT priority FROM $CRMSGlobals::queueTable WHERE id = '$bar'};
  return $self->SimpleSqlGet( $sql );
}

sub HasLockedItem
{
    my $self = shift;
    my $name = shift;
    
    my $sql = qq{SELECT id FROM $CRMSGlobals::queueTable WHERE locked = "$name" LIMIT 1};
    my $id = $self->SimpleSqlGet( $sql );

    if ($id) { return 1; }
    return 0;
}

sub GetLockedItem
{
    my $self = shift;
    my $name = shift;

    my $sql = qq{SELECT id FROM $CRMSGlobals::queueTable WHERE locked = "$name" LIMIT 1};
    my $id = $self->SimpleSqlGet( $sql );

    $self->Logit( "Get locked item for $name: $id" );

    return $id;
}

sub IsLocked
{
    my $self = shift;
    my $id   = shift;

    my $sql = qq{SELECT id FROM $CRMSGlobals::queueTable WHERE locked IS NOT NULL AND id = "$id"};
    my $id = $self->SimpleSqlGet( $sql );

    if ($id) { return 1; }
    return 0;
}

sub IsLockedForUser
{
    my $self = shift;
    my $id   = shift;
    my $name = shift;

    my $sql = "SELECT locked FROM $CRMSGlobals::queueTable WHERE id='$id'";
    my $ref = $self->get( 'dbh' )->selectall_arrayref( $sql );

    if ( scalar @{$ref} )
    {
        if ( $ref->[0]->[0] eq $name ) { return 1; }
    }
    return 0;
}

sub RemoveOldLocks
{
    my $self = shift;
    my $time = shift;

    if (! $time)  { $time = 86400; }

    my $time = $self->GetPrevDate($time);

    my $lockedRef = $self->GetLockedItems();
    foreach my $item ( keys %{$lockedRef} )
    {
        my $id = $lockedRef->{$item}->{id};
        my $user = $lockedRef->{$item}->{locked};
        my $since = $self->ItemLockedSince($id, $user);

        my $sql = "SELECT id FROM $CRMSGlobals::queueTable WHERE id='$id' AND '$time'>=time";
        my $old = $self->SimpleSqlGet($sql);

        if ( $old )
        {
            $self->Logit( "REMOVING OLD LOCK:\t$id, $user: $since | $time" );
            $self->UnlockItem( $id, $user );
        }
    }
}

sub PreviouslyReviewed
{
    my $self = shift;
    my $id   = shift;
    my $user = shift;

    ## expert reviewers can edit any time
    if ( $self->IsUserExpert( $user ) ) { return 0; }

    my $limit = $self->GetYesterday();

    my $sql = "SELECT id FROM $CRMSGlobals::reviewsTable WHERE id='$id' AND user='$user' AND time<'$limit'";
    my $found = $self->SimpleSqlGet( $sql );

    if ($found) { return 1; }
    return 0;
}

# Returns 0 on success, error message on error.
sub LockItem
{
    my $self = shift;
    my $id   = shift;
    my $name = shift;

    ## if already locked for this user, that's OK
    if ( $self->IsLockedForUser( $id, $name ) ) { return 0; }
    # Not locked for user, maybe someone else
    if ($self->IsLocked($id)) { return 'Item has already been locked by another user'; }
    ## can only have 1 item locked at a time
    my $locked = $self->HasLockedItem( $name );
    if ( $locked eq $id ) { return 0; }  ## already locked
    if ( $locked ) { return 'You already have a locked item'; }
    my $sql = qq{UPDATE $CRMSGlobals::queueTable SET locked = "$name" WHERE id = "$id"};
    $self->PrepareSubmitSql( $sql );
    $self->StartTimer( $id, $name );
    return 0;
}

sub UnlockItem
{
    my $self = shift;
    my $id   = shift;
    my $user = shift;

    if ( ! $self->IsLocked( $id ) ) { return 0; }

    my $sql = qq{UPDATE $CRMSGlobals::queueTable SET locked = NULL  WHERE id = "$id"};
    if ( ! $self->PrepareSubmitSql($sql) ) { return 0; }

    $self->RemoveFromTimer( $id, $user );
    $self->Logit( "unlocking $id" );
    return 1;
}


sub UnlockItemEvenIfNotLocked
{
    my $self = shift;
    my $id   = shift;
    my $user = shift;

    my $sql = qq{UPDATE $CRMSGlobals::queueTable SET locked = NULL  WHERE id = "$id"};
    if ( ! $self->PrepareSubmitSql($sql) ) { return 0; }

    $self->RemoveFromTimer( $id, $user );
    $self->Logit( "unlocking $id" );
    return 1;
}


sub UnlockAllItemsForUser
{
    my $self = shift;
    my $user = shift;

    my $sql = qq{SELECT id  FROM $CRMSGlobals::timerTable WHERE user= "$user"};
    my $ref = $self->get( 'dbh' )->selectall_arrayref( $sql );

    my $return = {};
    foreach my $row (@{$ref})
    {
        my $id = $row->[0];
   
        my $sql = qq{UPDATE $CRMSGlobals::queueTable SET locked = NULL  WHERE id = "$id"};
        $self->PrepareSubmitSql( $sql );
    }

    ## clear entry in table
    my $sql = qq{ DELETE FROM $CRMSGlobals::timerTable WHERE  user = "$user" };
    $self->PrepareSubmitSql( $sql );
}

sub GetLockedItems
{
    my $self = shift;
    my $user = shift;
    
    my $restrict = ($user)? "= '$user'":'IS NOT NULL';
    my $sql = qq{SELECT id, locked FROM $CRMSGlobals::queueTable WHERE locked $restrict};
    my $ref = $self->get( 'dbh' )->selectall_arrayref( $sql );

    my $return = {};
    foreach my $row (@{$ref})
    {
        my $id = $row->[0];
        my $lo = $row->[1];
        $return->{$id} = {"id" => $id, "locked" => $lo};
    }
    if ( $self->get('verbose') ) { $self->Logit( "locked: " , join(", ", keys %{$return}) ); }
    return $return;
}

sub ItemLockedSince
{
    my $self = shift;
    my $id   = shift;
    my $user = shift;

    my $sql = qq{SELECT start_time FROM $CRMSGlobals::timerTable WHERE id = "$id" and user = "$user"};
    return $self->SimpleSqlGet( $sql );
}

sub StartTimer
{
    my $self = shift;
    my $id   = shift;
    my $user = shift;
    
    my $sql = qq{ REPLACE INTO timer SET start_time = NOW(), id = "$id", user = "$user" };
    if ( ! $self->PrepareSubmitSql($sql) ) { return 0; }

    $self->Logit( "start timer for $id, $user" );
}

sub EndTimer
{
    my $self = shift;
    my $id   = shift;
    my $user = shift;

    my $sql = qq{ UPDATE timer SET end_time = NOW() WHERE id = "$id" and user = "$user" };
    if ( ! $self->PrepareSubmitSql($sql) ) { return 0; }

    ## add duration to reviews table
    $self->SetDuration( $id, $user );
    $self->Logit( "end timer for $id, $user" );
}

sub RemoveFromTimer
{
    my $self = shift;
    my $id   = shift;
    my $user = shift;

    ## clear entry in table
    my $sql = qq{ DELETE FROM timer WHERE id = "$id" and user = "$user" };
    $self->PrepareSubmitSql( $sql );

    return 1;
}

sub GetDuration
{
    my $self = shift;
    my $id   = shift;
    my $user = shift;

    my $sql = qq{ SELECT duration FROM $CRMSGlobals::reviewsTable WHERE user = "$user" AND id = "$id" };
    return $self->SimpleSqlGet( $sql );
}

sub SetDuration
{
    my $self = shift;
    my $id   = shift;
    my $user = shift;

    my $sql = qq{ SELECT TIMEDIFF((SELECT end_time   FROM timer where id = "$id" and user = "$user"),
                                  (SELECT start_time FROM timer where id = "$id" and user = "$user")) };
    my $dur = $self->SimpleSqlGet( $sql );

    if ( ! $dur ) { return; }

    ## insert time
    $sql = qq{ UPDATE $CRMSGlobals::reviewsTable SET duration = "$dur" WHERE user = "$user" AND id = "$id" };

    $self->PrepareSubmitSql( $sql );
    $self->RemoveFromTimer( $id, $user );
}

sub GetReviewerCount
{
    my $self = shift;
    my $user = shift;
    my $date = shift;
 
    return scalar( $self->ItemsReviewedByUser( $user, $date ) );
}

sub HasItemBeenReviewedByAnotherExpert
{
  my $self = shift;
  my $id   = shift;
  my $user = shift;
  
  my $stat = $self->GetStatus($id) ;
  if ($stat == 5 || $stat == 6)
  {
    my $sql = "SELECT COUNT(*) FROM $CRMSGlobals::reviewsTable WHERE id='$id' AND user='$user'";
    my $count = $self->SimpleSqlGet($sql);
    return ($count)? 0:1;
  }
  return 0;
}

## ----------------------------------------------------------------------------
##  Function:   get the next item to be reviewed (not something this user has
##              already reviewed)
##  Parameters: user name
##  Return:     barcode
## ----------------------------------------------------------------------------
sub GetNextItemForReview
{
    my $self = shift;
    my $name = shift;
    
    my $bar;
    
    # Only Anne reviews priority 4
    # FIXME: do something with user account table, not hardcode name.
    if ($name eq 'annekz')
    {
      my $sql = "SELECT id FROM $CRMSGlobals::queueTable WHERE locked IS NULL AND expcnt=0 AND priority=4 ORDER BY priority DESC, time ASC LIMIT 1";
      $bar = $self->SimpleSqlGet( $sql );
      #print "$sql<br/>\n";
    }
    # If user is expert, get priority 3 (and higher?) items; regular joe users can look for priority 2s.
    if (!$bar && $self->IsUserExpert($name))
    {
      my $sql = "SELECT id FROM $CRMSGlobals::queueTable WHERE locked IS NULL AND expcnt=0 AND priority>=2 AND priority<4 ORDER BY priority DESC, time ASC LIMIT 1";
      $bar = $self->SimpleSqlGet( $sql );
      #print "$sql<br/>\n";
    }
    my $exclude3 = ($self->IsUserExpert($name))? '':'q.priority<3 AND';
    if ( ! $bar )
    {
      # Get priority 2 items
      my $sql = "SELECT q.id FROM $CRMSGlobals::queueTable q, bibdata b WHERE q.id=b.id AND q.priority=2 AND q.locked IS NULL AND " .
                "q.status=0 AND q.expcnt=0 AND " .
                "(q.id NOT IN (SELECT DISTINCT id FROM $CRMSGlobals::reviewsTable) OR " .
                " q.id IN (SELECT DISTINCT id FROM $CRMSGlobals::reviewsTable r WHERE r.user != '$name' AND r.id IN (SELECT id FROM reviews r2 GROUP BY r2.id HAVING count(*) = 1))) " .
                "ORDER BY q.priority DESC, b.pub_date ASC, q.time ASC LIMIT 1";
      $bar = $self->SimpleSqlGet( $sql );
      #print "$sql<br/>\n";
    }
    if ( ! $bar )
    {
      # Find items reviewed once by some other user.
      my $sql = "SELECT id FROM $CRMSGlobals::queueTable q WHERE $exclude3 q.locked IS NULL AND q.status=0 AND q.expcnt=0 AND q.id IN " .
                "(SELECT DISTINCT id FROM $CRMSGlobals::reviewsTable r WHERE r.user != '$name' AND r.id IN (SELECT id FROM reviews r2 GROUP BY r2.id HAVING count(*) = 1)) " .
                "ORDER BY q.priority DESC, q.time ASC LIMIT 1";
      $bar = $self->SimpleSqlGet( $sql );
      #print "$sql<br/>\n";
    }
    if ( ! $bar )
    {
        # Get the 1st available item that has never been reviewed.
        # Exclude priority 1 some of the time, to 'fool' reviewers into not thinking everything is pd.
        my $exclude1 = (rand() >= 0.33)? 'q.priority!=1 AND':'';
        my $sql = "SELECT q.id FROM $CRMSGlobals::queueTable q, bibdata b WHERE q.id=b.id AND $exclude1 $exclude3 q.locked IS NULL AND " .
                  "q.status=0 AND q.expcnt=0 AND q.id NOT IN (SELECT DISTINCT id FROM $CRMSGlobals::reviewsTable) " .
                  "ORDER BY q.priority DESC, q.time ASC LIMIT 1";
        $bar = $self->SimpleSqlGet( $sql );
        #print "$sql<br/>\n";
        # Relax the priority 1 stuff if it fails
        if (!$bar)
        {
          $sql = "SELECT id FROM $CRMSGlobals::queueTable q, bibdata b WHERE q.id=b.id $exclude3 AND q.locked IS NULL AND " .
                 "q.status=0 AND q.expcnt=0 AND q.id NOT IN (SELECT DISTINCT id FROM $CRMSGlobals::reviewsTable) " .
                 "ORDER BY q.priority DESC, q.time ASC LIMIT 1";
          $bar = $self->SimpleSqlGet( $sql );
          #print "$sql<br/>\n";
        }
    }

    ## lock before returning
    my $err = $self->LockItem( $bar, $name );
    if ($err != 0)
    {
        $self->Logit( "failed to lock $bar for $name: $err" );
        return;
    }
    
    return $bar;
}

sub GetQueuePriorities
{
  my $self = shift;
  
  my $sql = qq{SELECT count(priority),priority FROM queue GROUP BY priority ASC};
  my $ref = $self->get( 'dbh' )->selectall_arrayref( $sql );

  my @return;
  foreach (@{$ref}) { push @return, sprintf("%d priority %d", $_->[0], $_->[1]); }
  return @return;
}

sub GetTopPriority
{
  my $self = shift;
  
  my $sql = qq{SELECT max(priority) FROM queue};
  return $self->SimpleSqlGet($sql);
}

sub GetNextPubYear
{
    my $self = shift;

    my $sql = qq{ SELECT pubyear from pubyearcycle};
    #my $ref = $self->get( 'dbh' )->selectall_arrayref( $sql );
    my $year = $self->SimpleSqlGet( $sql );

    my $nextyear = $year + 1;
    if ( $nextyear > 1963 )
    {
      $nextyear = 1923;
    }

    my $sql = qq{update pubyearcycle set pubyear=$nextyear};
    $self->PrepareSubmitSql( $sql );

    return $year;
}



sub ItemsReviewedByUser
{
    my $self  = shift;
    my $user  = shift;
    my $since = shift;
    my $until = shift;

    if ( ! $user ) { $user = $self->get("user"); }

    my $sql .= qq{ SELECT id FROM $CRMSGlobals::reviewsTable WHERE user = "$user" };

    ## if date, restrict to just items since that date
    if    ( $since ) { $sql .= qq{ AND time >= "$since" GROUP BY id ORDER BY time DESC }; }
    elsif ( $until ) { $sql .= qq{ AND time <  "$until" GROUP BY id ORDER BY time DESC LIMIT 20 }; }

    my $ref = $self->get( 'dbh' )->selectall_arrayref( $sql );

    my @return;
    foreach (@{$ref}) { push @return, $_->[0]; }
    return @return;
}

sub ItemWasReviewedByUser
{
    my $self  = shift;
    my $user  = shift;
    my $id    = shift;

    my $sql = qq{ SELECT id FROM $CRMSGlobals::reviewsTable WHERE user = "$user" AND id = "$id"};
    #my $ref = $self->get( 'dbh' )->selectall_arrayref( $sql );
    my $found = $self->SimpleSqlGet( $sql );

    if ($found) { return 1; }
    return 0;
}



sub GetItemReviewDetails
{
    my $self = shift;
    my $id   = shift;
    my $user = shift;

    my $sql = qq{ SELECT attr, reason, renNum, note FROM reviews WHERE id = "$id"};

    ## if name, limit to just that users review details
    if ( $user ) { $sql .= qq{ AND user = "$user" }; }

    my $ref = $self->get( 'dbh' )->selectall_arrayref( $sql );

    my @return;
    foreach my $r ( @{$ref} )
    {
        my $str = $self->GetRightsName($r->[0]) ."/". $self->GetReasonName($r->[1]);
        if ( $r->[2] ) { $str .= ", ". $self->LinkToStanford( $r->[2] ); }
        if ( $r->[3] ) { $str .= ", $r->[3]"; }
        push @return, $str;
    }

    return @return;
}

sub IsThirdReview
{
    my $self = shift;
    my $id   = shift;

    my $sql = qq{ SELECT count(id) FROM $CRMSGlobals::reviewsTable WHERE id = "$id"};
    my $ref = $self->get( 'dbh' )->selectall_arrayref( $sql );

    if ( $ref->[0]->[0] > 1 ) { return 1; }
    return 0;
}

sub GetRightsName
{
    my $self = shift;
    my $id   = shift;
    my %rights = (1 => 'pd', 2 => 'ic', 3 => 'opb', 4 => 'orph', 5 => 'und', 6 => 'umall', 7 => 'world', 8 => 'nobody', 9 => 'pdus');
    return $rights{$id};
    #my $sql = qq{ SELECT name FROM attributes WHERE id = "$id" };

    #my $ref = $self->get( 'sdr_dbh' )->selectall_arrayref($sql);
    #return $ref->[0]->[0];
}

sub GetReasonName
{
    my $self = shift;
    my $id   = shift;
    my %reasons = (1 => 'bib', 2 => 'ncn', 3 => 'con', 4 => 'ddd', 5 => 'man', 6 => 'pvt',
                   7 => 'ren', 8 => 'nfi', 9 => 'cdpp', 10 => 'cip', 11 => 'unp');
    return $reasons{$id};
    #my $sql = qq{ SELECT name FROM reasons WHERE id = "$id" };

    #my $ref = $self->get( 'sdr_dbh' )->selectall_arrayref($sql);
    #return $ref->[0]->[0];
}

sub GetRightsNum
{
    my $self = shift;
    my $id   = shift;
    my %rights = ('pd' => 1, 'ic' => 2, 'opb' => 3, 'orph' => 4, 'und' => 5, 'umall' => 6, 'world' => 7, 'nobody' => 8, 'pdus' => 9);
    return $rights{$id};
    #my $sql = qq{ SELECT id FROM attributes WHERE name = "$id" };

    #my $ref = $self->get( 'sdr_dbh' )->selectall_arrayref($sql);
    #return $ref->[0]->[0];
}

sub GetReasonNum
{
    my $self = shift;
    my $id   = shift;
    my %reasons = ('bib' => 1, 'ncn' => 2, 'con' => 3, 'ddd' => 4, 'man' => 5, 'pvt' => 6,
                   'ren' => 7, 'nfi' => 8, 'cdpp' => 9, 'cip' => 10, 'unp' => 11);
    return $reasons{$id};
    #my $sql = qq{ SELECT id FROM reasons WHERE name = "$id" };

    #my $ref = $self->get( 'sdr_dbh' )->selectall_arrayref($sql);
    #return $ref->[0]->[0];
}

sub GetCopyDate
{
    my $self = shift;
    my $id   = shift;
    my $user = shift;
    my $sql = qq{ SELECT copyDate FROM $CRMSGlobals::reviewsTable WHERE id = "$id" AND user = "$user"};

    return $self->SimpleSqlGet( $sql );
}

## ----------------------------------------------------------------------------
##  Function:   get renNum (stanford ren num)
##  Parameters: id
##  Return:     renNum
## ----------------------------------------------------------------------------
sub GetRenNum
{
    my $self = shift;
    my $id   = shift;
    my $user = shift;
    my $sql = qq{ SELECT renNum FROM $CRMSGlobals::reviewsTable WHERE id = "$id" AND user = "$user"};

    if ( ! $self->IsUserExpert($user) ) { $sql .= qq{ AND user = "$user"}; }

    return $self->SimpleSqlGet( $sql );
}

sub GetRenNums
{
    my $self = shift;
    my $id   = shift;
    my $user = shift;

    my $sql = qq{SELECT renNum FROM $CRMSGlobals::reviewsTable WHERE id = "$id" };

    ## if not expert, limit to just that users renNums
    if ( ! $self->IsUserExpert($user) ) { $sql .= qq{ AND user = "$user"}; }

    my $ref = $self->get( 'dbh' )->selectall_arrayref( $sql );

    my @return;
    foreach ( @{$ref} ) { if ($_->[0] ne '') { push @return, $_->[0]; } }
    return @return;
}

sub GetRenDate
{
    my $self = shift;
    my $id   = shift;
    
    $id =~ s, ,,gs;
    my $sql = qq{ SELECT DREG FROM $CRMSGlobals::stanfordTable WHERE ID = "$id" };

    return $self->SimpleSqlGet( $sql );
}

sub GetPrevDate
{
    my $self = shift;
    my $prev = shift;

    ## default 1 day (86,400 sec.)
    if (! $prev) { $prev = 86400; }
 
    my @p = localtime( time() - $prev );
    $p[3] = ($p[3]);
    $p[4] = ($p[4]+1);
    $p[5] = ($p[5]+1900);
    foreach (0,1,2,3,4) { $p[$_] = sprintf("%0*d", "2", $p[$_]); }

    ## DB format (YYYY-MM-DD HH:MM:SS)
    return "$p[5]-$p[4]-$p[3] $p[2]:$p[1]:$p[0]";
}


sub GetTodaysDate
{
    my $self = shift;
    my @p = localtime( time() );
    $p[4] = ($p[4]+1);
    $p[5] = ($p[5]+1900);
    foreach (0,1,2,3,4) { $p[$_] = sprintf("%0*d", "2", $p[$_]); }

    ## DB format (YYYY-MM-DD HH:MM:SS)
    return "$p[5]-$p[4]-$p[3] $p[2]:$p[1]:$p[0]";
}

sub OpenErrorLog
{
    my $self = shift;
    my $logFile = $self->get( 'logFile' );

    open( my $fh, ">>", $logFile );
    if (! defined $fh) { die "failed to open log: $logFile \n"; }

    my $oldfh = select($fh); $| = 1; select($oldfh); ## flush out

    $self->set('logFh', $fh );
}

sub CloseErrorLog
{
    my $self = shift;
    close $self->get( 'logFh' );
}

sub Logit
{
    my $self = shift;
    my $str  = shift;

    $self->OpenErrorLog();

    my $date = $self->GetTodaysDate();
    my $fh = $self->get( 'logFh' );

    print $fh "$date: $str\n";
    $self->CloseErrorLog();
}

## ----------------------------------------------------------------------------
##  Function:   add to and get errors
##              $self->SetError( "foo" );
##              my $r = $self->GetErrors();
##              if ( defined $r ) { $self->Logit( join(", ", @{$r}) ); }
##  Parameters: 
##  Return:     
## ----------------------------------------------------------------------------
sub SetError
{
    my $self   = shift;
    my $error  = shift;
    my $errors = $self->get( 'errors' );
    push @{$errors}, $error;
}

sub GetErrors
{
    my $self = shift;
    return $self->get( 'errors' );
}

# The cgi footer prints all errors. If already processed and displayed, no need to repeat.
sub ClearErrors
{
  my $self = shift;
  
  my $errors = [];
  $self->set( 'errors', $errors );
}

sub GetQueueSize
{
    my $self = shift;

    my $sql = qq{ SELECT count(*) from $CRMSGlobals::queueTable};
    my $count = $self->SimpleSqlGet( $sql );
    
    return $count;
}


sub GetTotalUndInf
{
    my $self = shift;

    my $sql = qq{ SELECT count(*) from $CRMSGlobals::queueTable where status= 3};
    my $count = $self->SimpleSqlGet( $sql );
    
    if ($count) { return $count; }
    return 0;
}

sub GetTotalWithFinalDetermination
{
    my $self = shift;

    my $sql = qq{ SELECT count(*) from $CRMSGlobals::queueTable where status= 4 OR status = 5};
    my $count = $self->SimpleSqlGet( $sql );
    
    if ($count) { return $count; }
    return 0;
}

sub GetTotalConflict
{
    my $self = shift;

    my $sql = qq{ SELECT count(*) from $CRMSGlobals::queueTable where status= 2};
    my $count = $self->SimpleSqlGet( $sql );
    
    if ($count) { return $count; }
    return 0;
}


sub GetTotalInActiveQueue
{
    my $self = shift;

    my $sql = qq{ SELECT count(*) from $CRMSGlobals::queueTable where status > 0 };
    my $count = $self->SimpleSqlGet( $sql );
    
    if ($count) { return $count; }
    return 0;
}


sub GetTotalInHistoricalQueue
{
    my $self = shift;

    my $sql = qq{ SELECT count(*) from $CRMSGlobals::historicalreviewsTable };
    my $count = $self->SimpleSqlGet( $sql );
    
    if ($count) { return $count; }
    return 0;
}


sub GetReviewsWithStatusNumber
{
    my $self = shift;
    my $status = shift;

    my $sql = qq{ SELECT count(*) from $CRMSGlobals::queueTable where status = $status};
    my $count = $self->SimpleSqlGet( $sql );
    
    if ($count) { return $count; }
    return 0;
}

sub CreateQueueReport
{
  my $self = shift;
  
  my $report = '';
  my $sql = qq{ SELECT MAX(priority) FROM $CRMSGlobals::queueTable};
  my $maxpri = $self->SimpleSqlGet( $sql );
  my $priheaders = '';
  foreach my $pri (0 .. $maxpri) { $priheaders .= "<th>Priority&nbsp;$pri</th>" };
  $report .= "<table style='width:100px;'><tr style='vertical-align:top;'><td>\n";
  $report .= "<table class='exportStats'>\n<th>Status</th><th>Total</th>$priheaders<tr/>\n";
  foreach my $status (-1 .. 5)
  {
    my $statusClause = ($status == -1)? '':" WHERE STATUS=$status";
    my $sql = qq{ SELECT count(*) FROM $CRMSGlobals::queueTable $statusClause};
    my $count = $self->SimpleSqlGet( $sql );
    $status = 'All' if $status == -1;
    my $class = ($status eq 'All')?' class="total"':'';
    $report .= sprintf("<tr><td%s>$status</td><td%s>$count</td>", $class, $class);
    $sql = "SELECT id FROM $CRMSGlobals::queueTable $statusClause";
    $report .= $self->DoPriorityBreakdown($count,$sql,$maxpri,$class);
    $report .= "</tr>\n";
  }
  $sql = qq{ SELECT id FROM $CRMSGlobals::queueTable WHERE status=0 AND id NOT IN (SELECT id FROM $CRMSGlobals::reviewsTable)};
  my $count = $self->GetTotalAwaitingReview();
  my $class = ' class="major"';
  $report .= sprintf("<tr><td%s>Not&nbsp;Yet&nbsp;Active</td><td%s>$count</td>", $class, $class);
  $report .= $self->DoPriorityBreakdown($count,$sql,$maxpri,$class);
  $report .= "</table><br/><br/>\n";
  $report .= "</td><td style='padding-left:20px'>\n";
  $report .= "<table class='exportStats'>\n";
  my $val = $self->GetLastQueueTime();
  $val =~ s/\s/&nbsp;/g;
  $report .= "<tr><th>Last&nbsp;Queue&nbsp;Update</td><td>$val</td></tr>\n";
  $report .= sprintf("<tr><th>Volumes&nbsp;Last&nbsp;Added</td><td>%s</td></tr>\n", $self->GetLastIdQueueCount());
  $report .= sprintf("<tr><th>Cumulative&nbsp;Volumes&nbsp;in&nbsp;Queue&nbsp;(ever*)</td><td>%s</td></tr>\n", $self->GetTotalEverInQueue());
  $report .= sprintf("<tr><th>Volumes&nbsp;in&nbsp;Candidates</td><td>%s</td></tr>\n", $self->GetCandidatesSize());
  $val = $self->GetLastLoadTimeToCandidates();
  $val =~ s/\s/&nbsp;/g;
  $report .= sprintf("<tr><th>Last&nbsp;Candidates&nbsp;Addition</td><td>%s&nbsp;on&nbsp;$val</td></tr>", $self->GetLastLoadSizeToCandidates());
  $report .= "</table>\n";
  $report .= "<span class='smallishText'>* Not including legacy data (reviews/determinations made prior to June 2009)</span>";
  $report .= "</td></tr></table>\n";
  return $report;
}

sub CreateDeterminationReport()
{
  my $self = shift;
  
  my $report = '';
  $report .= "<table class='exportStats'>\n";
  my ($count,$time) = $self->GetLastExport();
  my $sql = "SELECT count(DISTINCT h.id) FROM exportdata e, historicalreviews h WHERE e.id=h.id AND h.status=4 AND e.time>=date_sub('$time', INTERVAL 1 MINUTE)";
  my $fours = $self->SimpleSqlGet($sql);
  $sql = "SELECT count(DISTINCT h.id) FROM exportdata e, historicalreviews h WHERE e.id=h.id AND h.status=5 AND e.time>=date_sub('$time', INTERVAL 1 MINUTE)";
  my $fives = $self->SimpleSqlGet($sql);
  $sql = "SELECT count(DISTINCT h.id) FROM exportdata e, historicalreviews h WHERE e.id=h.id AND h.status=6 AND e.time>=date_sub('$time', INTERVAL 1 MINUTE)";
  my $sixes = $self->SimpleSqlGet($sql);
  my $pct4 = 0;
  my $pct5 = 0;
  my $pct6 = 0;
  eval {$pct4 = 100.0*$fours/($fours+$fives+$sixes);};
  eval {$pct5 = 100.0*$fives/($fours+$fives+$sixes);};
  eval {$pct6 = 100.0*$sixes/($fours+$fives+$sixes);};
  $time =~ s/\s/&nbsp;/g;
  my $legacy = $self->GetTotalLegacyCount();
  my $cand = $self->GetNumberExportedFromCandidates();
  my $noncand = $self->GetNumberExportedNotFromCandidates();
  my $exported = $cand + $noncand;
  $report .= "<tr><th>Last&nbsp;CRMS&nbsp;Export</td><td>$count&nbsp;on&nbsp;$time</td></tr>";
  $report .= sprintf("<tr><th>&nbsp;&nbsp;&nbsp;&nbsp;Status&nbsp;4</td><td>$fours&nbsp;(%.1f%%)</td></tr>", $pct4);
  $report .= sprintf("<tr><th>&nbsp;&nbsp;&nbsp;&nbsp;Status&nbsp;5</td><td>$fives&nbsp;(%.1f%%)</td></tr>", $pct5);
  $report .= sprintf("<tr><th>&nbsp;&nbsp;&nbsp;&nbsp;Status&nbsp;6</td><td>$sixes&nbsp;(%.1f%%)</td></tr>", $pct6);
  $report .= sprintf("<tr><th>Total&nbsp;CRMS&nbsp;Determinations</td><td>%s</td></tr>", $exported);
  $report .= sprintf("<tr><th>&nbsp;&nbsp;&nbsp;&nbsp;From&nbsp;Candidates</td><td>%s</td></tr>", $cand);
  $report .= sprintf("<tr><th>&nbsp;&nbsp;&nbsp;&nbsp;From&nbsp;Elsewhere</td><td>%s</td></tr>", $noncand);
  $report .= sprintf("<tr><th>Total&nbsp;Legacy&nbsp;Determinations</td><td>%s</td></tr>", $legacy);
  $report .= sprintf("<tr><th>Total&nbsp;Determinations</td><td>%s</td></tr>", $exported + $legacy);
  $report .= "</table>\n";
  return $report;
}

sub CreateHistoricalReviewsReport
{
  my $self = shift;
  
  my $report = '';
  $report .= "<table class='exportStats'>\n";
  $report .= sprintf("<tr><th>CRMS&nbsp;Reviews</td><td>%s</td></tr>", $self->GetTotalNonLegacyReviewCount());
  $report .= sprintf("<tr><th>Legacy&nbsp;Reviews</td><td>%s</td></tr>", $self->GetTotalLegacyReviewCount());
  $report .= sprintf("<tr><th>Total&nbsp;Historical&nbsp;Reviews</td><td>%s</td></tr>", $self->GetTotalHistoricalReviewCount());
  $report .= "</table>\n";
  return $report;
}

sub CreateReviewReport
{
  my $self = shift;
  my $dbh = $self->get( 'dbh' );
  
  my $report = '';
  my $sql = qq{ SELECT MAX(priority) FROM $CRMSGlobals::queueTable};
  my $maxpri = $self->SimpleSqlGet( $sql );
  my $priheaders = '';
  foreach my $pri (0 .. $maxpri) { $priheaders .= "<th>Priority&nbsp;$pri</th>" };
  $report .= "<table class='exportStats'>\n<th>Status</th><th>Total</th>$priheaders<tr/>\n";
  my $notprocessedcnt = $self->GetTotalReviewedNotProcessed();
  
  my $undcnt = $self->GetTotalUndInf();
  my $conflictcnt = $self->GetTotalConflict();
  my $finalcnt = $self->GetTotalWithFinalDetermination();
  my $totalactive = $notprocessedcnt +  $undcnt + $conflictcnt + $finalcnt;
  $report .= "<tr><td class='total'>Active</td><td class='total'>$totalactive</td>";
  my $sql = qq{SELECT DISTINCT id FROM reviews};
  $report .= $self->DoPriorityBreakdown($totalactive,$sql,$maxpri,' class="total"') . "</tr>\n";
  
  # Unprocessed
  $report .= "<tr><td class='minor'>Unprocessed</td><td class='minor'>$notprocessedcnt</td>";
  $sql = qq{SELECT DISTINCT id FROM $CRMSGlobals::queueTable WHERE status=0 AND id IN (SELECT DISTINCT id FROM reviews)};
  $report .= $self->DoPriorityBreakdown($notprocessedcnt,$sql,$maxpri,' class="minor"') . "</tr>\n";
  
  # Unprocessed - single review
  $sql = <<END;
    SELECT DISTINCT id FROM reviews h1 WHERE id IN (SELECT id FROM queue WHERE status=0) AND id NOT IN
    (SELECT id FROM reviews h2 WHERE h1.id=h2.id AND h1.user!=h2.user)
END
  my $rows = $dbh->selectall_arrayref( $sql );
  my $count = scalar @{$rows};
  $report .= "<tr><td>&nbsp;&nbsp;&nbsp;&nbsp;Single&nbsp;Review</td><td>$count</td>";
  $report .= $self->DoPriorityBreakdown($count,$sql,$maxpri) . "</tr>\n";
  
  # Unprocessed - match
  $sql = <<END;
    SELECT DISTINCT id FROM reviews h1 WHERE id IN (SELECT id FROM queue WHERE status=0) AND id IN
    (SELECT id FROM reviews h2 WHERE h1.id=h2.id AND h1.user!=h2.user AND
     (h1.attr=h2.attr AND h1.reason=h2.reason AND (h1.attr!=5 OR h1.reason!=8) AND
      (h1.attr!=2 OR h1.reason!=7 OR
       (replace(h1.renNum,'\t','')=replace(h2.renNum,'\t','') AND h1.renDate=h2.renDate))))
END
  my $rows = $dbh->selectall_arrayref( $sql );
  $count = scalar @{$rows};
  $report .= "<tr><td>&nbsp;&nbsp;&nbsp;&nbsp;Matches</td><td>$count</td>";
  $report .= $self->DoPriorityBreakdown($count,$sql,$maxpri) . "</tr>\n";
  
  # Unprocessed - conflict
  $sql = <<END;
    SELECT DISTINCT id FROM reviews h1 WHERE id IN (SELECT id FROM queue WHERE status=0) AND id IN
    (SELECT id FROM reviews h2 WHERE h1.id=h2.id AND h1.user!=h2.user AND
     (h1.attr!=h2.attr OR h1.reason!=h2.reason OR
      (h1.attr=2 AND h1.reason=7 AND
       (replace(h1.renNum,'\t','')!=replace(h2.renNum,'\t','') OR h1.renDate!=h2.renDate))))
END
  my $rows = $dbh->selectall_arrayref( $sql );
  $count = scalar @{$rows};
  $report .= "<tr><td>&nbsp;&nbsp;&nbsp;&nbsp;Conflicts</td><td>$count</td>";
  $report .= $self->DoPriorityBreakdown($count,$sql,$maxpri) . "</tr>\n";
  
  # Unprocessed - matching und/nfi
  $sql = <<END;
    SELECT DISTINCT id FROM reviews h1 WHERE id IN (SELECT id FROM queue WHERE status=0) AND id IN
    (SELECT id FROM reviews h2 WHERE h1.id=h2.id AND h1.user!=h2.user AND
     (h1.attr=h2.attr AND h1.reason=h2.reason AND h1.attr=5 AND h1.reason=8))
END
  my $rows = $dbh->selectall_arrayref( $sql );
  $count = scalar @{$rows};
  $report .= "<tr><td>&nbsp;&nbsp;&nbsp;&nbsp;Matching&nbsp;<code>und/nfi</code></td><td>$count</td>";
  $report .= $self->DoPriorityBreakdown($count,$sql,$maxpri) . "</tr>\n";
  
  # Processed
  $sql = <<END;
    SELECT DISTINCT id FROM reviews WHERE id IN (SELECT DISTINCT id FROM queue WHERE status!=0)
END
  my $rows = $dbh->selectall_arrayref( $sql );
  $count = scalar @{$rows};
  $report .= "<tr><td class='minor'>Processed</td><td class='minor'>$count</td>";
  $report .= $self->DoPriorityBreakdown($count,$sql,$maxpri,' class="minor"') . "</tr>\n";
  
  $report .= "<tr><td>&nbsp;&nbsp;&nbsp;&nbsp;Conflicts</td><td>$conflictcnt</td>";
  $sql = qq{SELECT id from $CRMSGlobals::queueTable WHERE status=2};
  $report .= $self->DoPriorityBreakdown($conflictcnt,$sql,$maxpri) . "</tr>\n";

  $report .= "<tr><td>&nbsp;&nbsp;&nbsp;&nbsp;Matching&nbsp;<code>und/nfi</code></td><td>$undcnt</td>";
  $sql = qq{SELECT id from $CRMSGlobals::queueTable WHERE status=3};
  $report .= $self->DoPriorityBreakdown($undcnt,$sql,$maxpri) . "</tr>\n";

  $report .= "<tr><td>&nbsp;&nbsp;&nbsp;&nbsp;Awaiting&nbsp;Export</td><td>$finalcnt</td>";
  $sql = qq{SELECT id from $CRMSGlobals::queueTable WHERE status=4 OR status=5};
  $report .= $self->DoPriorityBreakdown($finalcnt,$sql,$maxpri) . "</tr>\n";
  $report .= sprintf("<tr><td colspan='%d'><span class='smallishText'>Last processed %s</span></td></tr>\n", $maxpri+3, $self->GetLastStatusProcessedTime());
  $report .= "</table>\n";
  return $report;
}

sub DoPriorityBreakdown
{
  my $self = shift;
  my $count = shift;
  my $sql = shift;
  my $max = shift;
  my $class = shift;
  my $dbh = $self->get( 'dbh' );
  my @breakdown = map {'';} (0..$max);
  $sql = "SELECT priority,COUNT(priority) FROM queue WHERE id IN ($sql) GROUP BY priority ORDER BY priority";
  my $rows = $dbh->selectall_arrayref( $sql );
  foreach my $row ( @{$rows} )
  {
    my $pri = $row->[0];
    my $n = $row->[1];
    my $pct = 0.0;
    eval {$pct = $n/$count*100.0;};
    #$breakdown[$pri] = sprintf('%d&nbsp;(%.1f%%)', $n, $pct);
    $breakdown[$pri] = $n;
  }
  return join '',map {"<td$class>$_</td>"} @breakdown;
}


sub GetTotalReviewedNotProcessed
{
    my $self = shift;

    my $sql = qq{ SELECT count(distinct id) from $CRMSGlobals::reviewsTable where id in ( select id from $CRMSGlobals::queueTable where status = 0)};
    my $count = $self->SimpleSqlGet( $sql );
    
    if ($count) { return $count; }
    return 0;
}

sub GetTotalAwaitingReview
{
    my $self = shift;

    my $sql = qq{ SELECT count(distinct id) from $CRMSGlobals::queueTable where status=0 and id not in ( select id from $CRMSGlobals::reviewsTable)};
    my $count = $self->SimpleSqlGet( $sql );
    
    if ($count) { return $count; }
    return 0;
}


sub GetLastLoadSizeToCandidates
{
    my $self = shift;

    my $sql = qq{SELECT addedamount from candidatesrecord order by time DESC LIMIT 1};
    my $count = $self->SimpleSqlGet( $sql );
    
    if ($count) { return $count; }
    return 0;

}

sub GetLastLoadTimeToCandidates
{
    my $self = shift;

    my $sql = qq{SELECT max(time) from candidatesrecord};
    my $time = $self->SimpleSqlGet( $sql );
    
    if ($time) { return $time; }
    return 'no data available';

}


sub GetTotalExported
{
    my $self = shift;

    my $sql = qq{SELECT sum( itemcount ) from $CRMSGlobals::exportrecordTable};
    my $count = $self->SimpleSqlGet( $sql );
    
    if ($count) { return $count; }
    return 0;

}


sub GetTotalEverInQueue
{
    my $self = shift;

    my $count_exported = $self->GetTotalExported();
    my $count_queue = $self->GetQueueSize();
    
    my $total = $count_exported +  $count_queue;
    return $total;
}

sub GetLastExport
{
    my $self = shift;

    my $sql = "SELECT itemcount,time FROM exportrecord WHERE itemcount>0 ORDER BY time DESC LIMIT 1";
    my $ref = $self->get( 'dbh' )->selectall_arrayref( $sql );
    my $count = $ref->[0]->[0];
    my $time = $ref->[0]->[1];
    return ($count,$time);

}

sub GetTotalLegacyCount
{
    my $self = shift;

    my $sql = qq{ SELECT COUNT(DISTINCT id) FROM $CRMSGlobals::historicalreviewsTable WHERE legacy=1 AND priority!=1 };
    my $ref = $self->get( 'dbh' )->selectall_arrayref( $sql );

    return $ref->[0]->[0];
}

sub GetTotalNonLegacyReviewCount
{
    my $self = shift;

    my $sql = qq{ SELECT COUNT(*) FROM $CRMSGlobals::historicalreviewsTable WHERE legacy!=1};
    my $ref = $self->get( 'dbh' )->selectall_arrayref( $sql );

    return $ref->[0]->[0];
}

sub GetTotalLegacyReviewCount
{
    my $self = shift;

    my $sql = qq{ SELECT COUNT(*) FROM $CRMSGlobals::historicalreviewsTable WHERE legacy=1};
    my $ref = $self->get( 'dbh' )->selectall_arrayref( $sql );

    return $ref->[0]->[0];

}

sub GetTotalHistoricalReviewCount
{
    my $self = shift;

    my $sql = qq{ SELECT COUNT(*) from $CRMSGlobals::historicalreviewsTable};
    my $ref = $self->get( 'dbh' )->selectall_arrayref( $sql );

    return $ref->[0]->[0];

}

sub GetLastQueueTime
{
    my $self = shift;

    my $sql = qq{ SELECT max( time ) from $CRMSGlobals::queuerecordTable where source = 'RIGHTSDB'};
    my $latest_time = $self->SimpleSqlGet( $sql );
    
    #Keep only the date
    #$latest_time =~ s,(.*) .*,$1,;

    return $latest_time;

}

sub GetLastStatusProcessedTime
{

    my $self = shift;

    my $sql = qq{ SELECT max(time) from  processstatus };
    my $last_time = $self->SimpleSqlGet( $sql );
    
    return $last_time;
}

sub GetLastIdQueueCount
{
    my $self = shift;

    my $latest_time = $self->GetLastQueueTime();

    my $sql = qq{ SELECT itemcount from $CRMSGlobals::queuerecordTable where time like '$latest_time%' AND source='RIGHTSDB'};
    my $latest_time = $self->SimpleSqlGet( $sql );
    
    return $latest_time;

}

sub DownloadSpreadSheetBkup
{
    my $self = shift;
    my $buffer = shift;

    if ($buffer)
    {

      my $ZipDir = qq{/tmp/out};
      `chmod 777 $ZipDir`;
      `rm -rf $ZipDir`;
      my $file = qq{$ZipDir\.zip};
      `rm -f $file`;
      `mkdir $ZipDir`;
      `chmod 777 $ZipDir`;

      #The out directory has to already exists.
      open  (FH, "> $ZipDir/out");
      print FH $buffer;
      close(FH);
      `chmod 777 $ZipDir/out`;

      my $ZipExec = '/usr/bin/zip';
      
      #/l/local/bin/zip
      #Call Unix to Zip the files
      my @args = ("$ZipExec", "-r", "$ZipDir", "$ZipDir");
      my $msg = qq{Error zipping file:};
      system (@args) == 0 or &errorBail( $msg );
      
      my $ZipFile = qq{/tmp/out.zip};
      $self->OutputZipFile ( $ZipFile );


    }

}

sub DownloadSpreadSheet
{
    my $self = shift;
    my $buffer = shift;

    if ($buffer)
    {

      print &CGI::header(-type => 'text/plain', -charset => 'utf-8'
                      );

      print $buffer;
   
    }

    return;

}

sub OutputZipFile
{
    my $self = shift;
    my $ZipFile = shift;

    open FH, "<$ZipFile";

    binmode(FH);

    print &CGI::header(-type => 'application/x-compressed',
                      );
    my ($bytesRead, $buffer);
    while ( $bytesRead = read(FH, $buffer, 1024) )
    {
        print $buffer;
    }
    
    close (FH);

    return;

}


sub CountAllReviewsForUser
{
  my $self = shift;
  my $user = shift;
  
  my $n = 0;
  my $sql = "SELECT count(*) FROM reviews WHERE user='$user'";
  $n += $self->SimpleSqlGet($sql);
  $sql = "SELECT count(*) FROM historicalreviews WHERE user='$user'";
  $n += $self->SimpleSqlGet($sql);
  return $n;
}


sub IsReviewCorrect
{
  my $self = shift;
  my $id = shift;
  my $user = shift;
  my $time = shift;
  
  return 1 if $self->IsUserExpert($user);
  my $sql = <<END;
    SELECT id FROM historicalreviews h1 WHERE id='$id' AND user='$user' AND time='$time' AND status=5 AND id IN
    (SELECT id FROM historicalreviews h2 WHERE h1.id=h2.id AND h1.user!=h2.user AND
     (h1.attr!=h2.attr OR h1.reason!=h2.reason OR
      (h1.attr=2 AND h1.reason=7 AND (h1.renNum!=h2.renNum OR h1.renDate!=h2.renDate)))
    AND h2.user IN
    (SELECT DISTINCT id FROM users WHERE type=2))
END
  return ($self->SimpleSqlGet( $sql ))? 0:1;
}


sub CountCorrectReviews
{
  my $self = shift;
  my $user = shift;
  my $start = shift;
  my $end = shift;
  #printf "CountCorrectReviews(%s)\n", join ', ', ($user,$start,$end);
  my $type1Clause = sprintf(' AND user IN (%s)', join(',', map {"'$_'"} $self->GetType1Reviewers()));
  my $startClause = ($start)? " AND time>='$start'":'';
  my $endClause = ($end)? " AND time<='$end' ":'';
  my $userClause = ($user eq 'all')? $type1Clause:" AND user='$user'";
  my $sql = "SELECT count(*) FROM $CRMSGlobals::historicalreviewsTable WHERE legacy=0 $startClause $endClause $userClause";
  my $total = $self->SimpleSqlGet($sql);
  #print "$sql => $total\n\n";
  my $correct = $total;
  if (!$self->IsUserExpert($user))
  {
    my $sql = "SELECT count(*) FROM $CRMSGlobals::historicalreviewsTable WHERE legacy=0 AND validated=1 $startClause $endClause $userClause";
    $correct = $self->SimpleSqlGet($sql);
    #print "$sql => $correct\n\n";
  }
  return ($correct,$total);
}


# Utility (I used it for debugging UTF-8 problems)
sub HexDump
{
  $_ = shift;
  my $offset = 0;
  my(@array,$format);
  my $dump = '';
  foreach my $data (unpack("a16"x(length($_[0])/16)."a*",$_[0]))
  {
    my($len)=length($data);
    if ($len == 16)
    {
      @array = unpack('N4', $data);
      $format="0x%08x (%05d)   %08x %08x %08x %08x   %s\n";
    }
    else
    {
      @array = unpack('C*', $data);
      $_ = sprintf "%2.2x", $_ for @array;
      push(@array, '  ') while $len++ < 16;
      $format="0x%08x (%05d)" .
           "   %s%s%s%s %s%s%s%s %s%s%s%s %s%s%s%s   %s\n";
    }
    $data =~ tr/\0-\37\177-\377/./;
    $dump .= sprintf $format,$offset,$offset,@array,$data;
    $offset += 16;
  }
  return $dump;
}

# Gets only those reviewers that are not experts
sub GetType1Reviewers
{
  my $self = shift;
  my $dbh = $self->get( 'dbh' );
  my $sql = 'SELECT DISTINCT id FROM users WHERE id NOT LIKE "rereport%" AND id NOT IN (SELECT id FROM users WHERE type=2)';
  return map {$_->[0]} @{$dbh->selectall_arrayref( $sql )};
}

sub GetMedianCorrect
{
  my $self = shift;
  my $start = shift;
  my $end = shift;
  my @users = $self->GetType1Reviewers();
  my @good = ();
  foreach my $user (@users)
  {
    my ($ncorr,$total) = $self->CountCorrectReviews($user, $start, $end);
    next unless $total;
    my $frac = 0.0;
    eval { $frac = 100.0*$ncorr/$total; };
    push @good, $frac;
  }
  @good = sort { $a <=> $b } @good;
  my $med = (scalar @good % 2 == 1)? $good[scalar @good / 2]  : ($good[(scalar @good / 2)-1] + $good[scalar @good / 2]) / 2;
  return $med;
}

# Is this a properly formatted RenDate?
sub IsRenDate
{
  my $self = shift;
  my $date = shift;
  my $rendateRE = '^\d\d?(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\d\d$';
  return ($date eq '' || $date =~ m/$rendateRE/);
}

sub SanityCheckDB
{
  my $self = shift;
  my $dbh = $self->get( 'dbh' );
  my $vidRE = '^[a-z]+\d?\.[a-zA-Z]?\d+$';
  my $pdRE = '^\d\d\d\d-\d\d-\d\d$';
  # ======== bibdata ========
  my $table = 'bibdata';
  # Volume ID must not have any spaces before, after, or in.
  # MySQL years should be valid, but it stores a value of '0000-00-00' in case of illegal value entered.
  my $sql = "SELECT id,pub_date,author,title FROM $table";
  my $rows = $dbh->selectall_arrayref( $sql );
  foreach my $row ( @{$rows} )
  {
    my $md = $self->MetadataURL($row->[0]);
    $md =~ s/&/&amp;/g;
    $self->SetError(sprintf("$table __ illegal volume id__ '%s'", $row->[0])) unless $row->[0] =~ m/$vidRE/;
    $self->SetError(sprintf("$table __ illegal pub_date for %s__ %s", $row->[0], $row->[1])) unless $row->[1] =~ m/$pdRE/;
    $self->SetError(sprintf("$table __ illegal pub_date for <a href='%s' target='_blank'>%s</a>__ %s", $md, $row->[0], $row->[1])) if substr($row->[1], 0, 4) eq '0000';
    #$self->SetError(sprintf("$table __ no author for %s__ '%s'", $row->[0], $row->[2])) if $row->[2] eq '';
    $self->SetError(sprintf("$table __ no title for <a href='%s' target='_blank'>%s</a>__ '%s'", $md, $row->[0], $row->[3])) if $row->[3] eq '';
    $self->SetError(sprintf("$table __ author encoding (%s) questionable for <a href='%s' target='_blank'>%s</a>__ '%s'", (utf8::is_utf8($row->[2]))?'utf-8':'ASCII', $md, $row->[0], $row->[2])) if $self->Mojibake($row->[2]);
    $self->SetError(sprintf("$table __ title encoding (%s) questionable for <a href='%s' target='_blank'>%s</a>__ '%s'", (utf8::is_utf8($row->[3]))?'utf-8':'ASCII', $md, $row->[0], $row->[3])) if $self->Mojibake($row->[3]);
    $self->SetError(sprintf("$table __ author encoding (%s) questionable for <a href='%s' target='_blank'>%s</a>__ '%s'", (utf8::is_utf8($row->[2]))?'utf-8':'ASCII', $md, $row->[0], $row->[2])) if $row->[2] =~ m/.*?\?\?.*/;
    $self->SetError(sprintf("$table __ title encoding (%s) questionable for <a href='%s' target='_blank'>%s</a>__ '%s'", (utf8::is_utf8($row->[3]))?'utf-8':'ASCII', $md, $row->[0], $row->[3])) if $row->[3] =~ m/.*?\?\?.*/;
  }
  # ======== candidates ========
  $table = 'candidates';
  $sql = "SELECT id,pub_date,author,title FROM $table";
  $rows = $dbh->selectall_arrayref( $sql );
  foreach my $row ( @{$rows} )
  {
    my $md = $self->MetadataURL($row->[0]);
    $md =~ s/&/&amp;/g;
    $self->SetError(sprintf("$table __ illegal volume id__ '%s'", $row->[0])) unless $row->[0] =~ m/$vidRE/;
    $self->SetError(sprintf("$table __ illegal pub_date for %s__ %s", $row->[0], $row->[1])) unless $row->[1] =~ m/$pdRE/;
    $self->SetError(sprintf("$table __ illegal pub_date for <a href='%s' target='_blank'>%s</a>__ %s", $md, $row->[0], $row->[1])) if substr($row->[1], 0, 4) eq '0000';
    $self->SetError(sprintf("$table __ no title for %s__ '%s'", $row->[0], $row->[3])) if $row->[3] eq '';
    $self->SetError(sprintf("$table __ author encoding (%s) questionable for <a href='%s' target='_blank'>%s</a>__ '%s'", (utf8::is_utf8($row->[2]))?'utf-8':'ASCII', $md, $row->[0], $row->[2])) if $self->Mojibake($row->[2]);
    $self->SetError(sprintf("$table __ title encoding (%s) questionable for <a href='%s' target='_blank'>%s</a>__ '%s'", (utf8::is_utf8($row->[3]))?'utf-8':'ASCII', $md, $row->[0], $row->[3])) if $self->Mojibake($row->[3]);
    $self->SetError(sprintf("$table __ author encoding (%s) questionable for <a href='%s' target='_blank'>%s</a>__ '%s'", (utf8::is_utf8($row->[2]))?'utf-8':'ASCII', $md, $row->[0], $row->[2])) if $row->[2] =~ m/.*?\?\?.*/;
    $self->SetError(sprintf("$table __ title encoding (%s) questionable for <a href='%s' target='_blank'>%s</a>__ '%s'", (utf8::is_utf8($row->[3]))?'utf-8':'ASCII', $md, $row->[0], $row->[3])) if $row->[3] =~ m/.*?\?\?.*/;
  }
  # ======== exportdata/exportdataBckup ========
  foreach $table ('exportdata','exportdataBckup')
  {
    # time must be in a format like 2009-07-16 07:00:02
    # id must not be ill-formed
    # attr/reason must be valid
    # user must be crms
    $sql = "SELECT time,id,attr,reason,user FROM $table";
    $rows = $dbh->selectall_arrayref( $sql );
    foreach my $row ( @{$rows} )
    {
      $self->SetError(sprintf("$table __ illegal time for %s__ '%s'", $row->[1], $row->[0])) unless $row->[0] =~ m/\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d/;
      $self->SetError(sprintf("$table __ illegal volume id__ '%s'", $row->[1])) unless $row->[1] =~ m/$vidRE/;
      my $comb = $row->[2] . '/' . $row->[3];
      $self->SetError(sprintf("$table __ illegal attr/reason for %s__ '%s'", $row->[1], $comb)) unless $self->GetAttrReasonCom($comb);
      $self->SetError(sprintf("$table __ illegal user for %s__ '%s' (should be 'crms')", $row->[1])) unless $row->[4] eq 'crms';
    }
  }
  # ======== exportrecord ========
  $table = 'exportrecord';
  $sql = "SELECT time FROM $table WHERE time='0000-00-00 00:00:00'";
  $rows = $dbh->selectall_arrayref( $sql );
  foreach my $row ( @{$rows} )
  {
    $self->SetError(sprintf("$table __ illegal time__ %s", $row->[0]));
  }
  # ======== historicalreviews ========
  $table = 'historicalreviews';
  $sql = "SELECT id,time,user,attr,reason,note,renNum,expert,duration,legacy,expertNote,renDate,copyDate,category,flagged,status,priority FROM $table";
  $rows = $dbh->selectall_arrayref( $sql );
  my %stati = (1=>1,4=>1,5=>1,6=>1);
  foreach my $row ( @{$rows} )
  {
    $self->SetError(sprintf("$table __ illegal volume id '%s'", $row->[0])) unless $row->[0] =~ m/$vidRE/;
    $self->SetError(sprintf("$table __ illegal time for %s__ '%s'", $row->[0], $row->[1])) unless $row->[1] =~ m/\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d/;
    $self->SetError(sprintf("$table __ illegal attr/reason for %s__ '%s/%s'", $row->[0], $row->[3], $row->[4])) unless $self->GetCodeFromAttrReason($row->[3],$row->[4]);
    $self->SetError(sprintf("$table __ spaces in renNum for %s__ '%s'", $row->[0], $row->[6])) if $row->[6] =~ m/(^\s+.*)|(.*?\s+$)/;
    $self->SetError(sprintf("$table __ illegal renDate for %s__ '%s' (should be like '14Oct70')", $row->[0], $row->[11])) unless $self->IsRenDate($row->[11]);
    $self->SetError(sprintf("$table __ illegal copyDate for %s__ '%s'", $row->[0], $row->[12])) unless $row->[12] eq '' or $row->[12] =~ m/\d\d\d\d/;
    $self->SetError(sprintf("$table __ illegal category for %s__ '%s'", $row->[0], $row->[13])) unless $row->[13] eq '' or $self->IsValidCategory($row->[13]);
    $self->SetError(sprintf("$table __ illegal status for %s__ '%s'", $row->[0], $row->[15])) unless $stati{$row->[15]};
    # FIXME: make sure there are no status 5 items that are not reviewed by an expert
  }
  # ======== queue ========
  $table = 'queue';
  $sql = "SELECT id,time,status,locked,priority,expcnt FROM $table";
  $rows = $dbh->selectall_arrayref( $sql );
  foreach my $row ( @{$rows} )
  {
    $self->SetError(sprintf("$table __ illegal volume id '%s'", $row->[0])) unless $row->[0] =~ m/$vidRE/;
    $self->SetError(sprintf("$table __ illegal time for %s__ '%s'", $row->[0], $row->[1])) unless $row->[1] =~ m/\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d/;
    $self->SetError(sprintf("$table __ illegal status for %s__ '%s'", $row->[0], $row->[2])) unless $row->[2] >= 0 and $row->[2] <= 6;
    if ($row->[2] == 5 || $row->[6])
    {
      $sql = sprintf("SELECT SUM(expert) FROM reviews WHERE id='%s'", $row->[0]);
      my $sum = $self->SimpleSqlGet($sql);
      $self->SetError(sprintf("$table __ illegal status/expcnt for %s__ '%s'/'%s' but there are no expert reviews", $row->[0], $row->[2])) unless $sum;
    }
  }
  # ======== reviews ========
  $table = 'reviews';
  $sql = "SELECT id,time,user,attr,reason,note,renNum,expert,duration,legacy,expertNote,renDate,copyDate,category,flagged,priority FROM $table";
  $rows = $dbh->selectall_arrayref( $sql );
  foreach my $row ( @{$rows} )
  {
    $self->SetError(sprintf("$table __ illegal volume id '%s'", $row->[0])) unless $row->[0] =~ m/$vidRE/;
    $self->SetError(sprintf("$table __ illegal time for %s__ '%s'", $row->[0], $row->[1])) unless $row->[1] =~ m/\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d/;
    $self->SetError(sprintf("$table __ illegal attr/reason for %s__ '%s/%s'", $row->[0], $row->[3], $row->[4])) unless $self->GetCodeFromAttrReason($row->[3],$row->[4]);
    $self->SetError(sprintf("$table __ spaces in renNum for %s__ '%s'", $row->[0], $row->[6])) if $row->[6] =~ m/(^\s+.*)|(.*?\s+$)/;
    $self->SetError(sprintf("$table __ illegal renDate for %s__ '%s' (should be like '14Oct70')", $row->[0], $row->[11])) unless $self->IsRenDate($row->[11]);
    $self->SetError(sprintf("$table __ illegal copyDate for %s__ '%s'", $row->[0], $row->[12])) unless $row->[12] eq '' or $row->[12] =~ m/\d\d\d\d/;
    $self->SetError(sprintf("$table __ illegal category for %s__ '%s'", $row->[0], $row->[13])) unless $row->[13] eq '' or $self->IsValidCategory($row->[13]);
  }
  # FIXME: make sure there are no und/nfi pairs with status other than 3
}

# Looks for stuff that the DB thinks is UTF-8 but is actually ISO Latin-1 8991 Shift-JIS or whatever.
sub Mojibake
{
  my $self = shift;
  my $text = shift;
  my $mojibake = '[ÊÃÄÅ¶¹¸©×«»§¼¡±]';
  return ($text =~ m/$mojibake/i);
}

sub ReviewSearchMenu
{
  my $self = shift;
  my $page = shift;
  my $searchName = shift;
  my $searchVal = shift;
  
  my @keys = ('Identifier','Title','Author','PubDate', 'Status','Legacy','UserId','Attribute',  'Reason',       'NoteCategory', 'Priority', 'Validated');
  my @labs = ('Identifier','Title','Author','Pub Date','Status','Legacy','User',  'Attr Number','Reason Number','Note Category','Priority', 'Verdict');
  if ($page ne 'adminHistoricalReviews')
  {
    splice @keys, 11, 1;
    splice @labs, 11, 1;
  }
  if (!$self->IsUserAdmin())
  {
    splice @keys, 10, 1;
    splice @labs, 10, 1;
  }
  if ($page eq 'userReviews' || $page eq 'editReviews')
  {
    splice @keys, 6, 1;
    splice @labs, 6, 1;
  }
  if ($page ne 'adminHistoricalReviews')
  {
    splice @keys, 3, 1;
    splice @labs, 3, 1;
  }
  my $html = "<select name='$searchName'>\n";
  foreach my $i (0 .. scalar @keys - 1)
  {
    $html .= sprintf(qq{  <option value="%s"%s>%s</option>\n}, $keys[$i], ($searchVal eq $keys[$i])? ' selected="selected"':'', $labs[$i]);
  }
  $html .= "</select>\n";
  return $html;
}

sub QueueSearchMenu
{
  my $self = shift;
  my $searchName = shift;
  my $searchVal = shift;
  
  my @keys = ('Identifier','Title','Author','PubDate', 'Status','Locked','Priority','Reviews','ExpertCount');
  my @labs = ('Identifier','Title','Author','Pub Date','Status','Locked','Priority','Reviews','Expert Reviews');
  my $html = "<select name='$searchName'>\n";
  foreach my $i (0 .. scalar @keys - 1)
  {
    $html .= sprintf(qq{  <option value="%s"%s>%s</option>\n}, $keys[$i], ($searchVal eq $keys[$i])? ' selected="selected"':'', $labs[$i]);
  }
  $html .= "</select>\n";
  return $html;
}

sub PageToEnglish
{
  my $self = shift;
  my $page = shift;
  my %pages = ('admin' => 'administrator page',
               'adminEditUser' => 'administer user accounts',
               'adminHistoricalReviews' => 'view all historical reviews',
               'adminQueue' => 'manage the queue',
               'adminReviews' => 'view all active reviews',
               'adminUser' => 'administer user accounts',
               'adminUserRate' => 'view user review rates',
               'editReviews' => 'edit reviews',
               'expert' => 'expert review',
               'exportStats' => 'export statistics',
               'queueAdd' => 'add to queue',
               'queueStatus' => 'queue status',
               'undReviews' => 'und/nfi items',
               'userRate' => 'view your review rate',
               'userReviews' => 'view your processed reviews',
               'debug' => 'debug',
               'rights' => 'rights query',
               'queue' => 'queue query',
               'determinationStats' => 'determination stats'
              );
  return $pages{$page} || 'home';
}

# Query the production rights database
sub RightsQuery
{
  my $self = shift;
  my $id = shift;
  my ($namespace,$n) = split '\.', $id;
  my $sql = 'SELECT a.name,rs.name,s.name,r.user,r.time,r.note FROM rights r, attributes a, reasons rs, sources s ' .
            "WHERE r.namespace='$namespace' AND r.id='$n' AND s.id=r.source AND a.id=r.attr AND rs.id=r.reason " .
            'ORDER BY r.time';
  return $self->get('sdr_dbh')->selectall_arrayref($sql);
}


1;
