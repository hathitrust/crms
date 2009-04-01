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

## ----------------------------------------------------------------------------
##  Function:   get a list of new barcodes (mdp.123456789) since a given date
##              1) 008:28 not equal ‘f’
##              2) Select records that meet criteria in (1), and have an mdp id 
##                 in call_no_2, and whose item statistic date is in the range
##                 that Greg requests.  
##              3) record has NOT been sent previously
##  Parameters: date
##  Return:     NOTHING, loads DB
## ----------------------------------------------------------------------------
sub LoadNewItems
{
    my $self    = shift;
    my $start   = shift;
    my $stop    = shift;

    if ( ! $start ) { $start = $self->GetUpdateTime(); }

    my $sql = qq{SELECT CONCAT(namespace, '.', id) AS id, MAX(time) AS time FROM rights } . 
              qq{WHERE attr = 2 AND time >= '$start' AND time <= '$stop' GROUP BY id};

    my $ref = $self->get('sdr_dbh')->selectall_arrayref( $sql );

    if ($self->get('verbose')) { print "found: " .  scalar( @{$ref} ) . ": $sql\n"; }

    ## design note: if these were in the same DB we could just INSERT
    ## into the new table, not SELECT then INSERT
    foreach my $row ( @{$ref} ) { $self->AddItemToQueue( $row->[0], $row->[1], 0 ); }
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

sub AddItemToQueue
{
    my $self    = shift;
    my $id      = shift;
    my $time    = shift;
    my $status  = shift;

    ## skip if $id has been reviewed
    if ( $self->IsItemInReviews( $id ) ) { return; }

    ## pub date between 1923 and 1963
    my $pub = $self->GetPublDate( $id );
    ## confirm date range and add check

    #Only care about items between 1923 and 1963
    if ( ( $pub >= '1923' ) && ( $pub <= '1963' ) )
    {

      ## no gov docs
      if ( $self->IsGovDoc( $id ) ) { $self->Logit( "skip fed doc: $id" ); return; }

      ## check for item, warn if already exists, then update ???
      my $sql = qq{INSERT INTO $CRMSGlobals::queueTable (id, time, status, pub_date) VALUES ('$id', '$time', $status, '$pub')};

      $self->PrepareSubmitSql( $sql );

      #Update the pub date in bibdata
      $self->UpdatePubDate ( $id, $pub );
      
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
##  Parameters: id, user, attr, reason, note, stanford reg. number
##  Return:     1 || 0
## ----------------------------------------------------------------------------
sub SubmitReview
{
    my $self = shift;
    my ($id, $user, $attr, $reason, $copyDate, $note, $regNum, $exp, $regDate, $category) = @_;

    if ( ! $self->ChechForId( $id ) )                     { $self->Logit("id check failed");          return 0; }
    if ( ! $self->CheckReviewer( $user, $exp ) )          { $self->Logit("review check failed");      return 0; }
    if ( ! $self->ValidateAttr( $attr ) )                 { $self->Logit("attr check failed");        return 0; }
    if ( ! $self->ValidateReason( $reason ) )             { $self->Logit("reason check failed");      return 0; }
    if ( ! $self->CheckAttrReasonComb( $attr, $reason ) ) { $self->Logit("attr/reason check failed"); return 0; }

    if ( ! $self->ValidateSubmission($attr, $reason, $note, $regNum, $regDate, $user) ) { return 0; }


    ## do some sort of check for expert submissions

    my @fieldList = ("id", "user", "attr", "reason", "note", "regNum", "regDate", "category");
    my @valueList = ($id,  $user,  $attr,  $reason,  $note,  $regNum,  $regDate, $category);

    if ($exp)      { push(@fieldList, "expert");   push(@valueList, $exp); }
    if ($copyDate) { push(@fieldList, "copyDate"); push(@valueList, $copyDate); }

    my $sql = qq{REPLACE INTO $CRMSGlobals::reviewsTable (} . join(", ", @fieldList) . 
              qq{) VALUES('} . join("', '", @valueList) . qq{')};

    if ( $self->get('verbose') ) { $self->Logit( $sql ); }

    $self->PrepareSubmitSql( $sql );

    if ( $exp ) { $self->RegisterExpertReview( $id );  }
    else        { $self->IncrementStatus( $id, $user, $attr ); }

    $self->EndTimer( $id, $user );
    $self->UnlockItem( $id, $user );

    return 1;
}

## ----------------------------------------------------------------------------
##  Function:   submit historical review  (from excel SS)   
##  Parameters: 
##  Return:     1 || 0
## ----------------------------------------------------------------------------
sub SubmitHistReview
{
    my $self = shift;
    my ($id, $user, $date, $attr, $reason, $cDate, $regNum, $regDate, $note, $eNote, $category) = @_;

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
    my $sql = qq{REPLACE INTO $CRMSGlobals::reviewsTable (id, user, attr, reason, copyDate, regNum, regDate, note, expertNote, hist, category) } .
              qq{VALUES('$id', '$user', '$attr', '$reason', '$cDate', '$regNum', '$regDate', $note, $eNote, 1, '$category') };

    $self->PrepareSubmitSql( $sql );

    return 1;
}

sub DeleteReview
{
    my $self = shift;
    my $id   = shift;
    my $user = shift;

    $self->Logit( "DELETE $id $user" );

    ## remove from review table
    my $sql  = qq{ DELETE FROM $CRMSGlobals::reviewsTable WHERE id = "$id" AND user = "$user" };
    $self->PrepareSubmitSql( $sql );

    ## minus 1 in status for queue, if there are two reviews that agree
    if ( $self->GetDoubleAgree($id) )
    {
        $sql = qq{ UPDATE $CRMSGlobals::queueTable SET status = status - 1 WHERE id = "$id" };
        $self->PrepareSubmitSql( $sql );
    }

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
    my $double = $self->GetDoubleRevItems();  
    foreach my $row ( @{$double} )
    {
        my $id = $row->[0];
        if ( $self->GetDoubleAgree( $id ) ) 
        { 
            push( @{$export}, $id ); 
            $dCount++;
        }
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

    my $user = "crms";
    my $time = $self->GetTodaysDate();
    my $fh   = $self->GetExportFh();
    my $user = "crms";
    my $src  = "null";

    foreach my $barcode ( @{$list} )
    {
        my ($attr,$reason) = $self->GetFinalAttrReason($barcode); 
        if ( ! $attr || ! $reason )
        {
            $self->Logit( "failed to get rights for $barcode on export" );
            next;
        }
        print $fh "$barcode\t$attr\t$reason\t$user\t$src\n";
        ## $self->RemoveFromQueue($barcode); ## DEBUG
    }
    close $fh;
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

    return $fh;
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

sub GetFinalAttrReason
{
    my $self = shift;
    my $id   = shift;

    ## order by expert so that if there is an expert review, return that one
    my $sql = qq{SELECT attr, reason FROM $CRMSGlobals::reviewsTable WHERE id = "$id" } .
              qq{ORDER BY expert DESC};
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
    my $sql  = qq{SELECT id FROM $CRMSGlobals::queueTable WHERE status > 2 AND status < 5 };
    my $ref  = $self->get( 'dbh' )->selectall_arrayref( $sql );

    return $ref;
}

sub GetDoubleRevItems
{
    my $self = shift;
    my $sql  = qq{SELECT id FROM $CRMSGlobals::queueTable WHERE status = 2 };
    my $ref  = $self->get( 'dbh' )->selectall_arrayref( $sql );

    return $ref;
}

sub GetDoubleAgree
{
    my $self = shift;
    my $id   = shift;

    my $sql  = qq{ SELECT id, attr, reason FROM $CRMSGlobals::reviewsTable WHERE id = "$id" }; 
    my $ref  = $self->get( 'dbh' )->selectall_arrayref( $sql );
    
    if ( scalar @{$ref} < 2 ) { return 0; }
    if ( scalar @{$ref} > 2 ) { return 0; }

    ## attr and reason are the same for both
    if ( $ref->[0]->[1] ne $ref->[1]->[1] ||
         $ref->[0]->[2] ne $ref->[1]->[2] )  { return 0; }

    return 1;
}

sub GetUndItems
{
    my $self = shift;
    my $sql  = qq{SELECT id FROM $CRMSGlobals::queueTable WHERE status = 5 };
    my $ref  = $self->get( 'dbh' )->selectall_arrayref( $sql );

    my @ids;
    foreach ( @{$ref} ) { push( @ids, $_->[0]); }

    return @ids;
}

## ----------------------------------------------------------------------------
##  Function:   Get the oldest item, not reviewed twice, not locked
##  Parameters: NOTHING
##  Return:     date
## ----------------------------------------------------------------------------
sub GetOldestItemForReview
{
    my $self = shift;

    my $sql  = qq{ SELECT id FROM $CRMSGlobals::queueTable WHERE locked is NULL AND } . 
               qq{ status < 2 ORDER BY pub_date LIMIT 1 };

    return $self->SimpleSqlGet( $sql );
}

sub RegisterExpertReview
{
    my $self = shift;
    my $id   = shift;

    my $sql  = qq{UPDATE $CRMSGlobals::queueTable SET status = 4 WHERE id = "$id"};

    $self->PrepareSubmitSql( $sql );
}

sub GetReviewsRef
{
    my $self    = shift;
    my $order   = shift;
    my $id      = shift;
    my $user    = shift;
    my $since   = shift;
    my $offset  = shift;
    
    if ( ! $offset ) { $offset = 0; }

    if ( ! $order || $order eq "time" ) { $order = "time DESC "; }

    my $sql = qq{ SELECT id, time, duration, user, attr, reason, note, regNum, expert, copyDate, expertNote, category, hist, regDate, flaged FROM $CRMSGlobals::reviewsTable };

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
        my $item = {
                     id         => $row->[0],
                     time       => $row->[1],
                     duration   => $row->[2],
                     user       => $row->[3],
                     attr       => $self->GetRightsName($row->[4]),
                     reason     => $self->GetReasonName($row->[5]),
                     note       => $row->[6],
                     regNum     => $row->[7],
                     expert     => $row->[8],
                     copyDate   => $row->[9],
                     expertNote => $row->[10],
                     category   => $row->[11],
                     hist       => $row->[12],
                     regDate    => $row->[13],
                     flaged     => $row->[14]
                   };
        push( @{$return}, $item );
    }

    return $return;
}

sub GetReviewsCount
{
    my $self    = shift;
    my $id      = shift;
    my $user    = shift;
    my $since   = shift;

    my $sql = qq{ SELECT count(id) FROM $CRMSGlobals::reviewsTable };

    if    ( $user )                    { $sql .= qq{ WHERE user = "$user" };   }

    if    ( $since && $user )          { $sql .= qq{ AND   time >= "$since"};  }
    elsif ( $since )                   { $sql .= qq{ WHERE time >= "$since" }; }

    if    ( $id && ($user || $since) ) { $sql .= qq{ AND   id = "$id" }; }
    elsif ( $id )                      { $sql .= qq{ WHERE id = "$id" }; }

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

sub DetailInfo
{
    my $self   = shift;
    my $id     = shift;
    my $user   = shift;
    
    my $url  = qq{/cgi/c/crms/crms?p=detailInfo&id=$id&user=$user};

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


sub IncrementStatus
{
    my $self = shift;
    my $id   = shift;
    my $user = shift;
    my $attr = shift;
  
    my ($otherAttr,$r) = $self->GetFinalAttrReason($id);

    ## If this and a previous attr is und (5) - set status to 5
    if ( $attr == 5 && $otherAttr eq "und" ) 
    {
        my $sql = qq{ UPDATE $CRMSGlobals::queueTable SET status = 5 WHERE id = "$id" };
        $self->PrepareSubmitSql( $sql );
        $self->Logit( "$id: two und/nfi reviews, status set to 5" );
    }

    ## if you have reviewed this one, don't increment
    if ( $self->ItemWasReviewedByUser($id, $user) ) { return; }

    my $sql = qq{ UPDATE $CRMSGlobals::queueTable SET status = status + 1 WHERE id = "$id" };
    $self->PrepareSubmitSql( $sql );
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

    my $sql  = qq{SELECT id,name, type FROM $CRMSGlobals::usersTable };
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

sub GetUserTypes
{
    my $self = shift;
    my $name = shift;

    my $sql = qq{SELECT type FROM $CRMSGlobals::usersTable WHERE id = "$name"};
    my $ref = $self->get( 'dbh' )->selectall_arrayref( $sql );

    my @return;
    foreach ( @{$ref} ) { push @return, $_->[0]; }
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

sub ValidateSubmission
{
    my $self = shift;
    my ($attr, $reason, $note, $regNum, $regDate, $user) = @_;
    my $return = 1;

    ## check user
    if ( ! $self->IsUserReviewer( $user ) )
    {
        $self->SetError( "Not a reviewer" );
        $return = 0;
    } 

    if ( ! $attr )   { $self->SetError( "missing rights" ); $return = 0; }
    if ( ! $reason ) { $self->SetError( "missing reason" ); $return = 0; }

    if ( $regNum && ( ! $regDate ) )
    { 
        $self->SetError( "missing renewal date" );
        $return = 0;
    }

    ## if und, must have a commentPre (note)
    if ( $attr == 5 && $note eq "" ) 
    {
        $self->SetError( "comment required for UND" );
        $return = 0;
    }

    ## ic/ren requires a reg number
    if ( $reason == 7 && $attr == 2 && $regNum eq "" ) 
    {
        $self->SetError( "missing renewal ID" );
        $return = 0;
    }

    return $return;
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
    my $record  = $self->GetRecordMetadata($barcode);
    if ( ! $record ) { $self->Logit( "failed in IsGovDoc: $barcode" ); }

    my $xpath   = q{//*[local-name()='controlfield' and @tag='008']};
    my $leader  = $record->findvalue( $xpath );
    my $doc     = substr($leader, 28, 1);
 
    if ( $doc eq "f" ) { return 1; }

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

    my $record  = $self->GetRecordMetadata($barcode);
    if ( ! $record ) { $self->Logit( "failed in GetPublDate: $barcode" ); }

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
    my $self = shift;
    my $id   = shift;

    ## my $ti   = $self->GetMarcDatafield( $id, "245", "a");
    my $ti   = $self->GetRecordTitleBc2Meta( $id );

    my $tiq  = $self->get("dbh")->quote( $ti );

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

    return $ti; 
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

    my $au = $self->GetMarcDatafield( $bar, "100", "a");

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

    $self->UpdateTitle( $barcode );

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

    ## if not in the queue, this is the time to add it.
    if ( ! $self->IsItemInQueue( $id ) )
    {
        $self->AddItemToQueue( $id, $self->GetTodaysDate(), 0 );
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
    my @itemsReviewedOnce = $self->GetItemsReviewedOnce( $name );

    ## if someone have been reviewed once (not by this user) sort by date (oldest first)
    if ( scalar(@itemsReviewedOnce) ) 
    {
        my $sql = qq{ SELECT id FROM $CRMSGlobals::queueTable WHERE locked is NULL AND status < 2 AND ( };
        my $first = pop @itemsReviewedOnce;
        $sql .= qq{ id = "$first" };
        foreach my $bar ( @itemsReviewedOnce ) { $sql .= qq{ OR id = "$bar" }; }
        $sql   .= qq{ ) ORDER BY pub_date LIMIT 1 };

        $barcode = $self->SimpleSqlGet( $sql );
        if ( $self->get("verbose") ) { $self->Logit("once: $sql"); }
    }

    if ( ! $barcode ) 
    {
        my @itemsReviewedByUser = $self->ItemsReviewedByUser( $name );

        ## we might want to change or remove the limit
        my $sql = qq{ SELECT id FROM $CRMSGlobals::queueTable WHERE locked is NULL AND } .
                  qq{ status < 2 ORDER BY pub_date LIMIT 100 };

        my $ref = $self->get( 'dbh' )->selectall_arrayref( $sql );

        foreach my $row ( @{$ref} )
        {
            if ( grep(/$row->[0]/, @itemsReviewedByUser) ) { next; }
            $barcode = $row->[0];
            last;
        }
    }

    ## lock before returning
    if ( ! $self->LockItem( $barcode, $name ) ) 
    { 
        $self->Logit( "failed to lock $barcode for $name" );
        return;
    }
    return $barcode;
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

## ----------------------------------------------------------------------------
##  Function:   get items that have been reviewed once
##  Parameters: 
##  Return:     list of barcodes
## ----------------------------------------------------------------------------
sub GetItemsReviewedOnce
{
    my $self = shift;
    my $name = shift;

    my $sql  = qq{ SELECT id, COUNT(id) FROM $CRMSGlobals::reviewsTable };

    if ( $name ne "" ) 
    { 
        $sql .= qq{ WHERE not(id IN (SELECT id FROM $CRMSGlobals::reviewsTable WHERE user = "$name")) } . 
                qq{ AND hist < 1 };
    }
    else { $sql .= qq{ WHERE hist < 1 }; }
    $sql .= qq{ GROUP BY id }; 

    if ( $self->get("verbose") ) { $self->Logit( "GetItemsReviewedOnce: $sql" ); }

    my $ref  = $self->get( 'dbh' )->selectall_arrayref( $sql );

    my @return;
    foreach (@{$ref}) 
    { 
        my $id = $_->[0];
        my $c  = $_->[1];

        ## make sure status is < 2
        $sql    = qq{SELECT id FROM $CRMSGlobals::queueTable WHERE id = "$id" AND status < 2};

        my $ref = $self->get( 'dbh' )->selectall_arrayref( $sql );
        
        if ($c == 1 and @{$ref}) { push @return, $id; }
    }

    return @return;
}

sub GetItemsInDispute
{
    my $self = shift;

    ## make sure the user is reviewer II ??

    ## rviewed at 2 times, not by an expert
    my $sql = qq{ SELECT id, CONCAT(id, ".", attr) AS a FROM ( SELECT * FROM } .
              qq{ $CRMSGlobals::reviewsTable WHERE id NOT IN ( SELECT id FROM } . 
              qq{ $CRMSGlobals::reviewsTable WHERE expert IS NOT NULL ) ) AS t1 GROUP BY a};
 
    my $ref = $self->get( 'dbh' )->selectall_arrayref( $sql );

    my %ids;
    foreach ( @{$ref} ) { $ids{$_->[0]}++; }

    my @return;
    foreach my $id ( keys %ids ) { if ( $ids{$id} > 1 ) { push @return, $id; } }

    return @return;
}

sub GetItemReviewDetails
{
    my $self = shift;
    my $id   = shift;
    my $user = shift;

    my $sql  = qq{ SELECT attr, reason, regNum, note FROM reviews WHERE id = "$id"};

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
##  Function:   get regNum (stanford reg num)
##  Parameters: id
##  Return:     regNum
## ----------------------------------------------------------------------------
sub GetRegNum
{
    my $self = shift;
    my $id   = shift;
    my $user = shift;
    my $sql  = qq{ SELECT regNum FROM $CRMSGlobals::reviewsTable WHERE id = "$id" AND user = "$user"};

    if ( ! $self->IsUserExpert($user) ) { $sql .= qq{ AND user = "$user"}; }

    return $self->SimpleSqlGet( $sql );
}

sub GetRegNums
{   
    my $self = shift;
    my $id   = shift;
    my $user = shift;

    my $sql  = qq{SELECT regNum FROM $CRMSGlobals::reviewsTable WHERE id = "$id" };

    ## if not expert, limit to just that users regNums
    if ( ! $self->IsUserExpert($user) ) { $sql .= qq{ AND user = "$user"}; }

    my $ref  = $self->get( 'dbh' )->selectall_arrayref( $sql );

    my @return;
    foreach ( @{$ref} ) { if ($_->[0] ne "") { push @return, $_->[0]; } }
    return @return;
}

sub GetRegDate
{
    my $self = shift;
    my $id   = shift;
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

1;

