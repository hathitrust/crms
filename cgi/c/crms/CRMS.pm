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

    $self->set( 'bc2metaUrl', q{http://mirlyn.lib.umich.edu/cgi-bin/bc2meta} );
    $self->set( 'oaiBaseUrl', q{http://mirlyn.lib.umich.edu/OAI} );
    $self->set( 'verbose',     $args{'verbose'});
    $self->set( 'parser',      XML::LibXML->new() );
    $self->set( 'barcodeID',   {} );
 
    $self->set( 'root',        $args{'root'} );
    $self->set( 'dev',         $args{'dev'} );
    $self->set( 'user',        $args{'user'} );

    $self->set( 'dbh',         $self->ConnectToDb() );
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

    if ( ! $self->get( 'dev' ) ) { $db_server = $CRMSGlobals::mysqlServer; }

    if ($self->get('verbose')) { $self->Logit( "DBI:mysql:mdp:$db_server, $db_user, [passwd]" ); }

    my $sdr_dbh   = DBI->connect( "DBI:mysql:mdp:$db_server", $db_user, $db_passwd,
              { RaiseError => 1, AutoCommit => 1 } ) || die "Cannot connect: $DBI::errstr";

    $sdr_dbh->{mysql_auto_reconnect} = 1;

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

sub SimpleSqlGet
{
    my $self = shift;
    my $sql  = shift;

    my $ref  = $self->get('dbh')->selectall_arrayref( $sql );
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


sub LoadNewItemsInCandidates
{
    my $self    = shift;

    my $start = $self->GetCandidatesTime();
    my $size = $self->GetCandidatesSize();

    my $msg = qq{Starting to load Candidate from rights table.\n};
    $msg .= qq{The max timestamp in the cadidates table $start, and the size is $size\n};
    print $msg;

    my $sql = qq{SELECT CONCAT(namespace, '.', id) AS id, MAX(time) AS time, attr, reason FROM rights WHERE time >= '$start' GROUP BY id};

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

    my $size = $self->GetCandidatesSize();
    $msg = qq{All DONE updating candidates from rights.  The cadidate now has $size rows.\n\n};
    print $msg;

    return 1;
}


sub LoadNewItems
{
    my $self    = shift;

    my $queuesize = $self->GetQueueSize();

    my $msg = qq{Starting to load queue from candidates.\n};
    $msg .= qq{The queue has $queuesize items in it presently.\n};
    print $msg;

    if ( $queuesize < 800 )
    {  
      my $limitcount = 800 - $queuesize;

      my $twodaysago = $self->TwoDaysAgo();
      
      my $sql = qq{SELECT id, time, pub_date, title, author from candidates where id not in ( select distinct id from reviews ) and id not in ( select distinct id from historicalreviews ) and time <= '$twodaysago' and id not like 'uc1%' order by time desc};

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

    $msg = qq{All DONE loading queue from candidates.\n};
    print $msg;

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

    #Only care about items between 1923 and 1963
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

    #Only care about items between 1923 and 1963
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

    #Only care about items between 1923 and 1963
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
	  my $sql = qq{INSERT INTO $CRMSGlobals::queueTable (id, time, status, pub_date, priority) VALUES ('$id', '$time', $status, '$pub', $priority)};

	  $self->PrepareSubmitSql( $sql );

	  $self->UpdateTitle ( $id );

	  #Update the pub date in bibdata
	  $self->UpdatePubDate ( $id, $pub );

	  my $author = $self->GetEncAuthor ( $id );
	  $self->UpdateAuthor ( $id, $author );

	  my $sql = qq{INSERT INTO $CRMSGlobals::queuerecordTable (itemcount, source ) values (1, 'ADMINSCRIPT')};
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

    if ( ! $self->ChechForId( $id ) )                     { $self->Logit("id check failed");          return 0; }
    if ( ! $self->CheckReviewer( $user, $exp ) )          { $self->Logit("review check failed");      return 0; }
    if ( ! $self->ValidateAttr( $attr ) )                 { $self->Logit("attr check failed");        return 0; }
    if ( ! $self->ValidateReason( $reason ) )             { $self->Logit("reason check failed");      return 0; }
    if ( ! $self->CheckAttrReasonComb( $attr, $reason ) ) { $self->Logit("attr/reason check failed"); return 0; }

    #remove any blancks from renNum
    $renNum =~ s, ,,gs;

    ## do some sort of check for expert submissions

    my @fieldList = ("id", "user", "attr", "reason", "note", "renNum", "renDate", "category");
    my @valueList = ($id,  $user,  $attr,  $reason,  $note,  $renNum,  $renDate, $category);

    if ($exp)      { push(@fieldList, "expert");   push(@valueList, $exp); }
    if ($copyDate) { push(@fieldList, "copyDate"); push(@valueList, $copyDate); }

    my $sql = qq{REPLACE INTO $CRMSGlobals::reviewsTable (} . join(", ", @fieldList) . 
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

        my ( $other_user, $other_attr, $other_reason, $other_renDate, $other_renNum ) = $self->GetOtherReview ( $id, $user );

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
		 if ( ( $renNum == $other_renNum ) && ( $renDate == $other_renDate ) )
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



## ----------------------------------------------------------------------------
##  Function:   submit historical review  (from excel SS)   
##  Parameters: 
##  Return:     1 || 0
## ----------------------------------------------------------------------------
sub SubmitHistReview
{
    my $self = shift;
    my ($id, $user, $date, $attr, $reason, $cDate, $renNum, $renDate, $note, $eNote, $category, $status) = @_;

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
    $self->UpdateTitle ( $id );

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
##  Parameters: NONE
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

  my $subject = qq{$count voulmes exported to rights dbreport to rithts db};
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


sub MoveFromReviewsToHistoricalReviews
{
    my $self = shift;
    my $id   = shift;

    my $status = $self->GetStatus ( $id );

    $self->Logit( "store $id in historicalreviews" );


    my $sql = qq{REPLACE into $CRMSGlobals::historicalreviewsTable (id, time, user, attr, reason, note, renNum, expert, duration, legacy, expertNote, renDate, copyDate, category, flagged) select id, time, user, attr, reason, note, renNum, expert, duration, 0, expertNote, renDate, copyDate, category, flagged from reviews where id='$id'};
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
              qq{ORDER BY expert, time DESC LIMIT 1};
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
      $sql = qq{ SELECT r.id, r.time, r.duration, r.user, r.attr, r.reason, r.note, r.renNum, r.expert, r.copyDate, r.expertNote, r.category, r.legacy, r.renDate, r.flagged, q.status, b.title, b.author FROM $CRMSGlobals::reviewsTable r, $CRMSGlobals::queueTable q, bibdata b WHERE q.id = r.id AND q.id = b.id AND q.status >= 0 };
    }
    elsif ( $type eq 'conflict' )
    {
      $sql = qq{ SELECT r.id, r.time, r.duration, r.user, r.attr, r.reason, r.note, r.renNum, r.expert, r.copyDate, r.expertNote, r.category, r.legacy, r.renDate, r.flagged, q.status, b.title, b.author FROM $CRMSGlobals::reviewsTable r, $CRMSGlobals::queueTable q, bibdata b WHERE q.id = r.id AND q.id = b.id  AND ( q.status = 2 ) };
    }
    elsif ( $type eq 'historicalreviews' )
    {
      $sql = qq{ SELECT r.id, r.time, r.duration, r.user, r.attr, r.reason, r.note, r.renNum, r.expert, r.copyDate, r.expertNote, r.category, r.legacy, r.renDate, r.flagged, r.status, b.title, b.author FROM $CRMSGlobals::historicalreviewsTable r, bibdata b  WHERE r.id = b.id AND r.status >= 0  };
    }
    elsif ( $type eq 'undreviews' )
      {
	$sql = qq{ SELECT r.id, r.time, r.duration, r.user, r.attr, r.reason, r.note, r.renNum, r.expert, r.copyDate, r.expertNote, r.category, r.legacy, r.renDate, r.flagged, q.status, b.title, b.author FROM $CRMSGlobals::reviewsTable r, $CRMSGlobals::queueTable q, bibdata b WHERE q.id = b.id  AND q.id = r.id AND q.status = 3 };
    }
    elsif ( $type eq 'userreviews' )
      {
	my $user = $self->get( "user" );
	$sql = qq{ SELECT r.id, r.time, r.duration, r.user, r.attr, r.reason, r.note, r.renNum, r.expert, r.copyDate, r.expertNote, r.category, r.legacy, r.renDate, r.flagged, q.status, b.title, b.author FROM $CRMSGlobals::reviewsTable r, $CRMSGlobals::queueTable q, bibdata b WHERE q.id = r.id AND q.id = b.id AND r.user = '$user' AND q.status > 0 };
    }
    elsif ( $type eq 'editreviews' )
    {
	my $user = $self->get( "user" );
	my $yesterday = $self->GetYesterday();
	$sql = qq{ SELECT r.id, r.time, r.duration, r.user, r.attr, r.reason, r.note, r.renNum, r.expert, r.copyDate, r.expertNote, r.category, r.legacy, r.renDate, r.flagged, q.status, b.title, b.author FROM $CRMSGlobals::reviewsTable r, $CRMSGlobals::queueTable q, bibdata b WHERE q.id = r.id AND q.id = b.id AND r.user = '$user' AND r.time >= "$yesterday" };
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
      $limit_section = qq{LIMIT $offset, 25};
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


    my $sql =  $self->CreateSQL ( $order, $direction, $search1, $search1value, $op1, $search2, $search2value, $since,$offset, $type, $limit );

    my $ref = $self->get( 'dbh' )->selectall_arrayref( $sql );

    my $buffer;
    if ( scalar @{$ref} != 0 )
    {
	if ( $type eq 'userreviews')
	{
	  $buffer .= qq{id\ttitle\tauthor\ttime\tattr\treason\tcategory\tnote\tflagged\n};
	}
	elsif ( $type eq 'editreviews' )
	{
	  $buffer .= qq{id\ttitle\tauthor\ttime\tattr\treason\tcategory\tnote\tflagged\n};
	}
	elsif ( $type eq 'undreviews' )
	{
	  $buffer .= qq{id\ttitle\tauthor\ttime\tstatus\tuser\tattr\treason\tcategory\tnote\tflagged\n}
	}
	elsif ( $type eq 'conflict' )
	{
	  $buffer .= qq{id\ttitle\tauthor\ttime\tstatus\tuser\tattr\treason\tcategory\tnote\tflagged\n};
	}
	elsif ( $type eq 'reviews' )
	{
	  $buffer .= qq{id\ttitle\tauthor\ttime\tstatus\tuser\tattr\treason\tcategory\tnote\tflagged\n};
	}
	elsif ( $type eq 'historicalreviews' )
	{
	  $buffer .= qq{id\ttitle\tauthor\ttime\tstatus\tlegacy\tuser\tattr\treason\tcategory\tnote\tflagged\n};
	}
    }

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
        my $renNum     = $row->[7];
        my $expert     = $row->[8];
        my $copyDate   = $row->[9];
        my $expertNote = $row->[10];
        my $category   = $row->[11];
        my $legacy     = $row->[12];
        my $renDate    = $row->[13];
        my $flagged     = $row->[14];
        my $status     = $row->[15];
        my $title      = $row->[16];
        my $author     = $row->[17];

	if ( $type eq 'userreviews')
	{
	  #for reviews
	  #id, title, author, review date, attr, reason, category, note, flagged.
	  $buffer .= qq{$id\t$title\t$author\t$time\t$attr\t$reason\t$category\t$note$flagged\n};
	}
	elsif ( $type eq 'editreviews' )
	{
	  #for editRevies
	  #id, title, author, review date, attr, reason, category, note, flagged.
	  $buffer .= qq{$id\t$title\t$author\t$time\t$attr\t$reason\t$category\t$note\t$flagged\n};
	}
	elsif ( $type eq 'undreviews' )
	{
	  #for und/nif
	  #id, title, author, review date, status, user, attr, reason, category, note, flagged.
	  $buffer .= qq{$id\t$title\t$author\t$time\t$status\t$user\t$attr\t$reason\t$category\t$note\t$flagged\n}
	}
	elsif ( $type eq 'conflict' )
	{
	  #for expert
	  #id, title, author, review date, status, user, attr, reason, category, note, flagged.
	  $buffer .= qq{$id\t$title\t$author\t$time\t$status\t$user\t$attr\t$reason\t$category\t$note\t$flagged\n};
	}
	elsif ( $type eq 'reviews' )
	{
	  #for adminReviews
	  #id, title, author, review date, status, user, attr, reason, category, note, flagged.
	  $buffer .= qq{$id\t$title\t$author\t$time\t$status\t$user\t$attr\t$reason\t$category\t$note\t$flagged\n};
	}
	elsif ( $type eq 'historicalreviews' )
	{
	  #for adminHistoricalReviews
	  #id, title, author, review date, status, user, attr, reason, category, note, flagged.
	  $buffer .= qq{$id\t$title\t$author\t$time\t$status\t$legacy\t$user\t$attr\t$reason\t$category\t$note\t$flagged\n};
	}

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
                     flagged     => $row->[14],
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
    
    if ( ! $offset ) { $offset = 0; }

    if ( ! $order || $order eq "time" ) { $order = "time DESC "; }

    my $sql = qq{ SELECT id, time, duration, user, attr, reason, note, renNum, expert, copyDate, expertNote, category, legacy, renDate, flagged, status FROM $CRMSGlobals::historicalreviewsTable };

    if    ( $user )                    { $sql .= qq{ WHERE user = "$user" };   }

    if    ( $since && $user )          { $sql .= qq{ AND   time >= "$since"};  }
    elsif ( $since )                   { $sql .= qq{ WHERE time >= "$since" }; }

    if    ( $id && ($user || $since) ) { $sql .= qq{ AND   id = "$id" }; }
    elsif ( $id )                      { $sql .= qq{ WHERE id = "$id" }; }

    $sql .= qq{ ORDER BY $order LIMIT $offset, 25 };

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
                     flagged     => $row->[14],
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

    $search1 = $self->ConvertToSearchTerm ( $search1, $type );
    $search2 = $self->ConvertToSearchTerm ( $search2, $type );


    my $sql;
    if ( $type eq 'reviews' )
    {
      $sql = qq{ SELECT count(*) FROM $CRMSGlobals::reviewsTable r, $CRMSGlobals::queueTable q, bibdata b WHERE q.id = r.id AND q.id = b.id AND q.status >= 0 };
    }
    elsif ( $type eq 'conflict' )
    {
      $sql = qq{ SELECT count(*) FROM $CRMSGlobals::reviewsTable r, $CRMSGlobals::queueTable q, bibdata b WHERE q.id = r.id AND q.id = b.id  AND ( q.status = 2 ) };
    }
    elsif ( $type eq 'historicalreviews' )
    {
      $sql = qq{ SELECT count(*) FROM $CRMSGlobals::historicalreviewsTable r, bibdata b  WHERE r.id = b.id AND r.status >= 0  };
    }
    elsif ( $type eq 'undreviews' )
      {
	$sql = qq{ SELECT count(*) FROM $CRMSGlobals::reviewsTable r, $CRMSGlobals::queueTable q, bibdata b WHERE q.id = b.id  AND q.id = r.id AND q.status = 3 };
    }
    elsif ( $type eq 'userreviews' )
      {
	my $user = $self->get( "user" );
	$sql = qq{ SELECT count(*) FROM $CRMSGlobals::reviewsTable r, $CRMSGlobals::queueTable q, bibdata b WHERE q.id = r.id AND q.id = b.id AND r.user = '$user' AND q.status > 0 };
    }
    elsif ( $type eq 'editreviews' )
    {
	my $user = $self->get( "user" );
	my $yesterday = $self->GetYesterday();
	$sql = qq{ SELECT count(*) FROM $CRMSGlobals::reviewsTable r, $CRMSGlobals::queueTable q, bibdata b WHERE q.id = r.id AND q.id = b.id AND r.user = '$user' AND r.time >= "$yesterday" };
	
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
    
    ## my $url  = 'http://babel.hathitrust.org/cgi/pt?attr=1&id=';
    my $url  = '/cgi/m/mdp/pt?skin=crms;attr=1;id=';

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
                 4 => "ic/ren", 5 => "ic/cdpp", 6 => "und/nfi" );

    my %str   = ("pd/ncn" => 1, "pd/ren"  => 2, "pd/cdpp" => 3,
                 "ic/ren" => 4, "ic/cdpp" => 5, "und/nfi" => 6);

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

sub ChechForId
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
    $sec =~ s,.*?:(.*?):.*,$1,;

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
    $sec =~ s,.*?:(.*?):.*,$1,;

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
  
  my $sql  = qq{ INSERT INTO userstats (user, month, year, monthyear, total_reviews, total_pd_ren, total_pd_cnn, total_pd_cdpp, total_ic_ren, total_ic_cdpp, total_und_nfi, total_time, time_per_review, reviews_per_hour, total_outliers) VALUES ('$user', '$month', '$year', '$start_date', $total_reviews_toreport, $total_pd_ren, $total_pd_cnn, $total_pd_cdpp, $total_ic_ren, $total_ic_cdpp, $total_und_nfi, $total_time, $time_per_review, $reviews_per_hour, $total_outliers )};

  $self->PrepareSubmitSql( $sql );

}


sub GetTheYear
{

   my $self = shift;

   my $newtime = scalar localtime(time());
   my $year = substr($newtime, 20, 4);

   return $year;	
	
}

sub CreateStatsReport
{	
   my $self = shift;
   my $user = shift;

   my $dbh = $self->get( 'dbh' );

   my $year = $self->GetTheYear ();	
   my $lastYear = $year - 1;

   my $min = qq{$lastYear-07};
   my $max = qq{$year-06};
   #find out how many distinct months there are
   my $sql = qq{SELECT distinct monthyear from userstats where monthyear >= '$min' and monthyear <= '$max'};
   
   my $rows = $dbh->selectall_arrayref( $sql );

   my @statdates;
   my $datecount = 0;
   foreach my $row ( @{$rows} )
   {
      push ( @statdates, $row->[0] );
      $datecount = $datecount + 1;
   }	

   my ( @outrow0, @outrow1, @outrow2, @outrow3, @outrow4, @outrow5, @outrow6, @outrow7, @outrow8, @outrow9, @outrow10 );
   foreach my $date ( @statdates )
   {

     my $sql = qq{SELECT total_reviews, total_pd_ren, total_pd_cnn, total_pd_cdpp, total_ic_ren, total_ic_cdpp, total_und_nfi, total_time, time_per_review, reviews_per_hour, total_outliers from userstats where monthyear='$date' and user='$user'};
   
     my $rows = $dbh->selectall_arrayref( $sql );

     foreach my $row ( @{$rows} )
     {
        push ( @outrow0,  $row->[0]  );	
        push ( @outrow1,  $row->[1]  );	
        push ( @outrow2,  $row->[2]  );	
        push ( @outrow3,  $row->[3]  );	
        push ( @outrow4,  $row->[4]  );	
        push ( @outrow5,  $row->[5]  );	
        push ( @outrow6,  $row->[6]  );	
        push ( @outrow7,  $row->[7]  );	
        push ( @outrow8,  $row->[8]  );	
        push ( @outrow9,  $row->[9]  );	
        push ( @outrow10, $row->[10] );	
     }
   }	

   my $report = qq{<table><tr><td>$user</td>};
   foreach my $date ( @statdates )
   {	
      $report .= qq{<td>$date</td>};
   }
   $report .= qq{</tr>\n};	
  
   $report .= qq{<tr><td>Total Reviews</td>};
   my $count = 0;
   while ( $count < $datecount )
   {
       $report .= qq{<td>$outrow0[$count]</td>};
       $count = $count + 1;
   }
   $report .= qq{</tr>};

   $report .= qq{<tr><td>PD-REN</td>};
   my $count = 0;
   while ( $count < $datecount )
   {
       $report .= qq{<td>$outrow1[$count]</td>};
       $count = $count + 1;
   }
   $report .= qq{</tr>};

   $report .= qq{<tr><td>PD-NCN</td>};
   my $count = 0;
   while ( $count < $datecount )
   {
       $report .= qq{<td>$outrow2[$count]</td>};
       $count = $count + 1;
   }
   $report .= qq{</tr>};

   $report .= qq{<tr><td>PD-CDPP</td>};
   my $count = 0;
   while ( $count < $datecount )
   {
       $report .= qq{<td>$outrow3[$count]</td>};
       $count = $count + 1;
   }
   $report .= qq{</tr>};

   $report .= qq{<tr><td>IC-REN</td>};
   my $count = 0;
   while ( $count < $datecount )
   {
       $report .= qq{<td>$outrow4[$count]</td>};
       $count = $count + 1;
   }
   $report .= qq{</tr>};

   $report .= qq{<tr><td>IC-CDPP</td>};
   my $count = 0;
   while ( $count < $datecount )
   {
       $report .= qq{<td>$outrow5[$count]</td>};
       $count = $count + 1;
   }
   $report .= qq{</tr>};

   $report .= qq{<tr><td>UND-NFI</td>};
   my $count = 0;
   while ( $count < $datecount )
   {
       $report .= qq{<td>$outrow6[$count]</td>};
       $count = $count + 1;
   }
   $report .= qq{</tr>};

   $report .= qq{<tr><td>Time Reviewing (minutes)</td>};
   my $count = 0;
   while ( $count < $datecount )
   {
       $report .= qq{<td>$outrow7[$count]</td>};
       $count = $count + 1;
   }
   $report .= qq{</tr>};

   $report .= qq{<tr><td>Time per Review (minutes)</td>};
   my $count = 0;
   while ( $count < $datecount )
   {
       $report .= qq{<td>$outrow8[$count]</td>};
       $count = $count + 1;
   }
   $report .= qq{</tr>};

   $report .= qq{<tr><td>Reviews per Hour</td>};
   my $count = 0;
   while ( $count < $datecount )
   {
       $report .= qq{<td>$outrow9[$count]</td>};
       $count = $count + 1;
   }
   $report .= qq{</tr>};

   $report .= qq{<tr><td>Outlier Reviews</td>};
   my $count = 0;
   while ( $count < $datecount )
   {
       $report .= qq{<td>$outrow10[$count]</td>};
       $count = $count + 1;
   }	
   $report .= qq{</tr></table>};
  
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



sub ValidateSubmission2
{
    my $self = shift;
    my ($attr, $reason, $note, $category, $renNum, $renDate, $user) = @_;
    my $errorMsg = "";

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
    }

    ## ic/cdpp requires a ren number
    if (  $attr == 2 && $reason == 9 && ( ( $renNum ) || ( $renDate ) ) )
    {
        $errorMsg .= qq{ic/cdpp should not include renewal info.  };
    }

    if ( $attr == 2 && $reason == 9 && ( ( ! $note )  || ( ! $category ) )  ) 
    {
        $errorMsg .= qq{ic/cdpp must include note category and note text.  };
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
      my $title   = $self->GetRecordTitleBc2Meta( $id );
    }

    my $tiq  = $self->get("dbh")->quote( $title );

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
    my $url    = "http://mirlyn.lib.umich.edu/cgi-bin/bc2meta?id=$id";
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

    my $au = $self->GetMarcDatafield ( $bar, 100, 'a');

    $au =~ s,\',\\\',g; ## escape '
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
    #my $url   = "http://mirlyn.lib.umich.edu/cgi-bin/api/marc.xml/uid/$sysId";
    #my $url    = "http://mirlyn.lib.umich.edu/cgi-bin/api_josh/marc.xml/itemid/$bar";
    my $url    = qq{http://mirlyn.lib.umich.edu/cgi-bin/bc2meta?id=$barcode&schema=marcxml};
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
    $id = "MIU01-" . $id;

    $barcodeID->{$barcode} = $id;   ## put into cache
    return $id;
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
        
        #Get the 1st available item that has never been reviewed.
        my $sql = qq{ SELECT id FROM $CRMSGlobals::queueTable WHERE locked is NULL AND } .
                  qq{ status = 0 AND expcnt = 0 AND id not in ( SELECT distinct id from $CRMSGlobals::reviewsTable ) and pub_date >= $nextPubDate ORDER BY priority DESC, pub_date ASC, time DESC LIMIT 1 };

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

sub GetNextPubYear
{
    my $self  = shift;

    my $sql   = qq{ SELECT pubyear from pubyearcycle};
    my $ref   = $self->get( 'dbh' )->selectall_arrayref( $sql );
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
    my $ref   = $self->get( 'dbh' )->selectall_arrayref( $sql );
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


sub GetReviewsWith4Status
{
    my $self = shift;

    my $sql  = qq{ SELECT count(*) from $CRMSGlobals::reviewsTable where id in ( select id from queue where status = 4)};
    my $count  = $self->SimpleSqlGet( $sql );
    
    if ($count) { return $count; }
    return 0;
}

sub GetReviewsWith5Status
{
    my $self = shift;

    my $sql  = qq{ SELECT count(distinct id) from $CRMSGlobals::reviewsTable where id in ( select id from queue where status = 5)};
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

