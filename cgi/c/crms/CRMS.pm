package CRMS;

## ----------------------------------------------------------------------------
## Object of shared code for the CRMS DB CGI and BIN scripts
##
## ----------------------------------------------------------------------------

use strict;
use LWP::UserAgent;
use XML::LibXML;
use POSIX qw(strftime);
use DBI qw(:sql_types);

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
    $self->set( 'dbhP',         $self->ConnectToDbForTesting() );

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

    $dbh->{mysql_auto_reconnect} = 1;

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

    $dbh->{mysql_auto_reconnect} = 1;

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

    my $sdr_dbh   = DBI->connect( "DBI:mysql:mdp:$db_server", $db_user, $db_passwd,
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

    my $ref  = $self->get('dbh')->selectall_arrayref( $sql );
    return $ref->[0]->[0];
}

sub SimpleSqlGetForTesting
{
    my $self = shift;
    my $sql  = shift;

    my $ref  = $self->get('dbhP')->selectall_arrayref( $sql );
    return $ref->[0]->[0];
}


sub GetCandidatesTime
{
  my $self = shift;

  my $sql = qq{select max(time) from candidates};
  my $time  = $self->SimpleSqlGet( $sql );

  return $time;
  
}


sub GetCandidatesSize
{
  my $self = shift;

  my $sql = qq{select count(*) from candidates};
  my $size  = $self->SimpleSqlGet( $sql );

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
	my $id       = $row->[0];

      my $sql  = qq{ SELECT count(*) from candidates where id="mdp.$id"};
      my $incan  = $self->SimpleSqlGet( $sql );
      
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
	my $id       = $row->[0];

      my $sql  = qq{ SELECT count(*) from candidates where id="mdp.$id"};
      my $incan  = $self->SimpleSqlGetForTesting( $sql );
      
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
    my $self    = shift;

    my $start = $self->GetCandidatesTime();
    my $start_size = $self->GetCandidatesSize();

    my $msg = qq{Before load, the max timestamp in the cadidates table $start, and the size is $start_size\n};
    print $msg;

    my $sql = qq{SELECT CONCAT(namespace, '.', id) AS id, MAX(time) AS time, attr, reason FROM rights WHERE time >= '$start' GROUP BY id order by time asc};

    my $ref = $self->get('sdr_dbh')->selectall_arrayref( $sql );

    if ($self->get('verbose')) { print "found: " .  scalar( @{$ref} ) . ": $sql\n"; }

    ## design note: if these were in the same DB we could just INSERT
    ## into the new table, not SELECT then INSERT
    my $inqueue;
    foreach my $row ( @{$ref} ) 
    { 
      my $attr =  $row->[2];
      my $reason =  $row->[3];

      if ( ( $attr == 2 ) && ( $reason == 1 ) )
      {	
	$self->AddItemToCandidates( $row->[0], $row->[1], 0, 0 ); 
      }
    }

    my $end_size = $self->GetCandidatesSize();

    $msg = qq{After load, the cadidate has $end_size rows.\n\n};
    print $msg;

    my $diff = $end_size - $start_size;

    #Record the update to the queue
    my $sql = qq{INSERT INTO candidatesrecord ( addedamount ) values ( $diff )};
    $self->PrepareSubmitSql( $sql );



    return 1;
}


sub LoadNewItems
{
    my $self    = shift;

    my $queuesize = $self->GetQueueSize();

    my $msg = qq{Before load, the queue has $queuesize volumes.\n};
    print $msg;

    if ( $queuesize < 800 )
    {  
      my $limitcount = 800 - $queuesize;

      my $twodaysago = $self->TwoDaysAgo();
      
      my $sql = qq{SELECT id, time, pub_date, title, author from candidates where id not in ( select distinct id from reviews ) and id not in ( select distinct id from historicalreviews ) order by time desc};

      my $ref = $self->get('dbh')->selectall_arrayref( $sql );

      if ($self->get('verbose')) { print "found: " .  scalar( @{$ref} ) . ": $sql\n"; }

      ## design note: if these were in the same DB we could just INSERT
      ## into the new table, not SELECT then INSERT
      my $count = 0;
      my $inqueue;
      foreach my $row ( @{$ref} ) 
      { 
	my $pub_date = $row->[2];
        my $title = $row->[3];
        my $author = $row->[4];

	my $inqueue = $self->AddItemToQueue( $row->[0], $row->[1], $pub_date, $title, $author, 0, 0 ); 
	$count = $count + $inqueue;

	if ( $count == $limitcount )
	{
	  goto FINISHED;
	}
      }

    FINISHED:

      #Record the update to the queue
      my $sql = qq{INSERT INTO $CRMSGlobals::queuerecordTable (itemcount, source ) values ($count, 'RIGHTSDB')};
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

      my $author = $self->GetEncAuthor ( $id );
      ## my $ti   = $self->GetMarcDatafield( $id, "245", "a");
      my $title   = $self->GetRecordTitleBc2Meta( $id );
      $title  =~ s,\',\\',gs;

      my $sql = qq{REPLACE INTO candidates (id, time, pub_date, title, author) VALUES ('$id', '$time', '$pub', '$title', '$author')};

      $self->PrepareSubmitSql( $sql );
      
      return 1;

    }

    return 0;
}


sub AddItemToQueue
{
    my $self     = shift;
    my $id       = shift;
    my $time     = shift;
    my $pub_date = shift;
    my $title    = shift; 
    my $author   = shift;
    my $status   = shift;
    my $priority = shift;


    ## give the existing item higher priority
    if ( $self->IsItemInQueue( $id ) ) 
    {  
      my $sql = qq{UPDATE $CRMSGlobals::queueTable SET time='$time' WHERE id='$id'};
      $self->PrepareSubmitSql( $sql );

      #return 0 because item was not added.
      return 0;
    }

    my $sql = qq{INSERT INTO $CRMSGlobals::queueTable (id, time, status, pub_date, priority) VALUES ('$id', '$time', $status, '$pub_date', $priority)};

    $self->PrepareSubmitSql( $sql );
      
    $self->UpdateTitle ( $id, $title );
      
    #Update the pub date in bibdata
    $self->UpdatePubDate ( $id, $pub_date );
    
    if ( ! $author )
    {
      $author = $self->GetEncAuthor ( $id );

    }
    else
    {
      $author =~ s,\',\\\',g; ## escape '
      $author =~ s,\",\\\",g; ## escape "
    }
    $self->UpdateAuthor ( $id, $author );
      
    return 1;

    return 0;
}


sub AddItemToQueueOrSetItemActive
{
    my $self     = shift;
    my $id       = shift;
    my $time     = shift;
    my $status   = shift;
    my $priority = shift;

    ## give the existing item higher priority
    if ( $self->IsItemInQueue( $id ) ) 
    {  
      my $sql = qq{UPDATE $CRMSGlobals::queueTable SET priority=$priority WHERE id='$id'};
      $self->PrepareSubmitSql( $sql ); 
      return 1;
    }

    my $record =  $self->GetRecordMetadata($id);

    if ( $record eq '' ) { return  'item was not found in mirlyn';}
    
    ## pub date between 1923 and 1963
    my $pub = $self->GetPublDate( $id, $record );
    ## confirm date range and add check

    #Only care about volumes between 1923 and 1963
    if ( ( $pub >= '1923' ) && ( $pub <= '1963' ) )
    {

      ## no gov docs
      if ( $self->IsGovDoc( $id, $record ) ) { $self->Logit( "skip fed doc: $id" ); return 'item is not a gov doc'; }
      
      #check 008 field postion 17 = "u" - this would indicate a us publication.
      if ( ! $self->IsUSPub( $id, $record ) ) { $self->Logit( "skip not us doc: $id" ); return 'item is not a US pub'; }

      #check FMT.
      if ( ! $self->IsFormatBK( $id, $record ) ) { $self->Logit( "skip not fmt bk: $id" ); return 'item is not BK format'; }

      ## check for item, warn if already exists
      my $sql = qq{INSERT INTO $CRMSGlobals::queueTable (id, time, status, pub_date, priority) VALUES ('$id', '$time', $status, '$pub', $priority)};

      $self->PrepareSubmitSql( $sql );

      $self->UpdateTitle ( $id );

      #Update the pub date in bibdata
      $self->UpdatePubDate ( $id, $pub );

      my $author = $self->GetEncAuthor ( $id );
      $self->UpdateAuthor ( $id, $author );
      
      my $sql = qq{INSERT INTO $CRMSGlobals::queuerecordTable (itemcount, source ) values (1, 'ADMINUI')};
      $self->PrepareSubmitSql( $sql );


      return 1;
    }

    return 'item is not in the range of 1923 to 1963';
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
  if ( $self->IsItemInReviews( $id ) ) { return; }

  my $record =  $self->GetRecordMetadata($id);

  ## pub date between 1923 and 1963
  my $pub = $self->GetPublDate( $id, $record );
  ## confirm date range and add check

  #Only care about volumes between 1923 and 1963
  if ( ( $pub >= '1923' ) && ( $pub <= '1963' ) )
  {
    ## no gov docs
    if ( $self->IsGovDoc( $id, $record ) ) { $self->Logit( "skip fed doc: $id" ); return; }

    #check 008 field postion 17 = "u" - this would indicate a us publication.
    if ( ! $self->IsUSPub( $id, $record ) ) { $self->Logit( "skip not us doc: $id" ); return; }

    #check FMT.
    if ( ! $self->IsFormatBK( $id, $record ) ) { $self->Logit( "skip not fmt bk: $id" ); return 0; }

    my $sql  = qq{ SELECT count(*) from $CRMSGlobals::queueTable where id="$id"};
    my $count  = $self->SimpleSqlGet( $sql );
    if ( $count == 1 )
    {
        $sql = qq{ UPDATE $CRMSGlobals::queueTable SET priority = 1 WHERE id = "$id" };
        $self->PrepareSubmitSql( $sql );      
    }
    else
    {
      $sql = qq{INSERT INTO $CRMSGlobals::queueTable (id, time, status, pub_date, priority) VALUES ('$id', '$time', $status, '$pub', $priority)};

      $self->PrepareSubmitSql( $sql );

      $self->UpdateTitle ( $id );

      #Update the pub date in bibdata
      $self->UpdatePubDate ( $id, $pub );

      my $author = $self->GetEncAuthor ( $id );
      $self->UpdateAuthor ( $id, $author );

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
        $sql = qq{INSERT INTO $CRMSGlobals::queuerecordTable (time, itemcount, source ) values ($time, 1, 'ADMINSCRIPT')};
      }
      $self->PrepareSubmitSql( $sql );
    }
  }
}

sub IsItemInQueue
{
    my $self = shift;
    my $bar  = shift;

    my $sql  = qq{SELECT id FROM $CRMSGlobals::queueTable WHERE id = '$bar'};
    my $id   = $self->SimpleSqlGet( $sql );

    if ($id) { return 1; }
    return 0;
}

sub TranslateCategory
{
    my $self = shift;
    my $category  = shift;



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
    else  { return $category };
    
}

sub IsItemInReviews
{
    my $self = shift;
    my $bar  = shift;

    my $sql  = qq{SELECT id FROM $CRMSGlobals::reviewsTable WHERE id = '$bar'};
    my $id   = $self->SimpleSqlGet( $sql );

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

    if ( ! $self->CheckForId( $id ) )                     { $self->Logit("id check failed");          return 0; }
    if ( ! $self->CheckReviewer( $user, $exp ) )          { $self->Logit("review check failed");      return 0; }
    if ( ! $self->ValidateAttr( $attr ) )                 { $self->Logit("attr check failed");        return 0; }
    if ( ! $self->ValidateReason( $reason ) )             { $self->Logit("reason check failed");      return 0; }
    if ( ! $self->CheckAttrReasonComb( $attr, $reason ) ) { $self->Logit("attr/reason check failed"); return 0; }

    #remove any blanks from renNum
    $renNum =~ s, ,,gs;

    ## do some sort of check for expert submissions

    $note =~ s,\',\\',gs;
    
    my $sql = qq{ SELECT priority FROM $CRMSGlobals::queueTable WHERE id='$id' LIMIT 1 };
    my $priority = $self->SimpleSqlGet( $sql );
    
    my @fieldList = ('id', 'user', 'attr', 'reason', 'note', 'renNum', 'renDate', 'category', 'priority');
    my @valueList = ($id,  $user,  $attr,  $reason,  $note,  $renNum,  $renDate, $category, $priority);

    if ($exp)      { push(@fieldList, "expert");   push(@valueList, $exp); }
    if ($copyDate) { push(@fieldList, "copyDate"); push(@valueList, $copyDate); }
    
    $sql = qq{REPLACE INTO $CRMSGlobals::reviewsTable (} . join(", ", @fieldList) . 
           qq{) VALUES('} . join("', '", @valueList) . qq{')};

    if ( $self->get('verbose') ) { $self->Logit( $sql ); }

    $self->PrepareSubmitSql( $sql );

    if ( $exp ) { $self->SetExpertReviewCnt( $id, $user );  }

    $self->EndTimer( $id, $user );
    $self->UnlockItem( $id, $user );

    return 1;
}


sub SetExpertReviewCnt
{
    my $self = shift;
    my $id   = shift;

    my $sql = qq{ UPDATE $CRMSGlobals::queueTable set expcnt=1 WHERE id = "$id" };
    $self->PrepareSubmitSql( $sql );

    #We have decided to register the expert decission right away.
    $self->RegisterExpertReview( $id );

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
        my $id      =  $row->[0];
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

    my $yesterday = $self->GetYesterday();
 
    my $sql = qq{SELECT id, user, attr, reason, renNum, renDate FROM $CRMSGlobals::reviewsTable WHERE id IN ( SELECT id from $CRMSGlobals::queueTable where status = 0) group by id having count(*) = 2};

    my $ref = $self->get( 'dbh' )->selectall_arrayref( $sql );

    foreach my $row ( @{$ref} )
    {
        my $id      =  $row->[0];
	my $user    = $row->[1];
	my $attr    = $row->[2];
        my $reason  = $row->[3];
	my $renNum  = $row->[4];
        my $renDate = $row->[5];

        my ( $other_user, $other_attr, $other_reason, $other_renNum, $other_renDate ) = $self->GetOtherReview ( $id, $user );

	if ( ( $attr == $other_attr ) && ( $reason == $other_reason ) )
	{
           #If both und/nfi them status is 3
	   if ( ( $attr == 5 ) && ( $reason == 8 ) )
	   {
	      $self->RegisterStatus( $id, 3 );	      
	   }
	   else #Mark as 4 - two that agree
	   {
	      #If they are ic/ren then the renal date and id must match
	      if ( ( $attr == 2 ) && ( $reason == 7 ) )
	      {
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

    my $sql  = qq{ INSERT INTO  processstatus VALUES ( )};
    $self->PrepareSubmitSql( $sql );

}

sub GetUnProcessCounts
{
    my $self = shift;

    my $yesterday = $self->GetYesterday();
 
    my $sql = qq{SELECT id, user, attr, reason, renNum, renDate FROM $CRMSGlobals::reviewsTable WHERE id IN ( SELECT id from $CRMSGlobals::queueTable where status = 0) group by id having count(*) = 2};

    my $ref = $self->get( 'dbh' )->selectall_arrayref( $sql );


    my $reviewonlycnt = 0;
    my $matchcnt = 0;
    my $conflictcnt = 0;
    my $undcnt = 0;

    foreach my $row ( @{$ref} )
    {
        my $id      =  $row->[0];
	my $user    = $row->[1];
	my $attr    = $row->[2];
        my $reason  = $row->[3];
	my $renNum  = $row->[4];
        my $renDate = $row->[5];

        my ( $other_user, $other_attr, $other_reason, $other_renNum, $other_renDate ) = $self->GetOtherReview ( $id, $user );

	if ( ( $attr == $other_attr ) && ( $reason == $other_reason ) )
	{
           #If both und/nfi them status is 3
	   if ( ( $attr == 5 ) && ( $reason == 8 ) )
	   {
	       $undcnt = $undcnt + 1;	      
	   }
	   else #Mark as 4 - two that agree
	   {
	      #If they are ic/ren then the renal date and id must match
	      if ( ( $attr == 2 ) && ( $reason == 7 ) )
	      {
		 if ( ( $renNum eq $other_renNum ) && ( $renDate eq $other_renDate ) )
		 {
		   #Mark as 4
		   $matchcnt = $matchcnt + 1;
		 }
		 else
		 {
		   #Mark as 2
		   $conflictcnt = $conflictcnt + 1;
		 }
	      }
	      else #all other cases mark as 4
	      {
		$matchcnt = $matchcnt + 1;
	      }
	    }
	  }
	  else #Mark as 2 - two that disagree 
	  {
	    $conflictcnt = $conflictcnt + 1;
	  }
    }

    $reviewonlycnt = $self->GetTotalReviewedNotProcessed () - $matchcnt - $conflictcnt - $undcnt;

    my $out = qq{ 1 reviews =>$reviewonlycnt, matches => $matchcnt, conflicts => $conflictcnt, und/nfi => $undcnt };
    return $out;

}



## ----------------------------------------------------------------------------
##  Function:   submit historical review  (from excel SS)   
##  Parameters: 
##  Return:     1 || 0
## ----------------------------------------------------------------------------
sub SubmitHistReview
{
    my $self = shift;
    my ($id, $user, $date, $attr, $reason, $cDate, $renNum, $renDate, $note, $eNote, $category, $status, $title) = @_;

    ## change attr and reason back to numbers
    $attr   = $self->GetRightsNum( $attr );
    $reason = $self->GetReasonNum( $reason );

    if ( ! $self->ValidateAttr( $attr ) )                 { $self->Logit("attr check failed");        return 0; }
    if ( ! $self->ValidateReason( $reason ) )             { $self->Logit("reason check failed");      return 0; }
    if ( ! $self->CheckAttrReasonComb( $attr, $reason ) ) { $self->Logit("attr/reason check failed"); return 0; }
    
    ## do some sort of check for expert submissions

    $note  = $self->get('dbh')->quote($note);
    $eNote = $self->get('dbh')->quote($eNote);

    ## all good, INSERT
    my $sql = qq{REPLACE INTO $CRMSGlobals::historicalreviewsTable (id, user, time, attr, reason, copyDate, renNum, renDate, note, expertNote, legacy, category, status) } .
              qq{VALUES('$id', '$user', '$date', '$attr', '$reason', '$cDate', '$renNum', '$renDate', $note, $eNote, 1, '$category', $status) };

    $self->PrepareSubmitSql( $sql );

    #Now load this info into the bibdata table.
    $self->UpdateTitle ( $id, $title );

    #Update the pub date in bibdata
    my $pub = $self->GetPublDate( $id );
    $self->UpdatePubDate ( $id, $pub );

    my $author = $self->GetEncAuthor ( $id );
    $self->UpdateAuthor ( $id, $author );

    return 1;
}


sub ClearQueueAndExport
{
    my $self   = shift;

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
    $self->Logit( "export reviewed items removed from queue ($eCount)" );
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

    my $user  = "crms";
    my $time  = $self->GetTodaysDate();
    my ( $fh, $file )    = $self->GetExportFh();
    my $user  = "crms";
    my $src   = "null";
    my $count = 0;

    foreach my $barcode ( @{$list} )
      {
	#The routine GetFinalAttrReason may need to change - jose
        my ($attr,$reason) = $self->GetFinalAttrReason($barcode); 

        print $fh "$barcode\t$attr\t$reason\t$user\t$src\n";

	my $sql  = qq{ INSERT INTO  exportdata (time, id, attr, reason, user )VALUES ('$time', '$barcode', '$attr', '$reason', '$user' )};
	$self->PrepareSubmitSql( $sql );

	my $sql  = qq{ INSERT INTO  exportdataBckup (time, id, attr, reason, user )VALUES ('$time', '$barcode', '$attr', '$reason', '$user' )};
	$self->PrepareSubmitSql( $sql );


        $self->MoveFromReviewsToHistoricalReviews($barcode); ## DEBUG
        $self->RemoveFromQueue($barcode); ## DEBUG

	$count = $count + 1;

    }
    close $fh;

    my $sql  = qq{ INSERT INTO  $CRMSGlobals::exportrecordTable (itemcount) VALUES ( $count )};
    $self->PrepareSubmitSql( $sql );

    $self->EmailReport ( $count, $file );	

}

sub EmailReport
{
  my $self    = shift;
  my $count   = shift;
  my $file    = shift;

  my $subject = qq{$count volumes exported to rights db};
  my $to = qq{annekz\@umich.edu};

  use Mail::Sender;
  my $sender = new Mail::Sender
    {smtp => 'mail.umdl.umich.edu', from => 'annekz@umich.edu'};
  $sender->MailFile({to => $to,
  		     subject => $subject,
  		     msg => "See attachment.",
  		     file => $file});
  $sender->Close;

}

sub GetNumberExportedFromCandidates
{
  my $self = shift;


  my $sql  = qq{ SELECT count(distinct id) from historicalreviews where legacy= 0 and id in (select id from candidates)};
  my $count  = $self->SimpleSqlGet( $sql );
    
  if ($count) { return $count; }
  return 0;

}

sub GetNumberExportedNotFromCandidates
{
  my $self = shift;

  my $sql  = qq{ SELECT count(distinct id) from historicalreviews where legacy= 0 and id not in (select id from candidates)};
  my $count  = $self->SimpleSqlGet( $sql );
    
  if ($count) { return $count; }
  return 0;


}

sub GetExportFh
{
    my $self = shift;
    my $date = $self->GetTodaysDate();
    $date    =~ s/:/_/g;
    $date    =~ s/ /_/g;
 
    my $out  = $self->get('root') . "/prep/c/crms/crms_" . $date . ".rights";

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


    my $sql = qq{INSERT into $CRMSGlobals::historicalreviewsTable (id, time, user, attr, reason, note, renNum, expert, duration, legacy, expertNote, renDate, copyDate, category, priority) select id, time, user, attr, reason, note, renNum, expert, duration, 0, expertNote, renDate, copyDate, category, priority from reviews where id='$id'};
    $self->PrepareSubmitSql( $sql );

    my $sql = qq{ UPDATE $CRMSGlobals::historicalreviewsTable set status=$status WHERE id = "$id" };
    $self->PrepareSubmitSql( $sql );


    $self->Logit( "remove $id from reviews" );

    my $sql = qq{ DELETE FROM $CRMSGlobals::reviewsTable WHERE id = "$id" };
    $self->PrepareSubmitSql( $sql );

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
    my $sql  = qq{SELECT id FROM $CRMSGlobals::queueTable WHERE status = 5 };
    my $ref  = $self->get( 'dbh' )->selectall_arrayref( $sql );

    return $ref;
}

sub GetDoubleRevItemsInAgreement
{
    my $self = shift;
    my $sql  = qq{SELECT id FROM $CRMSGlobals::queueTable WHERE status = 4 };
    my $ref  = $self->get( 'dbh' )->selectall_arrayref( $sql );

    return $ref;
}


sub RegisterExpertReview
{
    my $self = shift;
    my $id   = shift;

    my $sql  = qq{UPDATE $CRMSGlobals::queueTable SET status = 5 WHERE id = "$id"};

    $self->PrepareSubmitSql( $sql );
}

sub RegisterStatus
{
    my $self   = shift;
    my $id     = shift;
    my $status = shift;

    my $sql  = qq{UPDATE $CRMSGlobals::queueTable SET status = $status WHERE id = "$id"};

    $self->PrepareSubmitSql( $sql );
}

sub GetYesterday
{
    my $self    = shift;

    my $newtime = scalar localtime(time() - ( 24 * 60 * 60 ));
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
    my $day = substr($newtime, 8, 2);
    $day =~ s, ,0,g;
   
    my $yesterday = qq{$year-$month-$day};

    return $yesterday;
}


sub TwoDaysAgo
{
    my $self    = shift;

    my $newtime = scalar localtime(time() - ( 24 * 60 * 60 * 2 ));
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
    my $day = substr($newtime, 8, 2);
    $day =~ s, ,0,g;
   
    my $towdaysago = qq{$year-$month-$day};

    return $towdaysago;
}



sub ConvertToSearchTerm
{
    my $self           = shift;
    my $search         = shift;
    my $type           = shift;

    my $new_search = '';
    if     ( $search eq 'Identifier' ) { $new_search = qq{r.id}; }
    elsif  ( $search eq 'UserId' ) { $new_search = qq{r.user}; }
    elsif  ( $search eq 'Status' ) 
    { 
      if ( $type eq 'historicalreviews' ){ $new_search = qq{r.status};  }
      else { $new_search = qq{q.status};  }
    }
    elsif  ( $search eq 'Attribute' ) { $new_search = qq{r.attr}; }
    elsif  ( $search eq 'Reason' ) { $new_search = qq{r.reason}; }
    elsif  ( $search eq 'NoteCategory' ) { $new_search = qq{r.category}; }
    elsif  ( $search eq 'Legacy' ) { $new_search = qq{r.legacy}; }
    elsif  ( $search eq 'Title' ) { $new_search = qq{b.title}; }
    elsif  ( $search eq 'Author' ) { $new_search = qq{b.author}; }
    elsif  ( $search eq 'Priority' ) { $new_search = qq{r.priority}; }
    
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

    my $since              = shift;
    my $offset             = shift;

    my $type               = shift;
    my $limit              = shift;
    
    my $PageSize = $self->GetPageSize ();
  
    $search1 = $self->ConvertToSearchTerm ( $search1, $type );
    $search2 = $self->ConvertToSearchTerm ( $search2, $type );

    if ( ! $offset ) { $offset = 0; }

    if ( ( $type eq 'userreviews' ) || ( $type eq 'editreviews' ) )
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
    if ( $type eq 'reviews' )
    {
      $sql = qq{ SELECT r.id, r.time, r.duration, r.user, r.attr, r.reason, r.note, r.renNum, r.expert, r.copyDate, r.expertNote, r.category, r.legacy, r.renDate, r.priority, q.status, b.title, b.author FROM $CRMSGlobals::reviewsTable r, $CRMSGlobals::queueTable q, bibdata b WHERE q.id = r.id AND q.id = b.id AND q.status >= 0 };
    }
    elsif ( $type eq 'conflict' )
    {
      $sql = qq{ SELECT r.id, r.time, r.duration, r.user, r.attr, r.reason, r.note, r.renNum, r.expert, r.copyDate, r.expertNote, r.category, r.legacy, r.renDate, r.priority, q.status, b.title, b.author FROM $CRMSGlobals::reviewsTable r, $CRMSGlobals::queueTable q, bibdata b WHERE q.id = r.id AND q.id = b.id  AND ( q.status = 2 ) };
    }
    elsif ( $type eq 'historicalreviews' )
    {
      $sql = qq{ SELECT r.id, r.time, r.duration, r.user, r.attr, r.reason, r.note, r.renNum, r.expert, r.copyDate, r.expertNote, r.category, r.legacy, r.renDate, r.priority, r.status, b.title, b.author FROM $CRMSGlobals::historicalreviewsTable r, bibdata b  WHERE r.id = b.id AND r.status >= 0  };
    }
    elsif ( $type eq 'undreviews' )
    {
      $sql = qq{ SELECT r.id, r.time, r.duration, r.user, r.attr, r.reason, r.note, r.renNum, r.expert, r.copyDate, r.expertNote, r.category, r.legacy, r.renDate, r.priority, q.status, b.title, b.author FROM $CRMSGlobals::reviewsTable r, $CRMSGlobals::queueTable q, bibdata b WHERE q.id = b.id  AND q.id = r.id AND q.status = 3 };
    }
    elsif ( $type eq 'userreviews' )
    {
      my $user = $self->get( "user" );
      $sql = qq{ SELECT r.id, r.time, r.duration, r.user, r.attr, r.reason, r.note, r.renNum, r.expert, r.copyDate, r.expertNote, r.category, r.legacy, r.renDate, r.priority, q.status, b.title, b.author FROM $CRMSGlobals::reviewsTable r, $CRMSGlobals::queueTable q, bibdata b WHERE q.id = r.id AND q.id = b.id AND r.user = '$user' AND q.status > 0 };
    }
    elsif ( $type eq 'editreviews' )
    {
      my $user = $self->get( "user" );
      my $yesterday = $self->GetYesterday();
      $sql = qq{ SELECT r.id, r.time, r.duration, r.user, r.attr, r.reason, r.note, r.renNum, r.expert, r.copyDate, r.expertNote, r.category, r.legacy, r.renDate, r.priority, q.status, b.title, b.author FROM $CRMSGlobals::reviewsTable r, $CRMSGlobals::queueTable q, bibdata b WHERE q.id = r.id AND q.id = b.id AND r.user = '$user' AND r.time >= "$yesterday" };
    }

    my ( $search1term, $search2term );
    if ( $search1value =~ m,.*\*.*, )
    {
      $search1value =~ s,\*,%,gs;
      $search1term = qq{$search1 like '$search1value'};
    }
    else
    {
      $search1term = qq{$search1 = '$search1value'};
    }
    if ( $search2value =~ m,.*\*.*, )
    {
      $search2value =~ s,\*,%,gs;
      $search2term = qq{$search2 like '$search2value'};
    }
    else
    {
      $search2term = qq{$search2 = '$search2value'};
    }

    if ( ( $search1value ne "" ) && ( $search2value ne "" ) )
    {
      { $sql .= qq{ AND ( $search1term  $op1  $search2term ) };   }
    }
    elsif ( $search1value ne "" )
    {
      { $sql .= qq{ AND $search1term  };   }
    }
    elsif (  $search2value ne "" )
    {
      { $sql .= qq{ AND $search2term  };   }
    }

    if ( $since ) { $sql .= qq{ AND r.time >= "$since" }; }

    my $limit_section = '';
    if ( $limit )
    {
      $limit_section = qq{LIMIT $offset, $PageSize};
    }
    if ( $order eq 'status' )
    {
      if ( $type eq 'historicalreviews' )
      {
        $sql .= qq{ ORDER BY r.$order $direction $limit_section };
      }
      else
      {
        $sql .= qq{ ORDER BY q.$order $direction $limit_section };
      }
    }
    elsif ( ( $order eq 'title' ) || ( $order eq 'author' ) )
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

    my $since              = shift;
    my $offset             = shift;

    my $type               = shift;
    my $limit              = 0;

    my $isadmin = $self->IsUserAdmin();
    my $sql =  $self->CreateSQL ( $order, $direction, $search1, $search1value, $op1, $search2, $search2value, $since,$offset, $type, $limit );
    
    my $ref = $self->get( 'dbh' )->selectall_arrayref( $sql );

    my $buffer;
    if ( scalar @{$ref} != 0 )
    {
	if ( $type eq 'userreviews')
	{
	  $buffer .= qq{id\ttitle\tauthor\ttime\tattr\treason\tcategory\tnote};
	}
	elsif ( $type eq 'editreviews' )
	{
	  $buffer .= qq{id\ttitle\tauthor\ttime\tattr\treason\tcategory\tnote};
	}
	elsif ( $type eq 'undreviews' )
	{
	  $buffer .= qq{id\ttitle\tauthor\ttime\tstatus\tuser\tattr\treason\tcategory\tnote}
	}
	elsif ( $type eq 'conflict' )
	{
	  $buffer .= qq{id\ttitle\tauthor\ttime\tstatus\tuser\tattr\treason\tcategory\tnote};
	}
	elsif ( $type eq 'reviews' )
	{
	  $buffer .= qq{id\ttitle\tauthor\ttime\tstatus\tuser\tattr\treason\tcategory\tnote};
	}
	elsif ( $type eq 'historicalreviews' )
	{
	  $buffer .= qq{id\ttitle\tauthor\ttime\tstatus\tlegacy\tuser\tattr\treason\tcategory\tnote};
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

	if ( $type eq 'userreviews')
	{
	  #for reviews
	  #id, title, author, review date, attr, reason, category, note, priority.
	  $buffer .= qq{$id\t$title\t$author\t$time\t$attr\t$reason\t$category\t$note};
	}
	elsif ( $type eq 'editreviews' )
	{
	  #for editRevies
	  #id, title, author, review date, attr, reason, category, note, priority.
	  $buffer .= qq{$id\t$title\t$author\t$time\t$attr\t$reason\t$category\t$note};
	}
	elsif ( $type eq 'undreviews' )
	{
	  #for und/nif
	  #id, title, author, review date, status, user, attr, reason, category, note, priority.
	  $buffer .= qq{$id\t$title\t$author\t$time\t$status\t$user\t$attr\t$reason\t$category\t$note}
	}
	elsif ( $type eq 'conflict' )
	{
	  #for expert
	  #id, title, author, review date, status, user, attr, reason, category, note, priority.
	  $buffer .= qq{$id\t$title\t$author\t$time\t$status\t$user\t$attr\t$reason\t$category\t$note};
	}
	elsif ( $type eq 'reviews' )
	{
	  #for adminReviews
	  #id, title, author, review date, status, user, attr, reason, category, note, priority.
	  $buffer .= qq{$id\t$title\t$author\t$time\t$status\t$user\t$attr\t$reason\t$category\t$note};
	}
	elsif ( $type eq 'historicalreviews' )
	{
	  #for adminHistoricalReviews
	  #id, title, author, review date, status, user, attr, reason, category, note, priority.
	  $buffer .= qq{$id\t$title\t$author\t$time\t$status\t$legacy\t$user\t$attr\t$reason\t$category\t$note};
	}
  $buffer .= sprintf("%s\n", ($self->IsUserAdmin())? "\t$priority":'');
    }

    $self->DownloadSpreadSheet ( $buffer );

    if ( $buffer ) { return 1; }
    else { return 0; }
}




sub GetReviewsRef
{
    my $self               = shift;
    my $order              = shift;
    my $direction          = shift;

    my $search1            = shift;
    my $search1value       = shift;
    my $op1                = shift;

    my $search2            = shift;
    my $search2value       = shift;

    my $since              = shift;
    my $offset             = shift;

    my $type               = shift;

    my $limit              = 1;

    my $sql =  $self->CreateSQL ( $order, $direction, $search1, $search1value, $op1, $search2, $search2value, $since, $offset, $type, $limit );

    my $ref = $self->get( 'dbh' )->selectall_arrayref( $sql );

    my $return = [];
    foreach my $row ( @{$ref} )
    {
        $row->[1] =~ s,(.*) .*,$1,;
        
        my $item = {
                     id         => $row->[0],
                     time       => $row->[1],
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
        push( @{$return}, $item );
    }

    return $return;
}

#Used for the detail display of legacy items.
sub GetHistoricalReviewsRef
{
    my $self    = shift;
    my $order   = shift;
    my $id      = shift;
    my $user    = shift;
    my $since   = shift;
    my $offset  = shift;
    
    my $PageSize = $self->GetPageSize ();

    if ( ! $offset ) { $offset = 0; }

    if ( ! $order || $order eq "time" ) { $order = "time DESC "; }

    my $sql = qq{ SELECT id, time, duration, user, attr, reason, note, renNum, expert, copyDate, expertNote, category, legacy, renDate, priority, status FROM $CRMSGlobals::historicalreviewsTable };

    if    ( $user )                    { $sql .= qq{ WHERE user = "$user" };   }

    if    ( $since && $user )          { $sql .= qq{ AND   time >= "$since"};  }
    elsif ( $since )                   { $sql .= qq{ WHERE time >= "$since" }; }

    if    ( $id && ($user || $since) ) { $sql .= qq{ AND   id = "$id" }; }
    elsif ( $id )                      { $sql .= qq{ WHERE id = "$id" }; }

    $sql .= qq{ ORDER BY $order LIMIT $offset, $PageSize };

    my $ref = $self->get( 'dbh' )->selectall_arrayref( $sql );

    my $return = [];
    foreach my $row ( @{$ref} )
    {
        $row->[1] =~ s,(.*) .*,$1,;
	
        my $item = {
                     id         => $row->[0],
                     time       => $row->[1],
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
                     status     => $row->[15]
                   };
        push( @{$return}, $item );
    }

    return $return;
}


sub GetReviewsCount
{
    my $self           = shift;
    my $search1        = shift;
    my $search1value   = shift;
    my $op1            = shift;
    my $search2        = shift;
    my $search2value   = shift;
    my $since          = shift;
    my $type           = shift;
    my $volumes        = shift;

    my $countExpression = qq{*};
    if ( $volumes )
    {
      $countExpression = qq{distinct r.id};
    }

    $search1 = $self->ConvertToSearchTerm ( $search1, $type );
    $search2 = $self->ConvertToSearchTerm ( $search2, $type );


    my $sql;
    if ( $type eq 'reviews' )
    {
      $sql = qq{ SELECT count($countExpression) FROM $CRMSGlobals::reviewsTable r, $CRMSGlobals::queueTable q, bibdata b WHERE q.id = r.id AND q.id = b.id AND q.status >= 0 };
    }
    elsif ( $type eq 'conflict' )
    {
      $sql = qq{ SELECT count($countExpression) FROM $CRMSGlobals::reviewsTable r, $CRMSGlobals::queueTable q, bibdata b WHERE q.id = r.id AND q.id = b.id  AND ( q.status = 2 ) };
    }
    elsif ( $type eq 'historicalreviews' )
    {
      $sql = qq{ SELECT count($countExpression) FROM $CRMSGlobals::historicalreviewsTable r, bibdata b  WHERE r.id = b.id AND r.status >= 0  };
    }
    elsif ( $type eq 'undreviews' )
    {
	$sql = qq{ SELECT count($countExpression) FROM $CRMSGlobals::reviewsTable r, $CRMSGlobals::queueTable q, bibdata b WHERE q.id = b.id  AND q.id = r.id AND q.status = 3 };
    }
    elsif ( $type eq 'userreviews' )
    {
	my $user = $self->get( "user" );
	$sql = qq{ SELECT count($countExpression) FROM $CRMSGlobals::reviewsTable r, $CRMSGlobals::queueTable q, bibdata b WHERE q.id = r.id AND q.id = b.id AND r.user = '$user' AND q.status > 0 };
    }
    elsif ( $type eq 'editreviews' )
    {
	my $user = $self->get( "user" );
	my $yesterday = $self->GetYesterday();
	$sql = qq{ SELECT count($countExpression) FROM $CRMSGlobals::reviewsTable r, $CRMSGlobals::queueTable q, bibdata b WHERE q.id = r.id AND q.id = b.id AND r.user = '$user' AND r.time >= "$yesterday" };
	
    }


    my ( $search1term, $search2term );
    if ( $search1value =~ m,.*\*.*, )
    {
      $search1value =~ s,\*,%,gs;
      $search1term = qq{$search1 like '$search1value'};
    }
    else
    {
      $search1term = qq{$search1 = '$search1value'};
    }
    if ( $search2value =~ m,.*\*.*, )
    {
      $search2value =~ s,\*,%,gs;
      $search2term = qq{$search2 like '$search2value'};
    }
    else
    {
      $search2term = qq{$search2 = '$search2value'};
    }

    if ( ( $search1value ne "" ) && ( $search2value ne "" ) )
    {
      { $sql .= qq{ AND ( $search1term  $op1  $search2term ) };   }
    }
    elsif ( $search1value ne "" )
    {
      { $sql .= qq{ AND $search1term  };   }
    }
    elsif (  $search2value ne "" )
    {
      { $sql .= qq{ AND $search2term  };   }
    }

    if ( $since ) { $sql .= qq{ AND r.time >= "$since" }; }


    return $self->SimpleSqlGet( $sql );
}


sub LinkToStanford
{
    my $self = shift;
    my $q    = shift;

    my $url  = 'http://collections.stanford.edu/copyrightrenewals/bin/search/simple/process?query=';

    return qq{<a href="$url$q">$q</a>};
}

sub LinkToPT
{
    my $self = shift;
    my $id   = shift;
    my $ti   = $self->GetTitle( $id );
    
    my $url  = 'http://babel.hathitrust.org/cgi/pt?attr=1&id=';
    #This url was used for testing.
    #my $url  = '/cgi/m/mdp/pt?skin=crms;attr=1;id=';

    return qq{<a href="$url$id" target="_blank">$ti</a>};
}

sub LinkToReview
{
    my $self = shift;
    my $id   = shift;
    my $ti   = $self->GetTitle( $id );
    
    ## my $url  = 'http://babel.hathitrust.org/cgi/pt?attr=1&id=';
    my $url  = qq{/cgi/c/crms/crms?p=review;barcode=$id;editing=1};

    return qq{<a href="$url" target="_blank">$ti</a>};
}

sub DetailInfo
{
    my $self   = shift;
    my $id     = shift;
    my $user   = shift;
    my $page   = shift;
    
    my $url  = qq{/cgi/c/crms/crms?p=detailInfo&id=$id&user=$user&page=$page};

    return qq{<a href="$url" target="_blank">$id</a>};
}

sub DetailInfoForReview
{
    my $self   = shift;
    my $id     = shift;
    my $user   = shift;
    my $page   = shift;
    
    my $url  = qq{/cgi/c/crms/crms?p=detailInfoForReview&id=$id&user=$user&page=$page};

    return qq{<a href="$url" target="_blank">$id</a>};
}


sub GetStatus
{
    my $self = shift;
    my $id   = shift;

    my $sql  = qq{ SELECT status FROM $CRMSGlobals::queueTable WHERE id = "$id"};
    my $ref  = $self->get( 'dbh' )->selectall_arrayref( $sql );
    my $str  = $self->SimpleSqlGet( $sql );

    return $str;

}

sub GetLegacyStatus
{
    my $self = shift;
    my $id   = shift;

    my $sql  = qq{ SELECT status FROM $CRMSGlobals::historicalreviewsTable WHERE id = "$id"};
    my $ref  = $self->get( 'dbh' )->selectall_arrayref( $sql );
    my $str  = $self->SimpleSqlGet( $sql );

    return $str;

}

sub ItemWasReviewedByOtherUser
{
    my $self   = shift;
    my $id     = shift;
    my $user   = shift;

    my $sql   = qq{ SELECT id FROM $CRMSGlobals::reviewsTable WHERE user != "$user" AND id = "$id"};
    my $ref   = $self->get( 'dbh' )->selectall_arrayref( $sql );
    my $found = $self->SimpleSqlGet( $sql );

    if ($found) { return 1; }
    return 0;

}

sub UsersAgreeOnReview
{
    my $self = shift;
    my $id   = shift;

    ##Agree is when the attr adn reason match.

    my $sql   = qq{ SELECT id, attr, reason FROM $CRMSGlobals::reviewsTable where id = '$id' Group by id, attr, reason having count(*) = 2};
    my $ref   = $self->get( 'dbh' )->selectall_arrayref( $sql );
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

    my $attr   = $self->GetRightsName( $ref->[0]->[0] );
    my $reason = $self->GetReasonName( $ref->[0]->[1] );
    return ($attr, $reason);
}


sub CheckAttrReasonComb 
{
    my $self = shift;
    my $in   = shift;

}

sub GetAttrReasonCom
{
    my $self = shift;
    my $in   = shift;
 
    my %codes = (1 => "pd/ncn", 2 => "pd/ren",  3 => "pd/cdpp",
                 4 => "ic/ren", 5 => "ic/cdpp", 6 => "und/nfi",
                 7 => "pdus/cdpp");

    my %str   = ("pd/ncn" => 1, "pd/ren"  => 2, "pd/cdpp" => 3,
                 "ic/ren" => 4, "ic/cdpp" => 5, "und/nfi" => 6,
                 "pdus/cdpp" => 7);

    if ( $in =~ m/\d/ ) { return $codes{$in}; }
    else                { return $str{$in};   }
}

sub GetAttrReasonFromCode
{
    my $self = shift;
    my $code = shift;

    if    ( $code eq "1" ) { return (1,2); }
    elsif ( $code eq "2" ) { return (1,7); }
    elsif ( $code eq "3" ) { return (1,9); }
    elsif ( $code eq "4" ) { return (2,7); }
    elsif ( $code eq "5" ) { return (2,9); }
    elsif ( $code eq "6" ) { return (5,8); }
    elsif ( $code eq "7" ) { return (9,9); }
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

    my $sql  = qq{ SELECT note FROM $CRMSGlobals::reviewsTable WHERE id = "$id" AND user = "$user"};
    my $ref  = $self->get( 'dbh' )->selectall_arrayref( $sql );
    my $str  = $self->SimpleSqlGet( $sql );

    return $str;

}

sub GetReviewCategory
{
    my $self = shift;
    my $id   = shift;
    my $user = shift;

    my $sql  = qq{ SELECT category FROM $CRMSGlobals::reviewsTable WHERE id = "$id" AND user = "$user"};
    my $ref  = $self->get( 'dbh' )->selectall_arrayref( $sql );
    my $str  = $self->SimpleSqlGet( $sql );

    return $str;
}


sub GetAttrReasonCode
{
    my $self = shift;
    my $id   = shift;
    my $user = shift;

    my $sql  = qq{ SELECT attr, reason FROM $CRMSGlobals::reviewsTable WHERE id = "$id" AND user = "$user"};
    my $ref  = $self->get( 'dbh' )->selectall_arrayref( $sql );

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
    my $sql  = qq{SELECT id FROM $CRMSGlobals::queueTable WHERE id = '$id'};
    my @rows = $dbh->selectrow_array( $sql );
    
    return scalar( @rows );
}

sub CheckReviewer
{
    my $self = shift;
    my $user = shift;
    my $exp  = shift;
    my $dbh  = $self->get( 'dbh' );

    my $sql  = qq{SELECT type FROM $CRMSGlobals::usersTable WHERE id = '$user'};
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

    my $sql  = qq{SELECT name FROM $CRMSGlobals::usersTable WHERE id = '$user' LIMIT 1};
    my $name = $self->SimpleSqlGet( $sql );

    if ( $name ne "" ) { return $name; }

    return 0;
}


sub GetAliasUserName
{
    my $self = shift;
    my $user = shift;

    if ( ! $user ) { $user = $self->get( "user" ); }

    my $sql  = qq{SELECT alias FROM $CRMSGlobals::usersTable WHERE id = '$user' LIMIT 1};
    my $name = $self->SimpleSqlGet( $sql );

    if ( $name ne "" ) { return $name; }

    return 0;
}

sub ChangeAliasUserName
{
    my $self = shift;
    my $user = shift;
    my $new_user = shift;

    if ( ! $user ) { $user = $self->get( "user" ); }

    my $sql  = qq{UPDATE $CRMSGlobals::usersTable set alias = '$new_user' WHERE id = '$user'};
    $self->PrepareSubmitSql( $sql );


}

sub ChangeDateFormat
{
    my $self = shift;
    my $date = shift;
    
    #go from MM/DD/YYYY to YYYY-MM-DD

    my $month = $date;
    $month =~ s,(.*?)\/.*?\/.*,$1,;

    my $day   = $date;
    $day =~ s,.*?\/(.*?)\/.*,$1,;

    my $year  = $date;
    $year =~ s,.*?\/.*?\/(.*),$1,;
    
    if ( $month < 10 ) { $month = qq{0$month}; }
    if ( $day < 10 ) { $day   = qq{0$day}; }

    my $value = qq{$year-$month-$day};

    return $value;
}

sub IsUserReviewer
{
    my $self = shift;
    my $user = shift;

    if ( ! $user ) { $user = $self->get( "user" ); }

    my $sql  = qq{ SELECT name FROM $CRMSGlobals::usersTable WHERE id = '$user' AND type = 1 };
    my $name = $self->SimpleSqlGet( $sql );

    if ($name) { return 1; }

    return 0;
}

sub IsUserReviewerExpert
{
    my $self = shift;
    my $user = shift;

    if ( ! $user ) { $user = $self->get( "user" ); }

    my $sql  = qq{ SELECT name FROM $CRMSGlobals::usersTable WHERE id = '$user' AND type = 2 };
    my $name = $self->SimpleSqlGet( $sql );

    if ($name) { return 1; }

    return 0;
}

sub IsUserExpert
{
    my $self = shift;
    my $user = shift;

    if ( ! $user ) { $user = $self->get( "user" ); }

    my $sql  = qq{ SELECT name FROM $CRMSGlobals::usersTable WHERE id = '$user' AND type = 2 };
    my $name = $self->SimpleSqlGet( $sql );

    if ($name) { return 1; }

    return 0;
}

sub IsUserAdmin
{
    my $self = shift;
    my $user = shift;

    if ( ! $user ) { $user = $self->get( "user" ); }
    
    my $sql  = qq{ SELECT name FROM $CRMSGlobals::usersTable WHERE id = '$user' AND type = 3 };
    my $name = $self->SimpleSqlGet( $sql );
    
    if ( $name ) { return 1; }
    
    return 0;
}

sub GetUserData
{
    my $self = shift;
    my $id   = shift;
    my $dbh  = $self->get( 'dbh' );

    my $sql  = qq{SELECT id, name, type FROM $CRMSGlobals::usersTable };
    if ( $id ne "" ) { $sql .= qq{ WHERE id = "$id"; } }

    my $ref  = $dbh->selectall_arrayref( $sql );

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
 
  my $sql  = qq{ SELECT max( time ) from reviews};
  my $reviews_max  = $self->SimpleSqlGet( $sql );

  my $sql  = qq{ SELECT min( time ) from reviews};
  my $reviews_min  = $self->SimpleSqlGet( $sql );

  my $sql  = qq{ SELECT max( time ) from historicalreviews where legacy=0};
  my $historicalreviews_max  = $self->SimpleSqlGet( $sql );

  my $sql  = qq{ SELECT min( time ) from historicalreviews where legacy=0};
  my $historicalreviews_min  = $self->SimpleSqlGet( $sql );

  my $max = $reviews_max;
  if ( $historicalreviews_max > $reviews_max ) { $max = $historicalreviews_max; }

  my $min = $reviews_min;
  if ( $historicalreviews_min < $reviews_min ) { $min = $historicalreviews_min; }
  
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

sub GetMonthStats
{
  my $self = shift;
  my $user = shift;
  my $start_date = shift;

  my $dbh  = $self->get( 'dbh' );

  my $sql;

  $sql  = qq{ SELECT count(*) FROM reviews WHERE user='$user' and time like '$start_date%'};
  my $total_reviews   = $self->SimpleSqlGet( $sql );

  $sql  = qq{ SELECT count(*) FROM historicalreviews WHERE user='$user' and legacy=0 and time like '$start_date%'};
  my $total_hist   = $self->SimpleSqlGet( $sql );

  my $total_reviews_toreport = $total_reviews + $total_hist;

  #pd/ren
  $sql  = qq{ SELECT count(*) FROM reviews WHERE user='$user' and attr=1 and reason=7 and time like '$start_date%'};
  my $total_reviews   = $self->SimpleSqlGet( $sql );

  $sql  = qq{ SELECT count(*) FROM historicalreviews WHERE user='$user' and legacy=0 and attr=1 and reason=7 and time like '$start_date%'};
  my $total_hist   = $self->SimpleSqlGet( $sql );

  my $total_pd_ren = $total_reviews + $total_hist;

  #pd/ncn
  $sql  = qq{ SELECT count(*) FROM reviews WHERE user='$user' and attr=1 and reason=2 and time like '$start_date%'};
  my $total_reviews   = $self->SimpleSqlGet( $sql );

  $sql  = qq{ SELECT count(*) FROM historicalreviews WHERE user='$user' and legacy=0 and attr=1 and reason=2 and time like '$start_date%'};
  my $total_hist   = $self->SimpleSqlGet( $sql );

  my $total_pd_cnn = $total_reviews + $total_hist;

  #pd/cdpp
  $sql  = qq{ SELECT count(*) FROM reviews WHERE user='$user' and attr=1 and reason=9 and time like '$start_date%'};
  my $total_reviews   = $self->SimpleSqlGet( $sql );

  $sql  = qq{ SELECT count(*) FROM historicalreviews WHERE user='$user' and legacy=0 and attr=1 and reason=9 and time like '$start_date%'};
  my $total_hist   = $self->SimpleSqlGet( $sql );

  my $total_pd_cdpp = $total_reviews + $total_hist;

  #ic/ren
  $sql  = qq{ SELECT count(*) FROM reviews WHERE user='$user' and attr=2 and reason=7 and time like '$start_date%'};
  my $total_reviews   = $self->SimpleSqlGet( $sql );

  $sql  = qq{ SELECT count(*) FROM historicalreviews WHERE user='$user' and legacy=0 and attr=2 and reason=7 and time like '$start_date%'};
  my $total_hist   = $self->SimpleSqlGet( $sql );

  my $total_ic_ren = $total_reviews + $total_hist;

  #ic/cdpp
  $sql  = qq{ SELECT count(*) FROM reviews WHERE user='$user' and attr=2 and reason=9 and time like '$start_date%'};
  my $total_reviews   = $self->SimpleSqlGet( $sql );

  $sql  = qq{ SELECT count(*) FROM historicalreviews WHERE user='$user' and legacy=0 and attr=2 and reason=9 and time like '$start_date%'};
  my $total_hist   = $self->SimpleSqlGet( $sql );

  my $total_ic_cdpp = $total_reviews + $total_hist;
  
  #pdus/cdpp
  $sql  = qq{ SELECT count(*) FROM reviews WHERE user='$user' and attr=9 and reason=9 and time like '$start_date%'};
  my $total_reviews   = $self->SimpleSqlGet( $sql );

  $sql  = qq{ SELECT count(*) FROM historicalreviews WHERE user='$user' and legacy=0 and attr=9 and reason=9 and time like '$start_date%'};
  my $total_hist   = $self->SimpleSqlGet( $sql );

  my $total_pdus_cdpp = $total_reviews + $total_hist;


  #und/nfi
  $sql  = qq{ SELECT count(*) FROM reviews WHERE user='$user' and attr=5 and reason=8 and time like '$start_date%'};
  my $total_reviews   = $self->SimpleSqlGet( $sql );

  $sql  = qq{ SELECT count(*) FROM historicalreviews WHERE user='$user' and legacy=0 and attr=5 and reason=8 and time like '$start_date%'};
  my $total_hist   = $self->SimpleSqlGet( $sql );

  my $total_und_nfi = $total_reviews + $total_hist;


  my $total_time = 0;
  #time reviewing ( in minutes ) - not including out lines 
  $sql  = qq{ SELECT duration FROM reviews WHERE user='$user' and time like '$start_date%' and duration <= '00:05:00'};

  my $rows = $dbh->selectall_arrayref( $sql );

  foreach my $row ( @{$rows} )
  {
    my $duration = $row->[0];
    #convert to minutes:
    my $min = $duration;
    $min =~ s,.*?:(.*?):.*,$1,;
    
    
    my $sec = $duration;
    $sec =~ s,.*?:.*?:(.*),$1,;

    $total_time = $total_time + $sec + (60*$min);
  }

  $sql  = qq{ SELECT duration FROM historicalreviews WHERE user='$user' and legacy=0 and time like '$start_date%' and duration <= '00:05:00'};
  my $total_hist   = $self->SimpleSqlGet( $sql );

  my $rows = $dbh->selectall_arrayref( $sql );

  foreach my $row ( @{$rows} )
  {
    my $duration = $row->[0];
    #convert to minutes:
    my $min = $duration;
    $min =~ s,.*?:(.*?):.*,$1,;
    
    
    my $sec = $duration;
    $sec =~ s,.*?:.*?:(.*),$1,;

    $total_time = $total_time + $sec + (60*$min);
  }

  $total_time = $total_time/60;

  
  #total outliers
  $sql  = qq{ SELECT count(*) FROM reviews WHERE user='$user' and time like '$start_date%' and duration > '00:05:00'};
  my $total_reviews   = $self->SimpleSqlGet( $sql );

  $sql  = qq{ SELECT count(*) FROM historicalreviews WHERE user='$user' and legacy=0 and time like '$start_date%' and duration > '00:05:00'};
  my $total_hist   = $self->SimpleSqlGet( $sql );

  my $total_outliers = $total_reviews + $total_hist;

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
  my $sql  = qq{ INSERT INTO userstats (user, month, year, monthyear, total_reviews, total_pd_ren, total_pd_cnn, total_pd_cdpp, total_pdus_cdpp, total_ic_ren, total_ic_cdpp, total_und_nfi, total_time, time_per_review, reviews_per_hour, total_outliers) VALUES ('$user', '$month', '$year', '$start_date', $total_reviews_toreport, $total_pd_ren, $total_pd_cnn, $total_pd_cdpp, $total_pdus_cdpp, $total_ic_ren, $total_ic_cdpp, $total_und_nfi, $total_time, $time_per_review, $reviews_per_hour, $total_outliers )};

  $self->PrepareSubmitSql( $sql );

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

# Returns a pair of date strings e.g. ('2008-07','2009-06') for the current fiscal year.
sub GetFiscalYear
{
  my $self = shift;
  my $ym = shift;
  my @range = $self->GetAllMonthsInFiscalYear($ym);
  return ($range[0], $range[-1]);
}

# Returns an array of date strings e.g. ('2008-07'...'2009-06') for the (current if no param) fiscal year.
sub GetAllMonthsInFiscalYear
{
  my $self = shift;
  my $ym = shift;
  my ( $year, $month );
  if ($ym) { ($year, $month) = split('-', $ym); }
  else { ($year, $month) = $self->GetTheYearMonth(); }
  my $startYear = ($month ge '07')? $year:$year-1;
  my $endYear = ($month ge '07')? $year+1:$year;
  my @range = ();
  for my $m (7..12) { push(@range, sprintf("$startYear-%.2d", $m)); }
  for my $m (1..6) { push(@range, sprintf("$endYear-%.2d", $m)); }
  return @range;
}

# Returns an array of date strings e.g. ('2008-07','2009-07') with start month of all fiscal years for which we have data.
sub GetAllFiscalYears
{
  my $self = shift;
  my $dbh = $self->get( 'dbh' );
  my $min = $self->SimpleSqlGet("SELECT min(time) from $CRMSGlobals::historicalreviewsTable WHERE legacy != 1");
  my $max = $self->SimpleSqlGet("SELECT max(time) from $CRMSGlobals::historicalreviewsTable WHERE legacy != 1");
  $min = substr($min,0,7);
  $max = substr($max,0,7);
  my ($minstart,$minend) = $self->GetFiscalYear($min);
  my ($maxstart,$maxend) = $self->GetFiscalYear($max);
  $minstart = substr($minstart, 0, 4);
  $maxstart = substr($maxstart, 0, 4);
  my @range = ();
  for (my $y = $minstart; $y < $maxend; $y++)
  {
    push(@range, $y);
  }
  return @range;
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
  my @statdates = ($cumulative)? $self->GetAllFiscalYears() : $self->GetAllMonthsInFiscalYear();
  my $y1 = substr($statdates[0],0,4);
  my $y2 = substr($statdates[-1],0,4);
  my $label = ($cumulative)? "Project Cumulative $y1-" : "Fiscal Cumulative $y1-$y2";
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
                'All PD' => 0, 'All IC' => 0);
    my $mintime = $date . '-01 00:00:00';
    my $maxtime = $date . '-31 23:59:59';
    if ($cumulative)
    {
      my ($y,$m) = split('-', $date);
      $mintime = "$y-$m-01 00:00:00";
      $maxtime = sprintf('%d-06-31 23:59:59', int($y)+1);
    }
    my $sql = qq{SELECT attr,reason FROM $CRMSGlobals::historicalreviewsTable h1 WHERE time=(SELECT max(h2.time) FROM $CRMSGlobals::historicalreviewsTable h2 WHERE h1.id = h2.id) AND (status=4 OR status=5) AND legacy=0 AND time >= '$mintime' AND time <= '$maxtime'};
    my $rows = $dbh->selectall_arrayref( $sql );
    foreach my $row ( @{$rows} )
    {
      my $attr = int($row->[0]);
      my $reason = int($row->[1]);
      my $code = $self->GetCodeFromAttrReason($attr, $reason);
      my $cat = $self->GetAttrReasonCom($code);
      $cat = 'All UND/NFI' if $cat eq 'und/nfi';
      if (exists $cats{$cat} or $cat eq 'All UND/NFI')
      {
        $cats{$cat}++;
        my $allkey = 'All ' . uc substr($cat,0,2);
        $cats{$allkey}++ if exists $cats{$allkey};
      }
    }
    for my $cat (keys %cats)
    {
      $stats{$cat}{$date} = $cats{$cat};
    }
  }
  $report .= "\n";
  my @titles = ('All PD', 'pd/ren', 'pd/ncn', 'pd/cdpp', 'pdus/cdpp', 'All IC', 'ic/ren', 'ic/cdpp', 'All UND/NFI', 'Total');
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
    my $of = 0;
    if ($title ne 'Total' && $doPercent)
    {
      $of = $gt;
      if (substr($title,0,3) ne 'All')
      {
        my $allcat = 'All ' . uc substr($title,0,2);
        $of = $catTotals{$allcat};
      }
      my $pct = eval { 100.0*$total/$of; };
      $pct = 0.0 unless $pct;
      $total = sprintf("$total:%.1f", $pct);
    }
    $report .= $delimiter . $total;
    foreach my $date (@usedates)
    {
      my $n = 0;
      if ($title eq 'Total') { $n = $monthTotals{$date}; }
      else
      {
        $n = $stats{$title}{$date};
        $n = 0 if !$n;
        if ($doPercent)
        {
          $of = $monthTotals{$date};
          if (substr($title,0,3) ne 'All')
          {
            my $allcat = 'All ' . uc substr($title,0,2);
            $of = $stats{$allcat}{$date};
          }
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
  my $data = $self->CreateExportData(',',$type == 2,0);
  my @lines = split m/\n/, $data;
  my $title = shift @lines;
  $title =~ s/Fiscal\sCumulative/Monthly Breakdown/ if $type == 0;
  $title =~ s/Fiscal\sCumulative/Total Determinations/ if $type == 1;
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
  my $gt = $totalline[1];
  my @monthtotals = @totalline[2,-1];
  foreach my $title (@titles)
  {
    # Extract the total,n1,n2... data
    my @line = split(',',$titleh{$title});
    shift @line;
    my $total = int(shift @line);
    $totals{$title} = $total;
    foreach my $n (@line) { $ceiling = int($n) if int($n) > $ceiling && $type == 1; }
    my $color = $colors{$title};
    my $attrs = sprintf('"dot-style":{"type":"solid-dot","dot-size":3,"colour":"%s"},"text":"%s","colour":"%s","on-show":{"type":"pop-up","cascade":1,"delay":0.2}',
                        $color, $title, $color);
    my @vals = @line;
    if ($type == 0)
    {
      for (my $i = 0; $i < scalar @line; $i++) { $line[$i] = 100.0*$line[$i]/$monthtotals[$i]; }
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

# Create an HTML table for the whole fiscal year's exports, month by month.
# If cumulative, columns are fiscal years, not months.
sub CreateExportReport
{
  my $self = shift;
  my $cumulative = shift;
  my $dbh = $self->get( 'dbh' );
  my $data = $self->CreateExportData(',', $cumulative, 1, 1);
  my @lines = split m/\n/, $data;
  my $nbsps = '&nbsp;&nbsp;&nbsp;&nbsp;';
  my $dllink = sprintf(qq{$nbsps<a target="_blank" href="/cgi/c/crms/getExportStats?type=text&c=%d">Download</a>}, $cumulative);
  my $report = sprintf("<h3>%s$dllink</h3>\n<table class='exportStats'>\n<tr>\n", shift @lines);
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
    my $title = shift @items;
    my $major = exists $majors{$title};
    $title =~ s/\s/&nbsp;/g;
    my $padding = ($major)? '':$nbsps;
    $report .= sprintf("<th%s><span%s>%s$title</span></th>",
      ($title eq 'Total')? ' style="text-align:right;"':'',
      ($major)? ' class="major"':'',
      ($major)? '':$nbsps);
    foreach my $item (@items)
    {
      my ($n,$pct) = split ':', $item;
      $n =~ s/\s/&nbsp;/g;
      $report .= sprintf("<td%s>%s%s$n%s%s</th>",
                         ($major)? ' class="major"':($title eq 'Total')? ' style="text-align:center;"':'',
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
  my $doCurrentMonth = shift;
  my $doPercent = shift;
  my $dbh = $self->get( 'dbh' );
  my $now = join('-', $self->GetTheYearMonth());
  my @statdates = ($cumulative)? $self->GetAllFiscalYears() : $self->GetAllMonthsInFiscalYear();
  my $y1 = substr($statdates[0],0,4);
  my $y2 = substr($statdates[-1],0,4);
  my $username = ($user eq 'all')? 'All Users':$self->GetUserName($user);
  my $label = ($cumulative)? "$username: Cumulative $y1-" : "$username: Fiscal Cumulative $y1-$y2";
  my $report = "$label\nCategories,Grand Total";
  my %stats = ();
  my @usedates = ();
  my @titles = ('All PD', 'pd/ren', 'pd/ncn', 'pd/cdpp', 'pdus/cdpp', 'All IC', 'ic/ren', 'ic/cdpp', 'All UND/NFI', 'Total',
                'Time Reviewing (mins)', '__Average__Time per Review (mins)','__Average__Reviews per Hour', 'Outlier Reviews');
  foreach my $date (@statdates)
  {
    last if $date gt $now;
    last if $date eq $now and !$doCurrentMonth;
    push @usedates, $date;
    $report .= ",$date";
    my %cats = ('All PD' => 0, 'pd/ren' => 0, 'pd/ncn' => 0, 'pd/cdpp' => 0, 'pdus/cdpp' => 0,
                'All IC' => 0, 'ic/ren' => 0, 'ic/cdpp' => 0,
                'All UND/NFI' => 0,
                'Time Reviewing (mins)' => 0, '__Average__Time per Review (mins)' => 0,
                '__Average__Reviews per Hour' => 0, 'Outlier Reviews' => 0);
    my $mintime = $date;
    my $maxtime = $date;
    if ($cumulative)
    {
      my ($y,$m) = split('-', $date);
      $mintime = "$y-$m";
      $maxtime = sprintf('%d-06', int($y)+1);
    }
    my $sql = qq{SELECT total_pd_ren, total_pd_cnn, total_pd_cdpp, total_pdus_cdpp, total_ic_ren, total_ic_cdpp, total_und_nfi, total_reviews, total_time, time_per_review, reviews_per_hour, total_outliers from userstats where monthyear >= '$mintime' AND monthyear <= '$maxtime' and user='$user'};
    if ($user eq 'all')
    {
      $sql = qq{SELECT SUM(total_pd_ren), SUM(total_pd_cnn), SUM(total_pd_cdpp), SUM(total_pdus_cdpp), SUM(total_ic_ren), SUM(total_ic_cdpp), SUM(total_und_nfi), SUM(total_reviews), SUM(total_time), AVG(time_per_review), AVG(reviews_per_hour), SUM(total_outliers) FROM userstats WHERE monthyear >= '$mintime' AND monthyear <= '$maxtime'};
    }
    
    my $rows = $dbh->selectall_arrayref( $sql );
    foreach my $row ( @{$rows} )
    {
      my $i = 0;
      my @newrow = ($row->[0]+$row->[1]+$row->[2]+$row->[3], $row->[0], $row->[1], $row->[2], $row->[3],
                    $row->[4]+$row->[5], $row->[4], $row->[5],
                    $row->[6], $row->[7], $row->[8], $row->[9], $row->[10], $row->[11]);
      foreach my $title (@titles)
      {
        if ('All' ne substr($title,0,3) || $title eq 'All UND/NFI')
        {
          my $n = $newrow[$i];
          $cats{$title} += $n;
          my $allkey = 'All ' . uc substr($title,0,2);
          $cats{$allkey} += $n if exists $cats{$allkey};
        }
        $i++;
      }
    }
    for my $cat (keys %cats)
    {
      $stats{$cat}{$date} = $cats{$cat};
    }
  }
  $report .= "\n";
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
  my %majors = ('All PD' => 1, 'All IC' => 1, 'All UND/NFI' => 1);
  my %minors = ('Time Reviewing (mins)' => 1, '__Average__Time per Review (mins)' => 1,
                '__Average__Reviews per Hour' => 1, 'Outlier Reviews' => 1);
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
    my $of = 0;
    if ($title ne 'Total' && $doPercent && !exists$minors{$title})
    {
      $of = $gt;
      if (substr($title,0,3) ne 'All')
      {
        my $allcat = 'All ' . uc substr($title,0,2);
        $of = $catTotals{$allcat};
      }
      my $pct = eval { 100.0*$total/$of; };
      $pct = 0.0 unless $pct;
      $total = sprintf("$total:%.1f", $pct);
    }
    $total = sprintf('%.1f', $total) if int($total) != $total;
    $report .= ',' . $total;
    foreach my $date (@usedates)
    {
      my $n = 0;
      if ($title eq 'Total') { $n = $monthTotals{$date}; }
      else
      {
        $n = $stats{$title}{$date};
        $n = 0 if !$n;
        if ($doPercent && !exists$minors{$title})
        {
          $of = $monthTotals{$date};
          if (substr($title,0,3) ne 'All')
          {
            my $allcat = 'All ' . uc substr($title,0,2);
            $of = $stats{$allcat}{$date};
          }
          my $pct = eval { 100.0*$n/$of; };
          $pct = 0.0 unless $pct;
          $n = sprintf("$n:%.1f", $pct);
        }
      }
      $n = 0 if !$n;
      $n = sprintf('%.1f', $n) if int($n) != $n;
      $report .= ',' . $n;
    }
    $report .= "\n";
  }
  my $avg = ($cumulative)? 'Average ':'';
  $report =~ s/__Average__/$avg/g;
  return $report;
}

sub CreateStatsReport
{
  my $self = shift;
  my $user = shift;
  my $cumulative = shift;
  my $data = $self->CreateStatsData($user, $cumulative, 1, 1);
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
  foreach my $line (@lines)
  {
    $report .= '<tr>';
    my @items = split(',', $line);
    my $i = 0;
    my $title = shift @items;
    my $class = (exists $majors{$title})? 'major':(exists $minors{$title})? 'minor':'';
    $title =~ s/\s/&nbsp;/g;
    my $padding = ($class eq 'major' || $class eq 'minor' || $title eq 'Total')? '':$nbsps;
    $report .= sprintf("<th%s><span%s>%s$title</span></th>",
                       ($title eq 'Total')? ' style="text-align:right;"':'',
                       ($class eq 'major')? ' class="major"':($class eq 'minor')? ' class="minor"':'',
                       $padding);
    foreach my $item (@items)
    {
      my ($n,$pct) = split ':', $item;
      $n =~ s/\s/&nbsp;/g;
      $report .= sprintf("<td%s%s>%s%s$n%s%s</th>",
                         ($class eq 'major')? ' class="major"':($class eq 'minor')? ' class="minor"':'',
                         ($title eq 'Total' || $class eq 'minor')? ' style="text-align:center;"':'',
                         $padding,
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

sub CreateThisMonthsStats
{
    my $self = shift;

    my $dbh = $self->get( 'dbh' );

    my $rows = $dbh->selectall_arrayref( "SELECT distinct id FROM users" );

    my @users;
    foreach my $row ( @{$rows} )
    {
      push ( @users, $row->[0] );
    }

    my ( $max_year, $max_month, $min_year, $min_month ) = $self->GetRange();

    my $max_date = qq{$max_year-$max_month};

    my $sql = qq{DELETE from userstats where monthyear='$max_date'};
    $self->PrepareSubmitSql( $sql );


    foreach my $user ( @users )
    {
      $self->GetMonthStats ( $user, $max_date );
    }
    
}



sub CreateInitialStats
{
    my $self = shift;

    my $dbh = $self->get( 'dbh' );

    my $sql = qq{DELETE from userstats};
    $self->PrepareSubmitSql( $sql );

    my $rows = $dbh->selectall_arrayref( "SELECT distinct id FROM users" );

    my @users;
    foreach my $row ( @{$rows} )
    {
      push ( @users, $row->[0] );
    }

    my ( $max_year, $max_month, $min_year, $min_month ) = $self->GetRange();

    my $go = 1;
    my $max_date = qq{$max_year-$max_month};
    while ( $go )
    {
      my $statDate = qq{$min_year-$min_month};
      foreach my $user ( @users )
      {
        $self->GetMonthStats ( $user, $statDate );
      }

      $min_month = $min_month + 1;
      if ( $min_month == 13 )
      {
	$min_month = '01';
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
	$errorMsg .= qq{the ren date you have entered $renDate is before 1950, we should not be recording them.   };
      }
	  
      if ( ( $renDate >= 1950 )  && ( $renDate <= 1953 ) )
      {
	if ( ( $renNum =~ m,^R\w{5}$, ) || ( $renNum =~ m,^R\w{6}$, ))
	{}
	else
	{
	  $errorMsg .= qq{Ren Number format is not correct for item in  1950 - 1953 range.   };
	}

      }
      if ( $renDate >= 1978 )
      {
	if ( $renNum =~ m,^RE\w{6}$, )
	{}
	else
	{
	  $errorMsg .= qq{Ren Number format is not correct for item with Ren Date >= 1978.   };
	}
	  
      }
    }
    else
    {
      $errorMsg .= qq{Ren Date is not of the right format, for example 17Dec73.   };
    }
  }

  retunr $errorMsg;


}


sub HasItemBeenReviewedByTwoReviewers
{
    my $self = shift;
    my $id   = shift;
    my $user = shift;

    my $msg = '0';
    if ( ! $self->IsUserReviewerExpert( $user ) )
    {
      my $sql  = qq{ SELECT count(*) from $CRMSGlobals::reviewsTable where id ='$id' and user != '$user'};
      my $count  = $self->SimpleSqlGet( $sql );
    
      if ($count >= 2 ) { $msg = qq{This volume does not need to be reviewed.  Two reviewers or an expert have already reviewed it. Please Cancel.}; }


      my $sql  = qq{ SELECT count(*) from $CRMSGlobals::queueTable where id ='$id' and status != 0};
      my $count  = $self->SimpleSqlGet( $sql );
    
      if ($count >= 1 ) { $msg = qq{This item has been processed already.  Please Cancel.}; }

    }
    return $msg;

}


sub ValidateSubmission2
{
    my $self = shift;
    my ($attr, $reason, $note, $category, $renNum, $renDate, $user) = @_;
    my $errorMsg = "";

    my $noteError = 0;

    ## check user
    if ( ! $self->IsUserReviewer( $user ) )
    {
        $errorMsg .= qq{Not a reviewer.  };
    } 

    if ( ( ! $attr ) || ( ! $reason ) )   { $errorMsg .= qq{rights/reason designation required.  }; }


    ## und/nfi
    if ( $attr == 5 && $reason == 8 && ( ( ! $note ) || ( ! $category ) )  )
    {
        $errorMsg .= qq{und/nfi must include note category and note text.   };
        $noteError = 1;
    }

    ## ic/ren requires a ren number
    if ( $attr == 2 && $reason == 7 && ( ( ! $renNum ) || ( ! $renDate ) )  )
    {
        $errorMsg .= qq{ic/ren must include renewal id and renewal date.  };
    }
    elsif ( $attr == 2 && $reason == 7 )
    {
        $renDate =~ s,.*[A-Za-z](.*),$1,;
        $renDate = qq{19$renDate};

        if ( $renDate < 1950 )
        {
           $errorMsg .= qq{renewal has expired; volume is pd.  date entered is $renDate };
        }
    }

    ## pd/ren requires a ren number
    if ( $attr == 1 && $reason == 7 &&  ( ( $renNum ) || ( $renDate ) )  )
    {
        $errorMsg .= qq{pd/ren should not include renewal info.  };
    }

    ## pd/ncn requires a ren number
    if (  $attr == 1 && $reason == 2 && ( ( $renNum ) || ( $renDate ) ) )
    {
        $errorMsg .= qq{pd/ncn should not include renewal info.  };
    }


    ## pd/cdpp requires a ren number
    if (  $attr == 1 && $reason == 9 && ( ( $renNum ) || ( $renDate )  ) )
    {
        $errorMsg .= qq{pd/cdpp should not include renewal info.  };
    }

    if ( $attr == 1 && $reason == 9 && ( ( ! $note ) || ( ! $category )  )  )
    {
        $errorMsg .= qq{pd/cdpp must include note category and note text.  };
        $noteError = 1;
    }

    ## ic/cdpp requires a ren number
    if (  $attr == 2 && $reason == 9 && ( ( $renNum ) || ( $renDate ) ) )
    {
        $errorMsg .= qq{ic/cdpp should not include renewal info.  };
    }

    if ( $attr == 2 && $reason == 9 && ( ( ! $note )  || ( ! $category ) )  )
    {
        $errorMsg .= qq{ic/cdpp must include note category and note text.  };
        $noteError = 1;
    }

    if ( $noteError == 0 )
    {
      if ( ( $category )  && ( ! $note ) )
	{
	  $errorMsg .= qq{must include a note if there is a category.  };
	}
      elsif ( ( $note ) && ( ! $category ) )
	{
          $errorMsg .= qq{must include a category if there is a note.  };
	}

    }

    ## pdus/cdpp requires a note and a 'Foreign' note category, and must not have a ren number
    if ($attr == 9 && $reason == 9)
    {
      if (( $renNum ) || ( $renDate ))
      {
        $errorMsg .= qq{rights/reason conflicts with renewal info.  };
      }
      if (( !$note ) || ( !$category ))
      {
        $errorMsg .= qq{note category/note text required.  };
      }
      if ($category ne 'Foreign Pub')
      {
        $errorMsg .= qq{rights/reason requires note category "Foreign Pub".  };
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
      $record  = $self->GetRecordMetadata($barcode);
    }

    if ( ! $record ) { return 0; }

    ## my $xpath   = q{//*[local-name()='oai_marc']/*[local-name()='fixfield' and @id='008']};
    my $xpath   = q{//*[local-name()='controlfield' and @tag='008']};
    my $leader  = $record->findvalue( $xpath );
    my $pubDate = substr($leader, 7, 4);

    return $pubDate;
}

sub GetMarcFixfield
{
    my $self    = shift;
    my $barcode = shift;
    my $field   = shift;

    my $record  = $self->GetRecordMetadata($barcode);
    if ( ! $record ) { $self->Logit( "failed in GetMarcFixfield: $barcode" ); }

    my $xpath   = qq{//*[local-name()='oai_marc']/*[local-name()='fixfield' and \@id='$field']};
    return $record->findvalue( $xpath );
}

sub GetMarcVarfield
{
    my $self    = shift;
    my $barcode = shift;
    my $field   = shift;
    my $label   = shift;
    
    my $record  = $self->GetRecordMetadata($barcode);
    if ( ! $record ) { $self->Logit( "failed in GetMarcVarfield: $barcode" ); }

    my $xpath   = qq{//*[local-name()='oai_marc']/*[local-name()='varfield' and \@id='$field']} .
                  qq{/*[local-name()='subfield' and \@label='$label']};

    return $record->findvalue( $xpath );
}

sub GetMarcControlfield
{
    my $self    = shift;
    my $barcode = shift;
    my $field   = shift;
    
    my $record  = $self->GetRecordMetadata($barcode);
    if ( ! $record ) { $self->Logit( "failed in GetMarcControlfield: $barcode" ); }

    my $xpath   = qq{//*[local-name()='controlfield' and \@tag='$field']};
    return $record->findvalue( $xpath );
}

sub GetMarcDatafield
{
    my $self    = shift;
    my $barcode = shift;
    my $field   = shift;
    my $code    = shift;

    my $record  = $self->GetRecordMetadata($barcode);
    if ( ! $record ) { $self->Logit( "failed in GetMarcDatafield: $barcode" ); }

    my $xpath   = qq{//*[local-name()='datafield' and \@tag='$field']} .
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
    

    my $record  = $self->GetRecordMetadata($barcode);
    if ( ! $record ) { $self->Logit( "failed in GetMarcDatafield: $barcode" ); }

    my $data;

    my $xpath   = qq{//*[local-name()='datafield' and \@tag='100']};
    eval{ $data .= $record->findvalue( $xpath ); };
    if ($@) { $self->Logit( "failed to parse metadata: $@" ); }

    my $xpath   = qq{//*[local-name()='datafield' and \@tag='110']};
    eval{ $data .= $record->findvalue( $xpath ); };
    if ($@) { $self->Logit( "failed to parse metadata: $@" ); }

    my $xpath   = qq{//*[local-name()='datafield' and \@tag='111']};
    eval{ $data .= $record->findvalue( $xpath ); };
    if ($@) { $self->Logit( "failed to parse metadata: $@" ); }

    my $xpath   = qq{//*[local-name()='datafield' and \@tag='130']};
    eval{ $data .= $record->findvalue( $xpath ); };
    if ($@) { $self->Logit( "failed to parse metadata: $@" ); }

    my $xpath   = qq{//*[local-name()='datafield' and \@tag='700']};
    eval{ $data .= $record->findvalue( $xpath ); };
    if ($@) { $self->Logit( "failed to parse metadata: $@" ); }

    my $xpath   = qq{//*[local-name()='datafield' and \@tag='710']};
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

    my $sql  = qq{ SELECT title FROM bibdata WHERE id = "$id" };
    my $ti   = $self->SimpleSqlGet( $sql );

    if ( $ti eq "" ) { $ti = $self->UpdateTitle($id); }

    #good for the title
    $ti =~ s,(.*\w).*,$1,;

    return $ti;
}

sub GetPubDate
{
    my $self = shift;
    my $id   = shift;

    my $sql  = qq{ SELECT pub_date FROM bibdata WHERE id = "$id" };
    my $pub_date   = $self->SimpleSqlGet( $sql );

    return $pub_date;
}

sub UpdateTitle
{
    my $self  = shift;
    my $id    = shift;
    my $title = shift;

    
    if ( ! $title )
    {
      ## my $ti   = $self->GetMarcDatafield( $id, "245", "a");
      $title   = $self->GetRecordTitleBc2Meta( $id );
    }

    #This is the problem.
    my $tiq  = $self->get('dbh')->quote( $title );

    my $sql  = qq{ SELECT count(*) from bibdata where id="$id"};
    my $count  = $self->SimpleSqlGet( $sql );
    if ( $count == 1 )
    {
       my $sql  = qq{ UPDATE bibdata set title=$tiq where id="$id"};
       $self->PrepareSubmitSql( $sql );
    }
    else
    {
       my $sql  = qq{ INSERT INTO bibdata (id, title, pub_date) VALUES ( "$id", $tiq, "")};
       $self->PrepareSubmitSql( $sql );
    }

    return $title; 
}


sub UpdatePubDate
{
    my $self = shift;
    my $id   = shift;
    my $pub_date = shift;

    my $sql  = qq{ SELECT count(*) from bibdata where id="$id"};
    my $count  = $self->SimpleSqlGet( $sql );
    if ( $count == 1 )
    {
       my $sql  = qq{ UPDATE bibdata set pub_date="$pub_date" where id="$id"};
       $self->PrepareSubmitSql( $sql );
    }
    else
    {
       my $sql  = qq{ INSERT INTO bibdata (id, title, pub_date) VALUES ( "$id", "", "$pub_date"};
       $self->PrepareSubmitSql( $sql );
    }

}


sub UpdateAuthor
{
    my $self = shift;
    my $id   = shift;
    my $author = shift;

    my $sql  = qq{ SELECT count(*) from bibdata where id="$id"};
    my $count  = $self->SimpleSqlGet( $sql );
    if ( $count == 1 )
    {
       my $sql  = qq{ UPDATE bibdata set author="$author" where id="$id"};
       $self->PrepareSubmitSql( $sql );
    }
    else
    {
       my $sql  = qq{ INSERT INTO bibdata (id, title, pub_date, author) VALUES ( "$id", "", "", "$author" ) };
       $self->PrepareSubmitSql( $sql );
    }

}



## use for now because the API is slow...
sub GetRecordTitleBc2Meta
{
    my $self = shift;
    my $id   = shift;

    ## get from object if we have it
    if ( $self->get( 'marcData' ) ne "" ) { return $self->get( 'marcData' ); }

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
    if ( $errorCode ne "" )
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

    my $au;
    #100, 110, 111, 130, 700, 710, 
    $au = $self->GetMarcDatafield ( $bar, 100, 'a');

    if ( ! $au )
    {
      $au = $self->GetMarcDatafield ( $bar, 110, 'a');
    }
    if ( ! $au )
    {
      $au = $self->GetMarcDatafield ( $bar, 111, 'a');
    }
    if ( ! $au )
    {
      $au = $self->GetMarcDatafield ( $bar, 130, 'a');
    }
    if ( ! $au )
    {
      $au = $self->GetMarcDatafield ( $bar, 700, 'a');
    }
    if ( ! $au )
    {
      $au = $self->GetMarcDatafield ( $bar, 710, 'a');
    }

    $au =~ s,(.*[A-Za-z]).*,$1,;

    $au =~ s,\',\\\',g; ## escape '
    return $au;
}

sub GetAuthorForReview
{
    my $self = shift;
    my $bar  = shift;

    my $au = $self->GetMarcDatafield ( $bar, 100, 'a');


    if ( ! $au )
    {
      $au = $self->GetMarcDatafield ( $bar, 110, 'a');
    }
    if ( ! $au )
    {
      $au = $self->GetMarcDatafield ( $bar, 111, 'a');
    }
    if ( ! $au )
    {
      $au = $self->GetMarcDatafield ( $bar, 130, 'a');
    }
    if ( ! $au )
    {
      $au = $self->GetMarcDatafield ( $bar, 700, 'a');
    }
    if ( ! $au )
    {
      $au = $self->GetMarcDatafield ( $bar, 710, 'a');
    }

    $au =~ s,(.*[A-Za-z]).*,$1,;

    return $au;
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

    my ($ns,$bar)  = split(/\./, $barcode);

    ## get from object if we have it
    if ( $self->get( $bar ) ne "" ) { return $self->get( $bar ); }

    #my $sysId = $self->BarcodeToId( $barcode );
    #my $url   = "http://mirlyn-aleph.lib.umich.edu/cgi-bin/api/marc.xml/uid/$sysId";
    #my $url    = "http://mirlyn-aleph.lib.umich.edu/cgi-bin/api_josh/marc.xml/itemid/$bar";
    my $url    = $self->get( 'bc2metaUrl' ) .'?id=' . $barcode . '&schema=marcxml';
    my $ua     = LWP::UserAgent->new;

    if ($self->get("verbose")) { $self->Logit( "GET: $url" ); }
    $ua->timeout( 1000 );
    my $req = HTTP::Request->new( GET => $url );
    my $res = $ua->request( $req );

    if ( ! $res->is_success ) { $self->Logit( "$url failed: ".$res->message() ); return; }

    my $source;
    eval { $source = $parser->parse_string( $res->content() ); };
    if ($@) { $self->Logit( "failed to parse ($url):$@" ); return; }

    my $errorCode = $source->findvalue( "//*[name()='error']" );
    if ( $errorCode ne "" )
    {
        $self->Logit( "$url \nfailed to get MARC for $barcode: $errorCode " . $res->content() );
        return;
    }

    #my ($record) = $source->findnodes( "//record" );
    my ($record) = $source->findnodes( "." );
    $self->set( $bar, $record );

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
    if ( $barcodeID->{$barcode} ne "" ) { return $barcodeID->{$barcode}; }

    my $url = $bc2metaUrl . "?id=$barcode" . "&no_meta=1";
    
    my $ua = LWP::UserAgent->new;
    $ua->timeout( 1000 ); 
    my $req = HTTP::Request->new( GET => $url );
    my $res = $ua->request( $req );

    if ( ! $res->is_success ) { $self->Logit( "$url failed: ".$res->message() ); return; }

    $res->content =~ m,<doc_number>\s*(\d+)\s*</doc_number>,s;
    
    my $id = $1;
    if ( $id eq "" ) { return; }  ## error or not found
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
    my $id  = $self->SimpleSqlGet( $sql );

    if ($id) { return 1; }
    return 0;
}

sub GetLockedItem
{
    my $self = shift;
    my $name = shift;

    my $sql = qq{SELECT id FROM $CRMSGlobals::queueTable WHERE locked = "$name" LIMIT 1};
    my $id  = $self->SimpleSqlGet( $sql );

    $self->Logit( "Get locked item for $name: $id" ); 

    return $id;
}

sub IsLocked
{
    my $self = shift;
    my $id   = shift;

    my $sql = qq{SELECT id FROM $CRMSGlobals::queueTable WHERE locked IS NOT NULL AND id = "$id"};
    my $id  = $self->SimpleSqlGet( $sql );

    if ($id) { return 1; }
    return 0;
}

sub IsLockedForUser
{
    my $self = shift;
    my $id   = shift;
    my $name = shift;

    my $sql = qq{SELECT locked FROM $CRMSGlobals::queueTable WHERE id = "$id"};
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
        my $id    = $lockedRef->{$item}->{id};
        my $user  = $lockedRef->{$item}->{locked};
        my $since = $self->ItemLockedSince($id, $user);

        my $sql   = qq{ SELECT id FROM $CRMSGlobals::queueTable WHERE id = "$id" AND "$time" >= time };
        my $old   = $self->SimpleSqlGet($sql);

        if ( $old ) 
        { 
            $self->Logit( "REMOVING OLD LOCK:\t$id, $user: $since | $time" );
            $self->UnlockItem( $id, $user);
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

    my $limit = $self->GetYesterdaysDate();

    my $sql   = qq{SELECT id FROM $CRMSGlobals::reviewsTable WHERE id = "$id" } .
                qq{ AND user = "$user" AND time < "$limit" };
    my $found = $self->SimpleSqlGet( $sql );

    if ($found) { return 1; }
    return 0;
}

sub LockItem
{
    my $self = shift;
    my $id   = shift;
    my $name = shift;

    ## if already locked for this user, that's OK
    if ( $self->IsLockedForUser( $id, $name ) ) { return 1; }

    ## can only have 1 item locked at a time 
    my $locked = $self->HasLockedItem( $name );

    if ( $locked eq $id ) { return 1; }  ## already locked
    if ( $locked ) 
    { 
        ## user has something locked already
        ## add some error handling
        return 0; 
    }

    my $sql  = qq{UPDATE $CRMSGlobals::queueTable SET locked = "$name" WHERE id = "$id"};
    if ( ! $self->PrepareSubmitSql($sql) ) { return 0; }

    $self->StartTimer( $id, $name );
    return 1;
}

sub UnlockItem
{
    my $self = shift;
    my $id   = shift;
    my $user = shift;

    if ( ! $self->IsLocked( $id ) ) { return 0; }

    my $sql  = qq{UPDATE $CRMSGlobals::queueTable SET locked = NULL  WHERE id = "$id"};
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

    my $sql  = qq{UPDATE $CRMSGlobals::queueTable SET locked = NULL  WHERE id = "$id"};
    if ( ! $self->PrepareSubmitSql($sql) ) { return 0; }

    $self->RemoveFromTimer( $id, $user );
    $self->Logit( "unlocking $id" );
    return 1;
}


sub UnlockAllItemsForUser
{
    my $self = shift;
    my $user = shift;

    my $sql  = qq{SELECT id  FROM $CRMSGlobals::timerTable WHERE user= "$user"};
    my $ref  = $self->get( 'dbh' )->selectall_arrayref( $sql );

    my $return = {}; 
    foreach my $row (@{$ref}) 
    { 
        my $id = $row->[0];
   
	my $sql  = qq{UPDATE $CRMSGlobals::queueTable SET locked = NULL  WHERE id = "$id"};
	$self->PrepareSubmitSql( $sql );

    }

    ## clear entry in table
    my $sql = qq{ DELETE FROM $CRMSGlobals::timerTable WHERE  user = "$user" };
    $self->PrepareSubmitSql( $sql );

}

sub GetLockedItems
{
    my $self = shift;
    my $sql  = qq{SELECT id, locked FROM $CRMSGlobals::queueTable WHERE locked IS NOT NULL};

    my $ref  = $self->get( 'dbh' )->selectall_arrayref( $sql );

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

    my $sql  = qq{SELECT start_time FROM $CRMSGlobals::timerTable WHERE id = "$id" and user = "$user"};
    return $self->SimpleSqlGet( $sql );

}

sub StartTimer
{
    my $self = shift;
    my $id   = shift;
    my $user = shift;    
    
    my $sql  = qq{ REPLACE INTO timer SET start_time = NOW(), id = "$id", user = "$user" };
    if ( ! $self->PrepareSubmitSql($sql) ) { return 0; }

    $self->Logit( "start timer for $id, $user" );
}

sub EndTimer
{
    my $self = shift;
    my $id   = shift;
    my $user = shift;    

    my $sql  = qq{ UPDATE timer SET end_time = NOW() WHERE id = "$id" and user = "$user" };
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

sub GetReviewerPace
{
    my $self = shift;
    my $user = shift;
    my $date = shift;

    if ( ! $user ) { $user = $self->get("user"); }

    if ( ! $date ) 
    {
        $date = POSIX::strftime("%Y-%m-%d %H:%M:%S", localtime(time - 2629743));
        ## if ($self->get('verbose')) { $self->Logit( "date: $date"); }
    }

    my @items = $self->ItemsReviewedByUser( $user, $date );
    my $count = scalar( @items );

    my $totalTime;
    foreach my $item ( @items ) 
    { 
        my $dur = $self->GetDuration( $item, $user );
        my ($h,$m,$s) = split(":", $dur);
        my $time = $s + ($m * 60) + ($h * 3660);
        $totalTime += $time;
    }

    if ( ! $count ) { return 0; }

    my $ave = int( ($totalTime / $count) + .5 );
    ## if ($self->get('verbose')) { $self->Logit( "$totalTime / $count : $ave" ); }

    if ( ! $ave ) { return 0; }

    my ($h,$m) = (0,0);
    while ($ave > 3660 ) { $h++; $ave -= 3660; }
    while ($ave > 60 )   { $m++; $ave -= 60;   }

    my $return;
    if ( $h ) { $return .= "$h:"; }
    if ( $m ) { $return .= sprintf("%02d",$m) .":"; }
    $return .= sprintf("%02d",$ave);

    return $return;
}

sub GetReviewerCount
{
    my $self = shift;
    my $user = shift;
    my $date = shift;
 
    return scalar( $self->ItemsReviewedByUser( $user, $date ) );
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
    my $barcode;

    #Find items reviewed once by some other user
    my $sql = qq{ SELECT id FROM $CRMSGlobals::queueTable WHERE locked is NULL AND status = 0 AND expcnt = 0 AND id in ( };
    $sql   .= qq{ SELECT distinct id from $CRMSGlobals::reviewsTable where user != '$name' and id in (select id from reviews group by id having count(*) = 1) ) };
    $sql   .= qq{ ORDER BY priority DESC, pub_date ASC, time DESC LIMIT 1 };

    $barcode = $self->SimpleSqlGet( $sql );
    if ( $self->get("verbose") ) { $self->Logit("once: $sql"); }

    if ( ! $barcode ) 
    {
        my $nextPubDate = $self->GetNextPubYear();
        
        # If there is a priority 2, do DESC on priority order. If priority 1, do ASC 20% of the time (to pick up
        # a few priority 0 items if they exist. This is basically to 'fool' reviewers into not thinking everything is pd.
        my $sort = 'DESC';
        my $top = $self->TopPriority();
        $sort = 'ASC' if $top == 1 and rand() <= 0.2;
        #Get the 1st available item that has never been reviewed.
        my $sql = qq{ SELECT id FROM $CRMSGlobals::queueTable WHERE locked is NULL AND } .
                  qq{ status = 0 AND expcnt = 0 AND id not in ( SELECT distinct id from $CRMSGlobals::reviewsTable ) and pub_date >= $nextPubDate ORDER BY priority $sort, pub_date ASC, time DESC LIMIT 1 };

        my $ref = $self->get( 'dbh' )->selectall_arrayref( $sql );

        $barcode = $self->SimpleSqlGet( $sql );

    }

    ## lock before returning
    if ( ! $self->LockItem( $barcode, $name ) ) 
    { 
        $self->Logit( "failed to lock $barcode for $name" );
        return;
    }
    
    return $barcode;
}

sub TopPriority
{
  my $self = shift;
  
  my $sql = "SELECT max(priority) FROM $CRMSGlobals::queueTable";
  return $self->SimpleSqlGet($sql);
}

sub GetQueuePriorities
{
  my $self = shift;
  
  my $sql = qq{SELECT count(priority),priority FROM queue GROUP BY priority ASC};
  my $ref  = $self->get( 'dbh' )->selectall_arrayref( $sql );

  my @return;
  foreach (@{$ref}) { push @return, sprintf("%d priority %d", $_->[0], $_->[1]); }
  return @return;
}

sub GetNextPubYear
{
    my $self  = shift;

    my $sql   = qq{ SELECT pubyear from pubyearcycle};
    #my $ref   = $self->get( 'dbh' )->selectall_arrayref( $sql );
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

    my $ref  = $self->get( 'dbh' )->selectall_arrayref( $sql );

    my @return;
    foreach (@{$ref}) { push @return, $_->[0]; }
    return @return;
}

sub ItemWasReviewedByUser
{
    my $self  = shift;
    my $user  = shift;
    my $id    = shift;

    my $sql   = qq{ SELECT id FROM $CRMSGlobals::reviewsTable WHERE user = "$user" AND id = "$id"};
    #my $ref   = $self->get( 'dbh' )->selectall_arrayref( $sql );
    my $found = $self->SimpleSqlGet( $sql );

    if ($found) { return 1; }
    return 0;
}



sub GetItemReviewDetails
{
    my $self = shift;
    my $id   = shift;
    my $user = shift;

    my $sql  = qq{ SELECT attr, reason, renNum, note FROM reviews WHERE id = "$id"};

    ## if name, limit to just that users review details
    if ( $user ) { $sql .= qq{ AND user = "$user" }; }

    my $ref  = $self->get( 'dbh' )->selectall_arrayref( $sql );

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

    my $sql  = qq{ SELECT count(id) FROM $CRMSGlobals::reviewsTable WHERE id = "$id"};
    my $ref  = $self->get( 'dbh' )->selectall_arrayref( $sql );

    if ( $ref->[0]->[0] > 1 ) { return 1; }
    return 0;
}

sub GetRightsName
{
    my $self = shift;
    my $id   = shift;
    my $sql  = qq{ SELECT name FROM attributes WHERE id = "$id" };

    my $ref  = $self->get( 'sdr_dbh' )->selectall_arrayref($sql);
    return $ref->[0]->[0];
}

sub GetReasonName
{
    my $self = shift;
    my $id   = shift;
    my $sql  = qq{ SELECT name FROM reasons WHERE id = "$id" }; 

    my $ref  = $self->get( 'sdr_dbh' )->selectall_arrayref($sql);
    return $ref->[0]->[0];
}

sub GetRightsNum
{
    my $self = shift;
    my $id   = shift;
    my $sql  = qq{ SELECT id FROM attributes WHERE name = "$id" };

    my $ref  = $self->get( 'sdr_dbh' )->selectall_arrayref($sql);
    return $ref->[0]->[0];
}

sub GetReasonNum
{
    my $self = shift;
    my $id   = shift;
    my $sql  = qq{ SELECT id FROM reasons WHERE name = "$id" };

    my $ref  = $self->get( 'sdr_dbh' )->selectall_arrayref($sql);
    return $ref->[0]->[0];
}

sub GetCopyDate
{
    my $self = shift;
    my $id   = shift;
    my $user = shift;
    my $sql  = qq{ SELECT copyDate FROM $CRMSGlobals::reviewsTable WHERE id = "$id" AND user = "$user"};

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
    my $sql  = qq{ SELECT renNum FROM $CRMSGlobals::reviewsTable WHERE id = "$id" AND user = "$user"};

    if ( ! $self->IsUserExpert($user) ) { $sql .= qq{ AND user = "$user"}; }

    return $self->SimpleSqlGet( $sql );
}

sub GetRenNums
{   
    my $self = shift;
    my $id   = shift;
    my $user = shift;

    my $sql  = qq{SELECT renNum FROM $CRMSGlobals::reviewsTable WHERE id = "$id" };

    ## if not expert, limit to just that users renNums
    if ( ! $self->IsUserExpert($user) ) { $sql .= qq{ AND user = "$user"}; }

    my $ref  = $self->get( 'dbh' )->selectall_arrayref( $sql );

    my @return;
    foreach ( @{$ref} ) { if ($_->[0] ne "") { push @return, $_->[0]; } }
    return @return;
}

sub GetRenDate
{
    my $self = shift;
    my $id   = shift;
    
    $id =~ s, ,,gs;
    my $sql  = qq{ SELECT DREG FROM $CRMSGlobals::stanfordTable WHERE ID = "$id" };

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

sub GetYesterdaysDate
{
    my $self = shift;
    return $self->GetPrevDate();
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
    my $self    = shift;
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
    my $fh   = $self->get( 'logFh' );

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

sub GetQueueSize
{
    my $self = shift;

    my $sql  = qq{ SELECT count(*) from $CRMSGlobals::queueTable};
    my $count  = $self->SimpleSqlGet( $sql );
    
    return $count;
}


sub GetTotalUndInf
{
    my $self = shift;

    my $sql  = qq{ SELECT count(*) from $CRMSGlobals::queueTable where status= 3};
    my $count  = $self->SimpleSqlGet( $sql );
    
    if ($count) { return $count; }
    return 0;
}

sub GetTotalWithFinalDetermination
{
    my $self = shift;

    my $sql  = qq{ SELECT count(*) from $CRMSGlobals::queueTable where status= 4 OR status = 5};
    my $count  = $self->SimpleSqlGet( $sql );
    
    if ($count) { return $count; }
    return 0;
}

sub GetTotalConflict
{
    my $self = shift;

    my $sql  = qq{ SELECT count(*) from $CRMSGlobals::queueTable where status= 2};
    my $count  = $self->SimpleSqlGet( $sql );
    
    if ($count) { return $count; }
    return 0;
}


sub GetTotalInActiveQueue
{
    my $self = shift;

    my $sql  = qq{ SELECT count(*) from $CRMSGlobals::queueTable where status > 0 };
    my $count  = $self->SimpleSqlGet( $sql );
    
    if ($count) { return $count; }
    return 0;
}


sub GetTotalInHistoricalQueue
{
    my $self = shift;

    my $sql  = qq{ SELECT count(*) from $CRMSGlobals::historicalreviewsTable };
    my $count  = $self->SimpleSqlGet( $sql );
    
    if ($count) { return $count; }
    return 0;
}


sub GetReviewsWithStatusNumber
{
    my $self = shift;
    my $status = shift;

    my $sql  = qq{ SELECT count(*) from $CRMSGlobals::queueTable where status = $status};
    my $count  = $self->SimpleSqlGet( $sql );
    
    if ($count) { return $count; }
    return 0;
}




sub GetTotalReviewedNotProcessed
{
    my $self = shift;

    my $sql  = qq{ SELECT count(distinct id) from $CRMSGlobals::reviewsTable where id in ( select id from $CRMSGlobals::queueTable where status = 0)};
    my $count  = $self->SimpleSqlGet( $sql );
    
    if ($count) { return $count; }
    return 0;
}

sub GetTotalAwaitingReview
{
    my $self = shift;

    my $sql  = qq{ SELECT count(distinct id) from $CRMSGlobals::queueTable where status=0 and id not in ( select id from $CRMSGlobals::reviewsTable)};
    my $count  = $self->SimpleSqlGet( $sql );
    
    if ($count) { return $count; }
    return 0;
}


sub GetLastLoadSizeToCandidates
{
    my $self = shift;

    my $sql  = qq{SELECT addedamount from candidatesrecord order by time DESC LIMIT 1};
    my $count  = $self->SimpleSqlGet( $sql );
    
    if ($count) { return $count; }
    return 0;

}

sub GetLastLoadTimeToCandidates
{
    my $self = shift;

    my $sql  = qq{SELECT max(time) from candidatesrecord};
    my $time  = $self->SimpleSqlGet( $sql );
    
    if ($time) { return $time; }
    return 'no data available';

}


sub GetTotalExported
{
    my $self = shift;

    my $sql  = qq{SELECT sum( itemcount ) from $CRMSGlobals::exportrecordTable};
    my $count  = $self->SimpleSqlGet( $sql );
    
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


sub GetLastTimeExported
{
    my $self = shift;

    my $sql  = qq{ SELECT time from $CRMSGlobals::exportrecordTable order by 1 DESC LIMIT 1};
    my $export_date  = $self->SimpleSqlGet( $sql );
    
    return $export_date;
}

sub GetLastItemCountExported
{
    my $self = shift;

    my $sql  = qq{ SELECT itemcount, time from $CRMSGlobals::exportrecordTable order by 2 DESC LIMIT 1};
    my $ref = $self->get( 'dbh' )->selectall_arrayref( $sql );  

    return $ref->[0]->[0];

}

sub GetCumExportedCount
{
    my $self = shift;

    my $sql  = qq{ SELECT sum(itemcount) from $CRMSGlobals::exportrecordTable};
    my $ref = $self->get( 'dbh' )->selectall_arrayref( $sql );  

    return $ref->[0]->[0];

}

sub GetTotalLegacyCount
{
    my $self = shift;

    my $sql  = qq{ SELECT count(distinct id) from $CRMSGlobals::historicalreviewsTable where legacy=1};
    my $ref = $self->get( 'dbh' )->selectall_arrayref( $sql );  

    return $ref->[0]->[0];

}

sub GetTotalLegacyReviewCount
{
    my $self = shift;

    my $sql  = qq{ SELECT count(*) from $CRMSGlobals::historicalreviewsTable where legacy=1};
    my $ref = $self->get( 'dbh' )->selectall_arrayref( $sql );  

    return $ref->[0]->[0];

}

sub GetTotalHistoricalReviewCount
{
    my $self = shift;

    my $sql  = qq{ SELECT count(*) from $CRMSGlobals::historicalreviewsTable};
    my $ref = $self->get( 'dbh' )->selectall_arrayref( $sql );  

    return $ref->[0]->[0];

}

sub GetLastQueueTime
{
    my $self = shift;

    my $sql  = qq{ SELECT max( time ) from $CRMSGlobals::queuerecordTable where source = 'RIGHTSDB'};
    my $latest_time  = $self->SimpleSqlGet( $sql );
    
    #Keep only the date
    #$latest_time =~ s,(.*) .*,$1,;

    return $latest_time;

}

sub GetLastStatusProcessedTime 
{

    my $self = shift;

    my $sql  = qq{ SELECT max(time) from  processstatus };
    my $last_time  = $self->SimpleSqlGet( $sql );
    
    return $last_time;
}

sub GetLastIdQueueCount
{
    my $self = shift;

    my $latest_time = $self->GetLastQueueTime();

    my $sql  = qq{ SELECT itemcount from $CRMSGlobals::queuerecordTable where time like '$latest_time%' AND source='RIGHTSDB'};
    my $latest_time  = $self->SimpleSqlGet( $sql );
    
    return $latest_time;

}

sub GetPageSize
{
    my $self = shift;

    return 20;

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

      print &CGI::header(-type => 'text/plain',
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

1;
