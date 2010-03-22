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
use Date::Calendar;
use Date::Calendar::Profiles qw( $Profiles );
use POSIX qw(strftime);
use DBI qw(:sql_types);
use List::Util qw(min max);

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
    if ($@)
    {
      $self->SetError("sql failed ($sql): " . $sth->errstr);
      $self->Logit("sql failed ($sql): " . $sth->errstr);
    }
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
    
    my $val = undef;
    eval {
      my $ref = $self->get('dbh')->selectall_arrayref( $sql );
      $val = $ref->[0]->[0];
    };
    if ($@)
    {
      $self->SetError("sql failed ($sql): " . $@);
      $self->Logit("sql failed ($sql): " . $@);
    }
    return $val;
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

sub ProcessReviews
{
  my $self = shift;
  
  my $start_size = $self->GetCandidatesSize();
  my $sql = 'SELECT id, user, attr, reason, renNum, renDate FROM reviews WHERE id IN (SELECT id FROM queue WHERE status=0) ' .
            'GROUP BY id HAVING count(*) = 2';
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
      #If both und/nfi then status is 3
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
  # Clear out all the locks
  my $sql = 'UPDATE queue SET locked=NULL WHERE locked IS NOT NULL';
  $self->PrepareSubmitSql( $sql );
  my $sql = 'INSERT INTO processstatus VALUES ( )';
  $self->PrepareSubmitSql( $sql );
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
    my $count = 0;
    my $start_size = $self->GetCandidatesSize();

    foreach my $id ( @{$list} )
    {
      #The routine GetFinalAttrReason may need to change - jose
      my ($attr,$reason) = $self->GetFinalAttrReason($id);

      print $fh "$id\t$attr\t$reason\t$user\tnull\n";
      
      my $src = $self->SimpleSqlGet("SELECT source FROM queue WHERE id='$id' ORDER BY time DESC LIMIT 1");
      
      my $sql = qq{ INSERT INTO  exportdata (time, id, attr, reason, user, src ) VALUES ('$time', '$id', '$attr', '$reason', '$user', '$src' )};
      $self->PrepareSubmitSql( $sql );
      
      my $gid = $self->SimpleSqlGet('SELECT MAX(gid) FROM exportdata');
      
      $sql = qq{ INSERT INTO exportdataBckup (time, id, attr, reason, user, src ) VALUES ('$time', '$id', '$attr', '$reason', '$user', '$src' )};
      $self->PrepareSubmitSql( $sql );

      $self->MoveFromReviewsToHistoricalReviews($id,$gid);
      $self->RemoveFromQueue($id);
      $self->RemoveFromCandidates($id);
      $count++;
    }
    close $fh;
    
    # Update correctness/validation now that everything is in historical
    foreach my $id ( @{$list} )
    {
      my $sql = "SELECT user,time,validated FROM historicalreviews WHERE id='$id'";
      my $ref = $self->get( 'dbh' )->selectall_arrayref( $sql );
      foreach my $row ( @{$ref} )
      {
        my $user = $row->[0];
        my $time = $row->[1];
        my $val  = $row->[2];
        my $val2 = $self->IsReviewCorrect($id, $user, $time);
        if ($val != $val2)
        {
          $sql = "UPDATE historicalreviews SET validated=$val2 WHERE id='$id' AND user='$user' AND time='$time'";
          $self->PrepareSubmitSql( $sql );
        }
      }
    }
    my $sql = qq{ INSERT INTO  $CRMSGlobals::exportrecordTable (itemcount) VALUES ( $count )};
    $self->PrepareSubmitSql( $sql );
    
    printf "After export, removed %d volumes from candidates.\n", $start_size-$self->GetCandidatesSize();
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

    my $sql = qq{ DELETE FROM $CRMSGlobals::queueTable WHERE id="$id" };
    $self->PrepareSubmitSql( $sql );

    return 1;
}

sub RemoveFromCandidates
{
  my $self = shift;
  my $id   = shift;

  my $sql = qq{ DELETE FROM candidates WHERE id="$id" };
  $self->PrepareSubmitSql( $sql );
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
    
    print "After load, candidates has $end_size rows. Added $diff\n\n";
    
    #Record the update to the queue
    my $sql = qq{INSERT INTO candidatesrecord ( addedamount ) values ( $diff )};
    $self->PrepareSubmitSql( $sql );

    return 1;
}


sub LoadNewItems
{
    my $self = shift;

    my $queuesize = $self->GetQueueSize();
    my $sql = 'SELECT COUNT(id) FROM queue WHERE priority=0';
    my $priZeroSize = $self->SimpleSqlGet($sql);
    printf "Before load, the queue has %d volumes.\n", $queuesize+$priZeroSize;
    my $needed = max($CRMSGlobals::queueSize - $queuesize, 300 - $priZeroSize);
    printf "Need $needed items (max of %d and %d).\n", $CRMSGlobals::queueSize - $queuesize, 300 - $priZeroSize;
    return if $needed <= 0;
    my $count = 0;
    my $y = 1923 + int(rand(40));
    while (1)
    {
      $sql = 'SELECT id, time, pub_date, title, author FROM candidates WHERE id NOT IN (SELECT DISTINCT id FROM queue) ' .
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
        last if $count >= $needed;
        $y++;
        $y = 1923 if $y > 1963;
      }
      last if $count >= $needed;
    }
    #Record the update to the queue
    my $sql = "INSERT INTO $CRMSGlobals::queuerecordTable (itemcount, source) VALUES ($count, 'RIGHTSDB')";
    $self->PrepareSubmitSql( $sql );
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
      $self->SetError("$id: UTF-8 check failed for quoted author: '$au'") unless $au eq "''" or utf8::is_utf8($au);
      
      my $title = $self->GetRecordTitleBc2Meta( $id );
      $title = $self->get('dbh')->quote($title);
      $self->SetError("$id: UTF-8 check failed for quoted title: '$title'") unless $title eq "''" or utf8::is_utf8($title);
      
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
  if ($override && 'annekz' ne $self->get('user'))
  {
    push @msgs, 'Only a superuser can set priority 4';
    $stat = 1;
  }
  ## give the existing item higher or lower priority
  elsif ( $self->IsItemInQueue( $id ) )
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
        my $sql = "INSERT INTO $CRMSGlobals::queueTable (id, priority, source) VALUES ('$id', $priority, 'adminui')";
        $self->PrepareSubmitSql( $sql );
        
        $self->UpdateTitle( $id );
        $self->UpdatePubDate( $id, $pub );
        $self->UpdateAuthor ( $id );
        
        my $sql = "INSERT INTO $CRMSGlobals::queuerecordTable (itemcount, source) VALUES (1, 'adminui')";
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
  my $source   = shift;

  ## skip if $id has been reviewed
  #if ( $self->IsItemInReviews( $id ) ) { return; }

  my $record = $self->GetRecordMetadata($id);

  ## pub date between 1923 and 1963
  my $pub = $self->GetPublDate( $id, $record );
  ## confirm date range and add check

  #Only care about volumes between 1923 and 1963
  if ( ( $pub >= '1923' ) && ( $pub <= '1963' ) )
  {
    ## no gov docs
    if ( $self->IsGovDoc( $id, $record ) ) { $self->SetError( "skip fed doc: $id" ); return 0; }

    #check 008 field postion 17 = "u" - this would indicate a us publication.
    if ( ! $self->IsUSPub( $id, $record ) ) { $self->SetError( "skip not us doc: $id" ); return 0; }

    #check FMT.
    if ( ! $self->IsFormatBK( $id, $record ) ) { $self->SetError( "skip not fmt bk: $id" ); return 0; }

    my $sql = qq{ SELECT count(*) from $CRMSGlobals::queueTable where id="$id"};
    my $count = $self->SimpleSqlGet( $sql );
    if ( $count == 1 )
    {
        $sql = qq{ UPDATE $CRMSGlobals::queueTable SET priority = 1 WHERE id = "$id" };
        $self->PrepareSubmitSql( $sql );
    }
    else
    {
      $sql = "INSERT INTO $CRMSGlobals::queueTable (id, time, status, priority, source) VALUES ('$id', '$time', $status, $priority, '$source')";

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
  else { $self->SetError( "skip bad date ($pub): $id" ); return 0; }
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

# Translates pre-CRMS, for legacyLoad.pl.
sub TranslateCategory
{
    my $self     = shift;
    my $category = uc shift;

    if    ( $category eq 'COLLECTION' ) { return 'Insert(s)'; }
    elsif ( $category =~ m/LANG.*/ ) { return 'Language'; }
    elsif ( $category eq 'MISC' ) { return 'Misc'; }
    elsif ( $category eq 'MISSING' ) { return 'Missing'; }
    elsif ( $category eq 'DATE' ) { return 'Date'; }
    elsif ( $category =~ m/REPRINT.*/ ) { return 'Reprint'; }
    elsif ( $category eq 'SERIES' ) { return 'Periodical'; }
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
  
  my %cats = ('Insert(s)' => 1, 'Language' => 1, 'Misc' => 1, 'Missing' => 1, 'Date' => 1, 'Reprint' => 1,
              'Periodical' => 1, 'Translation' => 1, 'Wrong Record' => 1, 'Foreign Pub' => 1, 'Dissertation/Thesis' => 1,
              'Expert Note' => 1, 'Not Class A' => 1, 'Edition' => 1, 'US Gov Doc' => 1);
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

# Used by experts to approve a review made by a reviewer.
sub CloneReview
{
  my $self   = shift;
  my $id     = shift;
  my $user   = shift;
  
  my $sql = "SELECT attr,reason FROM reviews WHERE id='$id'";
  my $rows = $self->get('dbh')->selectall_arrayref($sql);
  foreach my $row (@{$rows})
  {
    $self->SubmitReview($id,$user,$row->[0],$row->[1],undef,undef,undef,1,undef,'Expert Accepted');
    last;
  }
}

## ----------------------------------------------------------------------------
##  Function:   submit review
##  Parameters: id, user, attr, reason, note, stanford ren. number
##  Return:     1 || 0
## ----------------------------------------------------------------------------
sub SubmitReview
{
    my $self = shift;
    my ($id, $user, $attr, $reason, $copyDate, $note, $renNum, $exp, $renDate, $category, $swiss, $question) = @_;

    if ( ! $self->CheckForId( $id ) )                         { $self->SetError("id ($id) check failed");                    return 0; }
    if ( ! $self->CheckReviewer( $user, $exp ) )              { $self->SetError("reviewer ($user) check failed");            return 0; }
    if ( ! $self->ValidateAttr( $attr ) )                     { $self->SetError("attr ($attr) check failed");                return 0; }
    if ( ! $self->ValidateReason( $reason ) )                 { $self->SetError("reason ($reason) check failed");            return 0; }
    if ( ! $self->ValidateAttrReasonCombo( $attr, $reason ) ) { $self->SetError("attr/reason ($attr/$reason) check failed"); return 0; }
    
    $swiss = 1 if $swiss;
    $question = 1 if $question;
    #remove any blanks from renNum
    $renNum =~ s/\s+//gs;
    
    # Javascript code inserts the string 'searching...' into the review text box.
    # This in once case got submitted as the renDate in production
    $renDate = '' if $renDate eq 'searching...';

    $note = $self->get('dbh')->quote($note);
    
    my $priority = $self->GetItemPriority( $id );
    
    my @fieldList = ('id', 'user', 'attr', 'reason', 'renNum', 'renDate', 'category', 'priority');
    my @valueList = ($id,  $user,  $attr,  $reason,  $renNum,  $renDate, $category, $priority);
    
    if ($exp)
    {
      push(@fieldList, 'expert');
      push(@valueList, $exp);
      push(@fieldList, 'swiss');
      push(@valueList, $swiss);
    }
    if ($copyDate) { push(@fieldList, 'copyDate'); push(@valueList, $copyDate); }
    if ($note)     { push(@fieldList, 'note'); }
    
    my $sql = "REPLACE INTO $CRMSGlobals::reviewsTable (" . join(', ', @fieldList) .
              ") VALUES('" . join("', '", @valueList) . sprintf("'%s)", ($note)? ", $note":'');

    if ( $self->get('verbose') ) { $self->Logit( $sql ); }
    #print "$sql<br/>\n";
    $self->PrepareSubmitSql( $sql );

    if ( $exp )
    {
      my $sql = "UPDATE $CRMSGlobals::queueTable SET expcnt=1 WHERE id='$id'";
      $self->PrepareSubmitSql( $sql );
      my $qstatus = $self->SimpleSqlGet("SELECT status FROM queue WHERE id='$id'");
      my $status = ($attr == 5 && $reason == 8 && $qstatus == 3)? 6:5;
      #We have decided to register the expert decision right away.
      $self->RegisterStatus($id, $status);
    }
    
    $self->CheckPendingStatus($id);

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

sub CheckPendingStatus
{
  my $self = shift;
  my $id   = shift;
  
  my $sql = "SELECT id, user, attr, reason, renNum, renDate FROM reviews WHERE id='$id'";
  my $ref = $self->get( 'dbh' )->selectall_arrayref( $sql );
  if (scalar @{$ref} > 1)
  {
    my $row = @{$ref}[0];
    my $id      = $row->[0];
    my $user    = $row->[1];
    my $attr    = $row->[2];
    my $reason  = $row->[3];
    my $renNum  = $row->[4];
    my $renDate = $row->[5];
    
    my ( $other_user, $other_attr, $other_reason, $other_renNum, $other_renDate ) = $self->GetOtherReview( $id, $user );

    if ( ( $attr == $other_attr ) && ( $reason == $other_reason ) )
    {
      #If both und/nfi then status is 3
      if ( ( $attr == 5 ) && ( $reason == 8 ) )
      {
         $self->RegisterPendingStatus( $id, 3 );
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
            $self->RegisterPendingStatus( $id, 4 );
          }
          else
          {
            #Mark as 2
            $self->RegisterPendingStatus( $id, 2 );
          }
        }
        else #all other cases mark as 4
        {
          $self->RegisterPendingStatus( $id, 4 );
        }
      }
    }
    else #Mark as 2 - two that disagree
    {
      $self->RegisterPendingStatus( $id, 2 );
    }
  }
  elsif (scalar @{$ref} == 1) #Mark as 1: just single review unless it's a status 5 already.
  {
    $sql = "SELECT status FROM queue WHERE id='$id'";
    my $status = $self->SimpleSqlGet($sql);
    $status = 1 unless $status;
    $self->RegisterPendingStatus( $id, $status );
  }
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
    if ( ! $self->CheckReviewer( $user, $expert ) )           { $self->SetError("reviewer ($user) check failed"); return 0; }
    if ( ! $self->ValidateAttrReasonCombo( $attr, $reason ) ) { $self->SetError('attr/reason check failed');      return 0; }
    # FIXME: using annekz is a hack, but is needed since 'esaran' is not in the users table.
    my $err = $self->ValidateSubmissionHistorical($attr, $reason, $note, $category, $renNum, $renDate);
    if ($err) { $self->SetError($err); return 0; }
    ## do some sort of check for expert submissions

    if (!$noop)
    {
      $note = $self->get('dbh')->quote($note);
      
      ## all good, INSERT
      my $sql = 'REPLACE INTO historicalreviews (id, user, time, attr, reason, copyDate, renNum, renDate, note, legacy, category, status, expert, source) ' .
                qq{VALUES('$id', '$user', '$date', '$attr', '$reason', '$cDate', '$renNum', '$renDate', $note, 1, '$category', $status, $expert, 'legacy') };

      $self->PrepareSubmitSql( $sql );

      #Now load this info into the bibdata table.
      $self->UpdateTitle( $id );
      $self->UpdatePubDate( $id );
      $self->UpdateAuthor( $id );
      
      # Update status on status 1 item
      if ($status == 5)
      {
        $sql = qq{UPDATE $CRMSGlobals::historicalreviewsTable SET status=$status WHERE id='$id' AND gid IS NULL};
        $self->PrepareSubmitSql( $sql );
      }
      # Update validation on all items with this id
      $sql = "SELECT user,time,validated FROM historicalreviews WHERE id='$id'";
      my $ref = $self->get('dbh')->selectall_arrayref($sql);
      foreach my $row (@{$ref})
      {
        $user = $row->[0];
        $date = $row->[1];
        my $val  = $row->[2];
        my $val2 = $self->IsReviewCorrect($id, $user, $date);
        if ($val != $val2)
        {
          $sql = "UPDATE historicalreviews SET validated=$val2 WHERE id='$id' AND user='$user' AND time='$date'";
          $self->PrepareSubmitSql( $sql );
        }
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
    if ( ! $self->ValidateAttrReasonCombo( $attr, $reason ) ) { $self->Logit("bad attr/reason $attr/$reason");    return 0; }
    if ( ! $self->CheckReviewer( $user, 0 ) )                 { $self->SetError("reviewer ($user) check failed"); return 0; }
    ## do some sort of check for expert submissions

    if (!$noop)
    {
      ## all good, INSERT
      my $sql = qq{REPLACE INTO $CRMSGlobals::reviewsTable (id, user, time, attr, reason, legacy, priority) } .
                qq{VALUES('$id', '$user', '$date', '$attr', '$reason', 1, 1) };

      $self->PrepareSubmitSql( $sql );
      
      $sql = "UPDATE queue SET pending_status=1 WHERE id='$id'";
      $self->PrepareSubmitSql( $sql );
      
      #Now load this info into the bibdata table.
      $self->UpdateTitle( $id );
      $self->UpdatePubDate( $id );
      $self->UpdateAuthor( $id );
    }
    return 1;
}


sub MoveFromReviewsToHistoricalReviews
{
    my $self = shift;
    my $id   = shift;
    my $gid  = shift;
    
    $self->Logit( "store $id in historicalreviews" );
    
    my $sql = "SELECT source FROM queue WHERE id='$id'";
    my $source = $self->SimpleSqlGet($sql);
    my $status = $self->GetStatus( $id );
    
    $sql = 'INSERT into historicalreviews (id, time, user, attr, reason, note, renNum, expert, duration, legacy, expertNote, renDate, copyDate, category, priority, source, status, gid, swiss) ' .
           "select id, time, user, attr, reason, note, renNum, expert, duration, legacy, expertNote, renDate, copyDate, category, priority, '$source', $status, $gid, swiss from reviews where id='$id'";
    $self->PrepareSubmitSql( $sql );

    $self->Logit( "remove $id from reviews" );

    $sql = "DELETE FROM $CRMSGlobals::reviewsTable WHERE id='$id'";
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

    my $sql = qq{UPDATE $CRMSGlobals::queueTable SET status=$status WHERE id="$id"};

    $self->PrepareSubmitSql( $sql );
}

sub RegisterPendingStatus
{
    my $self   = shift;
    my $id     = shift;
    my $status = shift;

    my $sql = "UPDATE $CRMSGlobals::queueTable SET pending_status=$status WHERE id='$id'";

    $self->PrepareSubmitSql( $sql );
}

sub GetYesterday
{
  my $self = shift;
  
  my $yd = $self->SimpleSqlGet('SELECT DATE_SUB(NOW(), INTERVAL 1 DAY)');
  return substr($yd, 0, 10);
}

sub TwoWorkingDays
{
  my $self     = shift;
  my $readable = shift;
  
  my $time = $self->GetTodaysDate();
  my $cal = Date::Calendar->new( $Profiles->{'US'} );
  my @parts = split '-', $time;
  my $date = $cal->add_delta_workdays($parts[0],$parts[1],$parts[2],2);
  # Returned format is YYYYMMDD
  $date = sprintf '%s-%s-%s 23:59:59', substr($date,0,4), substr($date,4,2), substr($date,6,2);
  return ($readable)? $self->FormatDate($date):$date;
}

sub FormatDate
{
  my $self = shift;
  my $date = shift;
  
  my $sql = "SELECT DATE_FORMAT('$date', '%a, %M %e, %Y')";
  return $self->SimpleSqlGet( $sql );
}

sub FormatTime
{
  my $self = shift;
  my $time = shift;
  
  my $sql = "SELECT DATE_FORMAT('$time', '%a, %M %e, %Y at %l:%i %p')";
  return $self->SimpleSqlGet( $sql );
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
    elsif ( $search eq 'PubDate' ) { $new_search = 'b.pub_date'; }
    elsif ( $search eq 'Locked' ) { $new_search = 'q.locked'; }
    elsif ( $search eq 'ExpertCount' ) { $new_search = 'q.expcnt'; }
    elsif ( $search eq 'Reviews' )
    {
      $new_search = '(SELECT COUNT(*) FROM reviews r WHERE r.id=q.id)';
    }
    elsif ( $search eq 'Swiss' ) { $new_search = 'r.swiss'; }
    return $new_search;
}

sub CreateSQL
{
  my $self  = shift;
  my $stype = shift;
  
  return $self->CreateSQLForVolumesWide(@_) if $stype eq 'volumes';
  return $self->CreateSQLForVolumes(@_) if $stype eq 'groups';
  return $self->CreateSQLForReviews(@_);
}

sub CreateSQLForReviews
{
    my $self               = shift;
    my $page               = shift;
    my $order              = shift;
    my $dir                = shift;

    my $search1            = shift;
    my $search1value       = shift;
    my $op1                = shift;

    my $search2            = shift;
    my $search2value       = shift;
    my $op2                = shift;
    
    my $search3            = shift;
    my $search3value       = shift;
    
    my $startDate          = shift;
    my $endDate            = shift;
    my $offset             = shift;
    my $pagesize           = shift;
    my $limit              = shift;

    $search1 = $self->ConvertToSearchTerm( $search1, $page );
    $search2 = $self->ConvertToSearchTerm( $search2, $page );
    $search3 = $self->ConvertToSearchTerm( $search3, $page );
    $dir = 'DESC' unless $dir;
    if ( ! $offset ) { $offset = 0; }
    $pagesize = 20 unless $pagesize > 0;
    
    if ( ( $page eq 'userReviews' ) || ( $page eq 'editReviews' ) )
    {
      if ( ! $order || $order eq "time" ) { $order = "time"; }
    }
    else
    {
      if ( ! $order || $order eq "id" ) { $order = "id"; }
    }

    my $sql;
    if ( $page eq 'adminReviews' )
    {
      $sql = qq{SELECT r.id, r.time, r.duration, r.user, r.attr, r.reason, r.note, r.renNum, r.expert, r.copyDate, r.expertNote, r.category, r.legacy, r.renDate, r.priority, r.swiss, q.status, b.title, b.author FROM $CRMSGlobals::reviewsTable r, $CRMSGlobals::queueTable q, bibdata b WHERE q.id = r.id AND q.id = b.id };
    }
    elsif ( $page eq 'expert' )
    {
      $sql = qq{SELECT r.id, r.time, r.duration, r.user, r.attr, r.reason, r.note, r.renNum, r.expert, r.copyDate, r.expertNote, r.category, r.legacy, r.renDate, r.priority, r.swiss, q.status, b.title, b.author FROM $CRMSGlobals::reviewsTable r, $CRMSGlobals::queueTable q, bibdata b WHERE q.id = r.id AND q.id = b.id  AND ( q.status = 2 ) };
    }
    elsif ( $page eq 'adminHistoricalReviews' )
    {
      $sql = qq{SELECT r.id, r.time, r.duration, r.user, r.attr, r.reason, r.note, r.renNum, r.expert, r.copyDate, r.expertNote, r.category, r.legacy, r.renDate, r.priority, r.swiss, r.status, b.title, b.author, YEAR(b.pub_date), r.validated FROM bibdata b, $CRMSGlobals::historicalreviewsTable r WHERE r.id=b.id };
    }
    elsif ( $page eq 'undReviews' )
    {
      $sql = qq{SELECT r.id, r.time, r.duration, r.user, r.attr, r.reason, r.note, r.renNum, r.expert, r.copyDate, r.expertNote, r.category, r.legacy, r.renDate, r.priority, r.swiss, q.status, b.title, b.author FROM $CRMSGlobals::reviewsTable r, $CRMSGlobals::queueTable q, bibdata b WHERE q.id = b.id  AND q.id = r.id AND q.status = 3 };
    }
    elsif ( $page eq 'userReviews' )
    {
      my $user = $self->get( "user" );
      $sql = qq{SELECT r.id, r.time, r.duration, r.user, r.attr, r.reason, r.note, r.renNum, r.expert, r.copyDate, r.expertNote, r.category, r.legacy, r.renDate, r.priority, r.swiss, q.status, b.title, b.author FROM $CRMSGlobals::reviewsTable r, $CRMSGlobals::queueTable q, bibdata b WHERE q.id = r.id AND q.id = b.id AND r.user = '$user' AND q.status > 0 };
    }
    elsif ( $page eq 'editReviews' )
    {
      my $user = $self->get( "user" );
      my $yesterday = $self->GetYesterday();
      # Experts need to see stuff with any status; non-expert should only see stuff that hasn't been processed yet.
      my $restrict = ($self->IsUserExpert($user))? '':'AND q.status=0';
      $sql = qq{SELECT r.id, r.time, r.duration, r.user, r.attr, r.reason, r.note, r.renNum, r.expert, r.copyDate, r.expertNote, r.category, r.legacy, r.renDate, r.priority, r.swiss, q.status, b.title, b.author FROM $CRMSGlobals::reviewsTable r, $CRMSGlobals::queueTable q, bibdata b WHERE q.id = r.id AND q.id = b.id AND r.user = '$user' AND r.time >= "$yesterday" $restrict };
    }
    my $terms = $self->SearchTermsToSQL($search1, $search1value, $op1, $search2, $search2value, $op2, $search3, $search3value);
    $sql .= " AND $terms" if $terms;
    if ( $startDate ) { $sql .= qq{ AND r.time >= "$startDate 00:00:00" }; }
    if ( $endDate ) { $sql .= qq{ AND r.time <= "$endDate 23:59:59" }; }

    my $limit_section = '';
    if ( $limit )
    {
      $limit_section = qq{LIMIT $offset, $pagesize};
    }
    if ( $order eq 'status' )
    {
      if ( $page eq 'adminHistoricalReviews' )
      {
        $sql .= qq{ ORDER BY r.$order $dir $limit_section };
      }
      else
      {
        $sql .= qq{ ORDER BY q.$order $dir $limit_section };
      }
    }
    elsif ($order eq 'title' || $order eq 'author' || $order eq 'pub_date')
    {
       $sql .= qq{ ORDER BY b.$order $dir $limit_section };
    }
    else
    {
       $sql .= qq{ ORDER BY r.$order $dir $limit_section };
    }
    #print "$sql<br/>\n";
    my $countSql = $sql;
    $countSql =~ s/(SELECT\s+).+?(FROM.+)/$1 COUNT(*) $2/i;
    $countSql =~ s/(LIMIT\s\d+(,\s*\d+)?)//;
    #print "$countSql<br/>\n";
    my $totalReviews = $self->SimpleSqlGet($countSql);
    $countSql = $sql;
    $countSql =~ s/(SELECT\s?).+?(FROM.+)/$1 COUNT(DISTINCT r.id) $2/i;
    $countSql =~ s/(LIMIT\s\d+(,\s*\d+)?)//;
    #print "$countSql<br/>\n";
    my $totalVolumes = $self->SimpleSqlGet($countSql);
    my $n = POSIX::ceil($offset/$pagesize+1);
    my $of = POSIX::ceil($totalVolumes/$pagesize);
    $n = 0 if $of == 0;
    return ($sql,$totalReviews,$totalVolumes,$n,$of);
}

sub CreateSQLForVolumes
{
  my $self         = shift;
  my $page         = shift;
  my $order        = shift;
  my $dir          = shift;
  my $search1      = shift;
  my $search1value = shift;
  my $op1          = shift;
  my $search2      = shift;
  my $search2value = shift;
  my $op2          = shift;
  my $search3      = shift;
  my $search3value = shift;
  my $startDate    = shift;
  my $endDate      = shift;
  my $offset       = shift;
  my $pagesize     = shift;

  #print("CreateSQLForVolumes('$order','$dir','$search1','$search1value','$op1','$search2','$search2value','$op2','$search3','$search3value','$startDate','$endDate','$offset','$pagesize','$page');<br/>\n");
  $dir = 'DESC' unless $dir;
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
  $search3 = $self->ConvertToSearchTerm( $search3, $page );
  if ($order eq 'author' || $order eq 'title' || $order eq 'pub_date') { $order = 'b.' . $order; }
  elsif ($order eq 'status' && $page ne 'adminHistoricalReviews') { $order = 'q.' . $order; }
  else { $order = 'r.' . $order; }
  $search1 = 'r.id' unless $search1;
  my $order2 = ($dir eq 'ASC')? 'min':'max';
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
  # This should not happen; active reviews page does not have a checkbox!
  elsif ( $page eq 'editReviews' )
  {
    my $user = $self->get( 'user' );
    my $yesterday = $self->GetYesterday();
    push @rest, "r.time >= '$yesterday'";
    push @rest, 'q.status=0' unless $self->IsUserExpert($user);
  }
  my $terms = $self->SearchTermsToSQL($search1, $search1value, $op1, $search2, $search2value, $op2, $search3, $search3value);
  push @rest, $terms if $terms;
  push @rest, "date(r.time) >= '$startDate'" if $startDate;
  push @rest, "date(r.time) <= '$endDate'" if $endDate;
  my $restrict = join(' AND ', @rest);
  my $sql = "SELECT COUNT(r2.id) FROM $table r2 WHERE r2.id IN (SELECT r.id FROM $table r, bibdata b$doQ WHERE $restrict)";
  #print "$sql<br/>\n";
  my $totalReviews = $self->SimpleSqlGet($sql);
  my $sql = "SELECT COUNT(DISTINCT r.id) FROM $table r, bibdata b$doQ WHERE $restrict";
  #print "$sql<br/>\n";
  my $totalVolumes = $self->SimpleSqlGet($sql);
  $offset = $totalVolumes-($totalVolumes % $pagesize) if $offset >= $totalVolumes;
  $sql = "SELECT r.id as id, $order2($order) AS ord FROM $table r, bibdata b$doQ WHERE $restrict GROUP BY r.id " .
         "ORDER BY ord $dir LIMIT $offset, $pagesize";
  #print "$sql<br/>\n";
  my $n = POSIX::ceil($offset/$pagesize+1);
  my $of = POSIX::ceil($totalVolumes/$pagesize);
  $n = 0 if $of == 0;
  return ($sql,$totalReviews,$totalVolumes,$n,$of);
}

sub CreateSQLForVolumesWide
{
  my $self         = shift;
  my $page         = shift;
  my $order        = shift;
  my $dir          = shift;
  my $search1      = shift;
  my $search1value = shift;
  my $op1          = shift;
  my $search2      = shift;
  my $search2value = shift;
  my $op2          = shift;
  my $search3      = shift;
  my $search3value = shift;
  my $startDate    = shift;
  my $endDate      = shift;
  my $offset       = shift;
  my $pagesize     = shift;
  
  #print("GetVolumesRefWide('$order','$dir','$search1','$search1value','$op1','$search2','$search2value','$op2','$search3','$search3value','$startDate','$endDate','$offset','$pagesize','$page');<br/>\n");
  $dir = 'DESC' unless $dir;
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
  $search3 = $self->ConvertToSearchTerm( $search3, $page );
  if ($order eq 'author' || $order eq 'title' || $order eq 'pub_date') { $order = 'b.' . $order; }
  elsif ($order eq 'status' && $page ne 'adminHistoricalReviews') { $order = 'q.' . $order; }
  else { $order = 'r.' . $order; }
  $search1 = 'r.id' unless $search1;
  my $order2 = ($dir eq 'ASC')? 'min':'max';
  my @rest = ();
  my $table = 'reviews';
  my $top = 'bibdata b';
  my $status = 'r.status';
  if ($page eq 'adminHistoricalReviews')
  {
    $table = 'historicalreviews';
  }
  else
  {
    push @rest, 'r.id=q.id';
    $top = 'queue q INNER JOIN bibdata b ON q.id=b.id';
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
  # This should not happen; active reviews page does not have a checkbox!
  elsif ( $page eq 'editReviews' )
  {
    my $user = $self->get( 'user' );
    my $yesterday = $self->GetYesterday();
    push @rest, "r.time >= '$yesterday'";
    push @rest, 'q.status=0' unless $self->IsUserAdmin($user);
  }
  my ($joins,@rest2) = $self->SearchTermsToSQLWide($search1, $search1value, $op1, $search2, $search2value, $op2, $search3, $search3value, $table);
  push @rest, @rest2;
  push @rest, "date(r.time) >= '$startDate'" if $startDate;
  push @rest, "date(r.time) <= '$endDate'" if $endDate;
  my $restrict = join(' AND ', @rest);
  $restrict = 'WHERE '.$restrict if $restrict;
  my $sql = "SELECT COUNT(DISTINCT r.id, r.user,r.time) FROM $top INNER JOIN $table r ON b.id=r.id $joins $restrict";
  #print "$sql<br/>\n";
  my $totalReviews = $self->SimpleSqlGet($sql);
  my $sql = "SELECT COUNT(DISTINCT r.id) FROM $top INNER JOIN $table r ON b.id=r.id $joins $restrict";
  #print "$sql<br/>\n";
  my $totalVolumes = $self->SimpleSqlGet($sql);
  $offset = $totalVolumes-($totalVolumes % $pagesize) if $offset >= $totalVolumes;
  $sql = "SELECT r.id as id, $order2($order) AS ord FROM $top INNER JOIN $table r ON b.id=r.id $joins $restrict GROUP BY r.id " .
         "ORDER BY ord $dir LIMIT $offset, $pagesize";
  #print "$sql<br/>\n";
  my $n = POSIX::ceil($offset/$pagesize+1);
  my $of = POSIX::ceil($totalVolumes/$pagesize);
  $n = 0 if $of == 0;
  return ($sql,$totalReviews,$totalVolumes,$n,$of);
}

sub SearchTermsToSQL
{
  my $self = shift;
  my ($search1, $search1value, $op1, $search2, $search2value, $op2, $search3, $search3value) = @_;
  my ($search1term, $search2term, $search3term);
  $op1 = 'AND' unless $op1;
  $op2 = 'AND' unless $op2;
  $search1 = "YEAR($search1)" if $search1 =~ /pub_date/;
  $search2 = "YEAR($search2)" if $search2 =~ /pub_date/;
  $search3 = "YEAR($search3)" if $search3 =~ /pub_date/;
  if ( $search1value =~ m/.*\*.*/ )
  {
    $search1value =~ s/\*/_____/gs;
    $search1term = qq{$search1 LIKE '$search1value'};
  }
  elsif ($search1value)
  {
    $search1term = qq{$search1 = '$search1value'};
  }
  if ( $search2value =~ m/.*\*.*/ )
  {
    $search2value =~ s/\*/_____/gs;
    $search2term = sprintf("$search2 %sLIKE '$search2value'", ($op1 eq 'NOT')? 'NOT ':'');
  }
  elsif ($search2value)
  {
    $search2term = sprintf("$search2 %s= '$search2value'", ($op1 eq 'NOT')? '!':'');
  }

  if ( $search3value =~ m/.*\*.*/ )
  {
    $search3value =~ s/\*/_____/gs;
    $search3term = sprintf("$search3 %sLIKE '$search3value'", ($op2 eq 'NOT')? 'NOT ':'');
  }
  elsif ($search3value)
  {
    $search3term = sprintf("$search3 %s= '$search3value'", ($op2 eq 'NOT')? '!':'');
  }

  if ( $search1value =~ m/([<>]=?)\s*(\d+)\s*/ )
  {
    $search1term = "$search1 $1 $2";
  }
  if ( $search2value =~ m/([<>]=?)\s*(\d+)\s*/ )
  {
    my $op = $1;
    $op =~ y/<>/></ if $op1 eq 'NOT';
    $search2term = "$search2 $op $2";
  }
  if ( $search3value =~ m/([<>]=?)\s*(\d+)\s*/ )
  {
    my $op = $1;
    $op =~ y/<>/></ if $op1 eq 'NOT';
    $search3term = "$search3 $op $2";
  }
  $op1 = 'AND' if $op1 eq 'NOT';
  $op2 = 'AND' if $op2 eq 'NOT';
  my $tmpl = '(__1__ __op1__ __2__ __op2__ __3__)';
  $tmpl = '((__1__ __op1__ __2__) __op2__ __3__)' if ($op1 eq 'OR' && $op2 ne 'OR');
  $tmpl = '(__1__ __op1__ (__2__ __op2__ __3__))' if ($op2 eq 'OR' && $op1 ne 'OR');
  $tmpl =~ s/__1__/$search1term/;
  $op1 = '' unless $search1term and $search2term;
  $tmpl =~ s/__op1__/$op1/;
  $tmpl =~ s/__2__/$search2term/;
  $op2 = '' unless $search2term and $search3term;
  $tmpl =~ s/__op2__/$op2/;
  $tmpl =~ s/__3__/$search3term/;
  $tmpl =~ s/\(\s*\)//g;
  $tmpl =~ s/\(\s*\)//g;
  $tmpl =~ s/_____/%/g;
  #print "$tmpl<br/>\n";
  return $tmpl;
}

sub SearchTermsToSQLWide
{
  my $self = shift;
  my ($search1, $search1value, $op1, $search2, $search2value, $op2, $search3, $search3value, $table) = @_;
  $op1 = 'AND' unless $op1;
  $op2 = 'AND' unless $op2;
  # Pull down search 2 if no search 1
  if (!$search1value)
  {
    $search1 = $search2;
    $op1 = $op2;
    $search2 = $search3;
    $search1value = $search2value;
    $search2value = $search3value;
    $search3value = undef;
  }
  # Pull down search 3 if no search 2
  if (!$search2value)
  {
    $search2 = $search3;
    $search2value = $search3value;
    $search3value = undef;
  }
  my %pref2table = ('b'=>'bibdata','r'=>$table,'q'=>'queue');
  my $table1 = $pref2table{substr $search1,0,1};
  my $table2 = $pref2table{substr $search2,0,1};
  my $table3 = $pref2table{substr $search3,0,1};
  my ($search1term,$search2term,$search3term);
  my $search1_ = ($search1 =~ m/pub_date/)? "YEAR($search1)":$search1;
  my $search2_ = ($search2 =~ m/pub_date/)? "YEAR($search2)":$search2;
  my $search3_ = ($search3 =~ m/pub_date/)? "YEAR($search3)":$search3;
  if ( $search1value =~ m/.*\*.*/ )
  {
    $search1value =~ s/\*/_____/gs;
    $search1term = qq{$search1_ LIKE '$search1value'};
    $search1term =~ s/_____/%/g;
  }
  elsif ($search1value)
  {
    $search1term = qq{$search1_ = '$search1value'};
  }
  if ( $search2value =~ m/.*\*.*/ )
  {
    $search2value =~ s/\*/_____/gs;
    $search2term = sprintf("$search2_ %sLIKE '$search2value'", ($op1 eq 'NOT')? 'NOT ':'');
    $search2term =~ s/_____/%/g;
  }
  elsif ($search2value)
  {
    $search2term = sprintf("$search2_ %s= '$search2value'", ($op1 eq 'NOT')? '!':'');
  }
  if ( $search3value =~ m/.*\*.*/ )
  {
    $search3value =~ s/\*/_____/gs;
    $search3term = sprintf("$search3_ %sLIKE '$search3value'", ($op2 eq 'NOT')? 'NOT ':'');
    $search3term =~ s/_____/%/g;
  }
  elsif ($search3value)
  {
    $search3term = sprintf("$search3_ %s= '$search3value'", ($op2 eq 'NOT')? '!':'');
  }
  if ( $search1value =~ m/([<>]=?)\s*(\d+)\s*/ )
  {
    $search1term = "$search1_ $1 $2";
  }
  if ( $search2value =~ m/([<>]=?)\s*(\d+)\s*/ )
  {
    my $op = $1;
    $op =~ y/<>/></ if $op1 eq 'NOT';
    $search2term = "$search2_ $op $2";
  }
  if ( $search3value =~ m/([<>]=?)\s*(\d+)\s*/ )
  {
    my $op = $1;
    $op =~ y/<>/></ if $op2 eq 'NOT';
    $search3term = "$search3_ $op $2";
  }
  $op1 = 'AND' if $op1 eq 'NOT';
  $op2 = 'AND' if $op2 eq 'NOT';
  my $joins = '';
  my @rest = ();
  my $did2 = 0;
  my $did3 = 0;
  if ($search1term)
  {
    $search1term =~ s/[a-z]\./t1./;
    
    if ($op1 eq 'AND' || !$search2term)
    {
      $joins = "INNER JOIN $table1 t1 ON t1.id=r.id";
      push @rest, $search1term;
    }
    elsif ($op2 ne 'OR' || !$search3term)
    {
      $search2term =~ s/[a-z]\./t2./;
      $joins = "INNER JOIN (SELECT t1.id FROM $table1 t1 WHERE $search1term UNION SELECT t2.id FROM $table2 t2 WHERE $search2term) AS or1 ON or1.id=r.id";
      $did2 = 1;
    }
    else
    {
      $search2term =~ s/[a-z]\./t2./;
      $search3term =~ s/[a-z]\./t3./;
      $joins = "INNER JOIN (SELECT t1.id FROM $table1 t1 WHERE $search1term UNION SELECT t2.id FROM $table2 t2 WHERE $search2term UNION SELECT t3.id FROM $table3 t3 WHERE $search3term) AS or1 ON or1.id=r.id";
      $did2 = 1;
      $did3 = 1;
    }
  }
  if ($search2term && !$did2)
  {
    $search2term =~ s/[a-z]\./t2./;
    if ($op2 eq 'AND' || !$search3term)
    {
      $joins .= " INNER JOIN $table2 t2 ON t2.id=r.id";
      push @rest, $search2term;
    }
    else
    {
      $search3term =~ s/[a-z]\./t3./;
      $joins .= " INNER JOIN (SELECT t2.id FROM $table2 t2 WHERE $search2term UNION SELECT t3.id FROM $table3 t3 WHERE $search3term) AS or2 ON or2.id=r.id";
      $did3 = 1;
    }
  }
  if ($search3term && !$did3)
  {
    $search3term =~ s/[a-z]\./t3./;
    $joins .= " INNER JOIN $table3 t3 ON t3.id=r.id";
    push @rest, $search3term;
  }
  #foreach $_ (@rest) { print "R: $_<br/>\n"; }
  return ($joins,@rest);
}

sub SearchAndDownload
{
    my $self           = shift;
    my $page           = shift;
    my $order          = shift ;
    my $dir            = shift;

    my $search1        = shift;
    my $search1value   = shift;
    my $op1            = shift;

    my $search2        = shift;
    my $search2value   = shift;
    my $op2            = shift;
    
    my $search3        = shift;
    my $search3value   = shift;
    my $startDate      = shift;
    my $endDate        = shift;
    my $offset         = shift;

    my $stype          = shift;
    
    $stype = 'reviews' unless $stype;
    my $table ='reviews';
    my $top = 'bibdata b';
    my $status = 'r.status';
    if ($page eq 'adminHistoricalReviews')
    {
      $table = 'historicalreviews';
    }
    else
    {
      $top = 'queue q INNER JOIN bibdata b ON q.id=b.id';
      $status = 'q.status';
    }
    
    my ($sql,$totalReviews,$totalVolumes,$n,$of) =  $self->CreateSQL( $stype, $page, $order, $dir, $search1, $search1value, $op1, $search2, $search2value, $op2, $search3, $search3value, $startDate, $endDate, $offset, undef, 0 );
    
    my $ref = $self->get( 'dbh' )->selectall_arrayref( $sql );

    my $buffer = '';
    if ( scalar @{$ref} == 0 )
    {
      $buffer = 'No Results Found.';
    }
    else
    {
      if ( $page eq 'userReviews')
      {
        $buffer .= qq{id\ttitle\tauthor\ttime\tattr\treason\tcategory\tnote};
      }
      elsif ( $page eq 'editReviews' )
      {
        $buffer .= qq{id\ttitle\tauthor\ttime\tattr\treason\tcategory\tnote};
      }
      elsif ( $page eq 'undReviews' )
      {
        $buffer .= qq{id\ttitle\tauthor\ttime\tstatus\tuser\tattr\treason\tcategory\tnote}
      }
      elsif ( $page eq 'expert' )
      {
        $buffer .= qq{id\ttitle\tauthor\ttime\tstatus\tuser\tattr\treason\tcategory\tnote};
      }
      elsif ( $page eq 'adminReviews' )
      {
        $buffer .= qq{id\ttitle\tauthor\ttime\tstatus\tuser\tattr\treason\tcategory\tnote};
      }
      elsif ( $page eq 'adminHistoricalReviews' )
      {
        $buffer .= qq{id\ttitle\tauthor\tpub date\ttime\tstatus\tlegacy\tuser\tattr\treason\tcategory\tnote\tvalidated};
      }
      $buffer .= sprintf("%s\n", ($self->IsUserAdmin())? "\tpriority":'');
      if ($stype eq 'reviews')
      {
        $buffer .= $self->UnpackResults($page, $ref);
      }
      else
      {
        foreach my $row ( @{$ref} )
        {
          my $id = $row->[0];
          my $qrest = ($page ne 'adminHistoricalReviews')? ' AND r.id=q.id':'';
          $sql = "SELECT r.id, r.time, r.duration, r.user, r.attr, r.reason, r.note, r.renNum, r.expert, r.copyDate, r.expertNote, " .
                 "r.category, r.legacy, r.renDate, r.priority, r.swiss, $status, b.title, b.author" .
                 (($page eq 'adminHistoricalReviews')? ', YEAR(b.pub_date), r.validated ':' ') .
                 "FROM $top INNER JOIN $table r ON b.id=r.id " .
                 "WHERE r.id='$id' AND r.id=b.id $qrest ORDER BY $order $dir";
          #print "$sql<br/>\n";
          my $ref2;
          eval{$ref2 = $self->get( 'dbh' )->selectall_arrayref( $sql );};
          if ($@)
          {
            $self->SetError("SQL failed: '$sql' ($@)");
            $self->DownloadSpreadSheet( "order <<$order>>\nSQL failed: '$sql' ($@)" );
            return 0;
          }
          $buffer .= $self->UnpackResults($page, $ref2);
        }
      }
    }
    $self->DownloadSpreadSheet( $buffer );
    if ( $buffer ) { return 1; }
    else { return 0; }
}

sub UnpackResults
{
  my $self = shift;
  my $page = shift;
  my $ref  = shift;
  
  my $buffer = '';
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
    my $swiss      = $row->[15];
    my $status     = $row->[16];
    my $title      = $row->[17];
    my $author     = $row->[18];

    if ( $page eq 'userReviews')
    {
      #for reviews
      #id, title, author, review date, attr, reason, category, note.
      $buffer .= qq{$id\t$title\t$author\t$time\t$attr\t$reason\t$category\t$note};
    }
    elsif ( $page eq 'editReviews' )
    {
      #for editRevies
      #id, title, author, review date, attr, reason, category, note.
      $buffer .= qq{$id\t$title\t$author\t$time\t$attr\t$reason\t$category\t$note};
    }
    elsif ( $page eq 'undReviews' )
    {
      #for und/nif
      #id, title, author, review date, status, user, attr, reason, category, note.
      $buffer .= qq{$id\t$title\t$author\t$time\t$status\t$user\t$attr\t$reason\t$category\t$note}
    }
    elsif ( $page eq 'expert' )
    {
      #for expert
      #id, title, author, review date, status, user, attr, reason, category, note.
      $buffer .= qq{$id\t$title\t$author\t$time\t$status\t$user\t$attr\t$reason\t$category\t$note};
    }
    elsif ( $page eq 'adminReviews' )
    {
      #for adminReviews
      #id, title, author, review date, status, user, attr, reason, category, note.
      $buffer .= qq{$id\t$title\t$author\t$time\t$status\t$user\t$attr\t$reason\t$category\t$note};
    }
    elsif ( $page eq 'adminHistoricalReviews' )
    {
      my $pubdate = $row->[18];
      $pubdate = '?' unless $pubdate;
      my $validated = $row->[19];
      #id, title, author, review date, status, user, attr, reason, category, note, validated
      $buffer .= qq{$id\t$title\t$author\t$pubdate\t$time\t$status\t$legacy\t$user\t$attr\t$reason\t$category\t$note\t$validated};
    }
    $buffer .= sprintf("%s\n", ($self->IsUserAdmin())? "\t$priority":'');
  }
  return $buffer;
}

sub SearchAndDownloadDeterminationStats
{
  my $self      = shift;
  my $startDate = shift;
  my $endDate   = shift;
  my $monthly   = shift;
  
  my $buffer = $self->CreateExportStatusData("\t", $startDate, $endDate, $monthly);
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
    my $page               = shift;
    my $order              = shift;
    my $dir                = shift;

    my $search1            = shift;
    my $search1Value       = shift;
    my $op1                = shift;

    my $search2            = shift;
    my $search2Value       = shift;
    my $op2                = shift;
    
    my $search3            = shift;
    my $search3Value       = shift;

    my $startDate          = shift;
    my $endDate            = shift;
    my $offset             = shift;
    my $pagesize           = shift;

    my $limit              = 1;
    $pagesize = 20 unless $pagesize > 0;
    $offset = 0 unless $offset > 0;
    #print("GetReviewsRef('$page','$order','$dir','$search1','$search1Value','$op1','$search2','$search2Value','$op2','$search3','$search3Value','$startDate','$endDate','$offset','$pagesize');<br/>\n");
    my ($sql,$totalReviews,$totalVolumes) = $self->CreateSQLForReviews($page, $order, $dir, $search1, $search1Value, $op1, $search2, $search2Value, $op2, $search3, $search3Value, $startDate, $endDate, $offset, $pagesize, $limit);
    #print "$sql<br/>\n";
    my $ref = undef;
    eval { $ref = $self->get( 'dbh' )->selectall_arrayref( $sql ); };
    if ($@)
    {
      $self->SetError("SQL failed: '$sql' ($@)");
      return;
    }
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
                    swiss      => $row->[15],
                    status     => $row->[16],
                    title      => $row->[17],
                    author     => $row->[18]
                   };
        my $pubdate = $row->[19];
        $pubdate = '?' unless $pubdate;
        ${$item}{'pubdate'} = $pubdate if $page eq 'adminHistoricalReviews';
        ${$item}{'validated'} = $row->[20] if $page eq 'adminHistoricalReviews';
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
  my $page = $_[0];
  my $order = $_[1];
  my $dir = $_[2];
  my ($sql,$totalReviews,$totalVolumes,$n,$of) = $self->CreateSQLForVolumes(@_);
  my $ref = undef;
  eval { $ref = $self->get( 'dbh' )->selectall_arrayref( $sql ); };
  if ($@)
  {
    $self->SetError("SQL failed: '$sql' ($@)");
    return;
  }
  my $table = 'reviews';
  my $doQ = '';
  my $status = 'r.status';
  if ($page eq 'adminHistoricalReviews')
  {
    $table = 'historicalreviews';
  }
  else
  {
    $doQ = ', queue q';
    $status = 'q.status';
  }
  my $return = ();
  foreach my $row ( @{$ref} )
  {
    my $id = $row->[0];
    my $qrest = ($doQ)? ' AND r.id=q.id':'';
    $sql = "SELECT r.id, r.time, r.duration, r.user, r.attr, r.reason, r.note, r.renNum, r.expert, r.copyDate, r.expertNote, " .
           "r.category, r.legacy, r.renDate, r.priority, r.swiss, $status, b.title, b.author" .
           (($page eq 'adminHistoricalReviews')? ', YEAR(b.pub_date), r.validated ':' ') .
           "FROM $table r, bibdata b$doQ " .
           "WHERE r.id='$id' AND r.id=b.id $qrest ORDER BY $order $dir";
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
                  swiss      => $row->[15],
                  status     => $row->[16],
                  title      => $row->[17],
                  author     => $row->[18]
                 };
      my $pubdate = $row->[19];
      $pubdate = '?' unless $pubdate;
      ${$item}{'pubdate'} = $pubdate if $page eq 'adminHistoricalReviews';
      ${$item}{'validated'} = $row->[20] if $page eq 'adminHistoricalReviews';
      push( @{$return}, $item );
    }
  }
  my $data = {'rows' => $return,
              'reviews' => $totalReviews,
              'volumes' => $totalVolumes,
              'page' => $n,
              'of' => $of
             };
  return $data;
}

sub GetVolumesRefWide
{
  my $self = shift;
  my $page = $_[0];
  my $order = $_[1];
  my $dir = $_[2];
  
  my $table ='reviews';
  my $top = 'bibdata b';
  my $status = 'r.status';
  if ($page eq 'adminHistoricalReviews')
  {
    $table = 'historicalreviews';
  }
  else
  {
    $top = 'queue q INNER JOIN bibdata b ON q.id=b.id';
    $status = 'q.status';
  }
  my ($sql,$totalReviews,$totalVolumes,$n,$of) = $self->CreateSQLForVolumesWide(@_);
  my $ref = undef;
  eval { $ref = $self->get( 'dbh' )->selectall_arrayref( $sql ); };
  if ($@)
  {
    $self->SetError("SQL failed: '$sql' ($@)");
    return;
  }
  my $return = ();
  foreach my $row ( @{$ref} )
  {
    my $id = $row->[0];
    my $qrest = ($page ne 'adminHistoricalReviews')? ' AND r.id=q.id':'';
    $sql = "SELECT r.id, r.time, r.duration, r.user, r.attr, r.reason, r.note, r.renNum, r.expert, r.copyDate, r.expertNote, " .
           "r.category, r.legacy, r.renDate, r.priority, r.swiss, $status, b.title, b.author" .
           (($page eq 'adminHistoricalReviews')? ', YEAR(b.pub_date), r.validated ':' ') .
           "FROM $top INNER JOIN $table r ON b.id=r.id " .
           "WHERE r.id='$id' AND r.id=b.id $qrest ORDER BY $order $dir";
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
                  swiss      => $row->[15],
                  status     => $row->[16],
                  title      => $row->[17],
                  author     => $row->[18]
                 };
      my $pubdate = $row->[19];
      $pubdate = '?' unless $pubdate;
      ${$item}{'pubdate'} = $pubdate if $page eq 'adminHistoricalReviews';
      ${$item}{'validated'} = $row->[20] if $page eq 'adminHistoricalReviews';
      push( @{$return}, $item );
    }
  }
  my $data = {'rows' => $return,
              'reviews' => $totalReviews,
              'volumes' => $totalVolumes,
              'page' => $n,
              'of' => $of
             };
  return $data;
}

sub GetReviewsCount
{
  my $self           = shift;
  my $page           = shift;
  my $search1        = shift;
  my $search1value   = shift;
  my $op1            = shift;
  my $search2        = shift;
  my $search2value   = shift;
  my $op2            = shift;
  my $search3        = shift;
  my $search3value   = shift;
  my $startDate      = shift;
  my $endDate        = shift;
  my $stype          = shift;

  my ($sql,$totalReviews,$totalVolumes,$n,$of) = $self->CreateSQL($stype, $page, undef, 'ASC', $search1, $search1value, $op1, $search2, $search2value, $op2, $search3, $search3value, $startDate, $endDate, 0, undef, undef );
  return $totalReviews;
}

sub GetQueueRef
{
  my $self         = shift;
  my $order        = shift;
  my $dir          = shift;
  my $search1      = shift;
  my $search1Value = shift;
  my $op1          = shift;
  my $search2      = shift;
  my $search2Value = shift;
  my $startDate    = shift;
  my $endDate      = shift;
  my $offset       = shift;
  my $pagesize     = shift;
  my $download     = shift;
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

sub GetTheYear
{
  my $self = shift;
  
  return ($self->GetTheYearMonth())[0];
}

sub GetTheMonth
{
  my $self = shift;
  
  return ($self->GetTheYearMonth())[1];
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


# Returns an array of date strings e.g. ('2009-01'...'2009-12') for the (current if no param) year.
sub GetAllMonthsInYear
{
  my $self = shift;
  my $year = shift;
  
  my ($currYear, $currMonth) = $self->GetTheYearMonth();
  $year = $currYear unless $year;
  my $start = ($year eq '2009')? 7:1;
  my @months = ();
  foreach my $m ($start..12)
  {
    my $ym = sprintf("$year-%.2d", $m);
    last if $ym gt "$currYear-$currMonth";
    push @months, $ym;
  }
  return @months;
}

# Returns an array of date strings e.g. ('2009-01','2010-01') with start month of all years for which we have data.
sub GetAllYears
{
  my $self = shift;
  
  # FIXME: use the GetRange function
  my $min = $self->SimpleSqlGet('SELECT MIN(time) FROM exportdata');
  my $max = $self->SimpleSqlGet('SELECT MAX(time) FROM exportdata');
  $min = substr($min,0,4);
  $max = substr($max,0,4);
  return ($min..$max);
}


sub CreateExportData
{
  my $self           = shift;
  my $delimiter      = shift;
  my $cumulative     = shift;
  my $doCurrentMonth = shift;
  my $start          = shift;
  my $end            = shift;
  my $doPercent      = shift;
  
  #print "CreateExportData('$delimiter', $cumulative, $doCurrentMonth, '$start', '$end')<br/>\n";
  my $dbh = $self->get( 'dbh' );
  my ($year,$month) = $self->GetTheYearMonth();
  my $now = "$year-$month";
  $start = "$year-01" unless $start;
  $end = "$year-12" unless $end;
  ($start,$end) = ($end,$start) if $end lt $start;
  $start = '2009-07' if $start lt '2009-07';
  my @dates;
  if ($cumulative)
  {
    @dates = $self->GetAllYears();
  }
  else
  {
    my $sql = "SELECT DISTINCT(DATE_FORMAT(time,'%Y-%m')) FROM exportdata WHERE DATE_FORMAT(time,'%Y-%m')>='$start' AND DATE_FORMAT(time,'%Y-%m')<='$end' ORDER BY time ASC";
    #print "$sql<br/>\n";
    @dates = map {$_->[0];} @{$self->get('dbh')->selectall_arrayref( $sql )};
  }
  my $titleDate = '';
  if (!$cumulative)
  {
    my $startEng = substr($dates[0],0,4);
    my $endEng = substr($dates[-1],0,4);
    $titleDate = ($startEng eq $endEng)? $startEng:"$startEng-$endEng";
  }
  my $label = ($cumulative)? 'CRMS Project Cumulative' : "Cumulative $titleDate";
  my $report = sprintf("$label\nCategories%s%s", $delimiter, ($cumulative)? 'Grand Total':'Total');
  my %stats = ();
  my @usedates = ();
  foreach my $date (@dates)
  {
    #print "$date\n";
    last if $date eq $now and !$doCurrentMonth;
    push @usedates, $date;
    $report .= "$delimiter$date";
    my %cats = ('pd/ren' => 0, 'pd/ncn' => 0, 'pd/cdpp' => 0, 'pdus/cdpp' => 0, 'ic/ren' => 0, 'ic/cdpp' => 0,
                'All PD' => 0, 'All IC' => 0, 'All UND/NFI' => 0,
                'Status 4' => 0, 'Status 6' => 0, 'Status 6' => 0);
    my $lastDay;
    if (!$cumulative)
    {
      my ($year,$month) = split '-', $date;
      $lastDay = Days_in_Month($year,$month);
    }
    my $mintime = $date . (($cumulative)? '-01-01 00:00:00':'-01 00:00:00');
    my $maxtime = $date . (($cumulative)? '-12-31 23:59:59':"-$lastDay 23:59:59");
    my $sql = 'SELECT e.gid,e.time,e.attr,e.reason,h.status,e.id FROM exportdata e INNER JOIN historicalreviews h ON e.gid=h.gid WHERE ' .
              "e.time>='$mintime' AND e.time<='$maxtime' ORDER BY e.gid ASC, h.time DESC";
    my $rows = $dbh->selectall_arrayref( $sql );
    #printf "$sql : %d items<br/>\n", scalar @{$rows};
    my $lastid = undef;
    foreach my $row ( @{$rows} )
    {
      my $id = $row->[0];
      next if $id eq $lastid;
      $lastid = $id;
      my $time = $row->[1];
      my $attr = $row->[2];
      my $reason = $row->[3];
      my $status = $row->[4];
      my $bar = $row->[5];
      my $cat = "$attr/$reason";
      $cat = 'All UND/NFI' if $cat eq 'und/nfi';
      if (exists $cats{$cat} or $cat eq 'All UND/NFI')
      {
        $cats{$cat}++;
        my $allkey = 'All ' . uc substr($cat,0,2);
        $cats{$allkey}++ if exists $cats{$allkey};
      }
      $cats{'Status '.$status}++;
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

# Create an HTML table for the whole year's exports, month by month.
# If cumulative, columns are years, not months.
sub CreateExportReport
{
  my $self       = shift;
  my $cumulative = shift;
  my $start      = shift;
  my $end        = shift;
  
  my $data = $self->CreateExportData(',', $cumulative, 1, $start, $end, 1);
  my @lines = split m/\n/, $data;
  my $nbsps = '&nbsp;&nbsp;&nbsp;&nbsp;';
  my $title = shift @lines;
  $title .= '*' if $cumulative;
  my $report = sprintf("<table class='exportStats'>\n<tr>\n", $title);
  foreach my $th (split ',', shift @lines)
  {
    $th = $self->YearMonthToEnglish($th) if $th =~ m/^\d.*/;
    $th =~ s/\s/&nbsp;/g;
    $report .= sprintf("<th%s>$th</th>\n", ($th ne 'Categories')? ' style="text-align:center;"':'');
  }
  $report .= "</tr>\n";
  my %majors = ('All PD' => 1, 'All IC' => 1, 'All UND/NFI' => 1);
  my $titleline = '';
  foreach my $line (@lines)
  {
    my @items = split(',', $line);
    my $i = 0;
    $title = shift @items;
    #next if $just456 and ($title !~ m/Status.+/ and $title !~ /Total/);
    my $major = exists $majors{$title};
    $title =~ s/\s/&nbsp;/g;
    my $padding = ($major)? '':$nbsps;
    my $newline = sprintf("<tr><th%s><span%s>%s$title</span></th>",
      ($title eq 'Total')? ' style="text-align:right;"':'',
      ($major)? ' class="major"':(($title =~ m/Status.+/)? ' class="minor"':''),
      ($major)? '':$nbsps);
    foreach my $item (@items)
    {
      my ($n,$pct) = split ':', $item;
      $n =~ s/\s/&nbsp;/g;
      $newline .= sprintf("<td%s>%s%s$n%s%s</td>",
                         ($major)? ' class="major"':($title eq 'Total')? ' style="text-align:center;"':(($title =~ m/Status.+/)? ' class="minor"':''),
                         ($major)? '':$nbsps,
                         ($title eq 'Total')? '<b>':'',
                         ($title eq 'Total')? '</b>':'',
                         ($pct)? "&nbsp;($pct%)":'');
      $i++;
    }
    $newline .= "</tr>\n";
    #if ($title eq 'Total' && $just456) { $titleline = $newline; }
    #else
    { $report .= $newline; }
  }
  #$report .= $titleline if $just456;
  $report .= "</table>\n";
  return $report;
}

# Type arg is 0 for Monthly Breakdown, 1 for Total Determinations, 2 for cumulative (pie)
sub CreateExportGraph
{
  my $self  = shift;
  my $type  = int shift;
  my $start = shift;
  my $end   = shift;
  
  my $data = $self->CreateExportData(',', $type == 2, 0, $start, $end);
  #printf "CreateExportData(',', %d, 0, $start, $end)\n", ($type == 2);
  #print "$data\n";
  my @lines = split m/\n/, $data;
  my $title = shift @lines;
  $title .= '*' if $type == 2;
  $title =~ s/Cumulative/Monthly Breakdown/ if $type == 0;
  $title =~ s/Cumulative/Monthly Totals/ if $type == 1;
  my @dates = split(',', shift @lines);
  #printf "%d dates\n", scalar @dates;
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
    #print "$title\n";
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
  #$report .= sprintf "CreateExportData(',', %d, 0, $start, $end)\n", ($type == 2);
  #$report .= $data;
  return $report;
}


sub CreateExportStatusData
{
  my $self      = shift;
  my $delimiter = shift;
  my $start     = shift;
  my $end       = shift;
  my $monthly   = shift;
  my $title     = shift;
  
  my ($year,$month) = $self->GetTheYearMonth();
  my $titleDate = $self->YearMonthToEnglish("$year-$month");
  my $justThisMonth = (!$start && !$end);
  $start = "$year-$month-01" unless $start;
  my $lastDay = Days_in_Month($year,$month);
  $end = "$year-$month-$lastDay" unless $end;
  ($start,$end) = ($end,$start) if $end lt $start;
  $start = '2009-07-01' if $start lt '2009-07-01';
  my $sql = "SELECT DISTINCT(DATE(time)) FROM exportdata WHERE DATE(time)>='$start' AND DATE(time)<='$end'";
  #print "$sql<br/>\n";
  my @justdates = map {$_->[0];} @{$self->get('dbh')->selectall_arrayref( $sql )};
  my @dates = ();
  my $currmonth = 0;
  foreach my $date (@justdates)
  {
    my ($y,$m,$d) = split '-', $date;
    if ($m ne $currmonth && $currmonth)
    {
      push @dates, 'Total';
    }
    $currmonth = $m;
    push @dates, $date;
  }
  if (scalar @dates && !$justThisMonth)
  {
    my $startEng = $self->YearMonthToEnglish(substr($dates[0],0,7));
    my $endEng = $self->YearMonthToEnglish(substr($dates[-1],0,7));
    $titleDate = ($startEng eq $endEng)? $startEng:sprintf("%s to %s", $startEng, $endEng);
  }
  push @dates, 'Total';
  #$start = $dates[0];
  #$end = $dates[-1];
  
  my $report = ($title)? "$title\n":"Final Determinations Breakdown $titleDate\n";
  my @titles = ('Date','Status 4','Status 5','Status 6','Total','Status 4','Status 5','Status 6');
  $report .= join($delimiter, @titles) . "\n";
  my $currmonth;
  my $curryear;
  my @totals = (0,0,0);
  foreach my $date (@dates)
  {
    my ($y,$m,$d) = split '-', $date;
    my $date1 = $date;
    my $date2 = $date;
    if ($date eq 'Total')
    {
      $date .= sprintf(' %s', $self->YearMonthToEnglish("$curryear-$currmonth"));
      $date1 = "$curryear-$currmonth-01";
      my $lastDay = Days_in_Month($curryear,$currmonth);
      $date2 = "$curryear-$currmonth-$lastDay";
    }
    else
    {
      $currmonth = $m;
      $curryear = $y;
      next if $monthly;
    }
    my @line = (0,0,0,0,0,0,0);
    my @stati = $self->GetStatusBreakdown($date1, $date2);
    for (my $i=0; $i < 3; $i++)
    {
      $line[$i] = $stati[$i];
      $totals[$i] += $stati[$i];
    }
    $line[3] = $line[0] + $line[1] + $line[2];
    for (my $i=0; $i < 3; $i++)
    {
      my $pct = 0.0;
      eval {$pct = 100.0*$line[$i]/$line[3];};
      $line[$i+4] = sprintf('%.1f%%', $pct);
    }
    $report .= $date;
    $report .= $delimiter . join($delimiter, @line) . "\n";
  }
  if ($monthly && !$justThisMonth)
  {
    my $gt = $totals[0] + $totals[1] + $totals[2];
    push @totals, $gt;
    for (my $i=0; $i < 3; $i++)
    {
      my $pct = 0.0;
      eval {$pct = 100.0*$totals[$i]/$gt;};
      push @totals, sprintf('%.1f%%', $pct);
    }
    $report .= 'Total' . $delimiter . join($delimiter, @totals) . "\n";
  }
  return $report;
}

sub GetStatusBreakdown
{
  my $self  = shift;
  my $start = shift;
  my $end   = shift;
  
  my @counts = ();
  foreach my $status (4..6)
  {
    my $sql = 'SELECT COUNT(DISTINCT e.gid) FROM exportdata e INNER JOIN historicalreviews r ON e.gid=r.gid WHERE ' .
             "r.legacy=0 AND date(e.time)>='$start' AND date(e.time)<='$end' AND r.status=$status";
    #print "$sql<br/>\n";
    push @counts, $self->SimpleSqlGet($sql);
  }
  return @counts;
}

sub CreateExportStatusReport
{
  my $self     = shift;
  my $start    = shift;
  my $end      = shift;
  my $monthly  = shift;
  my $title    = shift;
  
  my $data = $self->CreateExportStatusData("\t", $start, $end, $monthly, $title);
  my @lines = split "\n", $data;
  $title = shift @lines;
  $title =~ s/\s/&nbsp;/g;
  my $url = sprintf("<a href='?p=determinationStats&amp;startDate=$start&amp;endDate=$end&amp;%sdownload=1&amp;target=_blank'>Download</a>",($monthly)?'monthly=on&amp;':'');
  my $report = "<h3>$title&nbsp;&nbsp;&nbsp;&nbsp;$url</h3>\n";
  $report .= "<table class='exportStats'>\n";
  $report .= "<tr><th/><th colspan='4'><span class='major'>Counts</span></th><th colspan='3'><span class='total'>Percentages</span></th></tr>\n";
  shift @lines; # titles
  $report .= "<tr><th>Date</th><th>Status&nbsp;4</th><th>Status&nbsp;5</th><th>Status&nbsp;6</th><th>Total</th><th>Status&nbsp;4</th><th>Status&nbsp;5</th><th>Status&nbsp;6</th></tr>\n";
  foreach my $line (@lines)
  {
    my @line = split "\t", $line;
    my $date = shift @line;
    my ($y,$m,$d) = split '-', $date;
    $date =~ s/\s/&nbsp;/g;
    #<tr><th style="text-align:right;"><span>&nbsp;&nbsp;&nbsp;&nbsp;Total</span></th><td style="text-align:center;">&nbsp;&nbsp;&nbsp;&nbsp;<b>467</b></td><td style="text-align:center;">
    if ($date eq 'Total')
    {
      $report .= '<tr><th style="text-align:right;">Total</th>';
    }
    elsif (substr($date,0,5) eq 'Total')
    {
      $report .= "<tr><th class='minor'><span class='minor'>$date</span></th>"
    }
    else
    {
      $report .= "<tr><th>$date</th>";
    }
    for (my $i=0; $i < 7; $i++)
    {
      my $class = '';
      my $style = ($i==3)? 'style="border-right:double 6px black"':'';
      if ($date ne 'Total' && (substr($date,0,5) eq 'Total' || $i == 3))
      {
        $class = 'class="minor"';
      }
      elsif ($date ne 'Total')
      {
        $class = 'class="total"';
        $class = 'class="major"' if $i < 3;
      }
      $report .= sprintf("<td $class $style>%s</td>\n", $line[$i]);
    }
    $report .= "</tr>\n";
  }
  $report .= "</table>\n";
  return $report;
}


sub CreateExportStatusGraph
{
  my $self    = shift;
  my $start   = shift;
  my $end     = shift;
  my $monthly = shift;
  my $title   = shift;
  
  my $data = $self->CreateExportStatusData("\t", $start, $end, $monthly, $title);
  my @lines = split "\n", $data;
  $title = shift @lines;
  shift @lines;
  my $report = '';
  
  my @usedates = ();
  my @stati = (4,5,6);
  my @elements = ();
  my %colors = (4 => '#22BB00', 5 => '#FF2200', 6 => '#0088FF');
  foreach my $status (@stati)
  {
    my @vals = ();
    my $color = $colors{$status};
    my $attrs = sprintf('"dot-style":{"type":"solid-dot","dot-size":3,"colour":"%s"},"text":"Status %s","colour":"%s","on-show":{"type":"pop-up","cascade":1,"delay":0.2}',
                        $color, $status, $color);
    foreach my $line (@lines)
    {
      my @line = split "\t", $line;
      my $date = shift @line;
      next if $date eq 'Total';
      next if $date =~ m/Total/ and !$monthly;
      $date =~ s/Total\s//;
      push @usedates, $date if $status == 4;
      my $count = $line[$status-4];
      my $pct = $line[$status];
      $pct =~ s/%//;
      push @vals, sprintf('{"value":%d,"tip":"%.1f%% (%d)"}', $pct, $pct, $count);
      
    }
    push @elements, sprintf('{"type":"line","values":[%s],%s}', join(',',@vals), $attrs);
  }
  my $report = sprintf('{"bg_colour":"#000000","title":{"text":"%s","style":"{color:#FFFFFF;font-family:Helvetica;font-size:15px;font-weight:bold;text-align:center;}"},"elements":[',$title);
  $report .= sprintf('%s]',join ',', @elements);
  $report .= ',"y_axis":{"max":100,"steps":10,"colour":"#888888","grid-colour":"#888888","labels":{"text":"#val#%","colour":"#FFFFFF"}}';
  $report .= sprintf(',"x_axis":{"colour":"#888888","grid-colour":"#888888","labels":{"labels":["%s"],"rotate":40,"colour":"#FFFFFF"}}', join('","',@usedates));
  $report .= '}';
  return $report;
}


sub CreateStatsData
{
  my $self       = shift;
  my $user       = shift;
  my $cumulative = shift;
  my $year       = shift;

  my $dbh = $self->get( 'dbh' );
  $year = ($self->GetTheYearMonth())[0] unless $year;
  my @statdates = ($cumulative)? $self->GetAllYears() : $self->GetAllMonthsInYear($year);
  my $username = ($user eq 'all')? 'All Users':$self->GetUserName($user);
  my $label = "$username: " . (($cumulative)? "CRMS&nbsp;Project&nbsp;Cumulative":"Cumulative $year");
  my $report = sprintf("$label\nCategories,Project Total%s", (!$cumulative)? ",Total $year":'');
  my %stats = ();
  my @usedates = ();
  my $earliest = '';
  my $latest = '';
  my @titles = ('All PD', 'pd/ren', 'pd/ncn', 'pd/cdpp', 'pdus/cdpp', 'All IC', 'ic/ren', 'ic/cdpp', 'All UND/NFI',
                '__TOT__', '__TOTNE__', '__VAL__', '__AVAL__', '__MVAL__',
                'Time Reviewing (mins)', 'Time per Review (mins)','Reviews per Hour', 'Outlier Reviews');
  foreach my $date (@statdates)
  {
    push @usedates, $date;
    $report .= ",$date";
    my $mintime = $date . (($cumulative)? '-01':'');
    my $maxtime = $date . (($cumulative)? '-12':'');
    $earliest = $mintime if $earliest eq '' or $mintime lt $earliest;
    $latest = $maxtime if $latest eq '' or $maxtime gt $latest;
    my $sql = qq{SELECT SUM(total_pd_ren) + SUM(total_pd_cnn) + SUM(total_pd_cdpp) + SUM(total_pdus_cdpp),
                 SUM(total_pd_ren), SUM(total_pd_cnn), SUM(total_pd_cdpp), SUM(total_pdus_cdpp),
                 SUM(total_ic_ren) + SUM(total_ic_cdpp),
                 SUM(total_ic_ren), SUM(total_ic_cdpp), SUM(total_und_nfi), SUM(total_reviews), 1,1,1,1, SUM(total_time),
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
    my ($year,$month) = split '-', $maxtime;
    my $lastDay = Days_in_Month($year,$month);
    $mintime .= '-01 00:00:00';
    $maxtime .= "-$lastDay 23:59:59";
    my ($ok,$oktot) = $self->CountCorrectReviews($user, $mintime, $maxtime);
    $stats{'__VAL__'}{$date} = $ok;
    $stats{'__TOTNE__'}{$date} = $oktot;
    $stats{'__AVAL__'}{$date} = $self->GetAverageCorrect($mintime, $maxtime);
    $stats{'__MVAL__'}{$date} = $self->GetMedianCorrect($mintime, $maxtime);
  }
  $report .= "\n";
  my %totals;
  my $sql = qq{SELECT SUM(total_pd_ren) + SUM(total_pd_cnn) + SUM(total_pd_cdpp) + SUM(total_pdus_cdpp),
               SUM(total_pd_ren), SUM(total_pd_cnn), SUM(total_pd_cdpp), SUM(total_pdus_cdpp),
               SUM(total_ic_ren) + SUM(total_ic_cdpp),
               SUM(total_ic_ren), SUM(total_ic_cdpp), SUM(total_und_nfi), SUM(total_reviews), 1,1,1,1, SUM(total_time),
               SUM(total_time)/(SUM(total_reviews)-SUM(total_outliers)),
               (SUM(total_reviews)-SUM(total_outliers))/SUM(total_time)*60.0, SUM(total_outliers)
               FROM userstats WHERE monthyear >= '$earliest' AND monthyear <= '$latest'};
  $sql .= " AND user='$user'" if $user ne 'all';
  #print "$sql<br/>\n";
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
  my ($year,$month) = split '-', $latest;
  my $lastDay = Days_in_Month($year,$month);
  $earliest .= '-01 00:00:00';
  $latest .= "-$lastDay 23:59:59";
  my ($ok,$oktot) = $self->CountCorrectReviews($user, $earliest, $latest);
  $totals{'__VAL__'} = $ok;
  $totals{'__TOTNE__'} = $oktot;
  $totals{'__AVAL__'} = $self->GetAverageCorrect($earliest, $latest);
  $totals{'__MVAL__'} = $self->GetMedianCorrect($earliest, $latest);
  # Project totals
  my %ptotals;
  if (!$cumulative)
  {
    $earliest = '2009-07';
    $latest = '3000-01';
    $sql = qq{SELECT SUM(total_pd_ren) + SUM(total_pd_cnn) + SUM(total_pd_cdpp) + SUM(total_pdus_cdpp),
               SUM(total_pd_ren), SUM(total_pd_cnn), SUM(total_pd_cdpp), SUM(total_pdus_cdpp),
               SUM(total_ic_ren) + SUM(total_ic_cdpp),
               SUM(total_ic_ren), SUM(total_ic_cdpp), SUM(total_und_nfi), SUM(total_reviews), 1,1,1,1, SUM(total_time),
               SUM(total_time)/(SUM(total_reviews)-SUM(total_outliers)),
               (SUM(total_reviews)-SUM(total_outliers))/SUM(total_time)*60.0, SUM(total_outliers)
               FROM userstats WHERE monthyear >= '$earliest'};
    $sql .= " AND user='$user'" if $user ne 'all';
    #print "$sql<br/>\n";
    my $rows = $dbh->selectall_arrayref( $sql );
    foreach my $row ( @{$rows} )
    {
      my $i = 0;
      foreach my $title (@titles)
      {
        $ptotals{$title} = $row->[$i];
        $i++;
      }
    }
    my ($ok,$oktot) = $self->CountCorrectReviews($user, $earliest, $latest);
    $ptotals{'__VAL__'} = $ok;
    $ptotals{'__TOTNE__'} = $oktot;
    $ptotals{'__AVAL__'} = $self->GetAverageCorrect($earliest, $latest);
    $ptotals{'__MVAL__'} = $self->GetMedianCorrect($earliest, $latest);
  }
  
  my %majors = ('All PD' => 1, 'All IC' => 1, 'All UND/NFI' => 1);
  my %minors = ('Time Reviewing (mins)' => 1, 'Time per Review (mins)' => 1,
                'Reviews per Hour' => 1, 'Outlier Reviews' => 1);
  foreach my $title (@titles)
  {
    $report .= $title;
    if (!$cumulative)
    {
      my $of = $ptotals{'__TOT__'};
      $of = $ptotals{'__TOTNE__'} if $title eq '__VAL__';
      my $n = $ptotals{$title};
      $n = 0 unless $n;
      if ($title eq '__MVAL__' || $title eq '__AVAL__')
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
    }
    my $of = $totals{'__TOT__'};
    $of = $totals{'__TOTNE__'} if $title eq '__VAL__';
    my $n = $totals{$title};
    $n = 0 unless $n;
    if ($title eq '__MVAL__' || $title eq '__AVAL__')
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
      if ($title eq '__MVAL__' || $title eq '__AVAL__')
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
  my $self              = shift;
  my $user              = shift;
  my $cumulative        = shift;
  my $suppressBreakdown = shift;
  my $year              = shift;
  
  my $data = $self->CreateStatsData($user, $cumulative, $year);
  my @lines = split m/\n/, $data;
  my $report = sprintf("<span style='font-size:1.3em;'><!--NAME--><b>%s</b></span><!--LINK-->\n<br/><table class='exportStats'>\n<tr>\n", shift @lines);
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
    next if $title eq '__AVAL__' and ($exp);
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
  my $avtitle = 'Average&nbsp;Validation&nbsp;Rate';
  $report =~ s/__AVAL__/$avtitle/;
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

# Returns an error message, or an empty string if no error.
sub ValidateSubmission2
{
    my $self = shift;
    my ($attr, $reason, $note, $category, $renNum, $renDate, $user) = @_;
    my $errorMsg = '';

    my $noteError = 0;

    ## check user
    if ( ! $self->IsUserReviewer( $user ) )
    {
        $errorMsg .= 'Not a reviewer.';
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

    ## pd/ren should not have a ren number or date
    if ( $attr == 1 && $reason == 7 &&  ( ( $renNum ) || ( $renDate ) )  )
    {
        $errorMsg .= 'pd/ren should not include renewal info.';
    }

    ## pd/ncn requires a ren number unless Gov Doc
    if (  $attr == 1 && $reason == 2 && ( ( ! $renNum ) || ( ! $renDate ) ) )
    {
        $errorMsg .= 'pd/ncn must include renewal id and renewal date.' unless $category eq 'US Gov Doc';
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
        if ($category ne 'US Gov Doc')
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
    
    ## US Gov Doc requires pd/ncn
    if ($category eq 'US Gov Doc' && ($attr != 1 || $reason != 2))
    {
      $errorMsg = 'note category only permitted with pd/ncn';
    }
    return $errorMsg;
}

# Returns an error message, or an empty string if no error.
# Relaxes constraints on ic/ren needing renewal id and date
sub ValidateSubmissionHistorical
{
    my $self = shift;
    my ($attr, $reason, $note, $category, $renNum, $renDate) = @_;
    my $errorMsg = '';

    my $noteError = 0;

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

    if ( ! $record ) { $self->SetError("no record in IsGovDoc: $barcode"); return 1; }
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

    if ( ! $record ) { $self->SetError("no record in IsUSPub: $barcode"); return 1; }

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

sub IsThesis
{
  my $self    = shift;
  my $barcode = shift;
  my $record  = shift;

  my $is = 0;
  if ( ! $record ) { $self->SetError("no record in IsThesis($barcode)"); return 0; }
  eval {
    my $xpath = "//*[local-name()='datafield' and \@tag='502']/*[local-name()='subfield'  and \@code='a']";
    my $doc  = $record->findvalue( $xpath );
    $is = 1 if $doc =~ m/thes(e|i)s/i or $doc =~ m/diss/i;
    my $nodes = $record->findnodes("//*[local-name()='datafield' and \@tag='500']");
    foreach my $node ($nodes->get_nodelist())
    {
      $doc = $node->findvalue("./*[local-name()='subfield' and \@code='a']");
      $is = 1 if $doc =~ m/thes(e|i)s/i or $doc =~ m/diss/i;
    }
  };
  $self->SetError("failed in IsThesis($barcode): $@") if $@;
  return $is;
}

# Translations: 041, first indicator=1, $a=eng, $h= (original
# language code); Translation (or variations thereof in 500(a) note field.
sub IsTranslation
{
  my $self    = shift;
  my $barcode = shift;
  my $record  = shift;

  my $is = 0;
  if ( ! $record ) { $self->SetError("no record in IsTranslation($barcode)"); return 0; }
  eval {
    my $xpath = "//*[local-name()='datafield' and \@tag='041' and \@ind1='1']/*[local-name()='subfield' and \@code='a']";
    my $lang  = $record->findvalue( $xpath );
    $xpath = "//*[local-name()='datafield' and \@tag='041' and \@ind1='1']/*[local-name()='subfield' and \@code='h']";
    my $orig  = $record->findvalue( $xpath );
    if ($lang && $orig)
    {
      $is = 1 if $lang eq 'eng' and $orig ne 'eng';
    }
    if (!$is && $lang)
    {
      # some uc volumes have no 'h' but instead concatenate everything in 'a'
      $is = 1 if length($lang) > 3 and substr($lang,0,3) eq 'eng';
    }
    if (!$is)
    {
      my $nodes = $record->findnodes("//*[local-name()='datafield' and \@tag='500']");
      foreach my $node ($nodes->get_nodelist())
      {
        my $doc = $node->findvalue("./*[local-name()='subfield' and \@code='a']");
        $is = 1 if $doc =~ m/translat(ion|ed)/i;
      }
    }
    if (!$is)
    {
      $xpath = "//*[local-name()='datafield' and \@tag='245']/*[local-name()='subfield' and \@code='c']";
      my $doc  = $record->findvalue( $xpath );
      if ($doc =~ m/translat(ion|ed)/i)
      {
        $is = 1;
        #$in245++;
        #print "245c: $id has '$doc'\n";
      }
    }
  };
  $self->SetError("failed in IsTranslation($barcode): $@") if $@;
  return $is;
}

# - Foreign ? use method used for bib extraction to detect
# second/foreign place of pub. From Tim?s documentation:
# Check of 260 field for multiple subfield a:
# If PubPlace 17 eq ?u?, and the 260 field contains multiple subfield
# a?s, then the data in each subfield a is normalized and matched
# against a list of known US cities.  If any of the subfield a?s are not
# in the list, then the mult_260a_non_us flag is set.
# Note: it is assumed this has passed the IsUSPub() check.
sub IsForeignPub
{
  my $self    = shift;
  my $barcode = shift;
  my $record  = shift;

  my $is = 0;
  if ( ! $record ) { $self->SetError("no record in IsForeignPub($barcode)"); return 0; }
  eval {
    my $xpath = "//*[local-name()='controlfield' and \@tag='008']";
    my $where  = $record->findvalue( $xpath );
    if (substr($where,17,1) eq 'u')
    {
      my @nodes = $record->findnodes("//*[local-name()='datafield' and \@tag='260']/*[local-name()='subfield' and \@code='a']")->get_nodelist();
      return if scalar @nodes == 1;
      foreach my $node (@nodes)
      {
        $where = $self->Normalize($node->textContent);
        my $cities = $self->get('cities');
        $cities = $self->ReadCities() unless $cities;
        if ($cities !~ m/==$where==/i)
        {
          $is = 1;
          last;
        }
      }
    }
  };
  $self->SetError("failed in IsForeignPub($barcode): $@") if $@;
  return $is;
}

sub ReadCities
{
  my $self = shift;
  
  my $in = $self->get('root') . "/prep/c/crms/us_cities.txt";
  open (FH, '<', $in) || $self->SetError("Could not open $in");
  my $cities = '';
  while( <FH> ) { chomp; $cities .= "==$_=="; }
  close FH;
  $self->set('cities',$cities);
  return $cities;
}

# This is code from Tim for normalizing the 260 subfield for U.S. cities.
sub Normalize
{
  my $self = shift;
  my $suba = shift;
  
  $suba =~ tr/A-Za-z / /c;
  $suba = lc($suba);
  $suba =~ s/ and / /;
  $suba =~ s/ etc / /;
  $suba =~ s/ dc / /;
  $suba =~ s/\s+/ /g;
  $suba =~ s/^\s*(.*?)\s*$/$1/;
  return $suba;
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
    if ($pubDateType eq 'q' || ($pubDate eq '||||' || $pubDate eq '####' || $pubDate eq '^^^^'))
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
    $self->Logit($self->HexDump($title));
  }
  my $tiq = $self->get('dbh')->quote( $title );
  if ($self->Mojibake($tiq))
  {
    $self->Logit("$0: Mojibake quoted title <<$tiq>> for $id!\n");
    $self->Logit($self->HexDump($tiq));
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

    # By default, GetPrevDate() returns the date/time 24 hours ago.
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
    my $sql = qq{UPDATE $CRMSGlobals::queueTable SET locked="$name" WHERE id="$id"};
    $self->PrepareSubmitSql( $sql );
    $self->StartTimer( $id, $name );
    return 0;
}

sub UnlockItem
{
    my $self = shift;
    my $id   = shift;
    my $user = shift;

    #if ( ! $self->IsLocked( $id ) ) { return 0; }

    my $sql = qq{UPDATE $CRMSGlobals::queueTable SET locked=NULL WHERE id="$id"};
    $self->PrepareSubmitSql($sql);
    #if ( ! $self->PrepareSubmitSql($sql) ) { return 0; }

    $self->RemoveFromTimer( $id, $user );
    #$self->Logit( "unlocking $id" );
    return 1;
}


sub UnlockItemEvenIfNotLocked
{
    my $self = shift;
    my $id   = shift;
    my $user = shift;

    my $sql = qq{UPDATE $CRMSGlobals::queueTable SET locked=NULL WHERE id="$id"};
    if ( ! $self->PrepareSubmitSql($sql) ) { return 0; }

    $self->RemoveFromTimer( $id, $user );
    #$self->Logit( "unlocking $id" );
    return 1;
}


sub UnlockAllItemsForUser
{
    my $self = shift;
    my $user = shift;

    my $sql = qq{SELECT id FROM $CRMSGlobals::timerTable WHERE user="$user"};
    my $ref = $self->get( 'dbh' )->selectall_arrayref( $sql );

    my $return = {};
    foreach my $row (@{$ref})
    {
        my $id = $row->[0];
   
        my $sql = qq{UPDATE $CRMSGlobals::queueTable SET locked=NULL WHERE id="$id"};
        $self->PrepareSubmitSql( $sql );
    }

    ## clear entry in table
    my $sql = qq{ DELETE FROM $CRMSGlobals::timerTable WHERE user="$user" };
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

    my $sql = qq{SELECT start_time FROM $CRMSGlobals::timerTable WHERE id="$id" AND user="$user"};
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
      my $sql = "SELECT id FROM queue WHERE locked IS NULL AND expcnt=0 AND priority>=4 ORDER BY priority DESC, time ASC LIMIT 1";
      $bar = $self->SimpleSqlGet( $sql );
      #print "$sql<br/>\n";
    }
    # If user is expert, get priority 3 items.
    if (!$bar && $self->IsUserExpert($name))
    {
      my $sql = "SELECT id FROM queue WHERE locked IS NULL AND expcnt=0 AND priority=3 ORDER BY time ASC LIMIT 1";
      $bar = $self->SimpleSqlGet( $sql );
      #print "$sql<br/>\n";
    }
    if ( ! $bar )
    {
      # Get priority 2 items that have not been reviewed yet
      my $sql = "SELECT q.id FROM queue q WHERE q.priority=2 AND q.locked IS NULL AND " .
                "q.status=0 AND q.expcnt=0 AND q.id NOT IN (SELECT DISTINCT id FROM reviews) " .
                "ORDER BY q.time ASC LIMIT 1";
      $bar = $self->SimpleSqlGet( $sql );
      #print "$sql<br/>\n";
    }
    my $exclude3 = ($self->IsUserExpert($name))? '':'q.priority<3 AND';
    if ( ! $bar )
    {
      # Find items reviewed once by some other user, preferring priority 2.
      # Exclude priority 1 some of the time, to 'fool' reviewers into not thinking everything is pd.
      my $exclude1 = (rand() >= 0.33)? 'q.priority!=1 AND':'';
      my $sql = "SELECT q.id FROM queue q INNER JOIN reviews r ON q.id=r.id INNER JOIN " .
                "(SELECT id FROM reviews GROUP BY id HAVING count(*)=1) AS r2 ON r.id=r2.id " .
                "WHERE $exclude1 $exclude3 q.locked IS NULL AND q.status=0 AND q.expcnt=0 AND r.user!='$name' " .
                "ORDER BY q.priority DESC, q.time ASC";
      #print "$sql<br/>\n";
      my $rows = $self->get('dbh')->selectall_arrayref($sql);
      my $idx = ($exclude1 eq '')? (rand scalar @{$rows}):0;
      $bar = $rows->[$idx]->[0];
    }
    if ( ! $bar )
    {
      # Get the 1st available item that has never been reviewed.
      my $sql = "SELECT q.id FROM $CRMSGlobals::queueTable q WHERE $exclude3 q.locked IS NULL AND " .
                "q.status=0 AND q.expcnt=0 AND q.id NOT IN (SELECT DISTINCT id FROM $CRMSGlobals::reviewsTable) " .
                "ORDER BY q.priority DESC, q.time ASC LIMIT 1";
      $bar = $self->SimpleSqlGet( $sql );
      #print "$sql<br/>\n";
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
  $report .= "<table class='exportStats'>\n<tr><th>Status</th><th>Total</th>$priheaders</tr>\n";
  foreach my $status (-1 .. 6)
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
  $report .= "</tr></table><br/><br/>\n";
  $report .= "</td><td style='padding-left:20px'>\n";
  $report .= "<table class='exportStats'>\n";
  my $val = $self->GetLastQueueTime(1);
  $val =~ s/\s/&nbsp;/g;
  $val = 'Never' unless $val;
  $report .= "<tr><th>Last&nbsp;Queue&nbsp;Update</th><td>$val</td></tr>\n";
  $report .= sprintf("<tr><th>Volumes&nbsp;Last&nbsp;Added</th><td>%s</td></tr>\n", ($self->GetLastIdQueueCount() or 0));
  $report .= sprintf("<tr><th>Cumulative&nbsp;Volumes&nbsp;in&nbsp;Queue&nbsp;(ever*)</th><td>%s</td></tr>\n", ($self->GetTotalEverInQueue() or 0));
  $report .= sprintf("<tr><th>Volumes&nbsp;in&nbsp;Candidates</th><td>%s</td></tr>\n", $self->GetCandidatesSize());
  $val = $self->GetLastLoadTimeToCandidates();
  $val =~ s/\s/&nbsp;/g;
  $report .= sprintf("<tr><th>Last&nbsp;Candidates&nbsp;Addition</th><td>%s&nbsp;on&nbsp;$val</td></tr>", $self->GetLastLoadSizeToCandidates());
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
  my $sql = "SELECT count(DISTINCT h.id) FROM exportdata e, historicalreviews h WHERE e.gid=h.gid AND h.status=4 AND e.time>=date_sub('$time', INTERVAL 1 MINUTE)";
  my $fours = $self->SimpleSqlGet($sql);
  $sql = "SELECT count(DISTINCT h.id) FROM exportdata e, historicalreviews h WHERE e.gid=h.gid AND h.status=5 AND e.time>=date_sub('$time', INTERVAL 1 MINUTE)";
  my $fives = $self->SimpleSqlGet($sql);
  $sql = "SELECT count(DISTINCT h.id) FROM exportdata e, historicalreviews h WHERE e.gid=h.gid AND h.status=6 AND e.time>=date_sub('$time', INTERVAL 1 MINUTE)";
  my $sixes = $self->SimpleSqlGet($sql);
  my $pct4 = 0;
  my $pct5 = 0;
  my $pct6 = 0;
  eval {$pct4 = 100.0*$fours/($fours+$fives+$sixes);};
  eval {$pct5 = 100.0*$fives/($fours+$fives+$sixes);};
  eval {$pct6 = 100.0*$sixes/($fours+$fives+$sixes);};
  my $legacy = $self->GetTotalLegacyCount();
  my %sources;
  $sql = 'SELECT src,COUNT(gid) FROM exportdata WHERE src IS NOT NULL GROUP BY src';
  my $rows = $self->get('dbh')->selectall_arrayref($sql);
  foreach my $row ( @{$rows} )
  {
    $sources{ $row->[0] } = $row->[1];
  }
  ($count,$time) = $self->GetLastExport(1);
  $time =~ s/\s/&nbsp;/g;
  $count = 'None' unless $count;
  $time = 'record' unless $time;
  my $exported = $self->SimpleSqlGet('SELECT COUNT(DISTINCT gid) FROM exportdata');
  $report .= "<tr><th>Last&nbsp;CRMS&nbsp;Export</th><td>$count&nbsp;on&nbsp;$time</td></tr>";
  $report .= sprintf("<tr><th>&nbsp;&nbsp;&nbsp;&nbsp;Status&nbsp;4</th><td>$fours&nbsp;(%.1f%%)</td></tr>", $pct4);
  $report .= sprintf("<tr><th>&nbsp;&nbsp;&nbsp;&nbsp;Status&nbsp;5</th><td>$fives&nbsp;(%.1f%%)</td></tr>", $pct5);
  $report .= sprintf("<tr><th>&nbsp;&nbsp;&nbsp;&nbsp;Status&nbsp;6</th><td>$sixes&nbsp;(%.1f%%)</td></tr>", $pct6);
  $report .= sprintf("<tr><th>Total&nbsp;CRMS&nbsp;Determinations</th><td>%s</td></tr>", $exported);
  foreach my $source (keys %sources)
  {
    my $n = $sources{$source};
    $report .= "<tr><th>&nbsp;&nbsp;&nbsp;&nbsp;From&nbsp;$source</th><td>$n</td></tr>";
  }
  #$report .= sprintf("<tr><th>&nbsp;&nbsp;&nbsp;&nbsp;From&nbsp;Elsewhere</td><td>%s</td></tr>", $noncand);
  $report .= sprintf("<tr><th>Total&nbsp;Legacy&nbsp;Determinations</th><td>%s</td></tr>", $legacy);
  $report .= sprintf("<tr><th>Total&nbsp;Determinations</th><td>%s</td></tr>", $exported + $legacy);
  $report .= "</table>\n";
  return $report;
}

sub CreateHistoricalReviewsReport
{
  my $self = shift;
  
  my $report = '';
  $report .= "<table class='exportStats'>\n";
  $report .= sprintf("<tr><th>CRMS&nbsp;Reviews</th><td>%s</td></tr>\n", $self->GetTotalNonLegacyReviewCount());
  $report .= sprintf("<tr><th>Legacy&nbsp;Reviews</th><td>%s</td></tr>\n", $self->GetTotalLegacyReviewCount());
  $report .= sprintf("<tr><th>Total&nbsp;Historical&nbsp;Reviews</th><td>%s</td></tr>\n", $self->GetTotalHistoricalReviewCount());
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
  $report .= "<table class='exportStats'>\n<tr><th>Status</th><th>Total</th>$priheaders</tr>\n";
  
  my $sql = 'SELECT DISTINCT id FROM reviews';
  my $rows = $dbh->selectall_arrayref( $sql );
  my $count = scalar @{$rows};
  $report .= "<tr><td class='total'>Active</td><td class='total'>$count</td>";
  $report .= $self->DoPriorityBreakdown($count,$sql,$maxpri,' class="total"') . "</tr>\n";
  
  # Unprocessed
  $sql = 'SELECT id FROM queue WHERE status=0 AND pending_status>0';
  $rows = $dbh->selectall_arrayref( $sql );
  $count = scalar @{$rows};
  $report .= "<tr><td class='minor'>Unprocessed</td><td class='minor'>$count</td>";
  $report .= $self->DoPriorityBreakdown($count,$sql,$maxpri,' class="minor"') . "</tr>\n";
  
  # Unprocessed - single review
  $sql = "SELECT id from $CRMSGlobals::queueTable WHERE status=0 AND pending_status=1";
  $rows = $dbh->selectall_arrayref( $sql );
  $count = scalar @{$rows};
  $report .= "<tr><td>&nbsp;&nbsp;&nbsp;&nbsp;Single&nbsp;Review</td><td>$count</td>";
  $report .= $self->DoPriorityBreakdown($count,$sql,$maxpri) . "</tr>\n";
  
  # Unprocessed - match
  $sql = "SELECT id from $CRMSGlobals::queueTable WHERE status=0 AND pending_status=4";
  my $rows = $dbh->selectall_arrayref( $sql );
  $count = scalar @{$rows};
  $report .= "<tr><td>&nbsp;&nbsp;&nbsp;&nbsp;Matches</td><td>$count</td>";
  $report .= $self->DoPriorityBreakdown($count,$sql,$maxpri) . "</tr>\n";
  
  # Unprocessed - conflict
  $sql = "SELECT id from $CRMSGlobals::queueTable WHERE status=0 AND pending_status=2";
  $rows = $dbh->selectall_arrayref( $sql );
  $count = scalar @{$rows};
  $report .= "<tr><td>&nbsp;&nbsp;&nbsp;&nbsp;Conflicts</td><td>$count</td>";
  $report .= $self->DoPriorityBreakdown($count,$sql,$maxpri) . "</tr>\n";
  
  # Unprocessed - matching und/nfi
  $sql = "SELECT id from $CRMSGlobals::queueTable WHERE status=0 AND pending_status=3";
  $rows = $dbh->selectall_arrayref( $sql );
  $count = scalar @{$rows};
  $report .= "<tr><td>&nbsp;&nbsp;&nbsp;&nbsp;Matching&nbsp;<code>und/nfi</code></td><td>$count</td>";
  $report .= $self->DoPriorityBreakdown($count,$sql,$maxpri) . "</tr>\n";
  
  # Processed
  $sql = 'SELECT id FROM queue WHERE status!=0';
  $rows = $dbh->selectall_arrayref( $sql );
  $count = scalar @{$rows};
  $report .= "<tr><td class='minor'>Processed</td><td class='minor'>$count</td>";
  $report .= $self->DoPriorityBreakdown($count,$sql,$maxpri,' class="minor"') . "</tr>\n";
  
  $sql = "SELECT id from $CRMSGlobals::queueTable WHERE status=2";
  $rows = $dbh->selectall_arrayref( $sql );
  $count = scalar @{$rows};
  $report .= "<tr><td>&nbsp;&nbsp;&nbsp;&nbsp;Conflicts</td><td>$count</td>";
  $report .= $self->DoPriorityBreakdown($count,$sql,$maxpri) . "</tr>\n";

  $sql = 'SELECT id from queue WHERE status=3';
  $rows = $dbh->selectall_arrayref( $sql );
  $count = scalar @{$rows};
  $report .= "<tr><td>&nbsp;&nbsp;&nbsp;&nbsp;Matching&nbsp;<code>und/nfi</code></td><td>$count</td>";
  $report .= $self->DoPriorityBreakdown($count,$sql,$maxpri) . "</tr>\n";

  $sql = "SELECT id from $CRMSGlobals::queueTable WHERE status=4 OR status=5 OR status=6";
  $rows = $dbh->selectall_arrayref( $sql );
  $count = scalar @{$rows};
  $report .= "<tr><td>&nbsp;&nbsp;&nbsp;&nbsp;Awaiting&nbsp;Export</td><td>$count</td>";
  $report .= $self->DoPriorityBreakdown($count,$sql,$maxpri) . "</tr>\n";
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

    my $sql = 'SELECT addedamount FROM candidatesrecord ORDER BY time DESC LIMIT 1';
    my $count = $self->SimpleSqlGet( $sql );
    
    if ($count) { return $count; }
    return 0;

}

sub GetLastLoadTimeToCandidates
{
    my $self = shift;

    my $sql = qq{SELECT DATE_FORMAT(MAX(time), "%a, %M %e, %Y at %l:%i %p") from candidatesrecord};
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
    my $readable = shift;
    
    my $sql = "SELECT itemcount,time FROM exportrecord WHERE itemcount>0 ORDER BY time DESC LIMIT 1";
    my $ref = $self->get( 'dbh' )->selectall_arrayref( $sql );
    my $count = $ref->[0]->[0];
    my $time = $ref->[0]->[1];
    $time = $self->FormatTime($time) if $readable;
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

    my $sql = qq{ SELECT COUNT(*) FROM $CRMSGlobals::historicalreviewsTable};
    my $ref = $self->get( 'dbh' )->selectall_arrayref( $sql );

    return $ref->[0]->[0];
}

sub GetLastQueueTime
{
    my $self     = shift;
    my $readable = shift;
    
    my $sql = qq{ SELECT MAX(time) FROM $CRMSGlobals::queuerecordTable WHERE source='RIGHTSDB'};
    my $time = $self->SimpleSqlGet( $sql );
    $time = $self->FormatTime($time) if $readable;
    return $time;
}

sub GetLastStatusProcessedTime
{
    my $self = shift;

    my $sql = qq{ SELECT MAX(time) FROM processstatus };
    my $time = $self->SimpleSqlGet( $sql );
    return $self->FormatTime($time);
}

sub GetLastIdQueueCount
{
    my $self = shift;

    my $latest_time = $self->GetLastQueueTime();

    my $sql = qq{ SELECT itemcount FROM $CRMSGlobals::queuerecordTable where time like '$latest_time%' AND source='RIGHTSDB'};
    my $latest_time = $self->SimpleSqlGet( $sql );
    
    return $latest_time;
}

sub DownloadSpreadSheetBkup
{
    my $self = shift;
    my $buffer = shift;

    if ($buffer)
    {

      my $ZipDir = '/tmp/out';
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
  
  # Has there ever been a swiss review for this volume?
  my $sql = "SELECT COUNT(id) FROM historicalreviews WHERE id='$id' AND swiss=1";
  my $swiss = $self->SimpleSqlGet($sql);
  # Get the review
  $sql = "SELECT attr,reason,renNum,renDate,expert FROM historicalreviews WHERE id='$id' AND user='$user' AND time='$time'";
  my $r = $self->get('dbh')->selectall_arrayref($sql);
  my $row = $r->[0];
  my $attr = $row->[0];
  my $reason = $row->[1];
  my $renNum = $row->[2];
  my $renDate = $row->[3];
  my $expert = $row->[4];
  #print "user $user $attr $reason $renNum $renDate\n";
  # Get the most recent expert review
  $sql = "SELECT attr,reason,renNum,renDate,user FROM historicalreviews WHERE id='$id' AND expert>0 ORDER BY time DESC";
  $r = $self->get('dbh')->selectall_arrayref($sql);
  return 1 unless scalar @{$r};
  $row = $r->[0];
  my $eattr = $row->[0];
  my $ereason = $row->[1];
  my $erenNum = $row->[2];
  my $erenDate = $row->[3];
  my $euser = $row->[4];
  #print "expert ($euser) $eattr $ereason $erenNum $erenDate\n";
  #print "$user $attr $reason $renNum $renDate\n";
  if ($attr != $eattr || $reason != $ereason)
  {
    #print ("$attr != $eattr || $reason != $ereason\n");
    return ($swiss && !$expert)? 2:0;
  }
  if ($eattr == 2 && $ereason == 7 && $attr == 2 && $reason == 7)
  {
    #print "$renNum ne $erenNum || $renDate ne $erenDate\n";
    if ($renNum ne $erenNum || $renDate ne $erenDate)
    {
      return ($swiss && !$expert)? 2:0;
    }
  }
  return 1;
}


sub CountCorrectReviews
{
  my $self  = shift;
  my $user  = shift;
  my $start = shift;
  my $end   = shift;
  
  my $type1Clause = sprintf(' AND user IN (%s)', join(',', map {"'$_'"} $self->GetType1Reviewers()));
  my $startClause = ($start)? " AND time>='$start'":'';
  my $endClause = ($end)? " AND time<='$end' ":'';
  my $userClause = ($user eq 'all')? $type1Clause:" AND user='$user'";
  my $sql = "SELECT count(*) FROM $CRMSGlobals::historicalreviewsTable WHERE legacy=0 AND validated!=2 $startClause $endClause $userClause";
  my $total = $self->SimpleSqlGet($sql);
  #print "$sql => $total<br/>\n";
  my $correct = $total;
  if (!$self->IsUserExpert($user))
  {
    my $sql = "SELECT count(*) FROM $CRMSGlobals::historicalreviewsTable WHERE legacy=0 AND validated=1 $startClause $endClause $userClause";
    $correct = $self->SimpleSqlGet($sql);
    #print "$sql => $correct<br/>\n";
  }
  #printf "CountCorrectReviews(%s): $correct of $total<br/>\n", join ', ', ($user,$start,$end);
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

sub GetAverageCorrect
{
  my $self  = shift;
  my $start = shift;
  my $end   = shift;
  
  my @users = $self->GetType1Reviewers();
  my $tot = 0.0;
  my $n = 0;
  foreach my $user (@users)
  {
    my ($ncorr,$total) = $self->CountCorrectReviews($user, $start, $end);
    next unless $total;
    my $frac = 0.0;
    eval { $frac = 100.0*$ncorr/$total; };
    #print " $user: $frac\n";
    $tot += $frac;
    $n++;
  }
  #printf "%s to %s: $tot/$n = %f\n", $start, $end, $tot/$n;
  my $pct = 0.0;
  eval {$pct = $tot/$n;};
  return $pct;
}

sub GetMedianCorrect
{
  my $self  = shift;
  my $start = shift;
  my $end   = shift;
  
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
  my $vidRE = '^[a-z]+\d?\.[a-zA-Z]?[a-zA-Z0-9]+$';
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
  # ======== exportdata ========
  # time must be in a format like 2009-07-16 07:00:02
  # id must not be ill-formed
  # attr/reason must be valid
  # user must be crms
  # src must not be NULL
  $table = 'exportdata';
  $sql = "SELECT time,id,attr,reason,user,src FROM $table";
  $rows = $dbh->selectall_arrayref( $sql );
  foreach my $row ( @{$rows} )
  {
    $self->SetError(sprintf("$table __ illegal time for %s__ '%s'", $row->[1], $row->[0])) unless $row->[0] =~ m/\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d/;
    $self->SetError(sprintf("$table __ illegal volume id__ '%s'", $row->[1])) unless $row->[1] =~ m/$vidRE/;
    my $comb = $row->[2] . '/' . $row->[3];
    $self->SetError(sprintf("$table __ illegal attr/reason for %s__ '%s'", $row->[1], $comb)) unless $self->GetAttrReasonCom($comb);
    $self->SetError(sprintf("$table __ illegal user for %s__ '%s' (should be 'crms')", $row->[1])) unless $row->[4] eq 'crms';
    $self->SetError(sprintf("$table __ NULL src for %s__ ", $row->[1])) unless $row->[4];
  }
  # All gid/id must match gid/id in historicalreviews
  $sql = "SELECT e.gid,e.id,h.id,e.src,h.source FROM $table e INNER JOIN historicalreviews h ON e.gid=h.gid WHERE e.id!=h.id OR e.src!=h.source";
  $rows = $dbh->selectall_arrayref( $sql );
  foreach my $row ( @{$rows} )
  {
    $self->SetError(sprintf("$table __ Nonmatching id for gid %s__ %s vs %s", $row->[0], $row->[1], $row->[2])) if $row->[1] ne $row->[2];
    # In one unusual case the below can happen: nonmatching sources.
    #$self->SetError(sprintf("$table __ Nonmatching src for gid %s__ %s vs%s", $row->[0], $row->[3], $row->[4])) if $row->[3] ne $row->[4];
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
    $sql = "SELECT id,status FROM $table WHERE expert>0 AND status!=5 AND status!=6";
    $rows = $dbh->selectall_arrayref( $sql );
    foreach my $row ( @{$rows} )
    {
      $self->SetError(sprintf("$table __ bad status for expert-reviewed %s__ '%s'", $row->[0], $row->[1]));
    }
    $sql = "SELECT id,status,gid,SUM(expert) AS ct FROM $table WHERE status=5 OR status=6 GROUP BY gid HAVING ct=0";
    $rows = $dbh->selectall_arrayref( $sql );
    foreach my $row ( @{$rows} )
    {
      $self->SetError(sprintf("$table __ no expert review for status %s %s__ ", $row->[1], $row->[0]));
    }
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
  my $mojibake = '[ÊÃÄÅ¶¹¸©×«»§¼¡±]';
  return ($text =~ m/$mojibake/i);
}

sub ReviewSearchMenu
{
  my $self = shift;
  my $page = shift;
  my $searchName = shift;
  my $searchVal = shift;
  
  my @keys = ('Identifier','Title','Author','PubDate', 'Status','Legacy','UserId','Attribute',  'Reason',       'NoteCategory', 'Priority', 'Validated', 'Swiss');
  my @labs = ('Identifier','Title','Author','Pub Date','Status','Legacy','User',  'Attr Number','Reason Number','Note Category','Priority', 'Verdict', 'Swiss');
  if (!$self->IsUserExpert())
  {
    splice @keys, 12, 1;
    splice @labs, 12, 1;
  }
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
  my $html = "<select name='$searchName' id='$searchName'>\n";
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
               'determinationStats' => 'determinations breakdown'
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

# Returns a reference to an array with (time,status,message)
sub GetSystemStatus
{
  my $self = shift;
  
  my @vals = ('forever','normal','');
  my $sql = 'SELECT time,status,message FROM systemstatus LIMIT 1';
  my $r = $self->get('dbh')->selectall_arrayref($sql);
  my $row = $r->[0];
  if ($row)
  {
    $vals[0] = $self->FormatTime($row->[0]) if $row->[0];
    $vals[1] = $row->[1] if $row->[1];
    $vals[2] = $row->[2] if $row->[2];
    if ($vals[2] eq '')
    {
      if ($vals[1] eq 'down')
      {
        $vals[2] = 'The CRMS is currently unavailable until further notice.';
      }
      elsif ($vals[1] eq 'partial')
      {
        $vals[2] = 'The CRMS has limited functionality. The "review" and "add to queue" (administrators only) pages are currently disabled until further notice.';
      }
    }
  }
  return \@vals;
}

sub SetSystemStatus
{
  my $self   = shift;
  my $status = shift;
  my $msg    = shift;
  
  my $sql = 'DELETE FROM systemstatus';
  $self->PrepareSubmitSql($sql);
  $msg = $self->get('dbh')->quote($msg);
  my $sql = "INSERT INTO systemstatus (status,message) VALUES ('$status',$msg)";
  $self->PrepareSubmitSql($sql);
}

1;
