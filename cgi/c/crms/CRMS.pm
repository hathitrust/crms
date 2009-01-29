package CRMS;

## ----------------------------------------------------------------------------
## Object of shared code for the CRMS DB CGI and BIN scripts
##
## ----------------------------------------------------------------------------

use strict;
use LWP::UserAgent;
use XML::LibXML;
use XML::LibXSLT;
use POSIX qw(strftime);
use DBI qw(:sql_types);

=head1 NAME

CRMS -- object of shared code

=cut

=head1 new()

  my $crms = CRMS->new(
    logFile      =>   'log.txt',
    configFile   =>   'crms.cfg',
    verbose      =>   1,
    root         =>   $DLXSROOT,
    dev          =>   $DLPS_DEV,
 );

=cut

## ----------------------------------------------------------------------------
##  Function:   new() for object
##  Parameters: %hash with a bunch of args
##  Return:     ref to object
## ----------------------------------------------------------------------------
sub new {
    my ($class, %args) = @_;
    my $self = bless {}, $class;

    if ( ! $args{'logFile'} )    { return "missing log file"; }
    if ( ! $args{'configFile'} ) { return "missing configFile"; }

    $self->set( 'logFile', $args{'logFile'} );
    ## $self->OpenErrorLog();

    my $errors = [];
    $self->set( 'errors', $errors );

    require $args{'configFile'};

    $self->set( '$bc2metaUrl', q{http://mirlyn.lib.umich.edu/cgi-bin/bc2meta} );
    $self->set( '$oaiBaseUrl', q{http://mirlyn.lib.umich.edu/OAI} );
    $self->set( 'verbose',     $args{'verbose'} );
    $self->set( 'parser',      XML::LibXML->new() );
    $self->set( 'barcodeID',   {} );
 
    $self->set( 'root',        $args{'root'} );
    $self->set( 'dev',         $args{'dev'} );

    $self->set( 'dbh',         $self->ConnectToDb() );
    $self->set( 'sdr_dbh',     $self->ConnectToSdrDb() );

    $self;
}

=head1 LoadNewItems()

LoadNewItems will load the new or changed records from the right DB and will load them into the CRMS reviewer queue.

    $crms->LoadNewItems( "2009-01-01 10:31:17" );

=cut

## ----------------------------------------------------------------------------
##  Function:   get a list of new barcodes (mdp.123456789) since a given date
##              1) 008:28 not equal ‘f’
##              2) Select records that meet criteria in (1), and have an mdp id 
##                 in call_no_2, and whose item statistic date is in the range
##                 that Greg requests.  Also, I check to see if the record has
##                 been sent previously -- if so, it’s exclud
##  Parameters: date
##  Return:     NOTHING, loads DB
## ----------------------------------------------------------------------------
sub LoadNewItems				## date
{
    my $self    = shift;
    my $update  = shift;
    my $dbh     = $self->get( 'dbh' );
    my $sdr_dbh = $self->get( 'sdr_dbh' );

    if ( ! $update ) { $update = $self->GetUpdateTime(); }

    my $sql = qq{SELECT CONCAT(namespace, '.', id) AS id, MAX(time) AS time FROM rights } . 
              qq{WHERE attr = 2 AND time >= '$update' GROUP BY id};

    my $ref = $sdr_dbh->selectall_arrayref( $sql );

    if ($self->get('verbose')) { print "found: " .  scalar( @{$ref} ) . ": $sql\n"; }

    ## design note: if these were in the same DB we could just INSERT
    ## into the new table, not SELECT then INSERT
    foreach my $row ( @{$ref} )
    {
        my $id      = $row->[0];
        my $time    = $row->[1];

        my $fedDoc  = $self->IsGovDoc( $id );
        if ( $fedDoc ) { $self->logit( "skip fed doc: $id" ); next; }

        my $pub     = $self->GetPublDate( $id );

        ## check for item, warn if already exists, then update ???
        my $iSql = qq{REPLACE INTO $CRMSGlobals::queueTable (id, time, pub_date) VALUES ('$id', '$time', '$pub')};

        $self->PrepareSubmitSql( $iSql );
    }
}

=head1 SubmitReview

  $crms->SubmitReview( id, user, attr, reason, note, stanford reg. number );

=cut

## ----------------------------------------------------------------------------
##  Function:   submit review
##  Parameters: id, user, attr, reason, note, stanford reg. number
##  Return:     1 || 0
## ----------------------------------------------------------------------------
sub SubmitReview
{
    my $self = shift;
    my ($id, $user, $attr, $reason, $date, $cDate, $note, $reg, $exp) = @_;

    if ( ! $self->ChechForId( $id ) )                { $self->logit("id check failed");          return 0; }
    if ( ! $self->ChechReviewer( $user, $exp ) )     { $self->logit("review check failed");      return 0; }
    if ( ! $self->ValidateAttr( $attr ) )            { $self->logit("attr check failed");        return 0; }
    if ( ! $self->ValidateReason( $reason ) )        { $self->logit("reason check failed");      return 0; }
    if ( ! $self->AttrReasonComb( $attr, $reason ) ) { $self->logit("attr/reason check failed"); return 0; }

    ## do some sort of check for expert submissions

    ## make sure this user did not already check this item
    if ( ! $self->ValidateSubmition( $id, $user ) ) { $self->logit("submit check failed"); return 0; }
   
    ## all good, INSERT
    my $sql = qq{INSERT INTO $CRMSGlobals::reviewsTable (id, user, attr, reason, date, cDate, note, regNum) } . 
              qq{VALUES('$id', '$user', '$attr', '$reason', '$date', '$cDate', '$note', '$reg') };

    if ( $exp )
    {
        $sql = qq{REPLACE INTO $CRMSGlobals::reviewsTable (id, user, attr, reason, date, cDate, note, regNum, expert) } .
              qq{VALUES('$id', '$user', '$attr', '$reason', '$date', '$cDate', '$note', '$reg', $exp) };
    }

    $self->PrepareSubmitSql( $sql );

    if ( $exp ) { $self->RegisterExpertReview( $id ); }
    else        { $self->IncrementStatus( $id );      }
    $self->UnlockItem( $id );
    $self->EndTimer( $id, $user );

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
    my ($id, $user, $date, $attr, $reason, $date, $cDate, $regNum, $regDate, $note, $eNote) = @_;

    ## change attr and reason back to numbers
    $attr   = $self->GetRightsNum( $attr );
    $reason = $self->GetReasonNum( $reason );

    if ( ! $self->ValidateAttr( $attr ) )            { $self->logit("attr check failed");        return 0; }
    if ( ! $self->ValidateReason( $reason ) )        { $self->logit("reason check failed");      return 0; }
    if ( ! $self->AttrReasonComb( $attr, $reason ) ) { $self->logit("attr/reason check failed"); return 0; }
    
    ## do some sort of check for expert submissions

    ## make sure this user did not already check this item
    if ( ! $self->ValidateSubmition( $id, $user ) ) { $self->logit("submit check failed"); return 0; }

    ## all good, INSERT
    my $sql = qq{INSERT INTO $CRMSGlobals::reviewsTable (id, user, attr, reason, date, cDate, regNum, regDate, note, expertNote, hist) } .
              qq{VALUES('$id', '$user', '$attr', '$reason', '$date', '$cDate', '$regNum', '$regDate', '$note', '$eNote', 1) };

    $self->PrepareSubmitSql( $sql );

    return 1;
}

sub DeleteReview
{
    my $self = shift;
    my $id   = shift;
    my $user = shift;

    $self->logit( "DELETE $id $user" );

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

sub ClearQueue
{
    my $self = shift;

    ## get items > 2, clear these  
    my @experts;
    my $expert = $self->GetExpertRevItems();

    foreach my $row ( @{$expert} )
    {
        my $id = $row->[0];
        push @experts, $id;
        ## $self->DelFromQueue( $id );
    }

    ## get items = 2 and see if they agree  
    my $doubles = $self->GetDoubleRevItems();  
    my @doubles;
    foreach my $row ( @{$doubles} )
    {
        my $id = $row->[0];
        if ( $self->GetDoubleAgree( $id ) ) 
        { 
            push @doubles, $id;
            ## $self->DelFromQueue( $id ); 
        }
    }

    ## report back
    my $eCount = scalar( @experts );
    $self->logit( "export reviewed items removed from queue ($eCount): " . join(", ", @experts) );
    my $dCount = scalar( @doubles );
    $self->logit( "double reviewed items removed from queue ($dCount): " . join(", ", @doubles) );

    return ("Double reviewed items removed from queue: $dCount",
            "Expert Items removed from queue: $eCount");
}

sub DelFromQueue
{
    my $self = shift;
    my $id   = shift;

    if ( ! $id ) { return 0; }
    my $sql  = qq{DELETE FROM $CRMSGlobals::queueTable  WHERE id = "$id"};

    $self->PrepareSubmitSql( $sql );
    return 1;
}

sub GetExpertRevItems
{
    my $self = shift;
    my $sql  = qq{SELECT id FROM $CRMSGlobals::queueTable WHERE status > 2 };
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

sub RegisterExpertReview
{
    my $self = shift;
    my $id   = shift;

    my $sql  = qq{UPDATE $CRMSGlobals::queueTable SET status = 4 WHERE id = "$id"};

    $self->PrepareSubmitSql( $sql );
}

sub GetReviewsHtml
{
    my $self    = shift;
    my $order   = shift;
    my $id      = shift;
    my $user    = shift;
    my $since   = shift;

    if ( $order eq "" )     { $order = "id"; }
    if ( $order eq "time" ) { $order = "time DESC "; }

    my $sql = qq{ SELECT id, time, user, attr, reason, note, regNum, expert, duration FROM $CRMSGlobals::reviewsTable };

    if    ( $user )                    { $sql .= qq{ WHERE user = "$user" };   }

    if    ( $since && $user )          { $sql .= qq{ AND   time >= "$since"};  }
    elsif ( $since )                   { $sql .= qq{ WHERE time >= "$since" }; }

    if    ( $id && ($user || $since) ) { $sql .= qq{ AND   id = "$id" }; }
    elsif ( $id )                      { $sql .= qq{ WHERE id = "$id" }; }

    $sql .= qq{ ORDER BY $order LIMIT 100 };

    my $ref = $self->get( 'dbh' )->selectall_arrayref( $sql );

    my $html = qq{<table class="allReviews">};
    $html   .= qq{<th>id</th><th>time</th><th>user</th><th>attr</th><th>reason</th><th>note</th><th>reg num</th>
                  <th>expert review</th><th>time taken</th><th>delete (be sure, no undo)</th>};

    foreach my $row ( @{$ref} )
    {
        $html .= qq{<tr><td>} . 
                    $self->LinkToPT($row->[0])       . qq{</td><td>$row->[1]</td><td>$row->[2]</td><td> }.
                    $self->GetRightsName($row->[3])  . qq{</td><td>} . 
                    $self->GetReasonName($row->[4])  . qq{</td><td>$row->[5]</td><td> } .
                    $self->LinkToStanford($row->[6]) . qq{</td><td>$row->[7]</td><td>$row->[8]</td><td>} .
                    $self->GetDeleteLink($row->[0], $row->[2])  . qq{</td></tr>};
    }

    $html .= qq{</table>};

    return $html;
}

sub GetDeleteLink
{
    my $self = shift;
    my $id   = shift;
    my $user = shift;

    return  qq{<a href="/cgi/c/crms/submitReview?barcode=$id&user=$user&delete=1">delete this review</a>};
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
    
    ## my $url  = 'http://babel.hathitrust.org/cgi/pt?attr=1&id=';
    my $url  = 'https://santelli.dev.umdl.umich.edu/cgi/m/mdp/pt?skin=crms;attr=1;id=';

    return qq{<a href="$url$id">$id</a>};
}

sub IncrementStatus
{
    my $self = shift;
    my $id   = shift;

    my $sql = qq{ UPDATE $CRMSGlobals::queueTable SET status = status + 1 WHERE id = "$id" };
    $self->PrepareSubmitSql( $sql );
}

sub AttrReasonComb
{
    my $self   = shift;
    my $attr   = shift;
    my $reason = shift;
 
    ## pd/ncn, pd/ren, ic/ren, pd/cdpp, ic/cdpp, und/nfi

}

sub ValidateSubmition
{
    my $self = shift;
    my $id   = shift;
    my $user = shift;
    my $dbh  = $self->get( 'dbh' );

    ## if user is expert, just return 1
    if ( $self->IsUserExpert($user) ) { return 1; }

    my $sql  = qq{SELECT id FROM $CRMSGlobals::reviewsTable WHERE id = '$id' AND user = '$user'};
    my @rows = $dbh->selectrow_array( $sql );
    
    if ( scalar( @rows ) ) { return 0; }
    return 1;
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

    ## maybe check the status or locked  (TODO)
}

sub ChechReviewer
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
    my $dbh  = $self->get( 'dbh' );

    my $sql  = qq{SELECT name FROM $CRMSGlobals::usersTable WHERE id = '$user' LIMIT 1};
    my $ref  = $dbh->selectall_arrayref( $sql );
    my $name = $ref->[0]->[0];

    if ( $name ne "" ) { return $name; }

    return "Unknown";
}

sub IsUserExpert
{
    my $self = shift;
    my $user = shift;

    my $sql  = qq{ SELECT name FROM $CRMSGlobals::usersTable WHERE id = '$user' AND type = 2 };
    my $ref  = $self->get( 'dbh' )->selectall_arrayref( $sql );

    if ( scalar @{$ref} ) { return 1; }

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

    my %return;
    foreach my $r ( @{$ref} )
    {
       $return{$r->[0]} = {'name'  => $r->[1], 
                           'types' => $userTypes{$r->[0]}};
    }

    return %return;
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

    if ( $args->{'reviewer'} ) { $self->AddUserReviewer( $sql ); }
    if ( $args->{'expert'} )   { $self->AddUserExpert( $sql );   }
    if ( $args->{'admin'} )    { $self->AddUserAdmin( $sql );    }

    return 1;
}

sub AddUserReviewer
{
    my $self = shift;
    my $sql  = shift;
    $sql    .= qq{, type = 1};

    $self->PrepareSubmitSql( $sql );
}

sub AddUserExpert
{
    my $self = shift;
    my $sql  = shift;
    $sql    .= qq{, type = 2};

    $self->PrepareSubmitSql( $sql );
}

sub AddUserAdmin
{
    my $self = shift;
    my $sql  = shift;
    $sql    .= qq{, type = 3};

    $self->PrepareSubmitSql( $sql );
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
    return 0;
}

sub PrepareSubmitSql
{
    my $self = shift;
    my $sql  = shift;

    my $sth = $self->get( 'dbh' )->prepare( $sql );
    eval { $sth->execute(); };
    if ($@) { $self->logit("sql failed ($sql): " . $sth->errstr); }
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

## ----------------------------------------------------------------------------
##  Function:   connect to the mysql DB
##  Parameters: nothing
##  Return:     ref to DBI
## ----------------------------------------------------------------------------
sub ConnectToDb                         ## NOTHING || ref to DB
{
    my $self      = shift;
    my $db_user   = $CRMSGlobals::mysqlUser;
    my $db_passwd = $CRMSGlobals::mysqlPasswd;
    my $db_server = $CRMSGlobals::mysqlServerDev;

    if ( ! $self->get( 'dev' ) ) { $db_server = $CRMSGlobals::mysqlServer; }

    if ($self->get('verbose')) { $self->logit( "DBI:mysql:crms:$db_server, $db_user, [passwd]" ); }

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
sub ConnectToSdrDb                      ## NOTHING || ref to DB
{
    my $self      = shift;
    my $db_user   = $CRMSGlobals::mysqlMdpUser;
    my $db_passwd = $CRMSGlobals::mysqlMdpPasswd;
    my $db_server = $CRMSGlobals::mysqlMdpServerDev;

    if ( ! $self->get( 'dev' ) ) { $db_server = $CRMSGlobals::mysqlServer; }

    if ($self->get('verbose')) { $self->logit( "DBI:mysql:mdp:$db_server, $db_user, [passwd]" ); }

    my $sdr_dbh   = DBI->connect( "DBI:mysql:mdp:$db_server", $db_user, $db_passwd,
              { RaiseError => 1, AutoCommit => 1 } ) || die "Cannot connect: $DBI::errstr";

    $sdr_dbh->{mysql_auto_reconnect} = 1;

    return $sdr_dbh;
}

sub IsGovDoc
{
    my $self    = shift;
    my $barcode = shift;
    my $record  = $self->GetRecordMetadata($barcode);
    my $xpath   = q{//*[local-name()='controlfield' and @tag='008']};
    my $leader  = $record->findvalue( $xpath );
    my $doc     = substr($leader, 28, 1);
 
    if ( $doc eq "f" ) { return 1; }

    return 0;
}

=head1 GetPublDate

Get the publ date for a given barcode
  
  $crms->GetPublDate( "mdp.123456789" );

=cut

## ----------------------------------------------------------------------------
##  Function:   get the publ date (260|c)for a specific vol.
##  Parameters: barcode
##  Return:     date string
## ----------------------------------------------------------------------------
sub GetPublDate				## barcode || publ date
{
    my $self    = shift;
    my $barcode = shift;
    my $record  = $self->GetRecordMetadata($barcode);
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
    my $xpath   = qq{//*[local-name()='datafield' and \@tag='$field']} .
                   qq{/*[local-name()='subfield'  and \@code='$code']};

    return $record->findvalue( $xpath );
}

=head1 GetRecordMetadata

Get the MARC21 metadata for a given record

  $crms->GetRecordMetadata( "mdp.123456789" );

=cut

## ----------------------------------------------------------------------------
##  Function:   get the metadata record (MARC21)
##  Parameters: barcode
##  Return:     XML::LibXML record doc
## ----------------------------------------------------------------------------
sub GetRecordMetadataOai
{
    my $self       = shift;
    my $bar        = shift;
    my $oaiBaseUrl = $self->get( 'oaiBaseUrl' );
    my $parser     = $self->get( 'parser' );
    
    my $id     = $self->BarcodeToId( $bar );
    my $format = "marc21";
    my $record;

    my $url = $oaiBaseUrl . "?verb=GetRecord&metadataPrefix=" . 
              $format  . "&identifier=oai:" . $CRMSGLobals::oaiHost_prod . ":$id";

    my $ua = LWP::UserAgent->new;
    $ua->timeout( 1000 ); ## # of seconds
    my $req = HTTP::Request->new( GET => $url );
    my $res = $ua->request( $req );

    if ( ! $res->is_success) 
    { 
        $self->logit( "Request failed: $url " . $res->message() ); 
        return; 
    }

    my $source;
    eval { $source = $parser->parse_string( $res->content() ); };
    if ($@) { $self->logit( "failed to parse response:$@" ); return; }

    my $errorCode = $source->findvalue( "//*[name()='error']" );
    if ( $errorCode ne "" )
    {
        $self->logit( "$url \nfailed to get $format for $id: $errorCode " . $res->content() );
        return;
    }

    ($record) = $source->findnodes( "//*[name()='record']" );

    return $record;
}

sub GetRecordMetadataBc2Meta
{
    my $self       = shift;
    my $barcode    = shift;

    ## get from object if we have it
    if ( $self->get( 'marcData' ) ne "" ) { return $self->get( 'marcData' ); }

    my $parser = $self->get( 'parser' );
    my $url    = $CRMSGlobals::bc2metaUrl . "?id=$barcode";;
    my $ua     = LWP::UserAgent->new;

    $ua->timeout( 1000 );
    my $req = HTTP::Request->new( GET => $url );
    my $res = $ua->request( $req );

    if ( ! $res->is_success ) { $self->logit( "$url failed: ".$res->message() ); return; }

    my $source;
    eval { $source = $parser->parse_string( $res->content() ); };
    if ($@) { $self->logit( "failed to parse response:$@" ); return; }

    my $errorCode = $source->findvalue( "//*[name()='error']" );
    if ( $errorCode ne "" )
    {
        $self->logit( "$url \nfailed to get MARC for $barcode: $errorCode " . $res->content() );
        return;
    }

    my ($record) = $source->findnodes( "//record" );
    $self->set( 'marcData', $record );

    return $record;
}

sub GetRecordMetadata
{
    my $self       = shift;
    my $barcode    = shift;
    my $parser     = $self->get( 'parser' );
    
    if ( ! $barcode ) { $self->logit( "no barcode given: $barcode" ); }

    my ($ns,$bar)  = split(/\./, $barcode);

    ## get from object if we have it
    if ( $self->get( 'marcData' ) ne "" ) { return $self->get( 'marcData' ); }

    ## my $sysId = $slef->BarcodeToId( $barcode );
    ## my $url   = "http://mirlyn.lib.umich.edu/cgi-bin/api/marc.xml/uid/$sysId";
    my $url    = "http://mirlyn.lib.umich.edu/cgi-bin/api_josh/marc.xml/itemid/$bar";
    my $ua     = LWP::UserAgent->new;

    $ua->timeout( 1000 );
    my $req = HTTP::Request->new( GET => $url );
    my $res = $ua->request( $req );

    if ( ! $res->is_success ) { $self->logit( "$url failed: ".$res->message() ); return; }

    my $source;
    eval { $source = $parser->parse_string( $res->content() ); };
    if ($@) { $self->logit( "failed to parse ($url):$@" ); return; }

    my $errorCode = $source->findvalue( "//*[name()='error']" );
    if ( $errorCode ne "" )
    {
        $self->logit( "$url \nfailed to get MARC for $barcode: $errorCode " . $res->content() );
        return;
    }

    my ($record) = $source->findnodes( "//record" );
    $self->set( 'marcData', $record );

    return $record;
}

## ----------------------------------------------------------------------------
##  Function:   get the mirlyn ID for a given barcode
##  Parameters: barcode
##  Return:     ID
## ----------------------------------------------------------------------------
sub BarcodeToId                         ## barcode || ID
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

    if ( ! $res->is_success ) { $self->logit( "$url failed: ".$res->message() ); return; }

    $res->content =~ m,<doc_number>\s*(\d+)\s*</doc_number>,s;
    my $id = $1;
    if ( $id eq "" ) { return; }  ## error or not found
    $id = "MIU01-" . $id;

    $barcodeID->{$barcode} = $id;   ## put into cache
    return $id;
}

## ----------------------------------------------------------------------------
##  Function:   get a list of user types
##  Parameters: user name
##  Return:     list of user types
## ----------------------------------------------------------------------------
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

sub HasLockedItem
{
    my $self = shift;
    my $name = shift;
    
    my $sql = qq{SELECT id FROM $CRMSGlobals::queueTable WHERE locked = "$name" LIMIT 1};
    my $ref = $self->get( 'dbh' )->selectall_arrayref( $sql );

    if ( scalar @{$ref} ) { return 1; }
    else                  { return 0; }
}

sub GetLockedItem
{
    my $self = shift;
    my $name = shift;

    my $sql = qq{SELECT id FROM $CRMSGlobals::queueTable WHERE locked = "$name" LIMIT 1};
    my $ref = $self->get( 'dbh' )->selectall_arrayref( $sql );

    $self->logit( "Get locked item for $name: $ref->[0]->[0]" ); 

    return $ref->[0]->[0];
}

sub IsLocked
{
    my $self = shift;
    my $id   = shift;

    my $sql = qq{SELECT id FROM $CRMSGlobals::queueTable WHERE locked IS NOT NULL AND id = "$id"};
    my $ref = $self->get( 'dbh' )->selectall_arrayref( $sql );

    if ( scalar @{$ref} ) { return 1; }
    else                  { return 0; }
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
        ## use has something locked already
        ## add some error handling
        return 0; 
    }

    my $sql  = qq{UPDATE queue SET locked = "$name" WHERE id = "$id"};
    my $sth  = $self->get( 'dbh' )->prepare( $sql ) or return 0;

    $sth->execute or return 0;

    $self->StartTimer( $id, $name );
    return 1;
}

sub UnlockItem
{
    my $self = shift;
    my $id   = shift;

    if ( ! $self->IsLocked( $id ) ) { return 0; }

    my $sql  = qq{UPDATE queue SET locked = NULL  WHERE id = "$id"};
    my $sth  = $self->get( 'dbh' )->prepare( $sql ) or return 0;

    $sth->execute or return 0;

    ## $self->EndTimer( $id, $name );
    $self->logit( "unlocking $id" );
}

sub StartTimer
{
    my $self = shift;
    my $id   = shift;
    my $user = shift;    
    
    my $sql  = qq{ REPLACE INTO timer SET start_time = NOW(), id = "$id", user = "$user" };
    my $sth  = $self->get( 'dbh' )->prepare( $sql ) or return 0;

    $sth->execute or return 0;

    $self->logit( "start timer for $id, $user" );
}

sub EndTimer
{
    my $self = shift;
    my $id   = shift;
    my $user = shift;    

    my $sql  = qq{ UPDATE timer SET end_time = NOW() WHERE id = "$id" and user = "$user" };
    my $sth  = $self->get( 'dbh' )->prepare( $sql ) or return 0;

    $sth->execute or return 0;

    ## OK, add duration to reviews table
    $self->SetDuration( $id, $user );

    $self->logit( "end timer for $id, $user" );
}

sub SetDuration
{
    my $self = shift;
    my $id   = shift;
    my $user = shift;


    my $sql = qq{ SELECT TIMEDIFF((SELECT end_time    FROM timer where id = "$id" and user = "$user"), 
                                   (SELECT start_time FROM timer where id = "$id" and user = "$user")) };

    my $ref = $self->get( 'dbh' )->selectall_arrayref( $sql );
    my $dur = $ref->[0]->[0];

    if ( ! $dur ) { return; }

    ## insert time
    $sql = qq{ UPDATE $CRMSGlobals::reviewsTable SET duration = "$dur" WHERE user = "$user" AND id = "$id" };

    $self->PrepareSubmitSql( $sql );
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

    ## if some have been reviewed once (not by this user) sort by date (oldest first)
    if ( scalar(@itemsReviewedOnce) ) 
    {
        my $sql = qq{ SELECT id FROM $CRMSGlobals::queueTable WHERE locked is NULL AND status < 2 AND ( };
        my $first = pop @itemsReviewedOnce;
        $sql .= qq{ id = "$first" };
        foreach my $bar ( @itemsReviewedOnce ) { $sql .= qq{ OR id = "$bar" }; }
        $sql   .= qq{ ) ORDER BY pub_date LIMIT 1 };

        my $ref  = $self->get( 'dbh' )->selectall_arrayref( $sql );
        $barcode = $ref->[0]->[0];
    }
    else
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
        $self->logit( "failed to lock $barcode for $name" );
        return;
    }
    return $barcode;
}

sub ItemsReviewedByUser
{
    my $self = shift;
    my $name = shift;

    my $sql .= qq{ SELECT id FROM $CRMSGlobals::reviewsTable WHERE user = "$name" GROUP BY id };

    my $ref  = $self->get( 'dbh' )->selectall_arrayref( $sql );

    my @return;
    foreach (@{$ref}) { push @return, $_->[0]; }
    return @return;
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

    ## $self->logit( "GetItemsReviewedOnce: $sql" );

    my $ref  = $self->get( 'dbh' )->selectall_arrayref( $sql );

    my @return;
    foreach (@{$ref}) 
    { 
        if ($_->[1] == 1) { push @return, $_->[0]; }
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

    my $sql  = qq{ SELECT attr, reason, regNum, note FROM reviews WHERE id = "$id"};
    my $ref  = $self->get( 'dbh' )->selectall_arrayref( $sql );

    my @return;
    foreach my $r ( @{$ref} ) 
    { 
        my $str = $self->GetRightsName($r->[0]) ."/". $self->GetReasonName($r->[1]) .", $r->[2]"; 
        if ($r->[3]) { $str .= ", $r->[3]"; }
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
    my $ref  = $self->get( 'sdr_dbh' )->selectall_arrayref( $sql );

    return $ref->[0]->[0];
}

sub GetReasonName
{
    my $self = shift;
    my $id   = shift;
    my $sql  = qq{ SELECT name FROM reasons WHERE id = "$id" };
    my $ref  = $self->get( 'sdr_dbh' )->selectall_arrayref( $sql );

    return $ref->[0]->[0];
}

sub GetRightsNum
{
    my $self = shift;
    my $id   = shift;
    my $sql  = qq{ SELECT id FROM attributes WHERE name = "$id" };
    my $ref  = $self->get( 'sdr_dbh' )->selectall_arrayref( $sql );

    return $ref->[0]->[0];
}

sub GetReasonNum
{
    my $self = shift;
    my $id   = shift;
    my $sql  = qq{ SELECT id FROM reasons WHERE name = "$id" };
    my $ref  = $self->get( 'sdr_dbh' )->selectall_arrayref( $sql );

    return $ref->[0]->[0];
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
    
    my $sql  = qq{ SELECT regNum FROM $CRMSGlobals::reviewsTable WHERE id = "$id" AND regNum IS NOT NULL};
    my $ref  = $self->get( 'dbh' )->selectall_arrayref( $sql );

    return $ref->[0]->[0];
}

sub GetRegDate
{
    my $self = shift;
    my $id   = shift;

    my $sql  = qq{ SELECT DREG FROM stanford WHERE ID = "$id" };
    my $ref  = $self->get( 'dbh' )->selectall_arrayref( $sql );

    return $ref->[0]->[0];
}

sub NormalizeRenewalId
{
    my $self = shift;
    my $id   = shift;

    if ( $id eq "" ) { return; }

    my $sql = qq{ SELECT regNum FROM $CRMSGlobals::reviewsTable WHERE id = "$id" };
    my $ref = $self->get( 'dbh' )->selectall_arrayref( $sql );
    my $reg = $ref->[0]->[0];

    if ( $reg eq "" ) { return; }

    my ($let, $num) = $reg =~ m/([a-z]+)([0-9]+)/i;

    if ( length($let) == 2 ) { return $let . sprintf( "%010d", $num ); }
    else                     { return $let . sprintf( "%9d",  $num ); }
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

    my $ref  = $self->get( 'dbh' )->selectall_arrayref( $sql );
    return $ref->[0]->[0];
}

## ----------------------------------------------------------------------------
##  Function:   get the latest time from the queue
##  Parameters: NOTHING
##  Return:     date
## ----------------------------------------------------------------------------
sub GetUpdateTime			## NOTHING || date
{
    my $self = shift;
    my $dbh  = $self->get( 'dbh' );

    my $sql = qq{SELECT MAX(time) FROM $CRMSGlobals::queueTable LIMIT 1};
    my @ref = $dbh->selectrow_array( $sql );
    return $ref[0] || '2000-01-01';
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

## ----------------------------------------------------------------------------
##  Function:   open a file 
##  Parameters: full path to log file
##  Return:     file handle to open file
## ----------------------------------------------------------------------------
sub OpenErrorLog                        ## full path to file || file handle
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

## ----------------------------------------------------------------------------
##  Function:   write to the log file
##  Parameters: STRING to log
##  Return:     NOTHING 
## ----------------------------------------------------------------------------
sub logit                               ## STRING (to be loged) 
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
##              $self->setError( "foo" );
##              my $r = $self->getErrors();
##              if ( defined $r ) { $self->logit( join(", ", @{$r}) ); }
##  Parameters: 
##  Return:     
## ----------------------------------------------------------------------------
sub setError
{
    my $self   = shift;
    my $error  = shift;
    my $errors = $self->get( 'errors' );
    push @{$errors}, $error;
}

sub getErrors
{
    my $self = shift;
    return $self->get( 'errors' );
}

## ----------------------------------------------------------------------------
##  Function:   object setter and getter
##  Parameters: 
##  Return:     
## ----------------------------------------------------------------------------
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

1;
