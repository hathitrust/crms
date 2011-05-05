package CRMS;

## ----------------------------------------------------------------------------
## Object of shared code for the CRMS DB CGI and BIN scripts
##
## ----------------------------------------------------------------------------

#use warnings;
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
use JSON::XS;

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
  $self->set( 'verbose',    $args{'verbose'});
  $self->set( 'root',       $args{'root'} );
  $self->set( 'dev',        $args{'dev'} );
  $self->set( 'user',       $args{'user'} );
  $self->set( 'dbh',        $self->ConnectToDb() );
  return $self;
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
  my $db        = 'crms';
  my $dev       = $self->get('dev');

  if ( !$dev )
  {
    $db_server = $CRMSGlobals::mysqlServer;
  }
  elsif ($dev eq 'crmstest')
  {
    $db = 'crmstest';
    $CRMSGlobals::queueSize = 1000;
  }
  if ($self->get('verbose')) { $self->Logit( "DBI:mysql:crms:$db_server, $db_user, [passwd]" ); }

  my $dbh = DBI->connect( "DBI:mysql:$db:$db_server", $db_user, $db_passwd,
            { RaiseError => 1, AutoCommit => 1 } ) || die "Cannot connect: $DBI::errstr";
  $dbh->{mysql_enable_utf8} = 1;
  $dbh->{mysql_auto_reconnect} = 1;
  my $sql = "SET NAMES 'utf8';";
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

# Gets cached dbh, or connects if no connection is made yet.
sub GetSdrDb
{
  my $self = shift;
  
  my $sdr_dbh = $self->get('sdr_dbh');
  if (!$sdr_dbh)
  {
    $sdr_dbh = $self->ConnectToSdrDb();
    $self->set('sdr_dbh', $sdr_dbh);
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
    return 0;
  }
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


sub GetCandidatesSize
{
  my $self = shift;

  return $self->SimpleSqlGet('SELECT count(*) FROM candidates');
}


sub ProcessReviews
{
  my $self = shift;

  my %stati = (2=>0,3=>0,4=>0,8=>0);
  my $dbh = $self->get( 'dbh' );
  my $sql = 'SELECT id FROM reviews WHERE id IN (SELECT id FROM queue WHERE status=0) GROUP BY id HAVING count(*) = 2';
  my $ref = $dbh->selectall_arrayref( $sql );
  # Get the underlying system status, ignoring replication delays.
  my $stat = @{$self->GetSystemStatus(1)}->[1];
  foreach my $row ( @{$ref} )
  {
    my $id = $row->[0];
    my $data = $self->CalcStatus($id, $stat);
    my $status = $data->{'status'};
    next unless $status > 0;
    my $hold = $data->{'hold'};
    if ($hold)
    {
      print "Not processing $id for $hold: it is held; system status is '$stat'\n" if $stat ne 'normal';
      next;
    }
    if ($status == 8)
    {
      my $attr = $data->{'attr'};
      my $reason = $data->{'reason'};
      my $category = $data->{'category'};
      my $note = $data->{'note'};
      $self->SubmitReview($id,'autocrms',$attr,$reason,$note,undef,1,undef,$category,0,0);
    }
    $self->RegisterStatus( $id, $status );
    $sql = "UPDATE reviews SET hold=NULL,sticky_hold=NULL,time=time WHERE id='$id'";
    $self->PrepareSubmitSql( $sql );
    $stati{$status}++;
  }
  # Clear out all the locks
  $sql = 'UPDATE queue SET locked=NULL WHERE locked IS NOT NULL';
  $self->PrepareSubmitSql( $sql );
  $sql = 'INSERT INTO processstatus VALUES ()';
  $self->PrepareSubmitSql( $sql );
  my ($s2,$s3,$s4,$s8) = ($stati{2},$stati{3},$stati{4},$stati{8});
  $self->PrepareSubmitSql('DELETE FROM predeterminationsbreakdown WHERE date=DATE(NOW())');
  $sql = "INSERT INTO predeterminationsbreakdown (date,s2,s3,s4,s8) VALUES (DATE(NOW()),$s2,$s3,$s4,$s8)";
  $self->PrepareSubmitSql($sql);
}

# Determines what status a given id should be based on existing reviews and system status.
# Returns a hashref (status,attr,reason,category,note) where attr, reason, note are for status 8
# autocrms dummy reviews.
# In the case of a hold, there will be a 'hold' key pointing to the user with the hold.
sub CalcStatus
{
  my $self = shift;
  my $id   = shift;
  my $stat = shift;

  my %return;
  my $dbh = $self->get( 'dbh' );
  my $status = 0;
  my $sql = "SELECT user,attr,reason,renNum,renDate,hold,NOW() FROM reviews WHERE id='$id'";
  my $ref = $dbh->selectall_arrayref( $sql );
  my ($user, $attr, $reason, $renNum, $renDate, $hold, $today) = @{ $ref->[0] };
  $sql = "SELECT user,attr,reason,renNum,renDate,hold FROM reviews WHERE id='$id' AND user!='$user'";
  $ref = $dbh->selectall_arrayref( $sql );
  my ($other_user, $other_attr, $other_reason, $other_renNum, $other_renDate, $other_hold) = @{ $ref->[0] };
  if ($other_hold && ($today lt $other_hold || $stat ne 'normal'))
  {
    $return{'hold'} = $other_user;
  }
  elsif ($attr == $other_attr)
  {
    # If both reviewers are non-advanced mark as provisional match
    if ((!$self->IsUserAdvanced($user)) && (!$self->IsUserAdvanced($other_user)))
    {
       $status = 3;
    }
    else #Mark as 4 or 8 - two that agree
    {
      if ($reason != $other_reason)
      {
        $status = 8;
        $return{'attr'} = $attr;
        $return{'reason'} = 13;
        $return{'category'} = 'Attr Match';
      }
      elsif ($attr == 2 && $reason == 7 && $other_reason == 7 && ($renNum ne $other_renNum || $renDate ne $other_renDate))
      {
        $status = 8;
        $return{'attr'} = $attr;
        $return{'reason'} = $reason;
        $return{'category'} = 'Attr Match';
        $return{'note'} = sprintf 'Nonmatching renewals: %s (%s) vs %s (%s)', $renNum, $renDate, $other_renNum, $other_renDate;
      }
      else
      {
        $status = 4;
      }
    }
  }
  # Do auto for ic vs und
  elsif (($attr == 2 && $other_attr == 5) || ($attr == 5 && $other_attr == 2))
  {
    # If both reviewers are non-advanced mark as provisional match
    if ((!$self->IsUserAdvanced($user)) && (!$self->IsUserAdvanced($other_user)))
    {
       $status = 3;
    }
    else #Mark as 8 - two that agree as und/crms
    {
      $status = 8;
      $return{'attr'} = 5;
      $return{'reason'} = 13;
      $return{'category'} = 'Attr Default';
    }
  }
  else #Mark as 2 - two that disagree
  {
    $status = 2;
  }
  $return{'status'} = $status;
  return \%return;
}

sub CheckPendingStatus
{
  my $self = shift;
  my $id   = shift;
  
  my $sql = "SELECT status FROM queue WHERE id='$id'";
  my $status = $self->SimpleSqlGet($sql);
  my $pstatus = $status;
  if (!$status)
  {
    $sql = "SELECT user,attr,reason,renNum,renDate FROM reviews WHERE id='$id' AND expert IS NULL";
    my $ref = $self->get( 'dbh' )->selectall_arrayref( $sql );
    if (scalar @{$ref} > 1)
    {
      my $row = @{$ref}[0];
      my $user    = $row->[0];
      my $attr    = $row->[1];
      my $reason  = $row->[2];
      my $renNum  = $row->[3];
      my $renDate = $row->[4];
      $row = @{$ref}[1];
      my $other_user    = $row->[0];
      my $other_attr    = $row->[1];
      my $other_reason  = $row->[2];
      my $other_renNum  = $row->[3];
      my $other_renDate = $row->[4];
      if ($attr == $other_attr)
      {
        # If both reviewers are non-advanced mark as provisional match
        if ( (!$self->IsUserAdvanced($user)) && (!$self->IsUserAdvanced($other_user)))
        {
          $pstatus = 3;
        }
        else #Mark as 4 or 8 - two that agree
        {
          $pstatus = 4;
          if ($reason != $other_reason)
          {
            $pstatus = 8;
          }
          elsif ($attr == 2 && $reason == 7 && $other_reason == 7 && ($renNum ne $other_renNum || $renDate ne $other_renDate))
          {
            $pstatus = 8;
          }
        }
      }
      # Do auto for ic vs und
      elsif (($attr == 2 && $other_attr == 5) || ($attr == 5 && $other_attr == 2))
      {
        # If both reviewers are non-advanced mark as provisional match
        if ((!$self->IsUserAdvanced($user)) && (!$self->IsUserAdvanced($other_user)))
        {
          $pstatus = 3;
        }
        else #Mark as 8 - two that sort of agree
        {
          $pstatus = 8;
        }
      }
      else #Mark as 2 - two that disagree
      {
        $pstatus = 2;
      }
    }
    elsif (scalar @{$ref} == 1) #Mark as 1: just single review unless it's a status 5/7 already.
    {
      $pstatus = 1 unless $status;
    }
  }
  $self->RegisterPendingStatus( $id, $pstatus );
}

# If fromcgi is set, don't try to create the export file, print stuff, or send mail.
sub ClearQueueAndExport
{
  my $self     = shift;
  my $fromcgi  = shift;

  my $aCount = 0;
  my $eCount = 0;
  my $dCount = 0;
  my $export = [];
  ## get status 8, clear these
  my $auto = $self->GetAutoResolvedItems();
  foreach my $row ( @{$auto} )
  {
    my $id = $row->[0];
    push( @{$export}, $id );
    $aCount++;
  }
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
  ## Get ic/bib volumes for those system IDs that have no chron/enum info.
  #my $dups = $self->ReviewDuplicateVolumes($export, $fromcgi);
  #my $dupCount = scalar @{ $dups };
  #foreach my $id ( @{$dups} )
  #{
  #  push( @{$export}, $id );
  #}
  $self->ExportReviews( $export, $fromcgi );
  $self->UpdateExportStats();
  $self->UpdateDeterminationsBreakdown();
  # Clear the deleted volumes
  my $sql = 'SELECT COUNT(*) FROM inherit WHERE del=1';
  my $dels = $self->SimpleSqlGet($sql);
  if ($dels)
  {
    print "Deleted inheriting volumes to be removed: $dels\n" unless $fromcgi;
    $self->PrepareSubmitSql('DELETE FROM inherit WHERE del=1');
  }
  else
  {
    print "No deleted inheriting volumes to remove.\n" unless $fromcgi;
  }
  return "Exported: $dCount matching, $eCount expert-reviewed, $aCount auto-resolved\n";
}

sub GetAutoResolvedItems
{
  my $self = shift;
  my $sql  = 'SELECT id FROM queue WHERE status=8';
  return $self->get( 'dbh' )->selectall_arrayref( $sql );
}

sub GetExpertRevItems
{
  my $self = shift;

  my $stat = @{$self->GetSystemStatus(1)}->[1];
  my $holdSQL = ($stat eq 'normal')? 'CURTIME()<hold':'hold IS NOT NULL';
  my $sql  = 'SELECT id FROM queue WHERE ((status>=5 AND status<8) OR status=9) AND id NOT IN ' .
             "(SELECT id FROM reviews WHERE $holdSQL)";
  return $self->get( 'dbh' )->selectall_arrayref( $sql );
}

sub GetDoubleRevItemsInAgreement
{
  my $self = shift;
  my $sql  = 'SELECT id FROM queue WHERE status=4';
  return $self->get( 'dbh' )->selectall_arrayref( $sql );
}

## ----------------------------------------------------------------------------
##  Function:   create a tab file of reviews to be loaded into the rights table
##              vol id | attr | reason | user | null
##              mdp.123 | ic   | ren    | crms | null
##  Parameters: A reference to a list of volume ids
##  Return:     1 || 0
## ----------------------------------------------------------------------------
sub ExportReviews
{
  my $self    = shift;
  my $list    = shift;
  my $fromcgi = shift;

  my $count = 0;
  my $user = 'crms';
  my $time = $self->GetTodaysDate();
  my ( $fh, $file ) = $self->GetExportFh() unless $fromcgi;
  my $start_size = $self->GetCandidatesSize();
  foreach my $id ( @{$list} )
  {
    my ($attr,$reason) = $self->GetFinalAttrReason($id);
    print $fh "$id\t$attr\t$reason\t$user\tnull\n" unless $fromcgi;
    my $src = $self->SimpleSqlGet("SELECT source FROM queue WHERE id='$id' ORDER BY time DESC LIMIT 1");
    my $sql = "INSERT INTO  exportdata (time, id, attr, reason, user, src) VALUES ('$time', '$id', '$attr', '$reason', '$user', '$src')";
    $self->PrepareSubmitSql( $sql );
    my $gid = $self->SimpleSqlGet('SELECT MAX(gid) FROM exportdata');
    $sql = "INSERT INTO exportdataBckup (time, id, attr, reason, user, src) VALUES ('$time', '$id', '$attr', '$reason', '$user', '$src')";
    $self->PrepareSubmitSql( $sql );
    $self->MoveFromReviewsToHistoricalReviews($id,$gid);
    $self->RemoveFromQueue($id);
    $self->RemoveFromCandidates($id);
    $count++;
  }
  close $fh unless $fromcgi;
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
  my $sql = "INSERT INTO  $CRMSGlobals::exportrecordTable (itemcount) VALUES ($count)";
  $self->PrepareSubmitSql( $sql );
  if (!$fromcgi)
  {
    printf "After export, removed %d volumes from candidates.\n", $start_size-$self->GetCandidatesSize();
    eval { $self->EmailReport ( $count, $file ); };
    $self->SetError("EmailReport() failed: $@") if $@;
  }
}

# Send email (to Anne) with rights export data.
sub EmailReport
{
  my $self    = shift;
  my $count   = shift;
  my $file    = shift;

  my $where = ($self->WhereAmI() or 'Prod');
  my $subject = sprintf('CRMS %s: %d volumes exported to rights db', $where, $count);
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

  #$self->Logit( "remove $id from queue" );
  my $sql = "DELETE FROM queue WHERE id='$id'";
  $self->PrepareSubmitSql( $sql );
}

sub RemoveFromCandidates
{
  my $self = shift;
  my $id   = shift;

  my $sql = "DELETE FROM candidates WHERE id='$id'";
  $self->PrepareSubmitSql( $sql );
}

sub LoadNewItemsInCandidates
{
  my $self = shift;

  $self->set('nosystem','nosystem');
  my $start = $self->SimpleSqlGet('SELECT max(time) FROM candidates');
  my $start_size = $self->GetCandidatesSize();
  print "Before load, the max timestamp in the candidates table is $start, and the size is $start_size\n";
  my $sql = "SELECT id,time FROM und WHERE src='no meta'";
  my $dbh = $self->get('dbh');
  my $ref = $dbh->selectall_arrayref( $sql );
  if (scalar @{ $ref })
  {
    printf "Checking %d possible no-meta additions to candidates\n", scalar @{ $ref };
    foreach my $row ( @{$ref} )
    {
      my $id   = $row->[0];
      my $time = $row->[1];

      $self->CheckAndLoadItemIntoCandidates($id, $time);
    }
  }
  $sql = "SELECT namespace,id,time FROM rights_current WHERE attr=2 AND reason=1 AND time>'$start' GROUP BY namespace, id";
  $dbh = $self->GetSdrDb();
  $ref = $dbh->selectall_arrayref( $sql );
  printf "Checking %d possible additions to candidates from rights DB\n", scalar @{ $ref };
  foreach my $row ( @{$ref} )
  {
    my $id   = $row->[0] . '.' . $row->[1];
    my $time = $row->[2];
    
    $self->CheckAndLoadItemIntoCandidates($id, $time);
  }
  my $end_size = $self->GetCandidatesSize();
  my $diff = $end_size - $start_size;
  print "After load, candidates has $end_size items. Added $diff.\n\n";
  #Record the update to the queue
  $sql = "INSERT INTO candidatesrecord (addedamount) VALUES ($diff)";
  $self->PrepareSubmitSql( $sql );
  $self->set('nosystem',undef);
  return 1; # FIXME: this only ever returns 1
}

# Adds a single ic/bib volume to candidates if possible, putting it in the und table if not.
sub CheckAndLoadItemIntoCandidates
{
  my $self = shift;
  my $id   = lc shift;
  my $time = shift;

  # If it was a gfv and it reverted to ic/bib, remove it from und, alert, and continue.
  if ($self->SimpleSqlGet("SELECT COUNT(*) FROM und WHERE id='$id' AND src='gfv'") > 0)
  {
    print "Unfilter $id -- reverted from pdus/gfv\n";
    my $sql = "DELETE FROM und WHERE id='$id'";
    $self->PrepareSubmitSql($sql);
  }
  if ($self->SimpleSqlGet("SELECT COUNT(*) FROM historicalreviews WHERE id='$id'") > 0)
  {
    print "Skip $id -- already in historical reviews\n";
    return;
  }
  my $sysid = $self->BarcodeToId($id);
  my $record;
  $record = $self->GetMetadata($sysid) if $sysid;
  if (!$record)
  {
    $self->ClearErrors() if 2 == scalar @{$self->GetErrors()};
    print "No metadata yet for $id: will try again tomorrow.\n";
    if (0 == $self->SimpleSqlGet("SELECT COUNT(*) FROM und WHERE id='$id'"))
    {
      my $sql = "REPLACE INTO und (id,src,time) VALUES ('$id','no meta','$time')";
      $self->PrepareSubmitSql( $sql );
    }
    return;
  }
  my $errs = $self->GetViolations($id, $record);
  if (scalar @{$errs} == 0)
  {
    my $src = $self->ShouldVolumeGoInUndTable($id, $record);
    if ($src)
    {
      my $sql = "SELECT COUNT(*) FROM und WHERE id='$id'";
      my $already = (1 == $self->SimpleSqlGet($sql));
      printf "Skip $id ($src) -- %s in filtered volumes\n", ($already)? 'updating':'inserting';
      $sql = "REPLACE INTO und (id,src,time) VALUES ('$id','$src','$time')";
      $self->PrepareSubmitSql( $sql );
      $sql = "DELETE FROM candidates WHERE id='$id'";
      $self->PrepareSubmitSql( $sql );
    }
    else
    {
      $self->CheckCandidateRightsInheritance($id, $sysid);
      $self->AddItemToCandidates($id, $time, $record);
      $self->PrepareSubmitSql("DELETE FROM und WHERE id='$id'");
    }
  }
  else
  {
    $self->PrepareSubmitSql("DELETE FROM und WHERE id='$id'");
  }
}

# Returns an array of error messages (reasons for unsuitability for CRMS) for a volume.
# Used by candidates loading to ignore inappropriate items.
# Used by Add to Queue page for filtering non-overrides.
# When used by an expert/admin to add to the queue, the date range becomes 1923-1977 if override
sub GetViolations
{
  my $self     = shift;
  my $id       = shift;
  my $record   = shift;
  my $priority = shift;
  my $override = shift;

  $priority = 0 unless $priority;
  my @errs = ();
  $record =  $self->GetMetadata($id) unless $record;
  if (!$record)
  {
    push @errs, 'not found in HathiTrust';
  }
  elsif ($priority < 4 || !$override)
  {
    my $pub = $self->GetPublDate( $id, $record );
    my $year = (($override && $priority == 3) || $priority == 4)? 1977:1963;
    push @errs, "$pub not in range 1923-$year" if ($pub < 1923 || $pub > $year);
    push @errs, 'gov doc' if $self->IsGovDoc( $id, $record );
    push @errs, 'foreign pub' if $self->IsForeignPub( $id, $record );
    push @errs, 'non-BK format' unless $self->IsFormatBK( $id, $record );
  }
  return \@errs;
}

# Returns a und table src code if the volume belongs in the und table instead of candidates.
sub ShouldVolumeGoInUndTable
{
  my $self   = shift;
  my $id     = shift;
  my $record = shift;

  my $src = undef;
  $record = $self->GetMetadata($id) unless $record;
  my $lang = $self->GetPubLanguage($id, $record);
  if ('eng' ne $lang) { $src = 'language'; }
  elsif ($self->IsThesis($id, $record)) { $src = 'dissertation'; }
  elsif ($self->IsTranslation($id, $record)) { $src = 'translation'; }
  elsif ($self->IsReallyForeignPub($id, $record)) { $src = 'foreign'; }
  elsif ($self->IsProbableGovDoc($id, $record)) { $src = 'gov'; }
  return $src;
}

sub AddItemToCandidates
{
  my $self   = shift;
  my $id     = shift;
  my $time   = shift;
  my $record = shift;

  $record = $self->GetMetadata($id) unless $record;
  my $pub = $self->GetPublDate($id, $record);
  my $au = $self->GetRecordAuthor($id, $record);
  $au = $self->get('dbh')->quote($au);
  $self->SetError("$id: UTF-8 check failed for quoted author: '$au'") unless $au eq "''" or utf8::is_utf8($au);
  my $title = $self->GetRecordTitle( $id, $record );
  $title = $self->get('dbh')->quote($title);
  $self->SetError("$id: UTF-8 check failed for quoted title: '$title'") unless $title eq "''" or utf8::is_utf8($title);
  my $sql = "REPLACE INTO candidates (id, time, pub_date, title, author) VALUES ('$id', '$time', '$pub-01-01', $title, $au)";
  $self->PrepareSubmitSql( $sql );
}

# Load candidates into queue.
# If the needed parameter is given, tries to make the total in the queue equal to needed.
# (In other words if there are 500 and you tell it needed = 1000, it loads 500 more.)
# Otherwise loads to the standard limit of 800, 500 Priority 0.
sub LoadNewItems
{
  my $self   = shift;
  my $needed = shift;

  my $queuesize = $self->GetQueueSize();
  my $priZeroSize = $self->GetQueueSize(0);
  print "Before load, the queue has $queuesize volumes, $priZeroSize priority 0.\n";
  if ($needed)
  {
    $needed = $needed - $queuesize;
    return if $needed < 0;
  }
  else
  {
    $needed = max($CRMSGlobals::queueSize - $queuesize, 500 - $priZeroSize);
  }
  printf "Need $needed items (max of %d and %d).\n", $CRMSGlobals::queueSize - $queuesize, 500 - $priZeroSize;
  return if $needed <= 0;
  my $count = 0;
  my $y = 1923 + int(rand(40));
  my %recs = %{$self->GetQueueRecords()};
  while (1)
  {
    my $sql = 'SELECT id, time, pub_date, title, author FROM candidates ' .
              'WHERE id NOT IN (SELECT DISTINCT id FROM inherit) ' .
              'AND id NOT IN (SELECT DISTINCT id FROM queue) ' .
              'AND id NOT IN (SELECT DISTINCT id FROM reviews) ' .
              'AND id NOT IN (SELECT DISTINCT id FROM historicalreviews) ' .
              'ORDER BY pub_date ASC, time DESC';
    my $ref = $self->get('dbh')->selectall_arrayref( $sql );
    #printf "%d results\n", scalar @{$ref};
    # This can happen in the testsuite.
    last unless scalar @{$ref};
    my $oldcount = $count;
    foreach my $row (@{$ref})
    {
      my $id = $row->[0];
      my $sysid = $self->BarcodeToId($id);
      my $dup = $recs{$sysid};
      if ($dup)
      {
        print "Skipping $id: queue has $dup on record $sysid\n";
        next;
      }
      my $pub_date = $row->[2];
      #print "Trying $id ($pub_date) against $y\n";
      next if $pub_date ne "$y-01-01";
      my $time = $row->[1];
      my $title = $row->[3];
      my $author = $row->[4];
      if ($self->AddItemToQueue( $id, $pub_date, $title, $author ))
      {
        printf "Added to queue: $id published %s\n", substr($pub_date, 0, 4);
        $count++;
        last if $count >= $needed;
        $y++;
        $y = 1923 if $y > 1963;
      }
    }
    if ($oldcount == $count)
    {
      $y++;
      $y = 1923 if $y > 1963;
    }
    last if $count >= $needed;
  }
  #Record the update to the queue
  my $sql = "INSERT INTO $CRMSGlobals::queuerecordTable (itemcount, source) VALUES ($count, 'RIGHTSDB')";
  $self->PrepareSubmitSql( $sql );
}

# Return a hash ref if sysid=>id of all volumes in the queue.
sub GetQueueRecords
{
  my $self = shift;

  my %dict = ();
  my $sql = 'SELECT id FROM queue';
  my $ref = $self->get('dbh')->selectall_arrayref($sql);
  foreach my $row (@{$ref})
  {
    my $id = $row->[0];
    my $sysid = $self->BarcodeToId($id);
    $dict{$sysid} = $id if $sysid;
  }
  return \%dict;
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

  return 0 if $self->IsItemInQueue($id);
  # queue table has priority and status default to 0, time to current timestamp.
  my $sql = "INSERT INTO $CRMSGlobals::queueTable (id) VALUES ('$id')";
  $self->PrepareSubmitSql( $sql );
  $self->UpdateTitle( $id, $title );
  $self->UpdatePubDate( $id, $pub_date );
  $self->UpdateAuthor( $id, $author );
  # Update system table with aleph system id.
  $self->BarcodeToId($id);
  return 1;
}

# Returns a status code (0=Add, 1=Error, 2=Skip, 3=Modify) followed by optional text.
sub AddItemToQueueOrSetItemActive
{
  my $self     = shift;
  my $id       = shift;
  my $priority = shift;
  my $override = shift;
  my $src      = shift;

  $src = 'adminui' unless $src;
  my $stat = 0;
  my @msgs = ();
  my $super = $self->IsUserSuperAdmin();
  if ($priority == 4 && !$super)
  {
    push @msgs, 'Only a super admin can set priority 4';
    $stat = 1;
  }
  ## give the existing item higher or lower priority
  elsif ( $self->IsItemInQueue( $id ) )
  {
    my $sql = "SELECT COUNT(*) FROM reviews WHERE id='$id'";
    my $count = $self->SimpleSqlGet($sql);
    my $oldpri = $self->GetPriority($id);
    if ($oldpri == $priority)
    {
      push @msgs, 'already in queue with the same priority';
      $stat = 2;
    }
    elsif ($oldpri > $priority && !$super)
    {
      push @msgs, 'already in queue with a higher priority';
      $stat = 2;
    }
    else
    {
      $sql = "UPDATE $CRMSGlobals::queueTable SET priority=$priority,time=NOW() WHERE id='$id'";
      $self->PrepareSubmitSql( $sql );
      push @msgs, "changed priority from $oldpri to $priority";
      if ($count)
      {
        $sql = "UPDATE $CRMSGlobals::reviewsTable SET priority=$priority,time=time WHERE id='$id'";
        $self->PrepareSubmitSql( $sql );
      }
      $stat = 3;
    }
    if ($count)
    {
      my $rlink = sprintf("already has $count <a href='?p=adminReviews;search1=Identifier;search1value=$id' target='_blank'>review%s</a>",
                          ($count==1)? '':'s');
      push @msgs, $rlink;
    }
  }
  else
  {
    my $record = $self->GetMetadata($id); 
    @msgs = @{ $self->GetViolations($id, $record, $priority, $override) };
    if (scalar @msgs)
    {
      $stat = 1;
    }
    else
    {
      my $sql = "INSERT INTO $CRMSGlobals::queueTable (id, priority, source) VALUES ('$id', $priority, '$src')";
      $self->PrepareSubmitSql( $sql );
      $self->UpdateTitle( $id, undef, $record );
      $self->UpdatePubDate( $id, undef, $record );
      $self->UpdateAuthor ( $id, undef, $record );
      $sql = "INSERT INTO $CRMSGlobals::queuerecordTable (itemcount, source) VALUES (1, '$src')";
      $self->PrepareSubmitSql( $sql );
    }
  }
  return $stat . join '; ', @msgs;
}

# Used by the script loadIDs.pl to add and/or bump priority on a volume
sub GiveItemsInQueuePriority
{
  my $self     = shift;
  my $id       = lc shift;
  my $time     = shift;
  my $status   = shift;
  my $priority = shift;
  my $source   = shift;

  my $record = $self->GetMetadata($id);
  my $errs = $self->GetViolations($id, $record);
  if (scalar @{$errs})
  {
    $self->SetError(sprintf "$id: %s", join ';', @{$errs});
    return 0;
  }
  my $sql = "SELECT COUNT(*) FROM $CRMSGlobals::queueTable WHERE id='$id'";
  my $count = $self->SimpleSqlGet( $sql );
  if ( $count == 1 )
  {
    $sql = "UPDATE $CRMSGlobals::queueTable SET priority=1 WHERE id ='$id'";
    $self->PrepareSubmitSql( $sql );
  }
  else
  {
    $sql = "INSERT INTO $CRMSGlobals::queueTable (id, time, status, priority, source) VALUES ('$id', '$time', $status, $priority, '$source')";
    $self->PrepareSubmitSql( $sql );
    $self->UpdateTitle( $id, undef, $record );
    $self->UpdatePubDate( $id, undef, $record );
    $self->UpdateAuthor( $id, undef, $record );
    # Accumulate counts for items added at the 'same time'.
    # Otherwise queuerecord will have a zillion kabillion single-item entries when importing
    # e.g. 2007 reviews for reprocessing.
    # We see if there is another ADMINSCRIPT entry for the current time; if so increment.
    # If not, add a new one.
    $sql = "SELECT itemcount FROM $CRMSGlobals::queuerecordTable WHERE time='$time' AND source='ADMINSCRIPT' LIMIT 1";
    my $itemcount = $self->SimpleSqlGet($sql);
    if ($itemcount)
    {
      $itemcount++;
      $sql = "UPDATE $CRMSGlobals::queuerecordTable SET itemcount=$itemcount WHERE time='$time' AND source='ADMINSCRIPT' LIMIT 1";
    }
    else
    {
      $sql = "INSERT INTO $CRMSGlobals::queuerecordTable (time, itemcount, source) values ('$time', 1, 'ADMINSCRIPT')";
    }
    $self->PrepareSubmitSql( $sql );
  }
  return 1;
}

sub IsItemInQueue
{
  my $self = shift;
  my $id   = shift;

  my $sql = "SELECT COUNT(*) FROM $CRMSGlobals::queueTable WHERE id='$id'";
  return $self->SimpleSqlGet($sql);
}

# Translates pre-CRMS, for legacyLoad.pl.
sub TranslateCategory
{
    my $self     = shift;
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

# Valid for DB reviews/historicalreviews
sub IsValidCategory
{
  my $self = shift;
  my $cat = shift;
  
  my %cats = ('Insert(s)' => 1, 'Language' => 1, 'Misc' => 1, 'Missing' => 1, 'Date' => 1, 'Reprint' => 1,
              'Periodical' => 1, 'Translation' => 1, 'Wrong Record' => 1, 'Foreign Pub' => 1, 'Dissertation/Thesis' => 1,
              'Expert Note' => 1, 'Not Class A' => 1, 'Edition' => 1,
              'Expert Accepted' => 1, 'Attr Match' => 1, 'Attr Default' => 1, 'Duplicate' => 1);
  return exists $cats{$cat};
}

# Used by experts to approve a review made by a reviewer.
# Returns an error message.
sub CloneReview
{
  my $self   = shift;
  my $id     = shift;
  my $user   = shift;
  
  my $result = $self->LockItem($id, $user, 1);
  return $result if $result;
  # SubmitReview unlocks it if it succeeds.
  if ($self->HasItemBeenReviewedByUser($id, $user))
  {
    $result = "Could not approve review for $id because you already reviewed it.";
  }
  elsif ($self->IsLockedForOtherUser($id, $user))
  {
    $result = "Could not approve review for $id because it is locked by another user.";
  }
  elsif ($self->HasItemBeenReviewedByAnotherExpert($id,$user))
  {
    $result = "Could not approve review for $id because it has already been reviewed by an expert.";
  }
  else
  {
    my $note = undef;
    my $sql = "SELECT attr,reason,renNum,renDate FROM reviews WHERE id='$id'";
    my $rows = $self->get('dbh')->selectall_arrayref($sql);
    my $attr = $rows->[0]->[0];
    my $reason = $rows->[0]->[1];
    if ($attr == 2 && $reason == 7 && ($rows->[0]->[2] ne $rows->[1]->[2] || $rows->[0]->[3] ne $rows->[1]->[3]))
    {
      $note = sprintf 'Nonmatching renewals: %s (%s) vs %s (%s)', $rows->[0]->[2], $rows->[0]->[3], $rows->[1]->[2], $rows->[1]->[3];
    }
    # If reasons mismatch, reason is 'crms'.
    $reason = 13 if $rows->[0]->[1] ne $rows->[1]->[1];
    $result = $self->SubmitReview($id,$user,$attr,$reason,$note,undef,1,undef,'Expert Accepted');
    $result = ($result == 0)? "Could not approve review for $id":undef;
  }
  return $result;
}


## ----------------------------------------------------------------------------
##  Function:   submit review
##  Parameters: id, user, attr, reason, note, stanford ren. number
##  Return:     1 || 0
## ----------------------------------------------------------------------------
sub SubmitReview
{
  my $self = shift;
  my ($id, $user, $attr, $reason, $note, $renNum, $exp, $renDate, $category, $swiss, $question) = @_;

  if ( ! $self->CheckForId( $id ) )                         { $self->SetError("id ($id) check failed");         return 0; }
  if ( ! $self->CheckReviewer( $user, $exp ) )              { $self->SetError("reviewer ($user) check failed"); return 0; }
  # ValidateAttrReasonCombo sets error internally on fail.
  if ( ! $self->ValidateAttrReasonCombo( $attr, $reason ) ) { return 0; }

  my $dbh = $self->get('dbh');
  #remove any blanks from renNum
  $renNum =~ s/\s+//gs;

  # Javascript code inserts the string 'searching...' into the review text box.
  # This in once case got submitted as the renDate in production
  $renDate = '' if $renDate =~ m/searching.*/i;

  $note = ($note)? $dbh->quote($note):'NULL';

  my $priority = $self->GetPriority( $id );

  my $hold = 'NULL';

  if ($question)
  {
    $hold = $dbh->quote($self->HoldExpiry($id, $user, 0));
    my $sql = "INSERT INTO note (note) VALUES ('hold from $user on $id')";
    $self->PrepareSubmitSql($sql);
  }

  my @fieldList = ('id', 'user', 'attr', 'reason', 'note', 'renNum', 'renDate', 'category', 'priority', 'hold');
  my @valueList = ("'$id'",  "'$user'",  $attr,  $reason,  $note, ($renNum)? "'$renNum'":'NULL',  ($renDate)? "'$renDate'":'NULL',
                   ($category)? "'$category'":'NULL', $priority, $hold);
  my $sql = "SELECT duration FROM reviews WHERE user='$user' AND id='$id'";
  my $dur = $self->SimpleSqlGet($sql);
  if ($dur)
  {
    push(@fieldList, 'duration');
    push(@valueList, "'$dur'");
  }
  if (!$question)
  {
    # Stash their hold if they are cancelling it
    my $oldhold = $self->SimpleSqlGet("SELECT hold FROM reviews WHERE id='$id' AND user='$user'");
    if ($oldhold)
    {
      push(@fieldList, 'sticky_hold');
      push(@valueList, "'$oldhold'");
    }
  }
  if ($exp)
  {
    $swiss = ($swiss)? 1:0;
    push(@fieldList, 'expert');
    push(@valueList, 1);
    push(@fieldList, 'swiss');
    push(@valueList, $swiss);
  }

  $sql = sprintf("REPLACE INTO $CRMSGlobals::reviewsTable (%s) VALUES (%s)", join(',', @fieldList), join(",", @valueList));
  if ( $self->get('verbose') ) { $self->Logit( $sql ); }
  my $result = $self->PrepareSubmitSql( $sql );
  if ($result)
  {
    if ( $exp )
    {
      my $expcnt = $self->SimpleSqlGet("SELECT COUNT(*) FROM reviews WHERE id='$id' AND expert=1");
      $sql = "UPDATE $CRMSGlobals::queueTable SET expcnt=$expcnt WHERE id='$id'";
      $result = $self->PrepareSubmitSql( $sql );
      my $status = $self->GetStatusForExpertReview($id, $user, $attr, $reason, $category, $renNum, $renDate);
      #We have decided to register the expert decision right away.
      $self->RegisterStatus($id, $status);
    }
    $self->CheckPendingStatus($id);
    $self->EndTimer( $id, $user );
    $self->UnlockItem( $id, $user );
  }
  return $result;
}

sub GetStatusForExpertReview
{
  my $self     = shift;
  my $id       = shift;
  my $user     = shift;
  my $attr     = shift;
  my $reason   = shift;
  my $category = shift;
  my $renNum   = shift;
  my $renDate  = shift;
  
  return 7 if $category eq 'Expert Accepted';
  return 9 if $category eq 'Rights Inherited';
  my $status = 5;
  # See if it's a provisional match and expert agreed with both of existing non-advanced reviews. If so, status 7.
  my $sql = "SELECT attr,reason,renNum,renDate FROM reviews WHERE id='$id' AND user IN (SELECT id FROM users WHERE expert=0 AND advanced=0)";
  my $ref = $self->get('dbh')->selectall_arrayref($sql);
  if (scalar @{ $ref } >= 2)
  {
    my $attr1    = $ref->[0]->[0];
    my $reason1  = $ref->[0]->[1];
    my $renNum1  = $ref->[0]->[2];
    my $renDate1 = $ref->[0]->[3];
    my $attr2    = $ref->[1]->[0];
    my $reason2  = $ref->[1]->[1];
    my $renNum2  = $ref->[1]->[2];
    my $renDate2 = $ref->[1]->[3];
    if ($attr1 == $attr2 && $reason1 == $reason2 && $attr == $attr1 && $reason == $reason1)
    {
      $status = 7;
      if ($attr1 == 2 && $reason1 == 7)
      {
        $status = 5 if ($renNum ne $renNum1 || $renNum ne $renNum2 || $renDate ne $renDate1 || $renDate ne $renDate2);
      }
    }
  }
  return $status;
}

sub GetPriority
{
  my $self = shift;
  my $id   = shift;
  
  my $sql = "SELECT priority FROM queue WHERE id='$id'";
  return $self->StripDecimal($self->SimpleSqlGet($sql));
}


## ----------------------------------------------------------------------------
##  Function:   submit historical review  (from excel SS)
##  Parameters: Lots of them -- last one does the sanity checks but no db updates
##  Return:     1 || 0
## ----------------------------------------------------------------------------
sub SubmitHistReview
{
  my $self = shift;
  my ($id, $user, $time, $attr, $reason, $renNum, $renDate, $note, $category, $status, $expert, $legacy, $source, $gid, $noop) = @_;

  $id = lc $id;
  $legacy = ($legacy)? 1:0;
  $gid = 'NULL' unless $gid;
  ## change attr and reason back to numbers
  $attr = $self->GetRightsNum( $attr ) unless $attr =~ m/^\d+$/;
  $reason = $self->GetReasonNum( $reason ) unless $reason =~ m/^\d+$/;
  # ValidateAttrReasonCombo sets error internally on fail.
  if ( ! $self->ValidateAttrReasonCombo( $attr, $reason ) ) { return 0; }
  if ($status != 9)
  {
    my $err = $self->ValidateSubmissionHistorical($attr, $reason, $note, $category, $renNum, $renDate);
    if ($err) { $self->SetError($err); return 0; }
  }
  ## do some sort of check for expert submissions
  if (!$noop)
  {
    $note = $self->get('dbh')->quote($note);
    ## all good, INSERT
    my $sql = 'REPLACE INTO historicalreviews (id, user, time, attr, reason, renNum, renDate, note, legacy, category, status, expert, source, gid) ' .
           "VALUES('$id', '$user', '$time', '$attr', '$reason', '$renNum', '$renDate', $note, $legacy, '$category', $status, $expert, '$source', $gid)";
    $self->PrepareSubmitSql( $sql );
    #Now load this info into the bibdata and system table.
    my $record = $self->GetMetadata($id);
    $self->UpdateTitle( $id, undef, $record );
    $self->UpdatePubDate( $id, undef, $record );
    $self->UpdateAuthor( $id, undef, $record );
    # Update status on status 1 item
    if ($status == 5)
    {
      $sql = "UPDATE $CRMSGlobals::historicalreviewsTable SET status=$status WHERE id='$id' AND legacy=1 AND gid IS NULL";
      $self->PrepareSubmitSql( $sql );
    }
    # Update validation on all items with this id
    $sql = "SELECT user,time,validated FROM historicalreviews WHERE id='$id'";
    my $ref = $self->get('dbh')->selectall_arrayref($sql);
    foreach my $row (@{$ref})
    {
      $user = $row->[0];
      $time = $row->[1];
      my $val  = $row->[2];
      my $val2 = $self->IsReviewCorrect($id, $user, $time);
      if ($val != $val2)
      {
        $sql = "UPDATE historicalreviews SET validated=$val2 WHERE id='$id' AND user='$user' AND time='$time'";
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

  my $sql = "SELECT source FROM queue WHERE id='$id'";
  my $source = $self->SimpleSqlGet($sql);
  my $status = $self->GetStatus( $id );
  $sql = 'INSERT into historicalreviews (id, time, user, attr, reason, note, renNum, expert, duration, legacy, renDate, category, priority, source, status, gid, swiss) ' .
         "select id, time, user, attr, reason, note, renNum, expert, duration, legacy, renDate, category, priority, '$source', $status, $gid, swiss from reviews where id='$id'";
  $self->PrepareSubmitSql( $sql );
  $sql = "DELETE FROM reviews WHERE id='$id'";
  $self->PrepareSubmitSql( $sql );
}

sub GetFinalAttrReason
{
  my $self = shift;
  my $id   = shift;

  ## order by expert so that if there is an expert review, return that one
  my $sql = "SELECT attr,reason FROM reviews WHERE id='$id' ORDER BY expert DESC, time DESC LIMIT 1";
  my $ref = $self->get( 'dbh' )->selectall_arrayref( $sql );
  if ( ! $ref->[0]->[0] )
  {
    $self->SetError( "$id not found in review table" );
  }
  my $attr   = $self->GetRightsName( $ref->[0]->[0] );
  my $reason = $self->GetReasonName( $ref->[0]->[1] );
  return ($attr, $reason);
}

sub RegisterStatus
{
  my $self   = shift;
  my $id     = shift;
  my $status = shift;

  my $sql = "UPDATE $CRMSGlobals::queueTable SET status=$status WHERE id='$id'";
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

sub HoldForItem
{
  my $self     = shift;
  my $id       = shift;
  my $user     = shift;
  
  my $exp = $self->SimpleSqlGet("SELECT hold FROM reviews WHERE id='$id' AND user='$user'");
  return $exp;
}

sub StickyHoldForItem
{
  my $self     = shift;
  my $id       = shift;
  my $user     = shift;
  
  my $exp = $self->SimpleSqlGet("SELECT sticky_hold FROM reviews WHERE id='$id' AND user='$user'");
  return $exp;
}

sub HoldExpiry
{
  my $self     = shift;
  my $id       = shift;
  my $user     = shift;
  my $readable = shift;
  
  my $exp = $self->HoldForItem($id,$user);
  $exp = $self->StickyHoldForItem($id,$user) unless $exp;
  $exp = $self->TwoWorkingDays() unless $exp;
  return ($readable)? $self->FormatDate($exp):$exp;
}

# Returned format is YYYY-MM-DD 23:59:59
sub TwoWorkingDays
{
  my $self = shift;
  my $time = shift;
  
  $time = $self->GetTodaysDate() unless $time;
  my $cal = Date::Calendar->new( $Profiles->{'US'} );
  my @parts = split '-', substr($time, 0, 10);
  my $date = $cal->add_delta_workdays($parts[0],$parts[1],$parts[2],2);
  $date = sprintf '%s-%s-%s 23:59:59', substr($date,0,4), substr($date,4,2), substr($date,6,2);
  return $date;
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
  if ( !$search || $search eq 'Identifier' )
  {
    $new_search = ($page eq 'queue')? 'q.id':'r.id';
  }
  if ( $search eq 'Time' )
  {
    $new_search = ($page eq 'queue')? 'q.time':'r.time';
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
  elsif ( $search eq 'Note' ) { $new_search = 'r.note'; }
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
  elsif ( $search eq 'ReviewDate' ) { $new_search = 'r.time'; }
  elsif ( $search eq 'Locked' ) { $new_search = 'q.locked'; }
  elsif ( $search eq 'ExpertCount' ) { $new_search = 'q.expcnt'; }
  elsif ( $search eq 'Reviews' )
  {
    $new_search = '(SELECT COUNT(*) FROM reviews r WHERE r.id=q.id)';
  }
  elsif ( $search eq 'Swiss' ) { $new_search = 'r.swiss'; }
  elsif ( $search eq 'Hold Thru' ) { $new_search = 'r.hold'; }
  elsif ( $search eq 'SysID' ) { $new_search = 's.sysid'; }
  elsif ( $search eq 'Holds' )
  {
    $new_search = '(SELECT COUNT(*) FROM reviews r WHERE r.id=q.id AND r.hold IS NOT NULL)';
  }
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
  my $download           = shift;

  $order = $self->ConvertToSearchTerm( $order, $page );
  $search1 = $self->ConvertToSearchTerm( $search1, $page );
  $search2 = $self->ConvertToSearchTerm( $search2, $page );
  $search3 = $self->ConvertToSearchTerm( $search3, $page );
  $dir = 'DESC' unless $dir;
  $offset = 0 unless $offset;
  $pagesize = 20 unless $pagesize > 0;
  my $sql = 'SELECT r.id,r.time,r.duration,r.user,r.attr,r.reason,r.note,r.renNum,r.expert,r.category,r.legacy,r.renDate,r.priority,r.swiss,';
  if ( $page eq 'adminReviews' )
  {
    $sql .= 'q.status,b.title,b.author,DATE(r.hold) FROM reviews r, queue q, bibdata b WHERE q.id=r.id AND q.id=b.id';
  }
  elsif ( $page eq 'holds' )
  {
    my $user = $self->get( "user" );
    $sql .= 'q.status,b.title,b.author,DATE(r.hold) FROM reviews r, queue q, bibdata b WHERE q.id=r.id AND q.id=b.id';
    $sql .= " AND r.user='$user' AND r.hold IS NOT NULL";
  }
  elsif ( $page eq 'adminHolds' )
  {
    $sql .= 'q.status,b.title,b.author,DATE(r.hold) FROM reviews r, queue q, bibdata b WHERE q.id=r.id AND q.id=b.id';
    $sql .= " AND r.hold IS NOT NULL";
  }
  elsif ( $page eq 'expert' )
  {
    $sql .= 'q.status,b.title,b.author,DATE(r.hold) FROM reviews r, queue q, bibdata b WHERE q.id=r.id AND q.id=b.id';
    $sql .= ' AND q.status=2';
  }
  elsif ( $page eq 'adminHistoricalReviews' )
  {
    my $doS = 'LEFT JOIN system s ON r.id=s.id';
    $doS = '' unless ($search1 . $search2 . $search3 . $order) =~ m/sysid/;
    my $doB = 'LEFT JOIN bibdata b ON r.id=b.id';
    $doB = '' unless ($search1 . $search2 . $search3 . $order) =~ m/^b\./;
    $sql .= "r.status,r.validated FROM historicalreviews r $doB $doS WHERE r.id IS NOT NULL";
  }
  elsif ( $page eq 'undReviews' )
  {
    $sql .= 'q.status,b.title,b.author,DATE(r.hold) FROM reviews r, queue q, bibdata b WHERE q.id=r.id AND q.id=b.id';
    $sql .= ' AND q.status=3';
  }
  elsif ( $page eq 'userReviews' )
  {
    my $user = $self->get( "user" );
    $sql = 'SELECT r.id, r.time, r.duration, r.user, r.attr, r.reason, r.note, r.renNum, r.expert, ' .
           'r.category, r.legacy, r.renDate, r.priority, r.swiss, q.status, b.title, b.author ' .
           "FROM $CRMSGlobals::reviewsTable r, $CRMSGlobals::queueTable q, bibdata b WHERE q.id=r.id AND q.id=b.id AND r.user='$user' AND q.status>0";
  }
  elsif ( $page eq 'editReviews' )
  {
    my $user = $self->get('user');
    my $yesterday = $self->GetYesterday();
    # Experts need to see stuff with any status; non-expert should only see stuff that hasn't been processed yet.
    my $restrict = ($self->IsUserExpert($user))? '':'AND q.status=0';
    $sql .= 'q.status, b.title, b.author, DATE(r.hold) FROM reviews r, queue q, bibdata b WHERE q.id=r.id AND q.id=b.id ' .
            "AND r.user='$user' AND (r.time>='$yesterday' OR r.hold IS NOT NULL) $restrict";
  }
  my $terms = $self->SearchTermsToSQL($search1, $search1value, $op1, $search2, $search2value, $op2, $search3, $search3value);
  $sql .= " AND $terms" if $terms;
  my $which = ($page eq 'holds')? 'r.hold':'r.time';
  if ( $startDate ) { $sql .= " AND $which >='$startDate 00:00:00' "; }
  if ( $endDate ) { $sql .= " AND $which <='$endDate 23:59:59' "; }
  my $limit = ($download)? '':"LIMIT $offset, $pagesize";
  $sql .= " ORDER BY $order $dir $limit ";
  #print "$sql<br/>\n";
  my $countSql = $sql;
  $countSql =~ s/(SELECT\s+).+?(FROM.+)/$1 COUNT(r.id),COUNT(DISTINCT r.id) $2/i;
  $countSql =~ s/(LIMIT\s\d+(,\s*\d+)?)//;
  my $ref = $self->get('dbh')->selectall_arrayref($countSql);
  my $totalReviews = $ref->[0]->[0];
  my $totalVolumes = $ref->[0]->[1];
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
  my $download     = shift;

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
  $order = $self->ConvertToSearchTerm( $order, $page );
  $search1 = 'r.id' unless $search1;
  my $order2 = ($dir eq 'ASC')? 'min':'max';
  my @rest = ();
  my $table = 'reviews';
  my $doQ = '';
  my $doS = '';
  my $status = 'r.status';
  if ($page eq 'adminHistoricalReviews')
  {
    $table = 'historicalreviews';
    $doS = 'LEFT JOIN system s ON r.id=s.id' if ($search1 . $search2 . $search3 . $order) =~ m/sysid/;
  }
  else
  {
    $doQ = 'INNER JOIN queue q ON r.id=q.id';
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
  $restrict = 'WHERE '.$restrict if $restrict;
  my $sql = "SELECT COUNT(r2.id) FROM $table r2 WHERE r2.id IN (SELECT r.id FROM $table r LEFT JOIN bibdata b ON r.id=b.id $doQ $doS $restrict)";
  #print "$sql<br/>\n";
  my $totalReviews = $self->SimpleSqlGet($sql);
  $sql = "SELECT COUNT(DISTINCT r.id) FROM $table r LEFT JOIN bibdata b ON r.id=b.id $doQ $doS $restrict";
  #print "$sql<br/>\n";
  my $totalVolumes = $self->SimpleSqlGet($sql);
  my $limit = ($download)? '':"LIMIT $offset, $pagesize";
  $offset = $totalVolumes-($totalVolumes % $pagesize) if $offset >= $totalVolumes;
  $sql = "SELECT r.id as id, $order2($order) AS ord FROM $table r LEFT JOIN bibdata b ON r.id=b.id $doQ $doS $restrict GROUP BY r.id " .
         "ORDER BY ord $dir $limit";
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
  my $download     = shift;
  
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
  $order = $self->ConvertToSearchTerm( $order, $page );
  $search1 = 'r.id' unless $search1;
  my $order2 = ($dir eq 'ASC')? 'min':'max';
  my @rest = ();
  my $table = 'reviews';
  my $top = 'bibdata b';
  my $status = 'r.status';
  if ($page eq 'adminHistoricalReviews')
  {
    $table = 'historicalreviews';
    $top = 'bibdata b ';
    $top .= 'LEFT JOIN system s ON b.id=s.id' if ($search1 . $search2 . $search3 . $order) =~ m/sysid/;
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
  #my $sql = "SELECT COUNT(r.id) FROM $top INNER JOIN $table r ON b.id=r.id $joins $restrict";
  my $sql = "SELECT COUNT(r2.id) FROM $table r2 WHERE r2.id IN (SELECT DISTINCT r.id FROM $top INNER JOIN $table r ON b.id=r.id $joins $restrict)";
  #print "$sql<br/>\n";
  my $totalReviews = $self->SimpleSqlGet($sql);
  $sql = "SELECT COUNT(DISTINCT r.id) FROM $top INNER JOIN $table r ON b.id=r.id $joins $restrict";
  #print "$sql<br/>\n";
  my $totalVolumes = $self->SimpleSqlGet($sql);
  $offset = $totalVolumes-($totalVolumes % $pagesize) if $offset >= $totalVolumes;
  my $limit = ($download)? '':"LIMIT $offset, $pagesize";
  $sql = "SELECT r.id as id, $order2($order) AS ord FROM $top INNER JOIN $table r ON b.id=r.id $joins $restrict GROUP BY r.id " .
         "ORDER BY ord $dir $limit";
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
  # Pull down search 2 if no search 1
  if (!length $search1value)
  {
    $search1 = $search2;
    $search2 = $search3;
    $search1value = $search2value;
    $search2value = $search3value;
    $search3value = $search3 = undef;
  }
  # Pull down search 3 if no search 2
  if (!length $search2value)
  {
    $search2 = $search3;
    $search2value = $search3value;
    $search3value = $search3 = undef;
  }
  $search1 = "YEAR($search1)" if $search1 eq 'pub_date';
  $search2 = "YEAR($search2)" if $search2 eq 'pub_date';
  $search3 = "YEAR($search3)" if $search3 eq 'pub_date';
  $search1value = $self->GetRightsNum($search1value) if $search1 eq 'r.attr';
  $search2value = $self->GetRightsNum($search2value) if $search2 eq 'r.attr';
  $search3value = $self->GetRightsNum($search3value) if $search3 eq 'r.attr';
  $search1value = $self->GetReasonNum($search1value) if $search1 eq 'r.reason';
  $search2value = $self->GetReasonNum($search2value) if $search2 eq 'r.reason';
  $search3value = $self->GetReasonNum($search3value) if $search3 eq 'r.reason';
  if ( $search1value =~ m/.*\*.*/ )
  {
    $search1value =~ s/\*/_____/gs;
    $search1term = "$search1 LIKE '$search1value'";
  }
  elsif (length $search1value)
  {
    $search1term = "$search1 = '$search1value'";
  }
  if ( $search2value =~ m/.*\*.*/ )
  {
    $search2value =~ s/\*/_____/gs;
    $search2term = sprintf("$search2 %sLIKE '$search2value'", ($op1 eq 'NOT')? 'NOT ':'');
  }
  elsif (length $search2value)
  {
    $search2term = sprintf("$search2 %s= '$search2value'", ($op1 eq 'NOT')? '!':'');
  }

  if ( $search3value =~ m/.*\*.*/ )
  {
    $search3value =~ s/\*/_____/gs;
    $search3term = sprintf("$search3 %sLIKE '$search3value'", ($op2 eq 'NOT')? 'NOT ':'');
  }
  elsif (length $search3value)
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
  $op1 = '' unless length $search1term and length $search2term;
  $tmpl =~ s/__op1__/$op1/;
  $tmpl =~ s/__2__/$search2term/;
  $op2 = '' unless length $search2term and length $search3term;
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
  $search1value = $self->GetRightsNum($search1value) if $search1 eq 'r.attr';
  $search2value = $self->GetRightsNum($search2value) if $search2 eq 'r.attr';
  $search3value = $self->GetRightsNum($search3value) if $search3 eq 'r.attr';
  $search1value = $self->GetReasonNum($search1value) if $search1 eq 'r.reason';
  $search2value = $self->GetReasonNum($search2value) if $search2 eq 'r.reason';
  $search3value = $self->GetReasonNum($search3value) if $search3 eq 'r.reason';
  # Pull down search 2 if no search 1
  if (!length $search1value)
  {
    $search1 = $search2;
    $search2 = $search3;
    $search1value = $search2value;
    $search2value = $search3value;
    $search3value = $search3 = undef;
  }
  # Pull down search 3 if no search 2
  if (!length $search2value)
  {
    $search2 = $search3;
    $search2value = $search3value;
    $search3value = $search3 = undef;
  }
  my %pref2table = ('b'=>'bibdata','r'=>$table,'q'=>'queue','s'=>'system');
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
    $search1term = "$search1_ LIKE '$search1value'";
    $search1term =~ s/_____/%/g;
  }
  elsif (length $search1value)
  {
    $search1term = "$search1_ = '$search1value'";
  }
  if ( $search2value =~ m/.*\*.*/ )
  {
    $search2value =~ s/\*/_____/gs;
    $search2term = sprintf("$search2_ %sLIKE '$search2value'", ($op1 eq 'NOT')? 'NOT ':'');
    $search2term =~ s/_____/%/g;
  }
  elsif (length $search2value)
  {
    $search2term = sprintf("$search2_ %s= '$search2value'", ($op1 eq 'NOT')? '!':'');
  }
  if ( $search3value =~ m/.*\*.*/ )
  {
    $search3value =~ s/\*/_____/gs;
    $search3term = sprintf("$search3_ %sLIKE '$search3value'", ($op2 eq 'NOT')? 'NOT ':'');
    $search3term =~ s/_____/%/g;
  }
  elsif (length $search3value)
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
  if (length $search1term)
  {
    $search1term =~ s/[a-z]\./t1./;
    if ($op1 eq 'AND' || !length $search2term)
    {
      $joins = "INNER JOIN $table1 t1 ON t1.id=r.id";
      push @rest, $search1term;
    }
    elsif ($op2 ne 'OR' || !length $search3term)
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
  if (length $search2term && !$did2)
  {
    $search2term =~ s/[a-z]\./t2./;
    if ($op2 eq 'AND' || !length $search3term)
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
  if (length $search3term && !$did3)
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
  my $order          = shift;
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

  my ($sql,$totalReviews,$totalVolumes,$n,$of) = $self->CreateSQL($stype, $page, $order, $dir, $search1, $search1value, $op1, $search2, $search2value, $op2, $search3, $search3value, $startDate, $endDate, 0, 0, 1 );
  
  my $ref = $self->get('dbh')->selectall_arrayref( $sql );

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
    elsif ( $page eq 'adminReviews' || $page eq 'adminHolds' )
    {
      $buffer .= qq{id\ttitle\tauthor\ttime\tstatus\tuser\tattr\treason\tcategory\tnote\tswiss\thold thru};
    }
    elsif ( $page eq 'adminHistoricalReviews' )
    {
      $buffer .= qq{id\tsystem id\ttitle\tauthor\tpub date\ttime\tstatus\tlegacy\tuser\tattr\treason\tcategory\tnote\tvalidated\tswiss};
    }
    $buffer .= sprintf("%s\n", ($self->IsUserAdmin())? "\tpriority":'');
    if ($stype eq 'reviews')
    {
      $buffer .= $self->UnpackResults($page, $ref);
    }
    else
    {
      $order = 'Identifier' if $order eq 'SysID';
      $order = $self->ConvertToSearchTerm($order);
      foreach my $row ( @{$ref} )
      {
        my $id = $row->[0];
        my $qrest = ($page ne 'adminHistoricalReviews')? ' AND r.id=q.id':'';
        $sql = 'SELECT r.id,r.time,r.duration,r.user,r.attr,r.reason,r.note,r.renNum,r.expert,' .
               "r.category,r.legacy,r.renDate,r.priority,r.swiss,$status," .
               (($page eq 'adminHistoricalReviews')?
                 'r.validated ':'b.title,b.author,r.hold ') .
               "FROM $top INNER JOIN $table r ON b.id=r.id " .
               "WHERE r.id='$id' AND r.id=b.id $qrest ORDER BY $order $dir";
        # FIXME: why is the AND r.id=b.id there? It's an inner join already.
        #print "$sql<br/>\n";
        my $ref2;
        eval{$ref2 = $self->get( 'dbh' )->selectall_arrayref( $sql );};
        if ($@)
        {
          $self->SetError("SQL failed: '$sql' ($@)");
          $self->DownloadSpreadSheet( "SQL failed: '$sql' ($@)" );
          return 0;
        }
        $buffer .= $self->UnpackResults($page, $ref2);
      }
    }
  }
  $self->DownloadSpreadSheet( $buffer );
  return ($buffer)? 1:0;
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
    for (my $i = 0; $i < scalar @{$row}; $i++)
    {
      $row->[$i] =~ s/[\n\r\t]+/ /gs;
    }
    my $id         = $row->[0];
    my $time       = $row->[1];
    my $duration   = $row->[2];
    my $user       = $row->[3];
    my $attr       = $self->GetRightsName($row->[4]);
    my $reason     = $self->GetReasonName($row->[5]);
    my $note       = $row->[6];
    my $renNum     = $row->[7];
    my $expert     = $row->[8];
    my $category   = $row->[9];
    my $legacy     = $row->[10];
    my $renDate    = $row->[11];
    my $priority   = $self->StripDecimal($row->[12]);
    my $swiss      = $row->[13];
    my $status     = $row->[14];
    my $title      = $row->[15]; # Validated in historical
    my $author     = $row->[16];
    my $hold       = $row->[17];
    
    if ( $page eq 'userReviews')
    {
      #for reviews
      #id, title, author, review date, attr, reason, category, note.
      $buffer .= qq{$id\t$title\t$author\t$time\t$attr\t$reason\t$category\t$note};
    }
    elsif ( $page eq 'editReviews' || $page eq 'holds' )
    {
      #for editReviews
      #id, title, author, review date, attr, reason, category, note.
      $buffer .= qq{$id\t$title\t$author\t$time\t$attr\t$reason\t$category\t$note\t$hold};
    }
    elsif ( $page eq 'undReviews' )
    {
      #for und/nfi
      #id, title, author, review date, status, user, attr, reason, category, note.
      $buffer .= qq{$id\t$title\t$author\t$time\t$status\t$user\t$attr\t$reason\t$category\t$note}
    }
    elsif ( $page eq 'expert' )
    {
      #for expert
      #id, title, author, review date, status, user, attr, reason, category, note.
      $buffer .= qq{$id\t$title\t$author\t$time\t$status\t$user\t$attr\t$reason\t$category\t$note};
    }
    elsif ( $page eq 'adminReviews' || $page eq 'adminHolds' )
    {
      #for adminReviews
      #id, title, author, review date, status, user, attr, reason, category, note.
      $buffer .= qq{$id\t$title\t$author\t$time\t$status\t$user\t$attr\t$reason\t$category\t$note\t$swiss\t$hold};
    }
    elsif ( $page eq 'adminHistoricalReviews' )
    {
      $author = $self->SimpleSqlGet("SELECT author FROM bibdata WHERE id='$id'");
      $title = $self->SimpleSqlGet("SELECT title FROM bibdata WHERE id='$id'");
      my $pubdate = $self->SimpleSqlGet("SELECT YEAR(pub_date) FROM bibdata WHERE id='$id'");
      $pubdate = '?' unless $pubdate;
      my $validated = $row->[15];
      #id, title, author, review date, status, user, attr, reason, category, note, validated
      my $sysid = $self->SimpleSqlGet("SELECT sysid FROM system WHERE id='$id'");
      $buffer .= qq{$id\t$sysid\t$title\t$author\t$pubdate\t$time\t$status\t$legacy\t$user\t$attr\t$reason\t$category\t$note\t$validated\t$swiss};
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
  my $priority  = shift;
  my $pre       = shift;
  
  my $buffer;
  if ($pre)
  {
    $buffer = $self->CreatePreDeterminationsBreakdownData("\t", $startDate, $endDate, $monthly, undef, $priority);
  }
  else
  {
    $buffer = $self->CreateDeterminationsBreakdownData("\t", $startDate, $endDate, $monthly, undef, $priority);
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
  
  my $buffer = $self->GetQueueRef($order, $dir, $search1, $search1Value, $op1, $search2, $search2Value, $startDate, $endDate, 0, 0, 1);
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

  $pagesize = 20 unless $pagesize > 0;
  $offset = 0 unless $offset > 0;

  #print("GetReviewsRef('$page','$order','$dir','$search1','$search1Value','$op1','$search2','$search2Value','$op2','$search3','$search3Value','$startDate','$endDate','$offset','$pagesize');<br/>\n");
  my ($sql,$totalReviews,$totalVolumes) = $self->CreateSQLForReviews($page, $order, $dir, $search1, $search1Value, $op1, $search2, $search2Value, $op2, $search3, $search3Value, $startDate, $endDate, $offset, $pagesize);
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
      my $id = $row->[0];
      my $item = {id         => $id,
                  time       => $row->[1],
                  date       => $date,
                  duration   => $row->[2],
                  user       => $row->[3],
                  attr       => $self->GetRightsName($row->[4]),
                  reason     => $self->GetReasonName($row->[5]),
                  note       => $row->[6],
                  renNum     => $row->[7],
                  expert     => $row->[8],
                  category   => $row->[9],
                  legacy     => $row->[10],
                  renDate    => $row->[11],
                  priority   => $self->StripDecimal($row->[12]),
                  swiss      => $row->[13],
                  status     => $row->[14],
                  title      => $row->[15],
                  author     => $row->[16]
                 };
      ${$item}{'hold'} = $row->[17] if $page eq 'adminReviews' or $page eq 'editReviews' or $page eq 'holds' or $page eq 'adminHolds';
      if ($page eq 'adminHistoricalReviews')
      {
        my $pubdate = $self->SimpleSqlGet("SELECT YEAR(pub_date) FROM bibdata WHERE id='$id'");
        $pubdate = '?' unless $pubdate;
        ${$item}{'pubdate'} = $pubdate;
        ${$item}{'author'} = $self->SimpleSqlGet("SELECT author FROM bibdata WHERE id='$id'");
        ${$item}{'title'} = $self->SimpleSqlGet("SELECT title FROM bibdata WHERE id='$id'");
        ${$item}{'sysid'} = $self->SimpleSqlGet("SELECT sysid FROM system WHERE id='$id'");
        ${$item}{'validated'} = $row->[15];
      }
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
  my $order = $self->ConvertToSearchTerm($_[1], $page);
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
  my $doS = '';
  my $status = 'r.status';
  if ($page eq 'adminHistoricalReviews')
  {
    $doS = 'LEFT JOIN system s ON r.id=s.id';
    $table = 'historicalreviews';
  }
  else
  {
    $doQ = 'INNER JOIN queue q ON r.id=q.id';
    $status = 'q.status';
  }
  my $return = ();
  foreach my $row ( @{$ref} )
  {
    my $id = $row->[0];
    $sql = 'SELECT r.id, r.time, r.duration, r.user, r.attr, r.reason, r.note, r.renNum, r.expert, ' .
           "r.category, r.legacy, r.renDate, r.priority, r.swiss, $status, b.title, b.author" .
           (($page eq 'adminHistoricalReviews')? ', YEAR(b.pub_date), r.validated, s.sysid ':' ') .
           (($page eq 'adminReviews' || $page eq 'editReviews' || $page eq 'holds' || $page eq 'adminHolds')? ', DATE(r.hold) ':' ') .
           "FROM $table r LEFT JOIN bibdata b ON r.id=b.id $doQ $doS " .
           "WHERE r.id='$id' ORDER BY $order $dir";
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
                  category   => $row->[9],
                  legacy     => $row->[10],
                  renDate    => $row->[11],
                  priority   => $self->StripDecimal($row->[12]),
                  swiss      => $row->[13],
                  status     => $row->[14],
                  title      => $row->[15],
                  author     => $row->[16]
                 };
      ${$item}{'hold'} = $row->[17] if $page eq 'adminReviews' or $page eq 'editReviews' or $page eq 'holds' or $page eq 'adminHolds';;
      if ($page eq 'adminHistoricalReviews')
      {
        my $pubdate = $row->[17];
        $pubdate = '?' unless $pubdate;
        ${$item}{'pubdate'} = $pubdate;
        ${$item}{'validated'} = $row->[18];
        ${$item}{'sysid'} = $self->SimpleSqlGet("SELECT sysid FROM system WHERE id='$id'");
      }
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
  my $order = $self->ConvertToSearchTerm($_[1], $page);
  my $dir = $_[2];
  
  my $table ='reviews';
  my $doQ = '';
  my $doS = '';
  my $status = 'r.status';
  if ($page eq 'adminHistoricalReviews')
  {
    $table = 'historicalreviews';
    $doS = 'INNER JOIN system s ON r.id=s.id';
  }
  else
  {
    $doQ = 'INNER JOIN queue q ON r.id=q.id';
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
    $sql = 'SELECT r.id, r.time, r.duration, r.user, r.attr, r.reason, r.note, r.renNum, r.expert, ' .
           "r.category, r.legacy, r.renDate, r.priority, r.swiss, $status, b.title, b.author" .
           (($page eq 'adminHistoricalReviews')? ', YEAR(b.pub_date), r.validated, s.sysid ':' ') .
           (($page eq 'adminReviews' || $page eq 'editReviews' || $page eq 'holds' || $page eq 'adminHolds')? ', DATE(r.hold) ':' ') .
           "FROM $table r LEFT JOIN bibdata b ON r.id=b.id $doQ $doS " .
           "WHERE r.id='$id' ORDER BY $order $dir";
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
                  category   => $row->[9],
                  legacy     => $row->[10],
                  renDate    => $row->[11],
                  priority   => $self->StripDecimal($row->[12]),
                  swiss      => $row->[13],
                  status     => $row->[14],
                  title      => $row->[15],
                  author     => $row->[16]
                 };
      ${$item}{'hold'} = $row->[17] if $page eq 'adminReviews' or $page eq 'editReviews' or $page eq 'holds';
      if ($page eq 'adminHistoricalReviews')
      {
        my $pubdate = $row->[17];
        $pubdate = '?' unless $pubdate;
        ${$item}{'pubdate'} = $pubdate;
        ${$item}{'validated'} = $row->[18];
        ${$item}{'sysid'} = $self->SimpleSqlGet("SELECT sysid FROM system WHERE id='$id'");
      }
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

  my ($sql,$totalReviews,$totalVolumes,$n,$of) = $self->CreateSQL($stype, $page, undef, 'ASC', $search1, $search1value, $op1, $search2, $search2value, $op2, $search3, $search3value, $startDate, $endDate, $stype );
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
  elsif ($order eq 'holds') { $order = '(SELECT COUNT(*) FROM reviews r WHERE r.id=q.id AND r.hold IS NOT NULL)'; }
  elsif ($order eq 'presented')
  {
    $order = sprintf "q.priority $dir, (SELECT COUNT(*) FROM reviews WHERE id=q.id) DESC, q.status DESC, q.time %s", ($dir eq 'DESC')? 'ASC':'DESC';
    $dir = '';
  }
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
  my @return = ();
  $sql = 'SELECT q.id, q.time, q.status, q.locked, YEAR(b.pub_date), q.priority, q.expcnt, b.title, b.author ' .
         "FROM queue q, bibdata b $restrict ORDER BY $order $dir $limit";
  #print "$sql<br/>\n";
  my $ref = undef;
  eval {
    $ref = $self->get( 'dbh' )->selectall_arrayref( $sql );
  };
  if ($@)
  {
    $self->SetError($@);
  }
  my $data = join "\t", ('ID','Title','Author','Pub Date','Date Added','Status','Locked','Priority','Reviews','Expert Reviews','Holds');
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
    $sql = "SELECT COUNT(*) FROM reviews WHERE id='$id' AND hold IS NOT NULL";
    #print "$sql<br/>\n";
    my $holds = $self->SimpleSqlGet($sql);
    my $item = {id         => $id,
                time       => $row->[1],
                date       => $date,
                status     => $row->[2],
                locked     => $row->[3],
                pubdate    => $pubdate,
                priority   => $self->StripDecimal($row->[5]),
                expcnt     => $row->[6],
                title      => $row->[7],
                author     => $row->[8],
                reviews    => $reviews,
                holds      => $holds
               };
    push @return, $item;
    if ($download)
    {
      $data .= sprintf("\n$id\t%s\t%s\t%s\t$date\t%s\t%s\t%s\t$reviews\t%s\t$holds",
                       $row->[7], $row->[8], $row->[4], $row->[2], $row->[3], $self->StripDecimal($row->[5]), $row->[6]);
    }
  }
  if (!$download)
  {
    my $n = POSIX::ceil($offset/$pagesize+1);
    my $of = POSIX::ceil($totalVolumes/$pagesize);
    $n = 0 if $of == 0;
    $data = {'rows' => \@return,
             'volumes' => $totalVolumes,
             'page' => $n,
             'of' => $of
            };
  }
  return $data;
}

sub LinkToPT
{
  my $self  = shift;
  my $id    = shift;
  my $title = shift;

  $title = $self->GetTitle( $id ) unless $title;
  $title = CGI::escapeHTML($title);
  my $url = 'https://babel.hathitrust.org/cgi/pt?attr=1&amp;id=';
  $self->ClearErrors();
  return "<a href='$url$id' target='_blank'>$title</a>";
}

sub LinkToReview
{
  my $self  = shift;
  my $id    = shift;
  my $title = shift;

  $title = $self->GetTitle( $id ) unless $title;
  $title = CGI::escapeHTML($title);
  my $url = "/cgi/c/crms/crms?p=review;barcode=$id;editing=1";
  $self->ClearErrors();
  return "<a href='$url' target='_blank'>$title</a>";
}

sub DetailInfo
{
  my $self   = shift;
  my $id     = shift;
  my $user   = shift;
  my $page   = shift;
  my $review = shift;

  my $url = "/cgi/c/crms/crms?p=detailInfo&amp;id=$id&amp;user=$user&amp;page=$page";
  $url .= ';review=1' if $review;
  return "<a href='$url' target='_blank'>$id</a>";
}

sub GetStatus
{
  my $self = shift;
  my $id   = shift;

  my $sql = "SELECT status FROM $CRMSGlobals::queueTable WHERE id='$id'";
  return $self->SimpleSqlGet( $sql );
}

sub IsVolumeInQueue
{
  my $self = shift;
  my $id   = shift;

  my $sql = "SELECT COUNT(id) FROM $CRMSGlobals::queueTable WHERE id='$id'";
  return ($self->SimpleSqlGet($sql) > 0);
}

sub ValidateAttrReasonCombo
{
  my $self    = shift;
  my $attr    = shift;
  my $reason  = shift;

  return 13 if $reason == 13;
  my $code = $self->GetCodeFromAttrReason($attr,$reason);
  $self->SetError( "bad attr/reason: $attr/$reason" ) unless $code;
  return $code;
}

sub GetAttrReasonCom
{
  my $self = shift;
  my $in   = shift;

  my %codes = (1 => 'pd/ncn',  2 => 'pd/ren',  3 => 'pd/cdpp', 4 => 'ic/ren',
               5 => 'ic/cdpp', 6 => 'und/nfi', 7 => 'pdus/cdpp', 8 => 'pd/add');

  my %str   = ('pd/ncn' => 1,  'pd/ren'  => 2, 'pd/cdpp' => 3, 'ic/ren' => 4,
               'ic/cdpp' => 5, 'und/nfi' => 6, 'pdus/cdpp' => 7 , 'pd/add' => 8);

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
  elsif ( $code eq '8' ) { return (1,14); }
}

sub GetCodeFromAttrReason
{
  my $self   = shift;
  my $attr   = shift;
  my $reason = shift;

  if ($attr == 1 and $reason == 2) { return 1; }
  if ($attr == 1 and $reason == 7) { return 2; }
  if ($attr == 1 and $reason == 9) { return 3; }
  if ($attr == 2 and $reason == 7) { return 4; }
  if ($attr == 2 and $reason == 9) { return 5; }
  if ($attr == 5 and $reason == 8) { return 6; }
  if ($attr == 9 and $reason == 9) { return 7; }
  if ($attr == 1 and $reason == 14) { return 8; }
}


sub GetAttrReasonCode
{
  my $self = shift;
  my $id   = shift;
  my $user = shift;

  my $sql = "SELECT attr, reason FROM reviews WHERE id='$id' AND user='$user'";
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
  my $sql = "SELECT id FROM $CRMSGlobals::queueTable WHERE id='$id'";
  my @rows = $dbh->selectrow_array( $sql );
  return scalar @rows;
}

sub AddUser
{
  my $self       = shift;
  my $id         = shift;
  my $kerberos   = shift;
  my $name       = shift;
  my $reviewer   = shift;
  my $advanced   = shift;
  my $expert     = shift;
  my $extadmin   = shift;
  my $admin      = shift;
  my $superadmin = shift;
  my $note       = shift;

  $reviewer = ($reviewer)? 1:0;
  $advanced = ($advanced)? 1:0;
  $expert = ($expert)? 1:0;
  $extadmin = ($extadmin)? 1:0;
  $admin = ($admin)? 1:0;
  $superadmin = ($superadmin)? 1:0;
  # Remove surrounding whitespace on user id, kerberos, and name.
  $id =~ s/^\s*(.+?)\s*$/$1/;
  $kerberos =~ s/^\s*(.+?)\s*$/$1/;
  $name =~ s/^\s*(.+?)\s*$/$1/;
  $kerberos = $self->SimpleSqlGet("SELECT kerberos FROM users WHERE id='$id'") unless $kerberos;
  $name = $self->SimpleSqlGet("SELECT name FROM users WHERE id='$id'") unless $name;
  $note = $self->SimpleSqlGet("SELECT note FROM users WHERE id='$id'") unless $note;
  my $sql = "REPLACE INTO users (id,kerberos,name,reviewer,advanced,expert,extadmin,admin,superadmin,note)" .
            " VALUES ('$id','$kerberos','$name',$reviewer,$advanced,$expert,$extadmin,$admin,$superadmin,'$note')";
  #print "$sql<br/>\n";
  $self->PrepareSubmitSql($sql);
  return 1;
}

sub DeleteUser
{
  my $self = shift;
  my $id   = shift;
  
  my $sql = "DELETE FROM users WHERE id='$id'";
  $self->PrepareSubmitSql($sql);
}


sub CheckReviewer
{
  my $self = shift;
  my $user = shift;
  my $exp  = shift;

  return 1 if $user eq 'autocrms';
  my $isReviewer = $self->IsUserReviewer($user);
  my $isAdvanced = $self->IsUserAdvanced($user);
  my $isExpert = $self->IsUserExpert($user);
  return $isExpert if $exp;
  return ($isReviewer || $isAdvanced || $isExpert);
}

sub GetUserName
{
  my $self = shift;
  my $user = shift;

  $user = $self->get('user') unless $user;
  my $sql = "SELECT name FROM users WHERE id='$user'";
  return $self->SimpleSqlGet( $sql );
}

sub GetUserNote
{
  my $self = shift;
  my $user = shift;

  $user = $self->get('user') unless $user;
  my $sql = "SELECT note FROM users WHERE id='$user'";
  return $self->SimpleSqlGet( $sql );
}

sub GetUserKerberosID
{
  my $self = shift;
  my $user = shift;

  $user = $self->get('user') unless $user;
  my $sql = "SELECT kerberos FROM users WHERE id='$user'";
  return $self->SimpleSqlGet( $sql );
}


sub GetAliasUserName
{
  my $self = shift;
  my $user = shift;

  $user = $self->get('user') unless $user;
  my $sql = "SELECT alias FROM users WHERE id='$user'";
  return $self->SimpleSqlGet( $sql );
}

sub ChangeAliasUserName
{
  my $self     = shift;
  my $user     = shift;
  my $new_user = shift;

  $user = $self->get('user') unless $user;
  my $sql = "UPDATE users SET alias='$new_user' WHERE id='$user'";
  $self->PrepareSubmitSql( $sql );
}

sub SameUser
{
  my $self = shift;
  my $u1   = shift;
  my $u2   = shift;
  
  $u1 = $self->SimpleSqlGet("SELECT kerberos FROM users WHERE id='$u1'");
  $u2 = $self->SimpleSqlGet("SELECT kerberos FROM users WHERE id='$u2'");
  return $u1 eq $u2 and $u1 ne '';
}

sub CanChangeToUser
{
  my $self = shift;
  my $me   = shift;
  my $him  = shift;
  
  return 0 if $me eq $him;
  return 1 if $self->SameUser($me, $him);
  return 0 if not ($self->IsUserAdmin($me) && $self->WhereAmI());
  my $sql = "SELECT reviewer,advanced,expert,admin,superadmin FROM users WHERE id='$me'";
  my $ref1 = $self->get('dbh')->selectall_arrayref($sql);
  $ref1 = $ref1->[0];
  $sql = "SELECT reviewer,advanced,expert,admin,superadmin FROM users WHERE id='$him'";
  my $ref2 = $self->get('dbh')->selectall_arrayref($sql);
  $ref2 = $ref2->[0];
  return 0 if $ref2->[4] and not $ref1->[4];
  return 1 if $ref1->[4];
  return 0 if $ref2->[3] and not $ref1->[3];
  return 1 if $ref1->[3];
  return 0 if $ref2->[2] and not $ref1->[2];
  return 1 if $ref1->[2];
  return 0 if $ref2->[1] and not $ref1->[1];
  return 1 if $ref1->[1];
  return 0 if $ref2->[0] and not $ref1->[0];
  return 1 if $ref1->[0];
  return 1;
}

sub IsUserReviewer
{
  my $self = shift;
  my $user = shift;

  $user = $self->get('user') unless $user;
  my $sql = "SELECT reviewer FROM users WHERE id='$user'";
  return $self->SimpleSqlGet( $sql );
}

sub IsUserAdvanced
{
  my $self = shift;
  my $user = shift;

  $user = $self->get('user') unless $user;
  my $sql = "SELECT advanced FROM users WHERE id='$user'";
  return $self->SimpleSqlGet( $sql );
}

sub IsUserExpert
{
  my $self = shift;
  my $user = shift;

  $user = $self->get('user') unless $user;
  my $sql = "SELECT expert FROM users WHERE id='$user'";
  return $self->SimpleSqlGet( $sql );
}

sub IsUserExtAdmin
{
  my $self = shift;
  my $user = shift;

  $user = $self->get('user') unless $user;
  my $sql = "SELECT extadmin FROM users WHERE id='$user'";
  return $self->SimpleSqlGet( $sql );
}

sub IsUserAdmin
{
  my $self = shift;
  my $user = shift;

  $user = $self->get('user') unless $user;
  my $sql = "SELECT (admin OR superadmin) FROM users WHERE id='$user'";
  return $self->SimpleSqlGet( $sql );
}

sub IsUserSuperAdmin
{
  my $self = shift;
  my $user = shift;

  $user = $self->get('user') unless $user;
  my $sql = "SELECT superadmin FROM users WHERE id='$user'";
  return $self->SimpleSqlGet( $sql );
}

# If order, orders by privilege level from low to high
sub GetUsers
{
  my $self  = shift;
  my $order = shift;
  
  my $dbh  = $self->get( 'dbh' );
  $order = ($order)? 'ORDER BY expert ASC, name ASC':'ORDER BY name ASC';
  my $sql = "SELECT id FROM users $order";
  my $ref = $dbh->selectall_arrayref( $sql );
  my @users = map { $_->[0]; } @{ $ref };
  return \@users;
}

sub IsUserIncarnationExpertOrHigher
{
  my $self = shift;
  my $user = shift;
  
  $user = $self->get('user') unless $user;
  my $sql = "SELECT id FROM users WHERE kerberos!='' AND kerberos IN (SELECT DISTINCT kerberos FROM users WHERE id='$user')";
  my $ref = $self->get('dbh')->selectall_arrayref($sql);
  foreach my $row (@{$ref})
  {
    my $id = $row->[0];
    return 1 if $self->IsUserExpert($id);
    return 1 if $self->IsUserAdmin($id);
  }
  return 0;
}

# Default 'UM', can also be 'IU', 'UW', or 'UMN'
sub GetUserAffiliation
{
  my $self = shift;
  my $id   = shift;
  
  my @parts = split '@', $id;
  if (scalar @parts > 1)
  {
    my $suff = $parts[1];
    return 'IU' if $suff eq 'indiana.edu';
    return 'UW' if $suff eq 'library.wisc.edu';
    return 'UMN' if $suff eq 'umn.edu';
  }
  return ($id =~ m/annekz/)? 'UM':'UM-ERAU';
}

sub GetUsersWithAffiliation
{
  my $self  = shift;
  my $aff   = shift;
  my $order = shift;
  
  my $users = $self->GetUsers($order);
  my @ausers = ();
  foreach my $user ( @{$users} )
  {
    push @ausers, $user if $aff eq $self->GetUserAffiliation($user);
  }
  return \@ausers;
}

sub CanUserSeeInstitutionalStats
{
  my $self = shift;
  my $inst = shift;
  my $user = shift;

  return 0 unless $inst;
  $user = $self->get('user') unless $user;
  return 1 if $self->IsUserExpert($user) or $self->IsUserAdmin($user);
  my $aff = $self->GetUserAffiliation($user);
  return ($aff eq $inst && $self->IsUserExtAdmin($user));
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
  my %months = ('Jan' => '01',
                'Feb' => '02',
                'Mar' => '03',
                'Apr' => '04',
                'May' => '05',
                'Jun' => '06',
                'Jul' => '07',
                'Aug' => '08',
                'Sep' => '09',
                'Oct' => '10',
                'Nov' => '11',
                'Dec' => '12',
               );
  my $month = $months{substr ($newtime,4,3)};
  return ($year, $month);
}

# Convert a yearmonth-type string, e.g. '2009-08' to English: 'August 2009'
# Pass 1 as a second parameter to leave it long, otherwise truncates to 3-char abbreviation
sub YearMonthToEnglish
{
  my $self      = shift;
  my $yearmonth = shift;
  my $long      = shift;

  my %months = ('01' => 'January',
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

# Returns an array of year strings e.g. ('2009','2010') for all years for which we have data.
sub GetAllExportYears
{
  my $self = shift;
  
  my @list = ();
  my $min = $self->SimpleSqlGet('SELECT MIN(time) FROM exportdata');
  my $max = $self->SimpleSqlGet('SELECT MAX(time) FROM exportdata');
  if ($min && $max)
  {
    $min = substr($min,0,4);
    $max = substr($max,0,4);
    @list = ($min..$max);
  }
  return \@list;
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
  
  #print "CreateExportData('$delimiter', $cumulative, $doCurrentMonth, '$start', '$end', '$doPercent')<br/>\n";
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
    @dates = @{$self->GetAllExportYears()};
  }
  else
  {
    my $sql = "SELECT DISTINCT(DATE_FORMAT(date,'%Y-%m')) FROM exportstats WHERE DATE_FORMAT(date,'%Y-%m')>='$start' AND DATE_FORMAT(date,'%Y-%m')<='$end' ORDER BY date ASC";
    #print "$sql<br/>\n";
    @dates = map {$_->[0];} @{$dbh->selectall_arrayref( $sql )};
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
    my %cats = ('pd/ren' => 0, 'pd/ncn' => 0, 'pd/cdpp' => 0, 'pd/crms' => 0, 'pd/add' => 0, 'pdus/cdpp' => 0,
                'ic/ren' => 0, 'ic/cdpp' => 0, 'ic/crms' => 0,
                'und/nfi' => 0, 'und/crms' => 0,
                'All PD' => 0, 'All IC' => 0, 'All UND' => 0,
                'Status 4' => 0, 'Status 5' => 0, 'Status 6' => 0, 'Status 7' => 0);
    my $lastDay;
    if (!$cumulative)
    {
      my ($year,$month) = split '-', $date;
      $lastDay = Days_in_Month($year,$month);
    }
    my $sql = 'SELECT SUM(e.pd_ren),SUM(e.pd_ncn),SUM(e.pd_cdpp),SUM(e.pd_crms),SUM(e.pd_add),SUM(e.pdus_cdpp),' .
               'SUM(e.ic_ren),SUM(e.ic_cdpp),SUM(e.ic_crms),SUM(e.und_nfi),SUM(e.und_crms),' .
               'SUM(d.s4),SUM(d.s5),SUM(d.s6),SUM(d.s7),SUM(d.s8),SUM(d.s9) ' .
               'FROM exportstats e INNER JOIN determinationsbreakdown d ON e.date=d.date WHERE ' .
              "e.date LIKE '$date%'";
    #print "$date: $sql<br/>\n";
    my $ref = $dbh->selectall_arrayref( $sql );
    #printf "$date: $sql : %d items<br/>\n", scalar @{$ref};
    $stats{'pd/ren'}{$date}    += $ref->[0]->[0];
    $stats{'pd/ncn'}{$date}    += $ref->[0]->[1];
    $stats{'pd/cdpp'}{$date}   += $ref->[0]->[2];
    $stats{'pd/crms'}{$date}   += $ref->[0]->[3];
    $stats{'pd/add'}{$date}    += $ref->[0]->[4];
    $stats{'pdus/cdpp'}{$date} += $ref->[0]->[5];
    $stats{'ic/ren'}{$date}    += $ref->[0]->[6];
    $stats{'ic/cdpp'}{$date}   += $ref->[0]->[7];
    $stats{'ic/crms'}{$date}   += $ref->[0]->[8];
    $stats{'und/nfi'}{$date}   += $ref->[0]->[9];
    $stats{'und/crms'}{$date}  += $ref->[0]->[10];
    $stats{'Status 4'}{$date}  += $ref->[0]->[11];
    $stats{'Status 5'}{$date}  += $ref->[0]->[12];
    $stats{'Status 6'}{$date}  += $ref->[0]->[13];
    $stats{'Status 7'}{$date}  += $ref->[0]->[14];
    $stats{'Status 8'}{$date}  += $ref->[0]->[15];
    $stats{'Status 9'}{$date}  += $ref->[0]->[16];
    for my $cat (keys %cats)
    {
      next if $cat =~ m/(All)|(Status)/;
      my $attr = $cat;
      $attr =~ s/(.+?)\/.*/$1/;
      my $allkey = 'All ' . uc substr $attr, 0, ($attr eq 'und')? 3:2;
      $stats{$allkey}{$date} += $stats{$cat}{$date};
      #printf "\$stats{'$allkey'}{'$date'} += \$stats{'$cat'}{'$date'} (%d)<br>\n", $stats{$cat}{$date} if $cat =~ m/und/;
    }
  }
  $report .= "\n";
  my @titles = ('All PD', 'pd/ren', 'pd/ncn', 'pd/cdpp', 'pd/crms', 'pd/add', 'pdus/cdpp',
                'All IC', 'ic/ren', 'ic/cdpp', 'ic/crms',
                'All UND', 'und/nfi', 'und/crms', 'Total',
                'Status 4', 'Status 5', 'Status 6', 'Status 7', 'Status 8', 'Status 9');
  my %monthTotals = ();
  my %catTotals = ('All PD' => 0, 'All IC' => 0, 'All UND' => 0);
  my $gt = 0;
  foreach my $date (@usedates)
  {
    my $monthTotal = $stats{'All PD'}{$date} + $stats{'All IC'}{$date} + $stats{'All UND'}{$date};
    $catTotals{'All PD'} += $stats{'All PD'}{$date};
    $catTotals{'All IC'} += $stats{'All IC'}{$date};
    $catTotals{'All UND'} += $stats{'All UND'}{$date};
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
  my $year       = shift;

  my $start = $year . '-01';
  my $end = $year . '-12';
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
  my %majors = ('All PD' => 1, 'All IC' => 1, 'All UND' => 1);
  my $titleline = '';
  foreach my $line (@lines)
  {
    my @items = split(',', $line);
    my $i = 0;
    $title = shift @items;
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
    $report .= $newline;
  }
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
  my @titles = ($type == 1)? ('Total'):('All PD','All IC','All UND');
  my %titleh = ('All PD' => $lines[0],'All IC' => $lines[7],'All UND' => $lines[11],'Total' => $lines[14]);
  my @elements = ();
  my %colors = ('All PD' => '#22BB00', 'All IC' => '#FF2200', 'All UND' => '#0088FF', 'Total' => '#FFFF00');
  my %totals = ('All PD' => 0, 'All IC' => 0, 'All UND' => 0);
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
    my @colorlist = ($colors{'All PD'}, $colors{'All IC'}, $colors{'All UND'});
    my @vals = ();
    foreach my $title (@titles)
    {
      my $pct = 0.0;
      eval { $pct = 100.0 * $totals{$title} / $gt; };
      push(@vals,sprintf('{"value":%s,"label":"%s\n%.1f%%"}', $totals{$title}, $title, $pct));
    }
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

sub CreatePreDeterminationsBreakdownData
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
  my $what = 'date';
  $what = 'DATE_FORMAT(date, "%Y-%m")' if $monthly;
  my $sql = "SELECT DISTINCT($what) FROM predeterminationsbreakdown WHERE date>='$start' AND date<='$end'";
  #print "$sql<br/>\n";
  my @dates = map {$_->[0];} @{$self->get('dbh')->selectall_arrayref( $sql )};
  if (scalar @dates && !$justThisMonth)
  {
    my $startEng = $self->YearMonthToEnglish(substr($dates[0],0,7));
    my $endEng = $self->YearMonthToEnglish(substr($dates[-1],0,7));
    $titleDate = ($startEng eq $endEng)? $startEng:sprintf("%s to %s", $startEng, $endEng);
  }
  my $report = ($title)? "$title\n":"Preliminary Determinations Breakdown $titleDate\n";
  my @titles = ('Date','Status 2','Status 3','Status 4','Status 8','Total','Status 2','Status 3','Status 4','Status 8');
  $report .= join($delimiter, @titles) . "\n";
  my @totals = (0,0,0,0);
  foreach my $date (@dates)
  {
    my ($y,$m,$d) = split '-', $date;
    my $date1 = $date;
    my $date2 = $date;
    if ($monthly)
    {
      $date1 = "$date-01";
      my $lastDay = Days_in_Month($y,$m);
      $date2 = "$date-$lastDay";
      $date = $self->YearMonthToEnglish($date);
    }
    my $sql = "SELECT s2,s3,s4,s8,s2+s3+s4+s8 FROM predeterminationsbreakdown WHERE date LIKE '$date1%'";
    #print "$sql<br/>\n";
    my ($s2,$s3,$s4,$s8,$sum) = @{$self->get('dbh')->selectall_arrayref( $sql )->[0]};
    my @line = ($s2,$s3,$s4,$s8,$sum,0,0,0,0);
    next unless $sum > 0;
    for (my $i=0; $i < 4; $i++)
    {
      $totals[$i] += $line[$i];
    }
    for (my $i=0; $i < 4; $i++)
    {
      my $pct = 0.0;
      eval {$pct = 100.0*$line[$i]/$line[4];};
      $line[$i+5] = sprintf('%.1f%%', $pct);
    }
    $report .= $date;
    $report .= $delimiter . join($delimiter, @line) . "\n";
  }
  my $gt = $totals[0] + $totals[1] + $totals[2] + $totals[3];
  push @totals, $gt;
  for (my $i=0; $i < 5; $i++)
  {
    my $pct = 0.0;
    eval {$pct = 100.0*$totals[$i]/$gt;};
    push @totals, sprintf('%.1f%%', $pct);
  }
  $report .= 'Total' . $delimiter . join($delimiter, @totals) . "\n";
  return $report;
}

sub CreateDeterminationsBreakdownData
{
  my $self      = shift;
  my $delimiter = shift;
  my $start     = shift;
  my $end       = shift;
  my $monthly   = shift;
  my $title     = shift;

  #print "CreateDeterminationsBreakdownData('$delimiter','$start','$end','$monthly','$title')<br/>\n";
  my ($year,$month) = $self->GetTheYearMonth();
  my $titleDate = $self->YearMonthToEnglish("$year-$month");
  my $justThisMonth = (!$start && !$end);
  $start = "$year-$month-01" unless $start;
  my $lastDay = Days_in_Month($year,$month);
  $end = "$year-$month-$lastDay" unless $end;
  my $what = 'date';
  $what = 'DATE_FORMAT(date, "%Y-%m")' if $monthly;
  my $sql = "SELECT DISTINCT($what) FROM determinationsbreakdown WHERE date>='$start' AND date<='$end'";
  #print "$sql<br/>\n";
  my @dates = map {$_->[0];} @{$self->get('dbh')->selectall_arrayref( $sql )};
  if (scalar @dates && !$justThisMonth)
  {
    my $startEng = $self->YearMonthToEnglish(substr($dates[0],0,7));
    my $endEng = $self->YearMonthToEnglish(substr($dates[-1],0,7));
    $titleDate = ($startEng eq $endEng)? $startEng:sprintf("%s to %s", $startEng, $endEng);
  }
  my $report = ($title)? "$title\n":"Determinations Breakdown $titleDate\n";
  my @titles = ('Date','Status 4','Status 5','Status 6','Status 7','Status 8','Subtotal','Status 9','Total','Status 4','Status 5','Status 6','Status 7','Status 8');
  $report .= join($delimiter, @titles) . "\n";
  my @totals = (0,0,0,0,0,0);
  foreach my $date (@dates)
  {
    my ($y,$m,$d) = split '-', $date;
    my $date1 = $date;
    my $date2 = $date;
    if ($monthly)
    {
      $date1 = $date . '-01';
      my $lastDay = Days_in_Month($y,$m);
      $date2 = "$date-$lastDay";
      $date = $self->YearMonthToEnglish($date);
    }
    my $sql = 'SELECT SUM(s4),SUM(s5),SUM(s6),SUM(s7),SUM(s8),SUM(s4+s5+s6+s7+s8),SUM(s9),SUM(s4+s5+s6+s7+s8+s9) ' .
              "FROM determinationsbreakdown WHERE date>='$date1' AND date<='$date2'";
    #print "$sql<br/>\n";
    my ($s4,$s5,$s6,$s7,$s8,$sum1,$s9,$sum2) = @{$self->get('dbh')->selectall_arrayref( $sql )->[0]};
    my @line = ($s4,$s5,$s6,$s7,$s8,$sum1,$s9,$sum2,0,0,0,0,0);
    next unless $sum1 > 0;
    for (my $i=0; $i < 5; $i++)
    {
      $totals[$i] += $line[$i];
    }
    $totals[5] += $line[6];
    for (my $i=0; $i < 5; $i++)
    {
      my $pct = 0.0;
      eval {$pct = 100.0*$line[$i]/$line[5];};
      $line[$i+8] = sprintf('%.1f%%', $pct);
    }
    $report .= $date;
    $report .= $delimiter . join($delimiter, @line) . "\n";
  }
  my $gt1 = $totals[0] + $totals[1] + $totals[2] + $totals[3] + $totals[4];
  my $gt2 = $gt1 + $totals[5];
  splice @totals, 5, 0, $gt1;
  push @totals, $gt2;
  for (my $i=0; $i < 5; $i++)
  {
    my $pct = 0.0;
    eval {$pct = 100.0*$totals[$i]/$gt1;};
    push @totals, sprintf('%.1f%%', $pct);
  }
  $report .= 'Total' . $delimiter . join($delimiter, @totals) . "\n";
  return $report;
}

sub CreateDeterminationsBreakdownReport
{
  my $self     = shift;
  my $start    = shift;
  my $end      = shift;
  my $monthly  = shift;
  my $title    = shift;
  my $pre      = shift;

  my $data;
  my %whichlines = (5=>1,7=>1);
  my $span1 = 8;
  my $span2 = 5;
  if ($pre)
  {
    $data = $self->CreatePreDeterminationsBreakdownData("\t", $start, $end, $monthly, $title);
    %whichlines = (4=>1);
    $span1 = 5;
    $span2 = 4;
  }
  else
  {
    $data = $self->CreateDeterminationsBreakdownData("\t", $start, $end, $monthly, $title);
    $pre = 0;
  }
  my $cols = $span1 + $span2;
  my @lines = split "\n", $data;
  $title = shift @lines;
  $title =~ s/\s/&nbsp;/g;
  my $url = sprintf("<a href='?p=determinationStats&amp;startDate=$start&amp;endDate=$end&amp;%sdownload=1&amp;pre=$pre' target='_blank'>Download</a>",($monthly)?'monthly=on&amp;':'');
  my $report = "<h3>$title&nbsp;&nbsp;&nbsp;&nbsp;$url</h3>\n";
  $report .= "<table class='exportStats'>\n";
  $report .= "<tr><th/><th colspan='$span1'><span class='major'>Counts</span></th><th colspan='$span2'><span class='total'>Percentages</span></th></tr>\n";
  my $titles = shift @lines;
  $report .= ('<tr>' . join('', map {s/\s/&nbsp;/g; "<th>$_</th>";} split("\t", $titles)) . '</tr>');
  foreach my $line (@lines)
  {
    my @line = split "\t", $line;
    my $date = shift @line;
    my ($y,$m,$d) = split '-', $date;
    $date =~ s/\s/&nbsp;/g;
    if ($date eq 'Total')
    {
      $report .= "<tr><th style='text-align:right;'>Total</th>";
    }
    else
    {
      $report .= "<tr><th>$date</th>";
    }
    for (my $i=0; $i < $cols; $i++)
    {
      my $class = '';
      my $style = ($i==max keys %whichlines)? "style='border-right:double 6px black;'":'';
      if ($whichlines{$i} && $date ne 'Total')
      {
        $class = 'class="minor"';
      }
      elsif ($date ne 'Total')
      {
        $class = 'class="total"';
        $class = 'class="major"' if $i < max keys %whichlines;
      }
      $report .= sprintf("<td $class $style>%s</td>\n", $line[$i]);
    }
    $report .= "</tr>\n";
  }
  $report .= "</table>\n";
  return $report;
}


sub CreateDeterminationsBreakdownGraph
{
  my $self     = shift;
  my $start    = shift;
  my $end      = shift;
  my $monthly  = shift;
  my $title    = shift;
  my $percent  = shift;

  my $data = $self->CreateDeterminationsBreakdownData("\t", $start, $end, $monthly, $title);
  my @lines = split "\n", $data;
  $title = shift @lines;
  shift @lines;
  my @usedates = ();
  my @elements = ();
  my $ceil = 100;
  my %colors = (4 => '#22BB00', 5 => '#FF2200', 6 => '#0088FF', 7 => '#C9A8FF', 8 => 'FFCC00', 9=>'FFFFFF');
  foreach my $status (sort keys %colors)
  {
    my @vals = ();
    my $color = $colors{$status};
    my $attrs = sprintf('"dot-style":{"type":"solid-dot","dot-size":3,"colour":"%s"},"text":"Status %s","colour":"%s","on-show":{"type":"pop-up","cascade":1,"delay":0.2}',
                        $color, $status, $color);
    next if $percent and $status == 9;
    if (scalar @lines <= 1)
    {
      my $date = substr $self->GetTodaysDate(), 0, 10;
      @lines = ("$date\t0\t0\t0\t0\t0\t0\t0\t0\t0.0%\t0.0%\t0.0%\t0.0%\t0.0%");
    }
    foreach my $line (@lines)
    {
      my @line = split "\t", $line;
      my $date = shift @line;
      next if $date eq 'Total';
      next if $date =~ m/Total/ and !$monthly;
      $date =~ s/Total\s//;
      push @usedates, $date if $status == 4;
      my $count = $line[$status-4];
      $count = $line[$status-3] if $status == 9;
      $ceil = $count if $count > $ceil;
      my $val = sprintf('{"value":%d,"tip":"%d"}', $count, $count);
      if ($percent)
      {
        my $pct = 100.0*$count/$line[5];
        $val = sprintf('{"value":%.1f,"tip":"%.1f%% (%d)"}', $pct, $pct, $count);
      }
      push @vals, $val;
    }
    push @elements, sprintf('{"type":"line","values":[%s],%s}', join(',',@vals), $attrs);
  }
  $ceil = 100 * POSIX::ceil($ceil/100.0);
  my $valfmt = '';
  if ($percent)
  {
    $ceil = 100;
    $valfmt = '"text":"#val#%",';
  }
  my $report = sprintf('{"bg_colour":"#000000","title":{"text":"%s","style":"{color:#FFFFFF;font-family:Helvetica;font-size:15px;font-weight:bold;text-align:center;}"},"elements":[',$title);
  $report .= sprintf('%s]',join ',', @elements);
  $report .= sprintf(',"y_axis":{"max":%d,"steps":%d,"colour":"#888888","grid-colour":"#888888","labels":{%s"colour":"#FFFFFF"}}', $ceil, $ceil/10, $valfmt);
  $report .= sprintf(',"x_axis":{"colour":"#888888","grid-colour":"#888888","labels":{"labels":["%s"],"rotate":40,"colour":"#FFFFFF"}}', join('","',@usedates));
  $report .= '}';
  return $report;
}

sub CreateDeterminationsBreakdownGraphOld
{
  my $self     = shift;
  my $start    = shift;
  my $end      = shift;
  my $monthly  = shift;
  my $title    = shift;
  my $priority = shift;

  $priority = undef if $priority eq 'All';
  my $data = $self->CreateDeterminationsBreakdownData("\t", $start, $end, $monthly, $title, $priority);
  my @lines = split "\n", $data;
  $title = shift @lines;
  shift @lines;
  my @usedates = ();
  my @elements = ();
  my %colors = (4 => '#22BB00', 5 => '#FF2200', 6 => '#0088FF', 7 => '#C9A8FF', 8 => 'FFCC00', 9=>'FFFFFF');
  foreach my $status (sort keys %colors)
  {
    my @vals = ();
    my $color = $colors{$status};
    my $attrs = sprintf('"dot-style":{"type":"solid-dot","dot-size":3,"colour":"%s"},"text":"Status %s","colour":"%s","on-show":{"type":"pop-up","cascade":1,"delay":0.2}',
                        $color, $status, $color);
    if (scalar @lines <= 1)
    {
      my $date = substr $self->GetTodaysDate(), 0, 10;
      @lines = ("$date\t0\t0\t0\t0\t0\t0\t0\t0.0%\t0.0%\t0.0%\t0.0%\t0.0%\t0.0%");
    }
    foreach my $line (@lines)
    {
      my @line = split "\t", $line;
      my $date = shift @line;
      next if $date eq 'Total';
      next if $date =~ m/Total/ and !$monthly;
      $date =~ s/Total\s//;
      push @usedates, $date if $status == 4;
      my $count = $line[$status-4];
      my $pct = $line[$status+3];
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

sub GetStatsYears
{
  my $self = shift;
  my $user = shift;

  my $usersql = '';
  $user = '' if $user eq 'all';
  if ($user)
  {
    if ('all__' eq substr $user, 0, 5)
    {
      my $inst = substr $user, 5;
      my $affs = $self->GetUsersWithAffiliation($inst);
      $usersql = sprintf "AND user IN ('%s')", join "','", @{$affs};
    }
    else
    {
      $usersql = "AND user='$user'";
    }
  }
  my $sql = "SELECT DISTINCT year FROM userstats WHERE total_reviews>0 $usersql ORDER BY year DESC";
  #print "$sql<br/>\n";
  my $ref = $self->get('dbh')->selectall_arrayref($sql);
  return unless scalar @{$ref};
  my @years = map {$_->[0];} @{$ref};
  my $thisyear = $self->GetTheYear();
  unshift @years, $thisyear unless $years[0] ge $thisyear;
  return \@years;
}

sub CreateStatsData
{
  my $self        = shift;
  my $delimiter   = shift;
  my $page        = shift;
  my $user        = shift;
  my $cumulative  = shift;
  my $year        = shift;
  my $inval       = shift;
  my $nononexpert = shift;
  my $dopercent   = shift;

  #print "CreateStatsData($delimiter,$page,$user,$cumulative,$year,$inval,$nononexpert,$dopercent)<br/>\n";
  my $instusers = undef;
  my $instusersne = undef;
  my $dbh = $self->get( 'dbh' );
  $year = ($self->GetTheYearMonth())[0] unless $year;
  my @statdates = ($cumulative)? reverse @{$self->GetStatsYears()} : $self->GetAllMonthsInYear($year);
  my $username;
  if ($user eq 'all') { $username = 'All Reviewers'; }
  elsif ('all__' eq substr $user, 0, 5)
  {
    my $inst = substr $user, 5;
    #print "inst '$inst'<br/>\n";
    $username = "All $inst Reviewers";
    my $affs = $self->GetUsersWithAffiliation($inst);
    $instusers = sprintf "'%s'", join "','", @{$affs};
    $instusersne = sprintf "'%s'", join "','", map {($self->IsUserExpert($_))? ():$_} @{$affs};
  }
  else { $username = $self->GetUserName($user) };
  #print "username '$username', instusers $instusers<br/>\n";
  my $label = "$username: " . (($cumulative)? "CRMS&nbsp;Project&nbsp;Cumulative":$year);
  my $report = sprintf("$label\nCategories%sProject Total%s", $delimiter, (!$cumulative)? ($delimiter . "Total $year"):'');
  my %stats = ();
  my %totals = ();
  my @usedates = ();
  my $earliest = '';
  my $latest = '';
  my @titles = ('PD Reviews', 'IC Reviews', 'UND/NFI Reviews', '__TOT__', '__TOTNE__', '__NEUT__', '__VAL__', '__AVAL__',
                'Time Reviewing (mins)', 'Time per Review (mins)','Reviews per Hour', 'Outlier Reviews');
  my $which = ($inval)? 'SUM(total_incorrect)':($page eq 'userRate')? 'SUM(total_correct)+SUM(total_neutral)':'SUM(total_correct)';
  foreach my $date (@statdates)
  {
    push @usedates, $date;
    $report .= $delimiter . $date;
    my $mintime = $date . (($cumulative)? '-01':'');
    my $maxtime = $date . (($cumulative)? '-12':'');
    $earliest = $mintime if $earliest eq '' or $mintime lt $earliest;
    $latest = $maxtime if $latest eq '' or $maxtime gt $latest;
    my $sql = "SELECT SUM(total_pd), SUM(total_ic), SUM(total_und),SUM(total_reviews),
               1, SUM(total_neutral), $which, 1, SUM(total_time),
               SUM(total_time)/(SUM(total_reviews)-SUM(total_outliers)),
               (SUM(total_reviews)-SUM(total_outliers))/SUM(total_time)*60.0, SUM(total_outliers)
               FROM userstats WHERE monthyear >= '$mintime' AND monthyear <= '$maxtime'";
    if ($instusers) { $sql .= " AND user IN ($instusers)"; }
    elsif ($user ne 'all') { $sql .= " AND user='$user'"; }
    #print "$sql<br/>\n";
    my $rows = $dbh->selectall_arrayref( $sql );
    my $row = @{$rows}->[0];
    my $i = 0;
    foreach my $title (@titles)
    {
      $stats{$title}{$date} = $row->[$i];
      $totals{$title} += $row->[$i];
      $i++;
    }
    my ($total,$correct,$incorrect,$neutral) = $self->GetValidation($mintime, $maxtime, $instusersne);
    $correct += $neutral if $page eq 'userRate';
    #print "total $total correct $correct incorrect $incorrect neutral $neutral for $mintime to $maxtime ($instusersne)<br/>\n";
    my $whichone = ($inval)? $incorrect:$correct;
    my $pct = eval{100.0*$whichone/$total;};
    if ('all__' eq substr $user, 0, 5)
    {
      my ($total2,$correct2,$incorrect2,$neutral2) = $self->GetValidation($mintime, $maxtime);
      $pct = eval{100.0*$incorrect2/$total2;};
    }
    if ($user eq 'all' || $instusers)
    {
      $stats{'__TOTNE__'}{$date} = $total;
      $stats{'__NEUT__'}{$date} = $neutral;
      $stats{'__VAL__'}{$date} = $whichone;
    }
    $stats{'__AVAL__'}{$date} = $pct;
  }
  $report .= "\n";
  $totals{'Time per Review (mins)'} = 0;
  $totals{'Reviews per Hour'} = 0.0;
  eval {
    $totals{'Time per Review (mins)'} = $totals{'Time Reviewing (mins)'}/($totals{'__TOT__'}-$totals{'Outlier Reviews'});
    $totals{'Reviews per Hour'} = ($totals{'__TOT__'}-$totals{'Outlier Reviews'})/$totals{'Time Reviewing (mins)'}*60.0;
  };
  $latest = "$year-01" unless $latest;
  $earliest = "$year-01" unless $earliest;
  my ($year,$month) = split '-', $latest;
  my $lastDay = Days_in_Month($year,$month);
  my ($total,$correct,$incorrect,$neutral) = $self->GetValidation($earliest, $latest, $instusersne);
  $correct += $neutral if $page eq 'userRate';
  #print "total $total correct $correct incorrect $incorrect neutral $neutral for $earliest to $latest ($instusersne)<br/>\n";
  my $whichone = ($inval)? $incorrect:$correct;
  my $pct = eval{100.0*$whichone/$total;};
  if ('all__' eq substr $user, 0, 5)
  {
    my ($total2,$correct2,$incorrect2,$neutral2) = $self->GetValidation($earliest, $latest);
    $pct = eval{100.0*$incorrect2/$total2;};
  }
  if ($user eq 'all' || $instusers)
  {
    $totals{'__TOTNE__'} = $total;
    $totals{'__NEUT__'} = $neutral;
    $totals{'__VAL__'} = $whichone;
  }
  $totals{'__AVAL__'} = $pct;
  # Project totals
  my %ptotals;
  if (!$cumulative)
  {
    my $sql = "SELECT SUM(total_pd),SUM(total_ic), SUM(total_und), SUM(total_reviews),
               1, SUM(total_neutral), $which, 1, SUM(total_time),
               SUM(total_time)/(SUM(total_reviews)-SUM(total_outliers)),
               (SUM(total_reviews)-SUM(total_outliers))/SUM(total_time)*60.0, SUM(total_outliers)
               FROM userstats WHERE monthyear >= '2009-07'";
    if ($instusers) { $sql .= " AND user IN ($instusers)"; }
    elsif ($user ne 'all') { $sql .= " AND user='$user'"; }
    #print "$sql<br/>\n";
    my $rows = $dbh->selectall_arrayref( $sql );
    my $row = @{$rows}->[0];
    my $i = 0;
    foreach my $title (@titles)
    {
      $ptotals{$title} = $row->[$i];
      $i++;
    }
    my ($total,$correct,$incorrect,$neutral) = $self->GetValidation('2009-07', '3000-01', $instusersne);
    $correct += $neutral if $page eq 'userRate';
    #print "project total $total correct $correct incorrect $incorrect neutral $neutral for $user<br/>\n";
    my $whichone = ($inval)? $incorrect:$correct;
    my $pct = eval{100.0*$whichone/$total;};
    if ('all__' eq substr $user, 0, 5)
    {
      my ($total2,$correct2,$incorrect2,$neutral2) = $self->GetValidation($earliest, $latest);
      $pct = eval{100.0*$incorrect2/$total2;};
    }
    if ($user eq 'all' || $instusers)
    {
      $ptotals{'__TOTNE__'} = $total;
      $ptotals{'__NEUT__'} = $neutral;
      $ptotals{'__VAL__'} = $whichone;
    }
    $ptotals{'__AVAL__'} = $pct;
  }
  
  my %majors = ('PD Reviews' => 1, 'IC Reviews' => 1, 'UND/NFI Reviews' => 1);
  my %minors = ('Time Reviewing (mins)' => 1, 'Time per Review (mins)' => 1,
                'Reviews per Hour' => 1, 'Outlier Reviews' => 1);
  foreach my $title (@titles)
  {
    next if ($user eq 'all') and $title eq '__AVAL__';
    next if $title eq '__TOTNE__' and $nononexpert;
    $report .= $title;
    if (!$cumulative)
    {
      my $of = $ptotals{'__TOT__'};
      $of = $ptotals{'__TOTNE__'} if ($title eq '__VAL__' or $title eq '__NEUT__') and ($user eq 'all' or $instusers);
      my $n = $ptotals{$title};
      $n = 0 unless $n;
      if ($title eq '__AVAL__')
      {
        $n = sprintf('%.1f%%', $n);
      }
      elsif ($title ne '__TOT__' && !exists $minors{$title})
      {
        my $pct = eval { 100.0*$n/$of; } or 0.0;
        $n = sprintf("$n:%.1f", $pct) if $dopercent;
      }
      elsif ($title eq 'Time per Review (mins)' || $title eq 'Reviews per Hour')
      {
        $n = sprintf('%.1f', $n) if $n > 0.0;
      }
      $report .= $delimiter . $n;
    }
    my $n = $totals{$title};
    $n = 0 unless $n;
    if ($title eq '__AVAL__')
    {
      $n = sprintf('%.1f%%', $n);
    }
    elsif ($title ne '__TOT__' && !exists $minors{$title})
    {
      my $of = $totals{'__TOT__'};
      $of = $totals{'__TOTNE__'} if ($title eq '__VAL__' or $title eq '__NEUT__') and ($user eq 'all' or $instusers);
      my $pct = eval { 100.0*$n/$of; } or 0.0;
      $n = sprintf("$n:%.1f", $pct) if $dopercent;
    }
    elsif ($title eq 'Time per Review (mins)' || $title eq 'Reviews per Hour')
    {
      $n = sprintf('%.1f', $n) if $n > 0.0;
    }
    $report .= $delimiter . $n;
    foreach my $date (@usedates)
    {
      $n = $stats{$title}{$date};
      $n = 0 if !$n;
      if ($title eq '__AVAL__')
      {
        $n = sprintf('%.1f%%', $n);
      }
      elsif ($title ne '__TOT__' && !exists $minors{$title})
      {
        my $of = $stats{'__TOT__'}{$date};
        $of = $stats{'__TOTNE__'}{$date} if ($title eq '__VAL__' or $title eq '__NEUT__') and ($user eq 'all' or $instusers);
        my $pct = eval { 100.0*$n/$of; } or 0.0;
        $n = sprintf("$n:%.1f", $pct) if $dopercent;
      }
      elsif ($title eq 'Time per Review (mins)' || $title eq 'Reviews per Hour')
      {
        $n = sprintf('%.1f', $n) if $n > 0.0;
      }
      $n = 0 unless $n;
      $report .= $delimiter . $n;
      #print "$user $title $n $of\n";
    }
    $report .= "\n";
  }
  return $report;
}

sub CreateStatsReport
{
  my $self              = shift;
  my $page              = shift;
  my $user              = shift;
  my $cumulative        = shift;
  my $suppressBreakdown = shift;
  my $year              = shift;
  my $inval             = shift;
  my $nononexpert       = shift;
  
  # FIXME: remove this param completely?
  $suppressBreakdown = 1;
  my $data = $self->CreateStatsData(',', $page, $user, $cumulative, $year, $inval, $nononexpert, 1);
  my @lines = split m/\n/, $data;
  my $dllink = <<END;
  <a href='crms?p=$page;download=1;user=$user;cumulative=$cumulative;year=$year;inval=$inval;nne=$nononexpert' target='_blank'>Download</a>
  <a class='tip' href='#'>
    <img style="border:0px solid;" width="16" height="16" alt="Rights/Reason Help" src="/c/crms/help.png"/>
    <span>
    <b>To get the downloaded stats into a spreadsheet:</b><br/>
      &#x2022; Click on the "Download" link (this will open a new page in your browser)<br/>
      &#x2022; Select all of the text on the new page and copy it<br/>
      &#x2022; Switch to Excel<br/>
      &#x2022; Choose the menu item <b>Edit &#x2192; Paste Special...</b><br/>
      &#x2022; Choose Unicode in the dialog box<br/>
    </span>
  </a>
END
  my $nbsps = '&nbsp;&nbsp;&nbsp;&nbsp;';
  my $report = sprintf("<span style='font-size:1.3em;'><b>%s</b></span>$nbsps $dllink\n<br/><table class='exportStats'>\n<tr>\n", shift @lines);
  foreach my $th (split ',', shift @lines)
  {
    $th = $self->YearMonthToEnglish($th) if $th =~ m/^\d.*/;
    $th =~ s/\s/&nbsp;/g;
    $report .= sprintf("<th%s>$th</th>\n", ($th ne 'Categories')? ' style="text-align:center;"':'');
  }
  $report .= "</tr>\n";
  my %majors = ('PD Reviews' => 1, 'IC Reviews' => 1, 'UND/NFI Reviews' => 1, '__TOT__' => 1);
  my %minors = ('Time Reviewing (mins)' => 1, 'Time per Review (mins)' => 1, 'Average Time per Review (mins)' => 1,
                'Reviews per Hour' => 1, 'Average Reviews per Hour' => 1, 'Outlier Reviews' => 1);
  my $exp = $self->IsUserExpert($user);
  foreach my $line (@lines)
  {
    my @items = split(',', $line);
    my $title = shift @items;
    next if $title eq '__VAL__' and ($exp);
    next if $title eq '__MVAL__' and ($exp);
    next if $title eq '__AVAL__' and ($exp);
    next if $title eq '__NEUT__' && ($exp || $page eq 'userRate');
    next if $title eq '__TOTNE__' and ($user ne 'all' and $user !~ m/all__/ and !$cumulative);
    next if ($cumulative or $user eq 'all' or $user !~ m/all__/ or $suppressBreakdown) and !exists $majors{$title} and !exists $minors{$title} and $title !~ m/__.+?__/;
    my $class = (exists $majors{$title})? 'major':(exists $minors{$title})? 'minor':'';
    $class = 'total' if $title =~ m/__.+?__/ and $title ne '__TOT__';
    $report .= '<tr>';
    my $title2 = $title;
    $title2 =~ s/\s/&nbsp;/g;
    my $padding = ($class eq 'major' || $class eq 'minor' || $class eq 'total')? '':$nbsps;
    my $style = '';
    $style = ' style="text-align:right;"' if $class eq 'total';
    $class = 'purple' if $title eq '__AVAL__';
    $title2 = $nbsps . $title2 if $title eq '__AVAL__';
    $report .= sprintf("<th$style><span%s>$padding$title2</span></th>", ($class)? " class='$class'":'');
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
  $report =~ s/__TOT__/Total&nbsp;Reviews*/;
  $report =~ s/__TOTNE__/Non-Expert&nbsp;Reviews/;
  my $vtitle = 'Validated&nbsp;Reviews&nbsp;&amp;&nbsp;Rate';
  $vtitle = 'Invalidated&nbsp;Reviews&nbsp;&amp;&nbsp;Rate' if $inval;
  $vtitle = 'Valid**&nbsp;Reviews&nbsp;&amp;&nbsp;Rate' if $page eq 'userRate';
  $report =~ s/__VAL__/$vtitle/;
  my $avtitle = 'Validation&nbsp;Rate&nbsp;(all&nbsp;reviewers)';
  $avtitle = 'Invalidation&nbsp;Rate&nbsp;(all&nbsp;reviewers)' if $inval;
  $avtitle = 'Validation**&nbsp;Rate&nbsp;(all&nbsp;reviewers)' if $page eq 'userRate';
  $report =~ s/__AVAL__/$avtitle/;
  my $ntitle = 'Neutral&nbsp;Reviews&nbsp;&amp;&nbsp;Rate';
  $report =~ s/__NEUT__/$ntitle/;
  return $report;
}

sub DownloadUserStats
{
  my $self        = shift;
  my $page        = shift;
  my $user        = shift;
  my $cumulative  = shift;
  my $year        = shift;
  my $inval       = shift;
  my $nononexpert = shift;
  
  my $report = $self->CreateStatsData("\t", $page, $user, $cumulative, $year, $inval, $nononexpert);
  $report =~ s/(\d\d\d\d-\d\d)/$self->YearMonthToEnglish($&)/ge;
  $report =~ s/&nbsp;/ /g;
  $report =~ s/__TOT__/Total Reviews/;
  $report =~ s/__TOTNE__/Non-Expert Reviews/;
  my $vtitle = 'Validated Reviews & Rate';
  $vtitle = 'Invalidated Reviews & Rate' if $inval;
  $vtitle = 'Valid Reviews & Rate' if $page eq 'userRate';
  $report =~ s/__VAL__/$vtitle/;
  my $avtitle = 'Validation Rate (all reviewers)';
  $avtitle = 'Invalidation Rate (all reviewers)' if $inval;
  $avtitle = 'Validation Rate (all reviewers)' if $page eq 'userRate';
  $report =~ s/__AVAL__/$avtitle/;
  my $ntitle = 'Neutral Reviews & Rate';
  $report =~ s/__NEUT__/$ntitle/;
  $self->DownloadSpreadSheet( $report );
  return ($report)? 1:0;
}

sub GetRange
{
  my $self = shift;

  my $max = $self->SimpleSqlGet('SELECT MAX(time) FROM historicalreviews WHERE legacy!=1');
  my $min = $self->SimpleSqlGet('SELECT MIN(time) FROM historicalreviews WHERE legacy!=1');
  my $max_year = $max;
  $max_year =~ s,(.*?)\-.*,$1,;
  my $max_month = $max;
  $max_month =~ s,.*?\-(.*?)\-.*,$1,;
  my $min_year = $min;
  $min_year =~ s,(.*?)\-.*,$1,;
  my $min_month = $min;
  $min_month =~ s,.*?\-(.*?)\-.*,$1,;
  return ($max_year, $max_month, $min_year, $min_month);
}

sub UpdateStats
{
  my $self = shift;

  my $sql = 'DELETE from userstats';
  $self->PrepareSubmitSql( $sql );
  my $users = $self->GetUsers();
  my ( $max_year, $max_month, $min_year, $min_month ) = $self->GetRange();
  my $max_date = "$max_year-$max_month";
  while ( 1 )
  {
    my $statDate = "$min_year-$min_month";
    foreach my $user ( @{ $users } )
    {
      $self->GetMonthStats( $user, $statDate );
    }
    $min_month = $min_month + 1;
    if ( $min_month == 13 )
    {
      $min_month = 1;
      $min_year = $min_year + 1;
    }
    $min_month = '0' . $min_month if $min_month < 10;
    my $new_test_date = "$min_year-$min_month";
    last if $new_test_date gt $max_date;
  }
}


sub GetMonthStats
{
  my $self       = shift;
  my $user       = shift;
  my $start_date = shift;

  return unless $start_date;

  my $sql = "SELECT count(*) FROM historicalreviews WHERE user='$user' AND legacy!=1 AND time LIKE '$start_date%'";
  my $total_reviews = $self->SimpleSqlGet( $sql );

  #pd/pdus
  $sql = "SELECT count(*) FROM historicalreviews WHERE user='$user' AND legacy!=1 AND (attr=1 OR attr=9) AND time LIKE '$start_date%'";
  my $total_pd = $self->SimpleSqlGet( $sql );

  #ic
  $sql = "SELECT count(*) FROM historicalreviews WHERE user='$user' AND legacy!=1 AND attr=2 AND time LIKE '$start_date%'";
  my $total_ic = $self->SimpleSqlGet( $sql );

  #und
  $sql = "SELECT count(*) FROM historicalreviews WHERE user='$user' AND legacy!=1 AND attr=5 AND time LIKE '$start_date%'";
  my $total_und = $self->SimpleSqlGet( $sql );

  #time reviewing ( in minutes ) - not including outliers
  $sql = "SELECT COALESCE(SUM(TIME_TO_SEC(duration)),0)/60.0 FROM historicalreviews WHERE
          user='$user' AND legacy!=1 AND time LIKE '$start_date%' AND duration <= '00:05:00'";
  my $total_time = $self->SimpleSqlGet( $sql );
  
  #total outliers
  $sql = "SELECT COUNT(*) FROM historicalreviews WHERE user='$user' AND legacy!=1 AND time LIKE '$start_date%' AND duration>'00:05:00'";
  my $total_outliers = $self->SimpleSqlGet( $sql );

  my $time_per_review = 0;
  if ( $total_reviews - $total_outliers > 0)
  {
    $time_per_review = ($total_time/($total_reviews - $total_outliers));
  }
  my $reviews_per_hour = 0;
  if ( $time_per_review > 0 )
  {
    $reviews_per_hour = (60/$time_per_review);
  }
  my ($year,$month) = split '-', $start_date;
  my $lastDay = Days_in_Month($year,$month);
  my $mintime = "$start_date-01 00:00:00";
  my $maxtime = "$start_date-$lastDay 23:59:59";
  my ($total_correct,$total_incorrect,$total_neutral) = $self->CountCorrectReviews($user, $mintime, $maxtime);
  $sql = 'INSERT INTO userstats (user, month, year, monthyear, total_reviews, total_pd, ' .
         'total_ic, total_und, total_time, time_per_review, reviews_per_hour, ' .
         'total_outliers, total_correct, total_incorrect, total_neutral) ' .
         "VALUES ('$user', '$month', '$year', '$start_date', $total_reviews, $total_pd, " .
         "$total_ic, $total_und, $total_time, $time_per_review, $reviews_per_hour, " .
         "$total_outliers, $total_correct, $total_incorrect, $total_neutral)";
  #print "$sql\n";
  $self->PrepareSubmitSql( $sql );
}

sub UpdateDeterminationsBreakdown
{
  my $self = shift;
  my $date = shift;

  $date = $self->SimpleSqlGet('SELECT CURDATE()') unless $date;
  my @counts;
  foreach my $status (4..9)
  {
    my $sql = 'SELECT COUNT(DISTINCT e.gid) FROM exportdata e INNER JOIN historicalreviews r ON e.gid=r.gid WHERE ' .
              "r.legacy!=1 AND DATE(e.time)='$date' AND r.status=$status";
    push @counts, $self->SimpleSqlGet($sql);
  }
  my $sql = sprintf "REPLACE INTO determinationsbreakdown (date,s4,s5,s6,s7,s8,s9) VALUES ('$date',%s)", join ',', @counts;
  $self->PrepareSubmitSql($sql);
}

sub UpdateExportStats
{
  my $self = shift;
  my $date = shift;

  my %counts;
  $date = $self->SimpleSqlGet('SELECT CURDATE()') unless $date;
  my $sql = "SELECT attr,reason FROM exportdata WHERE DATE(time)='$date'";
  my $ref = $self->get('dbh')->selectall_arrayref( $sql );
  foreach my $row (@{$ref})
  {
    my $attr = $row->[0];
    my $reason = $row->[1];
    $counts{$attr . '_' . $reason}++;
  }
  my @keys = keys %counts;
  my @vals = map {$counts{$_}} @keys;
  return unless scalar @keys;
  my $sql = sprintf "REPLACE INTO exportstats (date,%s) VALUES ('$date',%s)", join(',', @keys), join(',', @vals);
  $self->PrepareSubmitSql($sql);
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
          $errorMsg .= 'Ren number format is not correct for item in 1950 - 1953 range.';
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

  my $msg = '';
  if ( $self->IsUserExpert( $user ) )
  {
    if ($self->HasItemBeenReviewedByAnotherExpert($id,$user))
    {
      $msg = 'This volume does not need to be reviewed. An expert has already reviewed it. Please Cancel.';
    }
  }
  else
  {
    my $sql = "SELECT count(*) FROM $CRMSGlobals::reviewsTable WHERE id ='$id' AND user != '$user'";
    my $count = $self->SimpleSqlGet( $sql );
    if ($count >= 2 )
    {
      $msg = 'This volume does not need to be reviewed. Two reviewers or an expert have already reviewed it. Please Cancel.';
    }
    $sql = "SELECT count(*) FROM $CRMSGlobals::queueTable WHERE id ='$id' AND status!=0";
    $count = $self->SimpleSqlGet( $sql );
    if ($count >= 1 ) { $msg = 'This item has been processed already. Please Cancel.'; }
  }
  return $msg;
}

# Returns an error message, or an empty string if no error.
sub ValidateSubmission2
{
  my $self = shift;
  my ($id, $user, $attr, $reason, $note, $category, $renNum, $renDate) = @_;
  my $errorMsg = '';

  my $noteError = 0;
  my $hasren = ($renNum && $renDate);
  ## Someone else has the item locked?
  $errorMsg = 'This item has been locked by another reviewer. Please Cancel.' if $self->IsLockedForOtherUser($id);
  ## check user
  if ( ! $self->IsUserReviewer( $user ) && ! $self->IsUserAdvanced( $user ))
  {
    $errorMsg .= 'Not a reviewer.';
  }
  if ( ( ! $attr ) || ( ! $reason ) )
  {
    $errorMsg .= 'rights/reason designation required.';
  }
  my $date = $self->GetPubDate($id);
  ## und/nfi
  if ( $attr == 5 && $reason == 8 && ( ( ! $note ) || ( ! $category ) )  )
  {
    $errorMsg .= 'und/nfi must include note category and note text.';
    $noteError = 1;
  }
  ## ic/ren requires a nonexpired renewal if 1963 or earlier
  if ( $attr == 2 && $reason == 7 )
  {
    if ($hasren)
    {
      if ($date > 1963)
      {
        $errorMsg .= 'Renewal no longer required for works published after 1963. ';
      }
      else
      {
        $renDate =~ s,.*[A-Za-z](.*),$1,;
        $renDate = '19' . $renDate;
        if ( $renDate < 1950 )
        {
          $errorMsg .= "Renewal has expired; volume is pd. Date entered is $renDate. ";
        }
      }
    }
    else
    {
      $errorMsg .= 'ic/ren must include renewal id and renewal date. ';
    }
  }
  ## pd/ren should not have a ren number or date, and is not allowed for post-1963 works.
  if ( $attr == 1 && $reason == 7 )
  {
    if ($date > 1963)
    {
      $errorMsg .= 'Renewal no longer required for works published after 1963. ';
    }
    elsif ($hasren)
    {
      $errorMsg .= 'pd/ren should not include renewal info. ';
    }
  }
  ## pd/ncn requires a ren number in most cases
  ## For superadmins, ren info is optional for 23-63 and disallowed for 64-77
  ## For admins, ren info is optional only if Note and category 'Expert Note' for 23-63 and disallowed for 64-77
  ## For non-admins, ren info is required.
  if ($attr == 1 && $reason == 2)
  {
    if ($self->IsUserSuperAdmin($user))
    {
      $errorMsg .= 'Renewal no longer required for works published after 1963. ' if $date > 1963 && $hasren;
      #$errorMsg .= 'pd/ncn must include renewal id and renewal date. ' if $date <= 1963 && !$hasren;
    }
    elsif ($self->IsUserAdmin($user))
    {
      $errorMsg .= 'Renewal no longer required for works published after 1963. ' if $date > 1963 && $hasren;
      if ($date <= 1963 && ($category ne 'Expert Note' || !$note) && !$hasren)
      {
        $errorMsg .= 'pd/ncn must include either renewal id and renewal date, or note category "Expert Note". ';
      }
    }
    else
    {
      $errorMsg .= 'pd/ncn must include renewal id and renewal date. ' unless $hasren;
    }
  }
  ## pd/cdpp requires a ren number
  if (  $attr == 1 && $reason == 9 && ( ( $renNum ) || ( $renDate ) ) )
  {
    $errorMsg .= 'pd/cdpp should not include renewal info. ';
  }
  if ( $attr == 1 && $reason == 9 && ( ( !$note ) || ( !$category ) ) )
  {
    $errorMsg .= 'pd/cdpp must include note category and note text. ';
    $noteError = 1;
  }
  ## ic/cdpp requires a ren number
  if (  $attr == 2 && $reason == 9 && ( ( $renNum ) || ( $renDate ) ) )
  {
    $errorMsg .= 'ic/cdpp should not include renewal info. ';
  }
  if ( $attr == 2 && $reason == 9 && ( ( !$note )  || ( !$category ) ) )
  {
    $errorMsg .= 'ic/cdpp must include note category and note text. ';
    $noteError = 1;
  }
  ## pd/add can only be submitted by an admin and requires note and category
  if ($attr == 1 && $reason == 14)
  {
    if (!$self->IsUserAdmin($user))
    {
      $errorMsg .= 'pd/add requires admin privileges.';
    }
    elsif (( $renNum ) || ( $renDate ))
    {
      $errorMsg .= 'pd/add should not include renewal info. ';
    }
    if (( !$note ) || ( !$category ))
    {
      $errorMsg .= 'pd/add must include note category and note text. ';
      $noteError = 1;
    }
    elsif ($category ne 'Expert Note' && $category ne 'Foreign Pub' && $category ne 'Misc')
    {
      $errorMsg .= 'pd/add requires note category "Expert Note", "Foreign Pub" or "Misc". ';
    }
  }
  ## pdus/cdpp requires a note and a 'Foreign' or 'Translation' category, and must not have a ren number
  if ($attr == 9 && $reason == 9)
  {
    if (( $renNum ) || ( $renDate ))
    {
      $errorMsg .= 'pdus/cdpp should not include renewal info. ';
    }
    if (( !$note ) || ( !$category ))
    {
      $errorMsg .= 'pdus/cdpp must include note category/note text. ';
      $noteError = 1;
    }
    elsif ($category ne 'Foreign Pub' && $category ne 'Translation')
    {
      $errorMsg .= 'pdus/cdpp requires note category "Foreign Pub" or "Translation". ';
    }
  }
  if ( $noteError == 0 )
  {
    if ( ( $category )  && ( !$note ) )
    {
      if ($category ne 'Expert Accepted')
      {
        $errorMsg .= 'must include a note if there is a category. ';
      }
    }
    elsif ( ( $note ) && ( !$category ) )
    {
      $errorMsg .= 'must include a category if there is a note. ';
    }
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


# 008:28 is 'f' byte.
sub IsGovDoc
{
  my $self   = shift;
  my $id     = shift;
  my $record = shift;

  if ( ! $record ) { $self->SetError("no record in IsGovDoc: $id"); return 1; }
  my $xpath  = q{//*[local-name()='controlfield' and @tag='008']};
  my $leader = $record->findvalue( $xpath );
  return (substr($leader, 28, 1) eq 'f');
}

# An item is a probable gov doc if one of the following is true. All are case insensitive.
# Author begins with "United States" and 260 is blank
# Author begins with "United States" and 260a begins with "([)Washington"
# Author begins with "United States" and 260b begins with "U.S. G.P.O." or "U.S. Govt. Print. Off."
# Author begins with "Library of Congress" and 260a begins with "Washington"
# Title begins with "Code of Federal Regulations" and 260a begins with "Washington"
# Author is blank and 260(a) begins with "([)Washington" and 260(b) begins with "U.S."
# Author is blank and 260(a) begins with "([)Washington" and 260(b) begins with "G.P.O."
# Author is blank and 260(b) includes "National Aeronautics and Space"
# Author begins with "Federal Reserve Bank"
# Author includes "Bureau of Mines"
sub IsProbableGovDoc
{
  my $self   = shift;
  my $id     = shift;
  my $record = shift;

  $record = $self->GetMetadata($id) unless $record;
  if ( ! $record ) { $self->SetError("no record in IsProbableGovDoc: $id"); return 1; }
  my $author = $self->GetRecordAuthor($id, $record);
  my $title = $self->GetRecordTitle($id, $record);
  my $xpath  = q{//*[local-name()='datafield' and @tag='260']/*[local-name()='subfield' and @code='a']};
  my $field260a = $record->findvalue( $xpath ) or '';
  $xpath  = q{//*[local-name()='datafield' and @tag='260']/*[local-name()='subfield' and @code='b']};
  my $field260b = $record->findvalue( $xpath ) or '';
  $field260a =~ s/^\s*(.*?)\s*$/$1/;
  $field260b =~ s/^\s*(.*?)\s*$/$1/;
  # If there is an alphabetic character in 008:28 other than 'f', we accept it and say it is NOT probable
  $xpath  = q{//*[local-name()='controlfield' and @tag='008']};
  my $leader = lc $record->findvalue( $xpath );
  my $code = substr($leader, 28, 1);
  return 0 if ($code ne 'f' && $code =~ m/[a-z]/);
  if ($author =~ m/^united\s+states/i)
  {
    return 1 unless $field260a or $field260b;
    return 1 if $field260a =~ m/^\[?washington/i;
    return 1 if $field260b and ($field260b =~ m/^u\.s\.\s+g\.p\.o\./i or $field260b =~ m/^u\.s\.\s+govt\.\s+print\.\s+off\./i);
  }
  return 1 if $author =~ m/^library\s+of\s+congress/i and $field260a =~ m/^washington/i;
  return 1 if $title =~ m/^code\s+of\s+federal\s+regulations/i and $field260a =~ m/^washington/i;
  if (!$author)
  {
    return 1 if $field260a =~ m/^\[?washington/i and $field260b =~ m/^(u\.s\.|g\.p\.o\.)/i;
    return 1 if $field260b and $field260b =~ m/national\s+aeronautics\s+and\s+space/i;
  }
  else
  {
    return 1 if $author =~ m/^federal\s+feserve\s+bank/i;
    return 1 if $author =~ m/bureau\s+of\s+mines/i;
  }
  return 0;
}

sub IsFormatBK
{
  my $self   = shift;
  my $id     = shift;
  my $record = shift;

  if ( ! $record ) { $self->Logit( "no record in IsFormatBK: $id" ); }
  my $nodes = $record->findnodes(q{//*[local-name()='datafield' and @tag='970']});
  foreach my $node ($nodes->get_nodelist())
  {
    return 1 if 'BK' eq $node->findvalue("./*[local-name()='subfield' and \@code='a']");
  }
}

sub IsThesis
{
  my $self   = shift;
  my $id     = shift;
  my $record = shift;

  my $is = 0;
  if ( ! $record ) { $self->SetError("no record in IsThesis($id)"); return 0; }
  eval {
    my $xpath = "//*[local-name()='datafield' and \@tag='502']/*[local-name()='subfield' and \@code='a']";
    my $doc  = $record->findvalue( $xpath );
    $is = 1 if $doc =~ m/thes(e|i)s/i or $doc =~ m/diss/i;
    my $nodes = $record->findnodes("//*[local-name()='datafield' and \@tag='500']");
    foreach my $node ($nodes->get_nodelist())
    {
      $doc = $node->findvalue("./*[local-name()='subfield' and \@code='a']");
      $is = 1 if $doc =~ m/thes(e|i)s/i or $doc =~ m/diss/i;
    }
  };
  $self->SetError("failed in IsThesis($id): $@") if $@;
  return $is;
}

# Translations: 041, first indicator=1, $a=eng, $h= (original
# language code); Translation (or variations thereof) in 500(a) note field.
sub IsTranslation
{
  my $self   = shift;
  my $id     = shift;
  my $record = shift;

  my $is = 0;
  if ( ! $record ) { $self->SetError("no record in IsTranslation($id)"); return 0; }
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
  $self->SetError("failed in IsTranslation($id): $@") if $@;
  return $is;
}

# Rejects anything with 008 15-17 that is not '**u' or 'us*'.
# As a convenience (and for testing) returns undef for US titles and a string with the country code that failed.
sub IsForeignPub
{
  my $self   = shift;
  my $id     = shift;
  my $record = shift;

  my $is = undef;
  $record = $self->GetMetadata($id) unless $record;
  if ( ! $record ) { $self->SetError("no record in IsForeignPub($id)"); return undef; }
  eval {
    my $xpath = "//*[local-name()='controlfield' and \@tag='008']";
    my $code  = substr($record->findvalue( $xpath ), 15, 3);
    $is = $code if substr($code,2,1) ne 'u';
  };
  $self->SetError("failed in IsForeignPub($id): $@") if $@;
  return $is;
}

# second/foreign place of pub. From Tim's documentation:
# Check of 260 field for multiple subfield a:
# If PubPlace 17 eq 'u', and the 260 field contains multiple subfield
# a?s, then the data in each subfield a is normalized and matched
# against a list of known US cities.  If any of the subfield a?s are not
# in the list, then the mult_260a_non_us flag is set.
# As a convenience (and for testing) returns undef for US titles and a string with the city that failed.
sub IsReallyForeignPub
{
  my $self   = shift;
  my $id     = shift;
  my $record = shift;

  $record = $self->GetMetadata($id) unless $record;
  if ( ! $record ) { $self->SetError("no record in IsReallyForeignPub($id)"); return undef; }
  my $is = $self->IsForeignPub($id, $record);
  return $is if $is;
  eval {
    my @nodes = $record->findnodes("//*[local-name()='datafield' and \@tag='260']/*[local-name()='subfield' and \@code='a']")->get_nodelist();
    return if scalar @nodes == 1;
    foreach my $node (@nodes)
    {
      my $where = $self->Normalize($node->textContent);
      my $cities = $self->get('cities');
      $cities = $self->ReadCities() unless $cities;
      if ($cities !~ m/==$where==/i)
      {
        $is = $where;
        return;
      }
    }
  };
  $self->SetError("failed in IsReallyForeignPub($id): $@") if $@;
  return $is;
}

sub ReadCities
{
  my $self = shift;
  
  my $in = $self->get('root') . "/bin/c/crms/us_cities.txt";
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
##  Parameters: volume id
##  Return:     date string
## ----------------------------------------------------------------------------
sub GetPublDate
{
  my $self   = shift;
  my $id     = shift;
  my $record = shift;

  $record = $self->GetMetadata($id) unless $record;
  return 'unknown' unless $record;
  ## my $xpath = q{//*[local-name()='oai_marc']/*[local-name()='fixfield' and @id='008']};
  my $xpath   = q{//*[local-name()='controlfield' and @tag='008']};
  my $leader  = $record->findvalue( $xpath );
  return substr($leader, 7, 4);
}

sub GetPubLanguage
{
  my $self   = shift;
  my $id     = shift;
  my $record = shift;

  $record = $self->GetMetadata($id) unless $record;
  if ( ! $record ) { return 0; }

  ## my $xpath = q{//*[local-name()='oai_marc']/*[local-name()='fixfield' and @id='008']};
  my $xpath   = q{//*[local-name()='controlfield' and @tag='008']};
  my $leader  = $record->findvalue( $xpath );
  return substr($leader, 35, 3);
}

sub GetMarcFixfield
{
  my $self  = shift;
  my $id    = shift;
  my $field = shift;

  my $record = $self->GetMetadata($id);
  if ( ! $record ) { $self->Logit( "failed in GetMarcFixfield: $id" ); }

  my $xpath = qq{//*[local-name()='oai_marc']/*[local-name()='fixfield' and \@id='$field']};
  return $record->findvalue( $xpath );
}

sub GetMarcVarfield
{
  my $self  = shift;
  my $id    = shift;
  my $field = shift;
  my $label = shift;

  my $record = $self->GetMetadata($id);
  if ( ! $record ) { $self->Logit( "failed in GetMarcVarfield: $id" ); }

  my $xpath = qq{//*[local-name()='oai_marc']/*[local-name()='varfield' and \@id='$field']} .
              qq{/*[local-name()='subfield' and \@label='$label']};

  return $record->findvalue( $xpath );
}

sub GetMarcControlfield
{
  my $self  = shift;
  my $id    = shift;
  my $field = shift;

  my $record = $self->GetMetadata($id);
  if ( ! $record ) { $self->Logit( "failed in GetMarcControlfield: $id" ); }

  my $xpath = qq{//*[local-name()='controlfield' and \@tag='$field']};
  return $record->findvalue( $xpath );
}

sub GetMarcDatafield
{
  my $self   = shift;
  my $id     = shift;
  my $field  = shift;
  my $code   = shift;
  my $record = shift;

  $record = $self->GetMetadata($id) unless $record;
  if ( ! $record ) { $self->Logit( "failed in GetMarcDatafield: $id" ); }

  my $xpath = qq{//*[local-name()='datafield' and \@tag='$field'][1]} .
              qq{/*[local-name()='subfield'  and \@code='$code']};
  my $data;
  eval{ $data = $record->findvalue( $xpath ); };
  if ($@) { $self->Logit( "failed to parse metadata: $@" ); }
  return $data;
}

sub GetRecordAuthor
{
  my $self   = shift;
  my $id     = shift;
  my $record = shift;

  #After talking to Tim, the author info is in the 1XX field
  #Margrte told me that the only 1xx fields are: 100, 110, 111, 130. 700, 710
  $record = $self->GetMetadata($id) unless $record;
  if ( ! $record ) { $self->Logit( "failed in GetRecordAuthor: $id" ); }
  my $data = $self->GetMarcDatafield($id,'100','a',$record);
  if (!$data)
  {
    $data = $self->GetMarcDatafield($id,'110','a',$record);
    $data .= $self->GetMarcDatafield($id,'110','b',$record) if $data;
    $data = $self->GetMarcDatafield($id,'111','a',$record) unless $data;
    $data = $self->GetMarcDatafield($id,'130','a',$record) unless $data;
    $data = $self->GetMarcDatafield($id,'700','a',$record) unless $data;
    $data = $self->GetMarcDatafield($id,'710','a',$record) unless $data;
  }
  $data =~ s/\n+//gs;
  $data =~ s/[\s,\.]+$//;
  $data =~ s/^\s+//;
  return $data;
}

# Removes paren/brace/brack and backslash-escape single quote
sub GetEncTitle
{
  my $self = shift;
  my $bar  = shift;

  my $ti = $self->GetTitle( $bar );
  $ti =~ s,\',\\\',g; ## escape '
  $ti =~ s/[()[\]{}]//g;
  return $ti;
}

sub GetTitle
{
  my $self = shift;
  my $id   = shift;

  my $ti = $self->SimpleSqlGet("SELECT title FROM bibdata WHERE id='$id'");
  $ti = $self->UpdateTitle($id) unless $ti;
  # Get rid of trailing punctuation
  $ti =~ s/\s*[:\/,.;]\s*$//;
  return $ti;
}

## use for now because the API is slow...
sub GetRecordTitle
{
  my $self   = shift;
  my $id     = shift;
  my $record = shift;

  $record = $self->GetMetadata($id) unless $record;
  my $xpath = "//*[local-name()='datafield' and \@tag='245']/*[local-name()='subfield' and \@code='a']";
  my $title = '';
  eval{ $title = $record->findvalue( $xpath ); };
  if ($@) { $self->Logit( "failed to parse metadata: $@" ); }
  return $title;
}

sub GetPubDate
{
  my $self = shift;
  my $id   = shift;

  my $sql = "SELECT YEAR(pub_date) FROM bibdata WHERE id='$id'";
  my $date = $self->SimpleSqlGet($sql);
  $date = $self->UpdatePubDate($id) unless $date;
  return $date;
}

sub UpdateTitle
{
  my $self   = shift;
  my $id     = shift;
  my $title  = shift;
  my $record = shift;
  
  if ($id eq '')
  {
    $self->SetError("Trying to update title for empty volume id!\n");
    $self->Logit("$0: trying to update title for empty volume id!\n");
  }
  if ( ! $title )
  {
    ## my $ti = $self->GetMarcDatafield( $id, "245", "a");
    $title = $self->GetRecordTitle( $id, $record );
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
  my $sql = "SELECT COUNT(*) FROM bibdata WHERE id='$id'";
  my $count = $self->SimpleSqlGet( $sql );
  $sql = qq{ UPDATE bibdata SET title=$tiq WHERE id="$id"};
  if (!$count)
  {
    $sql = "INSERT INTO bibdata (id, title, pub_date) VALUES ('$id', $tiq, '')";
  }
  $self->PrepareSubmitSql( $sql );
  return $title;
}

sub UpdateCandidatesTitle
{
  my $self = shift;
  my $id   = shift;
  
  my $title = $self->GetRecordTitle( $id );
  my $tiq = $self->get('dbh')->quote( $title );
  $self->PrepareSubmitSql("UPDATE candidates SET title=$tiq,time=time WHERE id='$id'");
}

sub UpdatePubDate
{
  my $self   = shift;
  my $id     = shift;
  my $date   = shift;
  my $record = shift;

  if ($id eq '')
  {
    $self->SetError("Trying to update pub date for empty volume id!\n");
    $self->Logit("$0: trying to update pub date for empty volume id!\n");
  }
  $date = $self->GetPublDate($id, $record) unless $date;
  my $sql = "SELECT COUNT(*) FROM bibdata WHERE id='$id'";
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
  my $sql = "UPDATE candidates SET pub_date='$date-01-01',time=time WHERE id='$id'";
  $self->PrepareSubmitSql( $sql );
}

sub UpdateAuthor
{
  my $self   = shift;
  my $id     = shift;
  my $author = shift;
  my $record = shift;
  
  if ($id eq '')
  {
    $self->SetError("Trying to update author for empty volume id!\n");
    $self->Logit("$0: trying to update author for empty volume id!\n");
  }
  $author = $self->GetRecordAuthor( $id, $record ) unless $author;
  if ($self->Mojibake($author))
  {
    $self->Logit("$0: Mojibake author <<$author>> for $id!\n");
  }
  my $aiq = $self->get('dbh')->quote( $author );
  if ($self->Mojibake($aiq))
  {
    $self->Logit("$0: Mojibake quoted author <<$aiq>> for $id!\n");
  }
  my $sql = "SELECT count(*) FROM bibdata WHERE id='$id'";
  my $count = $self->SimpleSqlGet( $sql );
  $sql = "UPDATE bibdata SET author=$aiq WHERE id='$id'";
  if (!$count )
  {
    $sql = "INSERT INTO bibdata (id, title, pub_date, author) VALUES ('$id','','',$aiq)";
  }
  $self->PrepareSubmitSql( $sql );
  return $author;
}

sub UpdateCandidatesAuthor
{
  my $self = shift;
  my $id   = shift;

  my $author = $self->GetRecordAuthor( $id );
  my $aiq = $self->get('dbh')->quote( $author );
  my $sql = "UPDATE candidates SET author=$aiq,time=time WHERE id='$id'";
  $self->PrepareSubmitSql( $sql );
}

sub GetEncAuthor
{
  my $self = shift;
  my $bar  = shift;

  my $au = $self->GetEncAuthorForReview($bar);
  $au =~ s,\",\\\",g; ## escape "
  $au =~ s/[()[\]{}]//g;
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

  my $au = $self->SimpleSqlGet("SELECT author FROM bibdata WHERE id='$bar'");
  $au = $self->UpdateAuthor($bar) unless $au;
  $au =~ s,(.*[A-Za-z]).*,$1,;
  return $au;
}

## ----------------------------------------------------------------------------
##  Function:   get the metadata record (MARC21)
##  Parameters: volume id or system id
##  Return:     XML::LibXML record doc
## ----------------------------------------------------------------------------
sub GetMetadata
{
  my $self = shift;
  my $id   = shift;

  if ( ! $id ) { $self->SetError( "GetMetadata: no id given: '$id'" ); return; }
  # If it has a period, it's a volume ID
  my $url = ($id =~ m/\./)? "http://catalog.hathitrust.org/api/volumes/full/htid/$id.json" :
                            "http://catalog.hathitrust.org/api/volumes/full/recordnumber/$id.json";
  my $ua = LWP::UserAgent->new;
  $ua->timeout( 1000 );
  my $req = HTTP::Request->new( GET => $url );
  my $res = $ua->request( $req );
  if ( ! $res->is_success )
  {
    $self->SetError( $url . ' failed: ' . $res->message() );
    return;
  }
  my $xml = undef;
  my $json = JSON::XS->new;
  my $content = $res->content;
  eval {
    my $records = $json->decode($content)->{'records'};
    if ('HASH' eq ref $records)
    {
      my @keys = keys %$records;
      $xml = $records->{$keys[0]}->{'marc-xml'};
    }
    else { $self->SetError("HT Bib API found no data for '$id' (got '$content')"); return; }
  };
  if ($@) { $self->SetError( "failed to parse ($content):$@" ); return; }
  my $parser = $self->get('parser');
  if (!$parser)
  {
    $parser = XML::LibXML->new();
    $self->set('parser',$parser);
  }
  my $source;
  eval {
    $content = Encode::decode('utf8', $content);
    $source = $parser->parse_string( $xml );
  };
  if ($@) { $self->SetError( "failed to parse ($xml):$@" ); return; }
  my $xpc = XML::LibXML::XPathContext->new($source);
  my $ns = 'http://www.loc.gov/MARC21/slim';
  $xpc->registerNs(ns => $ns);
  my @records = $xpc->findnodes('//ns:record');
  return $records[0];
}

# Get the usRightsString field of the item record for the
# given volume id from the HT Bib API.
sub GetRightsString
{
  my $self = shift;
  my $id   = shift;

  if ( ! $id ) { $self->SetError( "GetMetadata: no id given: '$id'" ); return; }
  # If it has a period, it's a volume ID
  my $url = "http://catalog.hathitrust.org/api/volumes/brief/htid/$id.json";
  my $ua = LWP::UserAgent->new;
  $ua->timeout( 1000 );
  my $req = HTTP::Request->new( GET => $url );
  my $res = $ua->request( $req );
  if ( ! $res->is_success )
  {
    $self->SetError( $url . ' failed: ' . $res->message() );
    return;
  }
  my $rightsString = '';
  my $json = JSON::XS->new;
  my $content = $res->content;
  eval {
    my $items = $json->decode($content)->{'items'};
    if ('ARRAY' eq ref $items)
    {
      foreach my $item (@{$items})
      {
        if ($item->{'htid'} eq $id)
        {
          $rightsString = $item->{'usRightsString'};
          last;
        }
      }
    }
    else { $self->SetError("HT Bib API found no data for '$id' (got '$content')"); return; }
  };
  if ($@) { $self->SetError( "failed to parse ($content):$@" ); return; }
  return $rightsString;
}

## ----------------------------------------------------------------------------
##  Function:   get the mirlyn ID for a given volume id using the HT Bib API
##              update local system table if necessary.
##  Parameters: volume id
##  Return:     system id
## ----------------------------------------------------------------------------
sub BarcodeToId
{
  my $self = shift;
  my $id   = shift;

  my $sysid = undef;
  my $sql = "SELECT sysid FROM system WHERE id='$id'";
  $sysid = $self->SimpleSqlGet($sql);
  if (!$sysid)
  {
    my $url = "http://catalog.hathitrust.org/api/volumes/brief/htid/$id.json";
    my $ua = LWP::UserAgent->new;
    $ua->timeout( 1000 );
    my $req = HTTP::Request->new( GET => $url );
    my $res = $ua->request( $req );
    if ( ! $res->is_success )
    {
      $self->SetError( $url . ' failed: ' . $res->message() );
      return;
    }
    my $content = $res->content;
    my $records = undef;
    eval {
      my $json = JSON::XS->new;
      $records = $json->decode($content)->{'records'};
    };
    if ($@ || !$records) { $self->SetError( "failed to parse JSON for $id: $@" ); return; }
    elsif ('HASH' eq ref $records)
    {
      my @keys = keys %$records;
      $sysid = $keys[0];
      my $value = ($sysid)? "'$sysid'":'NULL';
      if ($self->get('nosystem') ne 'nosystem')
      {
        $sql = "REPLACE INTO system (id,sysid) VALUES ('$id',$value)";
        $self->PrepareSubmitSql($sql);
      }
    }
    else { $self->SetError("HT Bib API found no system id for '$id'\nReturned: '$content'\nURL: '$url'"); }
  }
  return $sysid;
}

sub GetReviewField
{
  my $self  = shift;
  my $id    = shift;
  my $user  = shift;
  my $field = shift;

  return $self->SimpleSqlGet("SELECT $field FROM reviews WHERE id='$id' AND user='$user' LIMIT 1");
}

sub HasLockedItem
{
  my $self = shift;
  my $name = shift;

  my $sql = "SELECT id FROM $CRMSGlobals::queueTable WHERE locked='$name' LIMIT 1";
  my $id = $self->SimpleSqlGet( $sql );
  return ($id)? 1:0;
}

sub GetLockedItem
{
  my $self = shift;
  my $name = shift;

  my $sql = "SELECT id FROM $CRMSGlobals::queueTable WHERE locked='$name' LIMIT 1";
  my $id = $self->SimpleSqlGet( $sql );
  return $id;
}

sub IsLocked
{
  my $self = shift;
  my $id   = shift;

  my $sql = "SELECT id FROM $CRMSGlobals::queueTable WHERE locked IS NOT NULL AND id='$id'";
  return ($self->SimpleSqlGet( $sql ))? 1:0;
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

sub IsLockedForOtherUser
{
  my $self = shift;
  my $id   = shift;
  my $user = shift;

  $user = $self->get('user') unless $user;
  my $sql = "SELECT locked FROM $CRMSGlobals::queueTable WHERE id='$id'";
  my $ref = $self->get( 'dbh' )->selectall_arrayref( $sql );
  if ( scalar @{$ref} )
  {
    my $lock = $ref->[0]->[0];
    if ( $lock && $lock ne $user ) { return 1; }
  }
  return 0;
}

sub RemoveOldLocks
{
  my $self = shift;
  my $time = shift;

  # By default, GetPrevDate() returns the date/time 24 hours ago.
  $time = $self->GetPrevDate($time);
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
      #$self->Logit( "REMOVING OLD LOCK:\t$id, $user: $since | $time" );
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
  my $sql = "SELECT id FROM $CRMSGlobals::reviewsTable WHERE id='$id' AND user='$user' AND time<'$limit' AND hold IS NULL";
  my $found = $self->SimpleSqlGet( $sql );
  return ($found)? 1:0;
}

# Returns 0 on success, error message on error.
sub LockItem
{
  my $self     = shift;
  my $id       = shift;
  my $name     = shift;
  my $override = shift;

  ## if already locked for this user, that's OK
  if ( $self->IsLockedForUser( $id, $name ) ) { return 0; }
  # Not locked for user, maybe someone else
  if ($self->IsLocked($id)) { return 'Volume has been locked by another user'; }
  ## can only have 1 item locked at a time (unless override)
  if (!$override)
  {
    my $locked = $self->HasLockedItem( $name );
    return 0 if $locked eq $id; ## already locked
    return "You already have a locked item ($locked)." if $locked;
  }
  my $sql = "UPDATE $CRMSGlobals::queueTable SET locked='$name' WHERE id='$id'";
  $self->PrepareSubmitSql( $sql );
  $self->StartTimer( $id, $name );
  return 0;
}

sub UnlockItem
{
  my $self = shift;
  my $id   = shift;
  my $user = shift;

  my $sql = "UPDATE $CRMSGlobals::queueTable SET locked=NULL WHERE id='$id' AND locked='$user'";
  $self->PrepareSubmitSql($sql);
  $self->RemoveFromTimer( $id, $user );
  return 1;
}

sub UnlockItemEvenIfNotLocked
{
  my $self = shift;
  my $id   = shift;
  my $user = shift;

  my $sql = "UPDATE $CRMSGlobals::queueTable SET locked=NULL WHERE id='$id'";
  if ( ! $self->PrepareSubmitSql($sql) ) { return 0; }
  $self->RemoveFromTimer( $id, $user );
  return 1;
}

sub UnlockAllItemsForUser
{
  my $self = shift;
  my $user = shift;

  my $sql = "SELECT id FROM $CRMSGlobals::timerTable WHERE user='$user'";
  my $ref = $self->get( 'dbh' )->selectall_arrayref( $sql );
  my $return = {};
  foreach my $row (@{$ref})
  {
    my $id = $row->[0];
    $sql = "UPDATE $CRMSGlobals::queueTable SET locked=NULL WHERE id='$id'";
    $self->PrepareSubmitSql( $sql );
  }
  ## clear entry in table
  $sql = "DELETE FROM $CRMSGlobals::timerTable WHERE user='$user'";
  $self->PrepareSubmitSql( $sql );
}

sub GetLockedItems
{
  my $self = shift;
  my $user = shift;

  my $restrict = ($user)? "='$user'":'IS NOT NULL';
  my $sql = "SELECT id, locked FROM $CRMSGlobals::queueTable WHERE locked $restrict";
  my $ref = $self->get( 'dbh' )->selectall_arrayref( $sql );
  my $return = {};
  foreach my $row (@{$ref})
  {
    my $id = $row->[0];
    my $lo = $row->[1];
    $return->{$id} = {'id' => $id, 'locked' => $lo};
  }
  return $return;
}

sub ItemLockedSince
{
  my $self = shift;
  my $id   = shift;
  my $user = shift;

  my $sql = "SELECT start_time FROM timer WHERE id='$id' AND user='$user'";
  return $self->SimpleSqlGet( $sql );
}

sub StartTimer
{
  my $self = shift;
  my $id   = shift;
  my $user = shift;

  my $sql = "REPLACE INTO timer SET start_time=NOW(), id='$id', user='$user'";
  $self->PrepareSubmitSql($sql);
}

sub EndTimer
{
  my $self = shift;
  my $id   = shift;
  my $user = shift;

  my $sql = "UPDATE timer SET end_time=NOW() WHERE id='$id' AND user='$user'";
  if ( ! $self->PrepareSubmitSql($sql) ) { return 0; }
  ## add duration to reviews table
  $self->SetDuration( $id, $user );
}

sub RemoveFromTimer
{
  my $self = shift;
  my $id   = shift;
  my $user = shift;

  ## clear entry in table
  my $sql = "DELETE FROM timer WHERE id='$id' AND user='$user'";
  $self->PrepareSubmitSql( $sql );
}

sub GetDuration
{
  my $self = shift;
  my $id   = shift;
  my $user = shift;

  my $sql = "SELECT duration FROM $CRMSGlobals::reviewsTable WHERE user='$user' AND id='$id'";
  return $self->SimpleSqlGet( $sql );
}

sub SetDuration
{
  my $self = shift;
  my $id   = shift;
  my $user = shift;

  my $sql = "SELECT TIMEDIFF(end_time,start_time) FROM timer where id='$id' AND user='$user'";
  my $dur = $self->SimpleSqlGet( $sql );
  if ($dur)
  {
    ## insert time
    $sql = "UPDATE reviews SET duration=ADDTIME(duration,'$dur'),time=time WHERE user='$user' AND id='$id'";
    $self->PrepareSubmitSql( $sql );
  }
  $self->RemoveFromTimer( $id, $user );
}

sub HasItemBeenReviewedByAnotherExpert
{
  my $self = shift;
  my $id   = shift;
  my $user = shift;
  
  my $stat = $self->GetStatus($id) ;
  if ($stat == 5 || $stat == 7)
  {
    my $sql = "SELECT COUNT(*) FROM $CRMSGlobals::reviewsTable WHERE id='$id' AND user='$user'";
    my $count = $self->SimpleSqlGet($sql);
    return ($count)? 0:1;
  }
  return 0;
}

sub HasItemBeenReviewedByUser
{
  my $self = shift;
  my $id   = shift;
  my $user = shift;
  
  my $sql = "SELECT COUNT(*) FROM $CRMSGlobals::reviewsTable WHERE id='$id' AND user='$user'";
  my $count = $self->SimpleSqlGet($sql);
  return ($count)? 1:0;
}

## ----------------------------------------------------------------------------
##  Function:   get the next item to be reviewed (not something this user has
##              already reviewed)
##  Parameters: user name
##  Return:     volume id
## ----------------------------------------------------------------------------
sub GetNextItemForReview
{
  my $self = shift;
  my $user = shift;
  
  my $id = undef;
  eval{
    my $sql = 'LOCK TABLES queue WRITE, queue AS q WRITE, reviews READ, reviews AS r READ, users READ, timer WRITE';
    $self->PrepareSubmitSql($sql);
    my $exclude = 'q.priority<3 AND';
    if ($self->IsUserSuperAdmin($user))
    {
      # Only Anne reviews priority 4
      $exclude = '';
    }
    # If user is expert, get priority 3 items.
    elsif ($self->IsUserExpert($user))
    {
      $exclude = 'q.priority<4 AND';
    }
    # Exclude priority 1 if our d100 roll is over the P1 threshold or user is not advanced
    my $exclude1 = (rand() >= $CRMSGlobals::priority1Frequency || !$self->IsUserAdvanced($user))? 'q.priority!=1 AND':'';
    $sql = 'SELECT q.id,(SELECT COUNT(*) FROM reviews r WHERE r.id=q.id) AS cnt FROM queue q ' .
           "WHERE $exclude $exclude1 q.expcnt=0 AND q.locked IS NULL " .
           'ORDER BY q.priority DESC, cnt DESC, q.time ASC';
    #print "$sql<br/>\n";
    my $ref = $self->get('dbh')->selectall_arrayref($sql);
    foreach my $row ( @{$ref} )
    {
      my $id2 = $row->[0];
      my $cnt = $row->[1];
      $sql = "SELECT COUNT(*) FROM reviews WHERE id='$id2'";
      next if 1 < $self->SimpleSqlGet($sql);
      $sql = "SELECT COUNT(*) FROM reviews WHERE id='$id2' AND user='$user'";
      next if 0 < $self->SimpleSqlGet($sql);
      my $err = $self->LockItem( $id2, $user );
      if (!$err)
      {
        $id = $id2;
        last;
      }
    }
  };
  $self->SetError($@) if $@;
  $self->PrepareSubmitSql('UNLOCK TABLES');
  if (!$id)
  {
    $self->SetError("Could not get a volume for $user to review.");
  }
  return $id;
}

sub GetRightsName
{
  my $self = shift;
  my $id   = shift;
  
  my %rights = (1 => 'pd', 2 => 'ic', 3 => 'opb', 4 => 'orph', 5 => 'und', 6 => 'umall', 7 => 'world', 8 => 'nobody', 9 => 'pdus');
  return $rights{$id};
}

sub GetReasonName
{
  my $self = shift;
  my $id   = shift;
  
  my %reasons = ( 1 => 'bib', 2 => 'ncn', 3 => 'con',   4 => 'ddd',  5 => 'man',  6 => 'pvt',
                  7 => 'ren', 8 => 'nfi', 9 => 'cdpp', 10 => 'cip', 11 => 'unp', 12 => 'gfv',
                 13 => 'crms', 14 => 'add');
  return $reasons{$id};
}

sub GetRightsNum
{
  my $self = shift;
  my $id   = shift;
  
  my %rights = ('pd'    => 1, 'ic'    => 2, 'opb'    => 3, 'orph' => 4, 'und' => 5,
                'umall' => 6, 'world' => 7, 'nobody' => 8, 'pdus' => 9);
  return $rights{$id};
}

sub GetReasonNum
{
  my $self = shift;
  my $id   = shift;
  
  my %reasons = ('bib'  => 1, 'ncn' => 2, 'con'  => 3, 'ddd' => 4,  'man' => 5,  'pvt' => 6,
                 'ren'  => 7, 'nfi' => 8, 'cdpp' => 9, 'cip' => 10, 'unp' => 11, 'gfv' => 12,
                 'crms' => 13, 'add' => 14);
  return $reasons{$id};
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
  return $self->SimpleSqlGet( $sql );
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

  $error .= "\n";
  $error .= $self->StackTrace();
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
  my $self     = shift;
  my $priority = shift;

  my $restrict = (defined $priority)? "WHERE priority=$priority":'';
  my $sql = "SELECT COUNT(*) FROM $CRMSGlobals::queueTable $restrict";
  return $self->SimpleSqlGet( $sql );
}


# Remove trailing zeroes and point-zeroes from a floating point format.
sub StripDecimal
{
  my $self = shift;
  my $dec  = shift;
  
  $dec =~ s/(\.[1-9]+)0+/$1/g;
  $dec =~ s/\.0*$//;
  return $dec;
}

sub CreateQueueReport
{
  my $self = shift;
  my $dbh = $self->get( 'dbh' );
  my $priheaders = '';
  my @pris = map {$_->[0]} @{ $dbh->selectall_arrayref('SELECT DISTINCT priority FROM queue ORDER BY priority ASC') };
  foreach my $pri (@pris)
  {
    $pri = $self->StripDecimal($pri);
    $priheaders .= "<th>Priority&nbsp;$pri</th>";
  }
  my $report = "<table class='exportStats'>\n<tr><th>Status</th><th>Total</th>$priheaders</tr>\n";
  foreach my $status (-1 .. 9)
  {
    my $statusClause = ($status == -1)? '':" WHERE STATUS=$status";
    my $sql = "SELECT COUNT(*) FROM $CRMSGlobals::queueTable $statusClause";
    my $count = $self->SimpleSqlGet( $sql );
    $status = 'All' if $status == -1;
    my $class = ($status eq 'All')?' class="total"':'';
    $class = ' style="background-color:#999999;"' if $status == 6;
    $report .= sprintf("<tr><td%s>$status%s</td><td%s>$count</td>", $class, ($status == 6)? '*':'', $class);
    $sql = "SELECT priority FROM queue $statusClause";
    my $ref = $dbh->selectall_arrayref($sql);
    $report .= $self->DoPriorityBreakdown($ref,$class,@pris);
    $report .= "</tr>\n";
  }
  my $sql = "SELECT priority FROM queue WHERE status=0 AND id NOT IN (SELECT id FROM reviews)";
  my $ref = $dbh->selectall_arrayref($sql);
  my $count = $self->GetTotalAwaitingReview();
  my $class = ' class="major"';
  $report .= sprintf("<tr><td%s>Not&nbsp;Yet&nbsp;Active</td><td%s>$count</td>", $class, $class);
  $report .= $self->DoPriorityBreakdown($ref,$class,@pris);
  $report .= "</tr>\n";
  $report .= sprintf("<tr><td nowrap='nowrap' colspan='%d'><span class='smallishText'>Note: includes both active and inactive volumes.</span><br/>\n", 2+scalar @pris);
  $report .= "<span class='smallishText'>* Status 6 no longer in use as of 4/19/2010.</span></td></tr>\n";
  $report .= "</table>\n";
  return $report;
}

sub CreateSystemReport
{
  my $self = shift;

  my $report = "<table class='exportStats'>\n";
  # Gets the (time,count) of last queue addition.
  my ($time,$cnt) = $self->GetLastQueueInfo();
  $time = 'Never' unless $time;
  $time =~ s/\s/&nbsp;/g;
  $report .= "<tr><th>Last&nbsp;Queue&nbsp;Update</th><td>$time</td></tr>\n";
  $report .= "<tr><th>Volumes&nbsp;Last&nbsp;Added</th><td>$cnt</td></tr>\n";
  $report .= sprintf("<tr><th>Cumulative&nbsp;Volumes&nbsp;in&nbsp;Queue&nbsp;(ever*)</th><td>%s</td></tr>\n", ($self->GetTotalEverInQueue() or 0));
  $report .= sprintf("<tr><th>Volumes&nbsp;in&nbsp;Candidates</th><td>%s</td></tr>\n", $self->GetCandidatesSize());
  my $val = $self->GetLastLoadTimeToCandidates();
  $val =~ s/\s/&nbsp;/g;
  $report .= sprintf("<tr><th>Last&nbsp;Candidates&nbsp;Addition</th><td>%s&nbsp;on&nbsp;$val</td></tr>", $self->GetLastLoadSizeToCandidates());
  my $count = $self->SimpleSqlGet('SELECT COUNT(*) FROM und');
  $report .= "<tr><th>Items&nbsp;Filtered**</th><td>$count</td></tr>\n";
  if ($count)
  {
    my $ref = $self->get('dbh')->selectall_arrayref('SELECT src,COUNT(src) FROM und GROUP BY src ORDER BY src');
    foreach my $row (@{ $ref})
    {
      my $src = $row->[0];
      my $n = $row->[1];
      $report .= sprintf("<tr><th>&nbsp;&nbsp;&nbsp;&nbsp;$src</th><td>$n&nbsp;(%0.1f%%)</td></tr>\n", 100.0*$n/$count);
    }
  }
  $report .= sprintf "<tr><th>Current&nbsp;Host</th><td>%s</td></tr>\n", $self->Hostname();
  my ($delay,$since) = $self->ReplicationDelay();
  my $alert = $delay >= 5;
  $delay .= ' second' . (($delay == 1)? '':'s');
  $delay = "<span style='color:#CC0000;font-weight:bold;'>$delay since $since</span>" if $alert;
  $report .= "<tr><th>Database&nbsp;Replication&nbsp;Delay</th><td>$delay</td></tr>\n";
  $report .= '<tr><td colspan="2">';
  $report .= '<span class="smallishText">* Not including legacy data (reviews/determinations made prior to July 2009).</span><br/>';
  $report .= '<span class="smallishText">** This number is not included in the "Volumes in Candidates" count above.</span>';
  $report .= "</td></tr></table>\n";
  return $report;
}

sub CreateDeterminationReport
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
  $sql = "SELECT count(DISTINCT h.id) FROM exportdata e, historicalreviews h WHERE e.gid=h.gid AND h.status=7 AND e.time>=date_sub('$time', INTERVAL 1 MINUTE)";
  my $sevens = $self->SimpleSqlGet($sql);
  $sql = "SELECT count(DISTINCT h.id) FROM exportdata e, historicalreviews h WHERE e.gid=h.gid AND h.status=8 AND e.time>=date_sub('$time', INTERVAL 1 MINUTE)";
  my $eights = $self->SimpleSqlGet($sql);
  $sql = "SELECT count(DISTINCT h.id) FROM exportdata e, historicalreviews h WHERE e.gid=h.gid AND h.status=9 AND e.time>=date_sub('$time', INTERVAL 1 MINUTE)";
  my $nines = $self->SimpleSqlGet($sql);
  my $total = $fours+$fives+$sixes+$sevens+$eights+$nines;
  my $pct4 = 0;
  my $pct5 = 0;
  my $pct6 = 0;
  my $pct7 = 0;
  my $pct8 = 0;
  my $pct9 = 0;
  eval {$pct4 = 100.0*$fours/$total;};
  eval {$pct5 = 100.0*$fives/$total;};
  eval {$pct6 = 100.0*$sixes/$total;};
  eval {$pct7 = 100.0*$sevens/$total;};
  eval {$pct8 = 100.0*$eights/$total;};
  eval {$pct9 = 100.0*$nines/$total;};
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
  $report .= sprintf("<tr><th style='color:#999999;'>&nbsp;&nbsp;&nbsp;&nbsp;Status&nbsp;6*</th><td style='background-color:#999999;'>$sixes&nbsp;(%.1f%%)</td></tr>", $pct6);
  $report .= sprintf("<tr><th>&nbsp;&nbsp;&nbsp;&nbsp;Status&nbsp;7</th><td>$sevens&nbsp;(%.1f%%)</td></tr>", $pct7);
  $report .= sprintf("<tr><th>&nbsp;&nbsp;&nbsp;&nbsp;Status&nbsp;8</th><td>$eights&nbsp;(%.1f%%)</td></tr>", $pct8);
  $report .= sprintf("<tr><th>&nbsp;&nbsp;&nbsp;&nbsp;Status&nbsp;9</th><td>$nines&nbsp;(%.1f%%)</td></tr>", $pct9);
  $report .= sprintf("<tr><th>Total&nbsp;CRMS&nbsp;Determinations</th><td>%s</td></tr>", $exported);
  foreach my $source (sort keys %sources)
  {
    my $n = $sources{$source};
    $report .= sprintf("<tr><th>&nbsp;&nbsp;&nbsp;&nbsp;%s</th><td>$n</td></tr>", $self->ExportSrcToEnglish($source));
  }
  $report .= sprintf("<tr><th>Total&nbsp;Legacy&nbsp;Determinations</th><td>%s</td></tr>", $legacy);
  $report .= sprintf("<tr><th>Total&nbsp;Determinations</th><td>%s</td></tr>", $exported + $legacy);
  $report .= "<tr><td colspan='2'><span class='smallishText'>* Status 6 no longer in use as of 4/19/2010.</span></td></tr>\n";
  $report .= "</table>\n";
  return $report;
}

sub CreateHistoricalReviewsReport
{
  my $self = shift;
  
  my $report = "<table class='exportStats'>\n";
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
  my $priheaders = '';
  my @pris = map {$_->[0]} @{ $dbh->selectall_arrayref('SELECT DISTINCT priority FROM queue ORDER BY priority ASC') };
  foreach my $pri (@pris)
  {
    $pri = $self->StripDecimal($pri);
    $priheaders .= "<th>Priority&nbsp;$pri</th>"
  }
  $report .= "<table class='exportStats'>\n<tr><th>Status</th><th>Total</th>$priheaders</tr>\n";
  
  my $sql = 'SELECT priority FROM queue WHERE id IN (SELECT DISTINCT id FROM reviews)';
  my $ref = $dbh->selectall_arrayref( $sql );
  my $count = scalar @{$ref};
  $report .= "<tr><td class='total'>Active</td><td class='total'>$count</td>";
  $report .= $self->DoPriorityBreakdown($ref,' class="total"',@pris) . "</tr>\n";
  
  # Unprocessed
  $sql = 'SELECT priority FROM queue WHERE status=0 AND pending_status>0';
  $ref = $dbh->selectall_arrayref( $sql );
  $count = scalar @{$ref};
  $report .= "<tr><td class='minor'>Unprocessed</td><td class='minor'>$count</td>";
  $report .= $self->DoPriorityBreakdown($ref,' class="minor"',@pris) . "</tr>\n";
  
  # Unprocessed - single review
  $sql = 'SELECT priority from queue WHERE status=0 AND pending_status=1';
  $ref = $dbh->selectall_arrayref( $sql );
  $count = scalar @{$ref};
  $report .= "<tr><td>&nbsp;&nbsp;&nbsp;Single&nbsp;Review</td><td>$count</td>";
  $report .= $self->DoPriorityBreakdown($ref,undef,@pris) . "</tr>\n";
  
  # Unprocessed - match
  $sql = 'SELECT priority from queue WHERE status=0 AND pending_status=4';
  $ref = $dbh->selectall_arrayref( $sql );
  $count = scalar @{$ref};
  $report .= "<tr><td>&nbsp;&nbsp;&nbsp;Match</td><td>$count</td>";
  $report .= $self->DoPriorityBreakdown($ref,undef,@pris) . "</tr>\n";
  
  # Unprocessed - conflict
  $sql = 'SELECT priority from queue WHERE status=0 AND pending_status=2';
  $ref = $dbh->selectall_arrayref( $sql );
  $count = scalar @{$ref};
  $report .= "<tr><td>&nbsp;&nbsp;&nbsp;Conflict</td><td>$count</td>";
  $report .= $self->DoPriorityBreakdown($ref,undef,@pris) . "</tr>\n";
  
  # Unprocessed - provisional match
  $sql = 'SELECT priority from queue WHERE status=0 AND pending_status=3';
  $ref = $dbh->selectall_arrayref( $sql );
  $count = scalar @{$ref};
  $report .= "<tr><td>&nbsp;&nbsp;&nbsp;Provisional&nbsp;Match</td><td>$count</td>";
  $report .= $self->DoPriorityBreakdown($ref,undef,@pris) . "</tr>\n";
  
  # Unprocessed - auto-resolved
  $sql = 'SELECT priority from queue WHERE status=0 AND pending_status=8';
  $ref = $dbh->selectall_arrayref( $sql );
  $count = scalar @{$ref};
  $report .= "<tr><td>&nbsp;&nbsp;&nbsp;Auto-Resolved</td><td>$count</td>";
  $report .= $self->DoPriorityBreakdown($ref,undef,@pris) . "</tr>\n";
  
  # Inheriting
  $sql = 'SELECT COUNT(*) FROM inherit WHERE del!=1';
  $count = $self->SimpleSqlGet($sql);
  $report .= "<tr class='inherit'><td>Can Inherit</td><td>$count</td>";
  $report .= "<td/>" for @pris;
  $report .= '</tr>';
  
  # Processed
  $sql = 'SELECT priority FROM queue WHERE status!=0';
  $ref = $dbh->selectall_arrayref( $sql );
  $count = scalar @{$ref};
  $report .= "<tr><td class='minor'>Processed</td><td class='minor'>$count</td>";
  $report .= $self->DoPriorityBreakdown($ref,' class="minor"',@pris) . "</tr>\n";
  
  $sql = "SELECT priority from $CRMSGlobals::queueTable WHERE status=2";
  $ref = $dbh->selectall_arrayref( $sql );
  $count = scalar @{$ref};
  $report .= "<tr><td>&nbsp;&nbsp;&nbsp;Conflict</td><td>$count</td>";
  $report .= $self->DoPriorityBreakdown($ref,undef,@pris) . "</tr>\n";

  $sql = 'SELECT priority from queue WHERE status=3';
  $ref = $dbh->selectall_arrayref( $sql );
  $count = scalar @{$ref};
  $report .= "<tr><td>&nbsp;&nbsp;&nbsp;Provisional&nbsp;Match</td><td>$count</td>";
  $report .= $self->DoPriorityBreakdown($ref,undef,@pris) . "</tr>\n";
  
  $sql = "SELECT priority from $CRMSGlobals::queueTable WHERE status>=4";
  $ref = $dbh->selectall_arrayref( $sql );
  $count = scalar @{$ref};
  $report .= "<tr><td>&nbsp;&nbsp;&nbsp;Awaiting&nbsp;Export</td><td>$count</td>";
  $report .= $self->DoPriorityBreakdown($ref,undef,@pris) . "</tr>\n";
  
  if ($count > 0)
  {
    for my $status (4..9)
    {
      $sql = "SELECT priority from queue WHERE status=$status";
      $ref = $dbh->selectall_arrayref( $sql );
      $count = scalar @{$ref};
      $report .= "<tr><td>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Status&nbsp;$status</td><td>$count</td>";
      $report .= $self->DoPriorityBreakdown($ref,undef,@pris) . "</tr>\n";
    }
  }
  $report .= sprintf("<tr><td nowrap='nowrap' colspan='%d'><span class='smallishText'>Last processed %s</span></td></tr>\n", 2+scalar @pris, $self->GetLastStatusProcessedTime());
  $report .= "</table>\n";
  return $report;
}

# Takes a selectall_arrayref ref in which each row has a priority as its first column
sub DoPriorityBreakdown
{
  my $self  = shift;
  my $ref   = shift;
  my $class = shift;
  
  my %breakdown;
  $breakdown{$_} = 0 for @_;
  foreach my $row (@{$ref})
  {
    my $pri = $self->StripDecimal($row->[0]);
    #print "Pri $pri<br/>\n";
    $breakdown{$pri}++;
  }
  my $ret = join '',map {sprintf "<td$class>%s</td>", $breakdown{$_}} sort keys %breakdown;
  #printf "%d priorities: %s <!-- $ret --><br/>\n"; scalar keys %breakdown, join ',', keys %breakdown;
  return $ret;
}


sub GetTotalAwaitingReview
{
  my $self = shift;

  my $sql = 'SELECT COUNT(id) FROM queue WHERE status=0 AND id NOT IN (SELECT DISTINCT id FROM reviews)';
  my $count = $self->SimpleSqlGet( $sql );
  return ($count)? $count:0;
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

  my $sql = 'SELECT DATE_FORMAT(MAX(time), "%a, %M %e, %Y at %l:%i %p") FROM candidatesrecord';
  my $time = $self->SimpleSqlGet( $sql );
  if ($time) { return $time; }
  return 'no data available';
}


sub GetTotalExported
{
  my $self = shift;

  my $sql = "SELECT SUM(itemcount) FROM $CRMSGlobals::exportrecordTable";
  return $self->SimpleSqlGet( $sql );
}


sub GetTotalEverInQueue
{
  my $self = shift;

  my $count_exported = $self->GetTotalExported();
  my $count_queue = $self->GetQueueSize();
  my $total = $count_exported + $count_queue;
  return $total;
}

sub GetLastExport
{
  my $self = shift;
  my $readable = shift;

  my $sql = "SELECT itemcount,time FROM exportrecord WHERE itemcount>0 ORDER BY time DESC LIMIT 1";
  my $ref = $self->get('dbh')->selectall_arrayref( $sql );
  my $count = $ref->[0]->[0];
  my $time = $ref->[0]->[1];
  $time = $self->FormatTime($time) if $readable;
  return ($count,$time);
}

sub GetTotalLegacyCount
{
  my $self = shift;

  my $sql = "SELECT COUNT(DISTINCT id) FROM $CRMSGlobals::historicalreviewsTable WHERE legacy=1 AND priority!=1";
  return $self->SimpleSqlGet( $sql );
}

sub GetTotalNonLegacyReviewCount
{
  my $self = shift;

  my $sql = "SELECT COUNT(*) FROM $CRMSGlobals::historicalreviewsTable WHERE legacy!=1";
  return $self->SimpleSqlGet( $sql );
}

sub GetTotalLegacyReviewCount
{
  my $self = shift;

  my $sql = "SELECT COUNT(*) FROM $CRMSGlobals::historicalreviewsTable WHERE legacy=1";
  return $self->SimpleSqlGet( $sql );
}

sub GetTotalHistoricalReviewCount
{
  my $self = shift;

  my $sql = "SELECT COUNT(*) FROM $CRMSGlobals::historicalreviewsTable";
  return $self->SimpleSqlGet( $sql );
}

# Gets the (time,count) of last queue addition.
sub GetLastQueueInfo
{
  my $self = shift;
  
  my $sql = 'SELECT time,itemcount FROM queuerecord WHERE source="RIGHTSDB" ORDER BY time DESC LIMIT 1';
  my $row = $self->get('dbh')->selectall_arrayref($sql)->[0];
  my $time = $self->FormatTime($row->[0]);
  my $cnt = $row->[1];
  return ($time,$cnt);
}

sub GetLastStatusProcessedTime
{
  my $self = shift;

  my $time = $self->SimpleSqlGet('SELECT MAX(time) FROM processstatus');
  return $self->FormatTime($time);
}

sub DownloadSpreadSheet
{
  my $self   = shift;
  my $buffer = shift;

  if ($buffer)
  {
    print &CGI::header(-type => 'text/plain', -charset => 'utf-8');
    print $buffer;
  }
}

sub CountReviewsForUser
{
  my $self = shift;
  my $user = shift;

  my $sql = "SELECT count(*) FROM reviews WHERE user='$user'";
  return $self->SimpleSqlGet($sql);
}

sub CountHistoricalReviewsForUser
{
  my $self = shift;
  my $user = shift;
  my $year = shift;

  my $ysql = ($year)? "AND time LIKE '$year%'":'';
  my $sql = "SELECT count(*) FROM historicalreviews WHERE user='$user' $ysql";
  return $self->SimpleSqlGet($sql);
}

sub CountAllReviewsForUser
{
  my $self = shift;
  my $user = shift;

  my $sql = "SELECT count(*) FROM reviews WHERE user='$user'";
  my $n = $self->SimpleSqlGet($sql);
  $sql = "SELECT count(*) FROM historicalreviews WHERE user='$user'";
  $n += $self->SimpleSqlGet($sql);
  return $n;
}


sub IsReviewCorrect
{
  my $self = shift;
  my $id   = shift;
  my $user = shift;
  my $time = shift;
  
  # Has there ever been a swiss review for this volume?
  my $sql = "SELECT COUNT(id) FROM historicalreviews WHERE id='$id' AND swiss=1";
  my $swiss = $self->SimpleSqlGet($sql);
  # Get the review
  $sql = "SELECT attr,reason,renNum,renDate,expert,status,time FROM historicalreviews WHERE id='$id' AND user='$user' AND time LIKE '$time%'";
  my $r = $self->get('dbh')->selectall_arrayref($sql);
  my $row = $r->[0];
  my $attr    = $row->[0];
  my $reason  = $row->[1];
  my $renNum  = $row->[2];
  my $renDate = $row->[3];
  my $expert  = $row->[4];
  my $status  = $row->[5];
  my $time    = $row->[6];
  #print "$attr, $reason, $renNum, $renDate, $expert, $swiss\n";
  # A non-expert with status 7 is protected rather like Swiss.
  return 1 if ($status == 7 && !$expert);
  # Get the most recent non-autocrms expert review.
  $sql = "SELECT attr,reason,renNum,renDate,user,swiss FROM historicalreviews WHERE id='$id' AND expert>0 AND time>'$time' ORDER BY time DESC";
  $r = $self->get('dbh')->selectall_arrayref($sql);
  return 1 unless scalar @{$r};
  $row = $r->[0];
  my $eattr    = $row->[0];
  my $ereason  = $row->[1];
  my $erenNum  = $row->[2];
  my $erenDate = $row->[3];
  my $euser    = $row->[4];
  my $eswiss   = $row->[5];
  #print "$eattr, $ereason, $erenNum, $erenDate, $euser\n";
  if ($attr != $eattr)
  {
    return (($swiss && !$expert) || ($eswiss && $euser eq 'autocrms'))? 2:0;
  }
  if ($reason != $ereason ||
      ($attr == 2 && $reason == 7 && ($renNum ne $erenNum || $renDate ne $erenDate)))
  {
    return (($swiss && !$expert) || ($eswiss && $euser eq 'autocrms'))? 2:0;
  }
  return 1;
}

sub UpdateCorrectness
{
  my $self = shift;
  my $id   = shift;

  my $sql = "SELECT user,time,validated FROM historicalreviews WHERE id='$id'";
  my $r = $self->get('dbh')->selectall_arrayref($sql);
  foreach my $row ( @{$r} )
  {
    my $user = $row->[0];
    my $time = $row->[1];
    my $val = $row->[2];
    my $val2 = $self->IsReviewCorrect($id, $user, $time);
    if ($val != $val2)
    {
      $sql = "UPDATE historicalreviews SET validated=$val2 WHERE id='$id' AND user='$user' AND time='$time'";
      #print "$sql\n";
      $self->PrepareSubmitSql($sql);
    }
  }
}


sub CountCorrectReviews
{
  my $self  = shift;
  my $user  = shift;
  my $start = shift;
  my $end   = shift;
  
  my $startClause = ($start)? " AND time>='$start'":'';
  my $endClause = ($end)? " AND time<='$end' ":'';
  my $userClause = " AND user='$user'";
  if ($user eq 'all')
  {
    $userClause = sprintf(' AND user IN (%s)', join(',', map {"'$_'"} $self->GetType1Reviewers()));
  }
  #print "$sql => $total<br/>\n";
  my $correct = 0;
  my $incorrect = 0;
  my $neutral = 0;
  my $sql = "SELECT validated,COUNT(id) FROM historicalreviews WHERE legacy!=1 $startClause $endClause $userClause GROUP BY validated";
  my $ref = $self->get('dbh')->selectall_arrayref($sql);
  foreach my $row ( @{$ref} )
  {
    my $val = $row->[0];
    my $cnt = $row->[1];
    $incorrect = $cnt if $val == 0;
    $correct = $cnt if $val == 1;
    $neutral = $cnt if $val == 2;
  }
  return ($correct,$incorrect,$neutral);
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
  my $sql = 'SELECT id FROM users WHERE id NOT LIKE "rereport%" AND expert=0';
  return map {$_->[0]} @{$dbh->selectall_arrayref( $sql )};
}

sub GetValidation
{
  my $self  = shift;
  my $start = shift;
  my $end   = shift;
  my $users = shift;
  
  $users = sprintf '"%s"', join '","', $self->GetType1Reviewers() unless $users;
  $start = substr($start,0,7);
  $end = substr($end,0,7);
  my $sql = 'SELECT SUM(total_reviews),SUM(total_correct),SUM(total_incorrect),SUM(total_neutral) FROM userstats ' .
            "WHERE monthyear>='$start' AND monthyear<='$end' AND user IN ($users)";
  #print "$sql<br/>\n";
  my $ref = $self->get('dbh')->selectall_arrayref($sql);
  my $row = $ref->[0];
  return @{ $row };
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
  my $vidRE = '^[a-z]+\d?\..+';
  my $pdRE = '^[1-9]\d\d\d-\d\d-\d\d$';
  my @errs = ();
  # ======== bibdata ========
  my $table = 'bibdata';
  # Volume ID must not have any spaces before, after, or in.
  # MySQL years should be valid, but it stores a value of '0000-00-00' in case of illegal value entered.
  my $sql = "SELECT id,pub_date,author,title FROM $table";
  my $rows = $dbh->selectall_arrayref( $sql );
  foreach my $row ( @{$rows} )
  {
    push @errs, sprintf("$table __ illegal volume id__ '%s'", $row->[0]) unless $row->[0] =~ m/$vidRE/;
    push @errs, sprintf("$table __ illegal pub_date for %s__ %s", $row->[0], $row->[1]) unless $row->[1] =~ m/$pdRE/;
    #push @errs, sprintf("$table __ no author for %s__ '%s'", $row->[0], $row->[2]) if $row->[2] eq '';
    push @errs, sprintf("$table __ no title for %s__ '%s'", $row->[0], $row->[3]) if $row->[3] eq '';
    push @errs, sprintf("$table __ author encoding (%s) questionable for %s__ '%s'", (utf8::is_utf8($row->[2]))?'utf-8':'ASCII', $row->[0], $row->[2]) if $self->Mojibake($row->[2]);
    push @errs, sprintf("$table __ title encoding (%s) questionable for %s__ '%s'", (utf8::is_utf8($row->[3]))?'utf-8':'ASCII', $row->[0], $row->[3]) if $self->Mojibake($row->[3]);
    push @errs, sprintf("$table __ author encoding (%s) questionable for %s__ '%s'", (utf8::is_utf8($row->[2]))?'utf-8':'ASCII', $row->[0], $row->[2]) if $row->[2] =~ m/.*?\?\?.*/;
    push @errs, sprintf("$table __ title encoding (%s) questionable for %s__ '%s'", (utf8::is_utf8($row->[3]))?'utf-8':'ASCII', $row->[0], $row->[3]) if $row->[3] =~ m/.*?\?\?.*/;
  }
  # ======== candidates ========
  $table = 'candidates';
  $sql = "SELECT id,pub_date,author,title FROM $table";
  $rows = $dbh->selectall_arrayref( $sql );
  foreach my $row ( @{$rows} )
  {
    push @errs, sprintf("$table __ illegal volume id__ '%s'", $row->[0]) unless $row->[0] =~ m/$vidRE/;
    push @errs, sprintf("$table __ illegal pub_date for %s__ %s", $row->[0], $row->[1]) unless $row->[1] =~ m/$pdRE/;
    push @errs, sprintf("$table __ no title for %s__ '%s'", $row->[0], $row->[3]) if $row->[3] eq '';
    push @errs, sprintf("$table __ author encoding (%s) questionable for %s__ '%s'", (utf8::is_utf8($row->[2]))?'utf-8':'ASCII', $row->[0], $row->[2]) if $self->Mojibake($row->[2]);
    push @errs, sprintf("$table __ title encoding (%s) questionable for %s__ '%s'", (utf8::is_utf8($row->[3]))?'utf-8':'ASCII', $row->[0], $row->[3]) if $self->Mojibake($row->[3]);
    push @errs, sprintf("$table __ author encoding (%s) questionable for %s__ '%s'", (utf8::is_utf8($row->[2]))?'utf-8':'ASCII', $row->[0], $row->[2]) if $row->[2] =~ m/.*?\?\?.*/;
    push @errs, sprintf("$table __ title encoding (%s) questionable for %s__ '%s'", (utf8::is_utf8($row->[3]))?'utf-8':'ASCII', $row->[0], $row->[3]) if $row->[3] =~ m/.*?\?\?.*/;
  }
  # ======== exportdata ========
  # time must be in a format like 2009-07-16 07:00:02
  # id must not be ill-formed
  # user must be crms
  # src must not be NULL
  $table = 'exportdata';
  $sql = "SELECT time,id,attr,reason,user,src FROM $table";
  $rows = $dbh->selectall_arrayref( $sql );
  foreach my $row ( @{$rows} )
  {
    push @errs, sprintf("$table __ illegal time for %s__ '%s'", $row->[1], $row->[0]) unless $row->[0] =~ m/\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d/;
    push @errs, sprintf("$table __ illegal volume id__ '%s'", $row->[1]) unless $row->[1] =~ m/$vidRE/;
    push @errs, sprintf("$table __ illegal user for %s__ '%s' (should be 'crms')", $row->[1]) unless $row->[4] eq 'crms';
    push @errs, sprintf("$table __ NULL src for %s__ ", $row->[1]) unless $row->[4];
  }
  # All gid/id must match gid/id in historicalreviews
  $sql = "SELECT e.gid,e.id,h.id,e.src,h.source FROM $table e INNER JOIN historicalreviews h ON e.gid=h.gid WHERE e.id!=h.id OR e.src!=h.source";
  $rows = $dbh->selectall_arrayref( $sql );
  foreach my $row ( @{$rows} )
  {
    push @errs, sprintf("$table __ Nonmatching id for gid %s__ %s vs %s", $row->[0], $row->[1], $row->[2]) if $row->[1] ne $row->[2];
    # In one unusual case the below can happen: nonmatching sources.
    #push @errs, sprintf("$table __ Nonmatching src for gid %s__ %s vs%s", $row->[0], $row->[3], $row->[4]) if $row->[3] ne $row->[4];
  }
  # ======== exportrecord ========
  $table = 'exportrecord';
  $sql = "SELECT time FROM $table WHERE time='0000-00-00 00:00:00'";
  $rows = $dbh->selectall_arrayref( $sql );
  foreach my $row ( @{$rows} )
  {
    push @errs, sprintf("$table __ illegal time__ %s", $row->[0]);
  }
  # ======== reviews ========
  $table = 'reviews';
  $sql = "SELECT id,time,user,attr,reason,note,renNum,expert,duration,legacy,renDate,category FROM $table";
  $rows = $dbh->selectall_arrayref( $sql );
  foreach my $row ( @{$rows} )
  {
    push @errs, sprintf("$table __ illegal volume id '%s'", $row->[0]) unless $row->[0] =~ m/$vidRE/;
    push @errs, sprintf("$table __ illegal time for %s__ '%s'", $row->[0], $row->[1]) unless $row->[1] =~ m/\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d/;
    push @errs, sprintf("$table __ spaces in renNum for %s__ '%s'", $row->[0], $row->[6]) if $row->[6] =~ m/(^\s+.*)|(.*?\s+$)/;
    push @errs, sprintf("$table __ illegal renDate for %s__ '%s' (should be like '14Oct70')", $row->[0], $row->[10]) unless $self->IsRenDate($row->[10]);
    push @errs, sprintf("$table __ illegal category for %s__ '%s'", $row->[0], $row->[12]) unless $row->[11] eq '' or $self->IsValidCategory($row->[11]);
  }
  # ======== historicalreviews ========
  $table = 'historicalreviews';
  $sql = "SELECT id,time,user,attr,reason,note,renNum,expert,duration,legacy,renDate,category,status FROM $table";
  $rows = $dbh->selectall_arrayref( $sql );
  my %stati = (1=>1,4=>1,5=>1,6=>1,7=>1);
  foreach my $row ( @{$rows} )
  {
    push @errs, sprintf("$table __ illegal volume id '%s'", $row->[0]) unless $row->[0] =~ m/$vidRE/;
    push @errs, sprintf("$table __ illegal time for %s__ '%s'", $row->[0], $row->[1]) unless $row->[1] =~ m/\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d/;
    push @errs, sprintf("$table __ spaces in renNum for %s__ '%s'", $row->[0], $row->[6]) if $row->[6] =~ m/(^\s+.*)|(.*?\s+$)/;
    push @errs, sprintf("$table __ illegal renDate for %s__ '%s' (should be like '14Oct70')", $row->[0], $row->[10]) unless $self->IsRenDate($row->[10]);
    push @errs, sprintf("$table __ illegal category for %s__ '%s'", $row->[0], $row->[11]) unless $row->[11] eq '' or $self->IsValidCategory($row->[11]);
    push @errs, sprintf("$table __ illegal status for %s__ '%s'", $row->[0], $row->[12]) unless $stati{$row->[12]};
    $sql = "SELECT id,status,gid,SUM(expert) AS ct FROM $table WHERE status=5 OR status=6 GROUP BY gid HAVING ct=0";
    $rows = $dbh->selectall_arrayref( $sql );
    foreach my $row ( @{$rows} )
    {
      push @errs, sprintf("$table __ no expert review for status %s %s__ ", $row->[1], $row->[0]);
    }
  }
  $sql = "SELECT id,status FROM historicalreviews WHERE legacy=1 AND user NOT LIKE 'rereport%' AND user!='annekz' AND status>3";
  $rows = $dbh->selectall_arrayref($sql);
  foreach my $row ( @{$rows} )
  {
    my $id = $row->[0];
    $sql = "SELECT COUNT(*) FROM historicalreviews WHERE id='$id' AND legacy=1 AND user='annekz'";
    if (!$self->SimpleSqlGet($sql))
    {
      push @errs, sprintf("$table __ bad status for legacy %s__ %s", $id, $row->[1]);
    }
  }
  # ======== queue ========
  $table = 'queue';
  $sql = "SELECT id,time,status,locked,priority,expcnt FROM $table";
  $rows = $dbh->selectall_arrayref( $sql );
  foreach my $row ( @{$rows} )
  {
    push @errs, sprintf("$table __ illegal volume id '%s'", $row->[0]) unless $row->[0] =~ m/$vidRE/;
    push @errs, sprintf("$table __ illegal time for %s__ '%s'", $row->[0], $row->[1]) unless $row->[1] =~ m/\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d/;
    push @errs, sprintf("$table __ illegal status for %s__ '%s'", $row->[0], $row->[2]) unless $row->[2] >= 0 and $row->[2] <= 7;
    if ($row->[2] == 5 || $row->[6])
    {
      $sql = sprintf("SELECT SUM(expert) FROM reviews WHERE id='%s'", $row->[0]);
      my $sum = $self->SimpleSqlGet($sql);
      push @errs, sprintf("$table __ illegal status/expcnt for %s__ '%s'/'%s' but there are no expert reviews", $row->[0], $row->[2]) unless $sum;
    }
  }
  return \@errs;
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
  my $self       = shift;
  my $page       = shift;
  my $searchName = shift;
  my $searchVal  = shift;
  my $order      = shift;
  
  my @keys = ('Identifier','SysID',    'Title','Author','PubDate', 'ReviewDate', 'Status','Legacy','UserId','Attribute',
              'Reason', 'NoteCategory', 'Note', 'Priority', 'Validated', 'Swiss', 'Hold Thru');
  my @labs = ('Identifier','System ID','Title','Author','Pub Date','Review Date', 'Status','Legacy','User',  'Attribute',
              'Reason','Note Category', 'Note', 'Priority', 'Verdict',   'Swiss', 'Hold Thru');
  
  if ($page ne 'adminReviews' && $page ne 'editReviews' && $page ne 'holds')
  {
    splice @keys, 16, 1; # Hold
    splice @labs, 16, 1;
  }
  if (!$self->IsUserExpert())
  {
    splice @keys, 15, 1; # Swiss
    splice @labs, 15, 1;
  }
  if ($page ne 'adminHistoricalReviews')
  {
    splice @keys, 14, 1;
    splice @labs, 14, 1; # Validated
  }
  if (!$self->IsUserAdmin())
  {
    splice @keys, 13, 1; # Priority
    splice @labs, 13, 1;
  }
  if ($page ne 'adminHistoricalReviews')
  {
    splice @keys, 7, 1; # Legacy
    splice @labs, 7, 1;
  }
  if (!$order)
  {
    splice @keys, 5, 1; # Review Date
    splice @labs, 5, 1;
  }
  if ($page ne 'adminHistoricalReviews')
  {
    splice @keys, 4, 1; # Pub Date
    splice @labs, 4, 1;
  }
  if ($page ne 'adminHistoricalReviews' || !($self->IsUserExpert() || $self->IsUserAdmin()))
  {
    splice @keys, 1, 1; # Sys ID
    splice @labs, 1, 1;
  }
  my $html = "<select title='Search Field' name='$searchName' id='$searchName'>\n";
  foreach my $i (0 .. scalar @keys - 1)
  {
    $html .= sprintf("  <option value='%s'%s>%s</option>\n", $keys[$i], ($searchVal eq $keys[$i])? ' selected="selected"':'', $labs[$i]);
  }
  $html .= '</select>';
  return $html;
}

# Generates HTML to get the field type menu on the Volumes in Queue page.
sub QueueSearchMenu
{
  my $self = shift;
  my $searchName = shift;
  my $searchVal = shift;
  
  my @keys = qw(Identifier Title Author PubDate Status Locked Priority Reviews ExpertCount Holds);
  my @labs = ('Identifier','Title','Author','Pub Date','Status','Locked','Priority','Reviews','Expert Reviews','Holds');
  my $html = "<select title='Search Field' name='$searchName' id='$searchName'>\n";
  foreach my $i (0 .. scalar @keys - 1)
  {
    $html .= sprintf("  <option value='%s'%s>%s</option>\n", $keys[$i], ($searchVal eq $keys[$i])? ' selected="selected"':'', $labs[$i]);
  }
  $html .= "</select>\n";
  return $html;
}

# This is used for the HTML page title.
sub PageToEnglish
{
  my $self = shift;
  my $page = shift;
  
  return 'home' unless $page;
  my %pages = ('adminEditUser' => 'user accounts',
               'adminHistoricalReviews' => 'historical reviews',
               'adminHolds' => 'all held reviews',
               'adminQueue' => 'all locked volumes',
               'adminReviews' => 'active reviews',
               'adminUser' => 'user accounts',
               'adminUserRate' => 'all review stats',
               'adminUserRateInst' => 'institutional review stats',
               'contact' => 'contact us',
               'debug' => 'system administration',
               'detailInfo' => 'review detail',
               'determinationStats' => 'determinations breakdown',
               'editReviews' => 'my unprocessed reviews',
               'expert' => 'conflicts',
               'exportStats' => 'export stats',
               'holds' => 'my held reviews',
               'inherit' => 'rights inheritance',
               'queue' => 'volumes in queue',
               'queueAdd' => 'add to queue',
               'queueStatus' => 'system summary',
               'retrieve' => 'retrieve volume ids',
               'review' => 'review',
               'rights' => 'query rights database',
               'systemStatus' => 'system status',
               'undReviews' => 'provisional matches',
               'userRate' => 'my review stats',
               'userReviews' => 'my processed reviews',
              );
  return $pages{$page};
}

# Query the production rights database. This returns an array ref of entries for the volume, oldest first.
# Returns: aref to aref of ($attr,$reason,$src,$usr,$time,$note)
sub RightsQuery
{
  my $self   = shift;
  my $id     = shift;
  my $latest = shift;
  
  my ($namespace,$n) = split m/\./, $id, 2;
  my $table = ($latest)? 'rights_current':'rights_log';
  my $sql = "SELECT a.name,rs.name,s.name,r.user,r.time,r.note FROM $table r, attributes a, reasons rs, sources s " .
            "WHERE r.namespace='$namespace' AND r.id='$n' AND s.id=r.source AND a.id=r.attr AND rs.id=r.reason " .
            'ORDER BY r.time ASC';
  my $ref;
  eval { $ref = $self->GetSdrDb()->selectall_arrayref($sql); };
  $self->SetError("Rights query for $id failed: $@") if $@;
  return $ref;
}

# Query Mirlyn holdings for this system id and return volume identifiers.
sub VolumeIDsQuery
{
  my $self   = shift;
  my $sysid  = shift;
  my $record = shift;

  my @ids;
  eval {
    $record = $self->GetMetadata($sysid) unless $record;
    my $nodes = $record->findnodes("//*[local-name()='datafield' and \@tag='974']");
    foreach my $node ($nodes->get_nodelist())
    {
      my $id = $node->findvalue("./*[local-name()='subfield' and \@code='u']");
      my $chron = $node->findvalue("./*[local-name()='subfield' and \@code='z']");
      my $rights = $self->GetRightsString($id);
      #print "$rights,$id,$chron<br/>\n";
      push @ids, $id . '__' . $chron . '__' . $rights;
    }
    $nodes = $record->findnodes("//*[local-name()='datafield' and \@tag='MDP']");
    foreach my $node ($nodes->get_nodelist())
    {
      my $id2 = $node->findvalue("./*[local-name()='subfield' and \@code='u']");
      my $chron = $node->findvalue("./*[local-name()='subfield' and \@code='z']");
      my $rights = $self->GetRightsString($id2);
      #print "$rights,$id,$chron<br/>\n";
      push @ids, $id2 . '__' . $chron . '__' . $rights;
    }
  };
  $self->SetError("Holdings query for $sysid failed: $@") if $@;
  return \@ids;
}

sub DownloadVolumeIDs
{
  my $self  = shift;
  my $sysid = shift;
  
  my $buffer = (join "\t", qw (ID Chron Rights Attr Reason Source User Time Note)) . "\n";
  my $rows = $self->VolumeIDsQuery($sysid);
  foreach my $line (@{$rows})
  {
    my ($id,$chron,$rights) = split '__', $line;
    $buffer .= (join "\t", (($id,$chron,$rights), @{$self->RightsQuery($id,1)->[0]})) . "\n";
  }
  $self->DownloadSpreadSheet($buffer);
  return (1 == scalar @{$self->GetErrors()});
}

# Returns a reference to an array with (time,status,message)
sub GetSystemStatus
{
  my $self    = shift;
  my $nodelay = shift;

  my @vals = ('forever','normal','');
  my ($delay,$since) = $self->ReplicationDelay();
  if (4 < $delay && !$nodelay)
  {
    @vals = ($since,
             'delayed',
             'The CRMS is currently experiencing delays. "Review" and "Add to Queue" pages may not be available. ' .
             'Please try again in a few minutes. ' .
             'Locked volumes may need to have reviews re-submitted.');
    return \@vals;
  }
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
        $vals[2] = 'The CRMS has limited functionality. "Review" and "Add to Queue" (administrators only) pages are currently disabled until further notice.';
      }
    }
  }
  return \@vals;
}

# Sets the status name {normal/down/partial} and the banner message to display in CRMS header.tt.
sub SetSystemStatus
{
  my $self   = shift;
  my $status = shift;
  my $msg    = shift;

  $self->PrepareSubmitSql('DELETE FROM systemstatus');
  $msg = $self->get('dbh')->quote($msg);
  my $sql = "INSERT INTO systemstatus (status,message) VALUES ('$status',$msg)";
  $self->PrepareSubmitSql($sql);
}

# How many items for this user have outstanding questions.
sub CountUserHolds
{
  my $self = shift;
  my $user = shift;

  my $report = '';
  my $sql = "SELECT COUNT(*) FROM reviews WHERE user='$user' AND hold IS NOT NULL";
  return $self->SimpleSqlGet($sql);
}

sub WhereAmI
{
  my $self = shift;

  my $dev = $self->get('dev');
  if ($dev)
  {
    return 'Training' if $dev eq 'crmstest';
    return 'Moses Dev' if $dev eq 'moseshll';
    return 'Dev';
  }
}

sub IsTrainingArea
{
  my $self = shift;

  my $where = $self->WhereAmI();
  return ($where eq 'Training');
}

sub ResetButton
{
  my $self = shift;
  my $nuke = shift;

  return unless $self->IsTrainingArea();
  if ($nuke)
  {
    my $ref = $self->get('dbh')->selectall_arrayref('SELECT id FROM queue WHERE status<4 AND id IN (SELECT DISTINCT id FROM reviews)');
    foreach my $row ( @{$ref} )
    {
      my $id = $row->[0];
      $self->PrepareSubmitSql("DELETE FROM queue WHERE id='$id'");
      $self->PrepareSubmitSql("DELETE FROM reviews WHERE id='$id'");
    }
  }
  else
  {
    $self->PrepareSubmitSql('DELETE FROM reviews WHERE priority>0');
    $self->PrepareSubmitSql('DELETE FROM queue WHERE priority>0');
  }
  $self->PrepareSubmitSql('UPDATE queue SET status=0,pending_status=0,expcnt=0 WHERE id NOT IN (SELECT DISTINCT id FROM reviews)');
}

sub Hostname
{
  my $self = shift;

  my $host = `hostname`;
  chomp $host;
  return $host;
}

sub ReplicationDelay
{
  my $self = shift;

  my $host = $self->Hostname();
  my $sql = "SELECT seconds,DATE_SUB(time, INTERVAL seconds SECOND) FROM mysqlrep.delay WHERE client='$host'";
  my $ref = $self->get('dbh')->selectall_arrayref($sql);
  my @return = ($ref->[0]->[0],$self->FormatTime($ref->[0]->[1]));
  return @return;
}

# Places an und volume back in candidates unless it qualifies for the und table in some other way.
sub RestoreUnd
{
  my $self    = shift;
  my $id      = shift;
  my $verbose = shift;

  my $time = $self->SimpleSqlGet("SELECT time FROM und WHERE id='$id'");
  my $src = $self->SimpleSqlGet("SELECT src FROM und WHERE id='$id'");
  if ($time || $src)
  {
    my $src2 = $self->ShouldVolumeGoInUndTable($id);
    if ($src2 && $src2 ne $src)
    {
      my $sql = "UPDATE und SET src='$src',time='$time' WHERE id='$id'";
      print "$sql\n" if $verbose;
      $self->PrepareSubmitSql($sql);
    }
    else
    {
      my $sql = "REPLACE INTO candidates (id,time) VALUES ('$id','$time')";
      print "$sql\n" if $verbose;
      $self->PrepareSubmitSql($sql);
      $self->UpdateCandidatesTitle($id);
      $self->UpdateCandidatesAuthor($id);
      $self->UpdateCandidatesPubDate($id);
      $sql = "DELETE FROM und WHERE id='$id'";
      print "$sql\n" if $verbose;
      $self->PrepareSubmitSql($sql);
    }
  }
}

sub StackTrace
{
  my $self = shift;
  
  my ( $path, $line, $subr );
  my $max_depth = 30;
  my $i = 1;
  my $trace = "--- Begin stack trace ---\n";
  while ( (my @call_details = (caller($i++))) && ($i<$max_depth) )
  {
    $trace .= "$call_details[1] line $call_details[2] in function $call_details[3]\n";
  }
  return $trace . "--- End stack trace ---\n";
}

sub LinkNoteText
{
  my $self = shift;
  my $note = shift;

  if ($note =~ m/See\sall\sreviews\sfor\sSys\s#(\d+)/)
  {
    my $url = "/cgi/c/crms/crms?p=adminHistoricalReviews;stype=reviews;search1=SysID;search1value=$1";
    $note =~ s/(See\sall\sreviews\sfor\sSys\s#)(\d+)/$1<a href="$url" target="_blank">$2<\/a>/;
  }
  return $note;
}

sub InheritanceSelectionMenu
{
  my $self = shift;
  my $searchName = shift;
  my $searchVal = shift;
  my $searchOnly = shift;
  
  my @keys = ('date','src','id','sysid','prior','change','title');
  my @labs = ('Export Date','Source Volume','Volume Inheriting', 'System ID', 'Prior CRMS Review', 'Access Change', 'Title');
  if ($searchOnly)
  {
    @keys = @keys[1..3];
    @labs = @labs[1..3];
  }
  my $html = "<select title='Search Field' name='$searchName' id='$searchName'>\n";
  foreach my $i (0 .. scalar @keys - 1)
  {
    $html .= sprintf("  <option value='%s'%s>%s</option>\n", $keys[$i], ($searchVal eq $keys[$i])? ' selected="selected"':'', $labs[$i]);
  }
  $html .= "</select>\n";
  return $html;
}


sub ConvertToInheritanceSearchTerm
{
  my $self   = shift;
  my $search = shift;

  my $new_search = $search;
  $new_search = 'DATE(e.time)' if $search eq 'date';
  $new_search = 'e.id' if (!$search || $search eq 'src');
  $new_search = 's.sysid' if $search eq 'sysid';
  $new_search = 'i.id' if $search eq 'id';
  $new_search = 'i.reason!=1' if $search eq 'prior';
  $new_search = '(i.attr=1 && (e.attr="ic" || e.attr="und") || (e.attr="pd" && (i.attr=2 || i.attr=5)))' if $search eq 'change';
  $new_search = 'b.title' if $search eq 'title';
  return $new_search;
}

sub GetInheritanceRef
{
  my $self         = shift;
  my $order        = shift;
  my $dir          = shift;
  my $search1      = shift;
  my $search1Value = shift;
  my $startDate    = shift;
  my $endDate      = shift;
  my $n            = shift;
  my $pagesize     = shift;
  my $download     = shift;
  
  $n = 1 unless $n;
  #print("GetInheritanceRef('$order','$dir','$search1','$search1Value','$startDate','$endDate','$offset','$pagesize','$download');<br/>\n");
  # these are 1-based
  $pagesize = 20 unless $pagesize > 0;
  $order = 'id' unless $order;
  $search1 = $self->ConvertToInheritanceSearchTerm($search1);
  $order = $self->ConvertToInheritanceSearchTerm($order);
  my @rest = ('i.del=0');
  my $tester1 = '=';
  my $tester2 = '=';
  if ( $search1Value =~ m/.*\*.*/ )
  {
    $search1Value =~ s/\*/%/gs;
    $tester1 = ' LIKE ';
  }
  if ( $search1Value =~ m/([<>!]=?)\s*(\d+)\s*/ )
  {
    $search1Value = $2;
    $tester1 = $1;
  }
  my $doS = ($search1 eq 's.sysid' || $order eq 's.sysid')? ' LEFT JOIN system s ON s.id=e.id ':'';
  push @rest, "DATE(e.time) >= '$startDate'" if $startDate;
  push @rest, "DATE(e.time) <= '$endDate'" if $endDate;
  push @rest, "$search1 $tester1 '$search1Value'" if $search1Value;
  my $restrict = ((scalar @rest)? 'WHERE ':'') . join(' AND ', @rest);
  my $sql = 'SELECT COUNT(DISTINCT e.id),COUNT(DISTINCT i.id) FROM inherit i ' .
            'LEFT JOIN exportdata e ON i.gid=e.gid ' .
            "LEFT JOIN bibdata b ON e.id=b.id $doS $restrict";
  my $ref;
  #print "$sql<br/>\n";
  eval {
    $ref = $self->get('dbh')->selectall_arrayref($sql);
  };
  if ($@)
  {
    $self->SetError($@);
  }
  my $totalVolumes = $ref->[0]->[0];
  my $inheritingVolumes = $ref->[0]->[1];
  my $of = POSIX::ceil($totalVolumes/$pagesize);
  $n = $of if $n > $of;
  my $first = ($n-1) * $pagesize + 1;
  my $last = $first + $pagesize - 1;
  #print "$n: $first-$last<br/>\n";
  my $return = ();
  $sql = 'SELECT i.id,i.attr,i.reason,i.gid,e.id,e.attr,e.reason,b.title,DATE(e.time),i.src FROM inherit i ' .
         'LEFT JOIN exportdata e ON i.gid=e.gid ' .
         "LEFT JOIN bibdata b ON e.id=b.id $doS $restrict ORDER BY $order $dir, e.id ASC";
  #print "$sql<br/>\n";
  $ref = undef;
  eval {
    $ref = $self->get('dbh')->selectall_arrayref($sql);
  };
  if ($@)
  {
    $self->SetError($@);
  }
  my $data = join "\t", ('ID','Title','Author','Pub Date','Date Added','Status','Locked','Priority','Reviews','Expert Reviews','Holds');
  my $i = 0;
  my $j = 0;
  my @return = ();
  my $currentSource = undef;
  foreach my $row (@{$ref})
  {
    my $id2 = $row->[4] || '';
    if ($currentSource ne $id2)
    {
      $currentSource = $id2;
      $i++;
      #print "$i $currentSource<br/>\n";
    }
    $j++;
    next if $i < $first;
    last if $i > $last;
    my $id = $row->[0];
    my $sysid = $self->BarcodeToId($id);
    my $attr = $self->GetRightsName($row->[1]);
    my $reason = $self->GetReasonName($row->[2]);
    my $gid = $row->[3];
    my $attr2 = $row->[5];
    my $reason2 = $row->[6];
    my $title = $row->[7];
    my $date = $row->[8];
    my $src = $row->[9];
    $title =~ s/&/&amp;/g;
    my ($pd,$pdus,$icund) = (0,0,0);
    $pd = 1 if ($attr eq 'pd' || $attr2 eq 'pd');
    $pdus = 1 if ($attr eq 'pdus' || $attr2 eq 'pdus');
    $icund = 1 if ($attr eq 'ic' || $attr2 eq 'ic');
    $icund = 1 if ($attr eq 'und' || $attr2 eq 'und');
    my $incrms = (($attr eq 'ic' && $reason eq 'bib') || $reason eq 'gfv')? undef:1;
    my $change = (($pd == 1 && $icund == 1) || ($pd == 1 && $pdus == 1) || ($icund == 1 && $pdus == 1));
    my $summary = '';
    if ($self->IsVolumeInQueue($id))
    {
      $summary = sprintf "in queue (P%s)", $self->GetPriority($id);
      $sql = "SELECT user FROM reviews WHERE id='$id'";
      my $ref2 = $self->get('dbh')->selectall_arrayref($sql);
      my $users = join ', ', (map {$_->[0]} @{$ref2});
      $summary .= "; reviewed by $users" if $users;
      my $locked = $self->SimpleSqlGet("SELECT locked FROM queue WHERE id='$id'");
      $summary .= "; locked for $locked" if $locked;
    }
    my %dic = ('i'=>$i, 'j'=>$j,'inheriting'=>$id, 'sysid'=>$sysid, 'rights'=>"$attr/$reason",
               'newrights'=>"$attr2/$reason2", 'incrms'=>$incrms, 'change'=>$change, 'from'=>$id2,
               'title'=>$title, 'gid'=>$gid, 'date'=>$date, 'summary'=>$summary, 'src'=>ucfirst $src);
    push @return, \%dic;
    if ($download)
    {
      #$data .= sprintf("\n$id\t%s\t%s\t%s\t$date\t%s\t%s\t%s\t$reviews\t%s\t$holds",
      #                 $row->[7], $row->[8], $row->[4], $row->[2], $row->[3], $self->StripDecimal($row->[5]), $row->[6]);
    }
  }
  if (!$download)
  {
    $data = {'rows' => \@return,
             'source' => $totalVolumes,
             'inheriting' => $inheritingVolumes,
             'n' => $n,
             'of' => $of
            };
    #print "Source ($totalVolumes) Inheriting ($inheritingVolumes) Page ($n) Of ($of)<br/>\n";
  }
  return $data;
}

sub DeleteInheritance
{
  my $self = shift;
  my $id  = shift;

  return 'skip' if $self->SimpleSqlGet("SELECT COUNT(*) FROM inherit WHERE id='$id' AND del=1");
  return 'skip' unless $self->SimpleSqlGet("SELECT COUNT(*) FROM inherit WHERE id='$id'");
  $self->PrepareSubmitSql("UPDATE inherit SET del=1 WHERE id='$id'");
  return 0;
}

sub GetDeletedInheritance
{
  my $self = shift;

  my $sql = 'SELECT id FROM inherit WHERE del=1';
  return $self->get('dbh')->selectall_arrayref($sql);
}

sub SubmitInheritance
{
  my $self = shift;
  my $id   = shift;

  my $sql = "SELECT COUNT(*) FROM reviews r INNER JOIN queue q ON r.id=q.id WHERE r.id='$id' AND r.user='autocrms' AND q.status=9";
  return 'skip' if $self->SimpleSqlGet($sql);
  # Check for a submit after reviews have been processed; WARNING this should not be done in production FIXME
  $sql = "SELECT COUNT(*) FROM historicalreviews r WHERE r.id='$id' AND r.user='autocrms' AND r.status=9";
  return 'skip' if $self->SimpleSqlGet($sql);
  $sql = "SELECT e.attr,e.reason,i.attr,i.reason,i.gid FROM inherit i INNER JOIN exportdata e ON i.gid=e.gid WHERE i.id='$id'";
  my $row = $self->get('dbh')->selectall_arrayref($sql)->[0];
  my $attr = $self->GetRightsNum($row->[0]);
  my $reason = $self->GetReasonNum($row->[1]);
  my $attr2 = $self->GetRightsName($row->[2]);
  my $reason2 = $self->GetReasonName($row->[3]);
  my $gid = $row->[4];
  return sprintf("$id (GID %s) is no longer available for inheritance (has it been processed?)", ($gid)? "$gid":'unknown') unless ($attr2 && $reason2);
  my $rights = "$attr2/$reason2";
  my $category = 'Rights Inherited';
  # Returns a status code (0=Add, 1=Error) followed by optional text.
  my $res = $self->AddInheritanceToQueue($id);
  my $code = substr $res, 0, 1;
  if ($code ne '0')
  {
    return $id . ': ' . substr $res, 1, length $res;
  }
  $self->PrepareSubmitSql("DELETE FROM reviews WHERE id='$id'");
  my $sysid = $self->BarcodeToId($id);
  my $note = "See all reviews for Sys #$sysid";
  my $swiss = ($self->SimpleSqlGet("SELECT COUNT(*) FROM historicalreviews WHERE id='$id'")>0)? 1:0;
  $self->SubmitReview($id,'autocrms',$attr,$reason,$note,undef,1,undef,$category,$swiss);
  $self->PrepareSubmitSql("DELETE FROM inherit WHERE id='$id'");
  return 0;
}

# Returns a status code (0=Add, 1=Error) followed by optional text.
sub AddInheritanceToQueue
{
  my $self = shift;
  my $id   = shift;

  my $stat = 0;
  my @msgs = ();
  if ($self->IsItemInQueue($id))
  {
    my $err = $self->LockItem($id, 'autocrms');
    if ($err)
    {
      push @msgs, $err;
      $stat = 1;
    }
    else
    {
      my $sql = "SELECT COUNT(*) FROM reviews WHERE id='$id' AND user NOT LIKE 'rereport%'";
      my $count = $self->SimpleSqlGet($sql);
      if ($count)
      {
        my $rlink = sprintf "already has $count <a href='?p=adminReviews;search1=Identifier;search1value=$id' target='_blank'>review%s</a>", ($count==1)? '':'s';
        push @msgs, $rlink;
        $stat = 1;
      }
    }
    $self->UnlockItem($id, 'autocrms');
  }
  else
  {
    my $record = $self->GetMetadata($id);
    @msgs = @{ $self->GetViolations($id, $record) };
    if (scalar @msgs)
    {
      $stat = 1;
    }
    else
    {
      my $sql = "INSERT INTO queue (id, priority, source) VALUES ('$id', 0, 'inherited')";
      $self->PrepareSubmitSql($sql);
      $self->UpdateTitle($id, undef, $record);
      $self->UpdatePubDate($id, undef, $record);
      $self->UpdateAuthor ($id, undef, $record);
      $sql = "INSERT INTO $CRMSGlobals::queuerecordTable (itemcount, source) VALUES (1, 'inheritance')";
      $self->PrepareSubmitSql($sql);
    }
  }
  return $stat . join '; ', @msgs;
}

sub GetTodaysInheritanceCount
{
  my $self = shift;

  #my $sql = 'SELECT COUNT(*) FROM queue WHERE status=9 AND DATE(time)=DATE(NOW())';
  my $sql = 'SELECT COUNT(*) FROM queue WHERE status=9';
  $self->SimpleSqlGet($sql);
}

sub LinkToCatalog
{
  my $self  = shift;
  my $sysid = shift;
  
  return "http://catalog.hathitrust.org/Record/$sysid";
}

sub LinkToHistorical
{
  my $self  = shift;
  my $sysid = shift;
  
  return "/cgi/c/crms/crms?p=adminHistoricalReviews;search1=SysID;search1value=$sysid";
}

sub LinkToRetrieve
{
  my $self  = shift;
  my $sysid = shift;
  
  return "/cgi/c/crms/crms?p=retrieve;query=$sysid";
}

sub LinkToMirlynDetails
{
  my $self  = shift;
  my $sysid = shift;

  return "http://mirlyn.lib.umich.edu/Record/$sysid/Details#tabs";
}

# Populates $data (a hash ref) with information about the duplication status of an exported determination.
sub DuplicateVolumesFromExport
{
  my $self   = shift;
  my $id     = shift;
  my $gid    = shift;
  my $sysid  = shift;
  my $attr   = shift;
  my $reason = shift;
  my $data   = shift;

  my %okatrr = ('pd/ncn' => 1,
                'pd/ren' => 1,
                'pd/cdpp' => 1,
                'pdus/cdpp' => 1,
                'pd/crms' => 1,
                'pd/add' => 1,
                'ic/ren' => 1,
                'ic/cdpp' => 1,
                'ic/crms' => 1,
                'und/nfi' => 1,
                'und/crms' => 1,
                'ic/bib' => 1);
  my $rows = $self->VolumeIDsQuery($sysid);
  if (1 == scalar @{$rows})
  {
    $data->{'nodups'}->{$id} = '' unless $data->{'nodups'}->{$id};
    $data->{'nodups'}->{$id} .= "$id\t$sysid\n";
    $data->{'nodupssys'}->{$sysid} = 1;
  }
  else
  {
    # Get most recent CRMS determination for any volume on this record
    # and see if it's more recent that what we're exporting.
    my $candidate = $id;
    my $candidateTime = $self->SimpleSqlGet("SELECT MAX(time) FROM historicalreviews WHERE id='$id'");
    my $sawchron = 0;
    foreach my $line (@{$rows})
    {
      my ($id2,$chron2,$rights2) = split '__', $line;
      $sawchron = 1 if $chron2;
      next if $id eq $id2;
      my $time = $self->SimpleSqlGet("SELECT MAX(time) FROM historicalreviews WHERE id='$id2'");
      if ($time && $time gt $candidateTime)
      {
        $candidate = $id2;
        $candidateTime = $time;
      }
    }
    foreach my $line (@{$rows})
    {
      my ($id2,$chron2,$rights2) = split '__', $line;
      my ($attr2,$reason2,$src2,$usr2,$time2,$note2) = @{$self->RightsQuery($id2,1)->[0]};
      if ($sawchron)
      {
        $data->{'chron'}->{$id} = '' unless $data->{'chron'}->{$id};
        $data->{'chron'}->{$id} .= "$id2\t$sysid\n";
        $data->{'chronsys'}->{$sysid} = 1;
        delete $data->{'unneeded'}->{$id};
        delete $data->{'unneededsys'}->{$sysid};
        delete $data->{'inherit'}->{$id};
        delete $data->{'inheritsys'}->{$sysid};
        delete $data->{'disallowed'}->{$id};
        delete $data->{'disallowedsys'}->{$sysid};
        return;
      }
      elsif ($candidate ne $id && $candidate ne $id2 && $id ne $id2)
      {
        $data->{'disallowed'}->{$id} = '' unless $data->{'disallowed'}->{$id};
        $data->{'disallowed'}->{$id} .= "$id2\t$sysid\t$attr2/$reason2\t$attr/$reason\t$id\t$candidate has newer review ($candidateTime)\n";
        $data->{'disallowedsys'}->{$sysid} = 1;
        delete $data->{'unneeded'}->{$id};
        delete $data->{'unneededsys'}->{$sysid};
        delete $data->{'inherit'}->{$id};
        delete $data->{'inheritsys'}->{$sysid};
        #return;
      }
      elsif ($id2 ne $id && !$data->{'chron'}->{$id})
      {
        my $oldrights = "$attr2/$reason2";
        if ($self->SimpleSqlGet("SELECT COUNT(*) FROM reviews WHERE id='$id2' AND user NOT LIKE 'rereport%'"))
        {
          my $user = $self->SimpleSqlGet("SELECT user FROM reviews WHERE id='$id2' AND user NOT LIKE 'rereport%' LIMIT 1");
          $data->{'disallowed'}->{$id} = '' unless $data->{'disallowed'}->{$id};
          $data->{'disallowed'}->{$id} .= "$id2\t$sysid\t$attr2/$reason2\t$oldrights\t$id\tHas an active review by $user\n";
          $data->{'disallowedsys'}->{$sysid} = 1;
        }
        elsif ($okatrr{$oldrights} || ($oldrights eq 'pdus/gfv' && $attr =~ m/^pd/))
        {
          # Always inherit onto a single-review priority 1
          my $rereps = $self->SimpleSqlGet("SELECT COUNT(*) FROM reviews WHERE id='$id2' AND user LIKE 'rereport%'");
          if ($attr2 eq $attr && $reason2 ne 'bib' && $rereps == 0)
          {
            $data->{'unneeded'}->{$id} = '' unless $data->{'unneeded'}->{$id};
            $data->{'unneeded'}->{$id} .= "$id2\t$sysid\t$oldrights\t$attr/$reason\t$id\n";
            $data->{'unneededsys'}->{$sysid} = 1;
          }
          else
          {
            $data->{'inherit'}->{$id} = '' unless $data->{'inherit'}->{$id};
            $data->{'inherit'}->{$id} .= "$id2\t$sysid\t$attr2\t$reason2\t$attr\t$reason\t$gid\n";
            $data->{'inheritsys'}->{$sysid} = 1;
          }
        }
        else
        {
          $data->{'disallowed'}->{$id} = '' unless $data->{'disallowed'}->{$id};
          $data->{'disallowed'}->{$id} .= "$id2\t$sysid\t$oldrights\t$attr/$reason\t$id\tRights\n";
          $data->{'disallowedsys'}->{$sysid} = 1;
        }
      }
    }
  }
}

# Finds the most recent CRMS exported determination for a non-chron duplicate
# (if the given volume is non-chron) and adds it to inherit table.
sub CheckCandidateRightsInheritance
{
  my $self  = shift;
  my $id    = shift;
  my $sysid = shift;

  my $rows = $self->VolumeIDsQuery($sysid);
  return if 1 == scalar @{$rows};
  my $cand;
  my $ctime;
  foreach my $line (@{$rows})
  {
    my ($id2,$chron2,$rights2) = split '__', $line;
    return if $chron2;
    # Don't allow inheritance at all if this volume has chron info.
    #return if $id2 eq $id and $chron2;
    next if $id2 eq $id;
    #next if $chron2;
    my $sql = "SELECT attr,reason,gid,time FROM exportdata WHERE id='$id2' AND time>='2011-06-02 00:00:00' ORDER BY time DESC LIMIT 1";
    my $ref = $self->get('dbh')->selectall_arrayref($sql);
    foreach my $row ( @{$ref} )
    {
      my $sttr2   = $row->[0];
      my $reason2 = $row->[1];
      my $gid2    = $row->[2];
      my $time2   = $row->[3];
      $cand = $gid2 unless $cand;
      $ctime = $time2 unless $ctime;
      if ($time2 gt $ctime)
      {
        $cand = $gid2;
        $ctime = $time2;
      }
    }
  }
  if ($cand)
  {
    my $sql = "INSERT INTO inherit (id,attr,reason,gid,src) VALUES ('$id',2,1,$cand,'candidates')";
    $self->PrepareSubmitSql($sql);
  }
}

sub ExportSrcToEnglish
{
  my $self = shift;
  my $src  = shift;
  
  my %srces = ('adminui' => 'Added to Queue',
               'rereport' => 'Rereports');
  my $eng = $srces{$src};
  $eng = ucfirst $src unless $eng;
  return $eng;
}

1;
