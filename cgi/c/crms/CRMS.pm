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
use POSIX;
use DBI qw(:sql_types);
use List::Util qw(min max);
use JSON::XS;

binmode(STDOUT, ':utf8'); #prints characters in utf8

## ----------------------------------------------------------------------------
##  Function:   new() for object
##  Parameters: %hash with a bunch of args
##  Return:     ref to object
## ----------------------------------------------------------------------------
sub new
{
  my ($class, %args) = @_;
  my $self = bless {}, $class;

  my $sys = $args{'sys'};
  $sys = 'crms' unless $sys;
  my $root = $args{'root'};
  my $cfg = $root . '/bin/c/crms/' . $sys . '.cfg';
  my %d = $self->ReadConfigFile($cfg);
  if (!%d)
  {
    $sys = 'crms';
    $cfg = $root . '/bin/c/crms/' . $sys . '.cfg';
    %d = $self->ReadConfigFile($cfg);
  }
  $self->set($_,        $d{$_}) for keys %d;
  $self->set('logFile', $args{'logFile'});
  my $errors = [];
  $self->set('errors',  $errors);
  $self->set('verbose', $args{'verbose'});
  $self->set('root',    $root);
  $self->set('dev',     $args{'dev'});
  $self->set('user',    $args{'user'});
  $self->set('sys',     $sys);
  $self->SetError('Warning: configFile parameter is obsolete.') if $args{'configFile'};
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

sub Version
{
  return '4.4.1';
}

# Is this CRMS or CRMS World (or something else entirely)?
# This is the human-readable version.
sub System
{
  my $self = shift;

  return $self->GetSystemVar('system', 'CRMS');
}

# This is the NOT SO human-readable version used in sys=blah URL param
# and the -x blah script param.
sub Sys
{
  my $self = shift;

  return $self->get('sys');
}

sub ReadConfigFile
{
  my $self = shift;
  my $path = shift;
  
  my %dict = ();
  my $fh;
  unless (open $fh, '<:encoding(UTF-8)', $path)
  {
    $self->SetError('failed to read config file at $path: ' . $!);
    return undef;
  }
  read $fh, my $buff, -s $path; # one of many ways to slurp file.
  close $fh;
  my @lines = split "\n", $buff;
  foreach my $line (@lines)
  {
    $line =~ s/#.*//;
    if ($line =~ m/(\S+)\s*=\s*(\S+(\s+\S+)*)/i)
    {
      $dict{$1} = $2;
    }
  }
  return %dict;
}

## ----------------------------------------------------------------------------
##  Function:   connect to the mysql DB
##  Parameters: nothing
##  Return:     ref to DBI
## ----------------------------------------------------------------------------
sub ConnectToDb
{
  my $self = shift;

  my $db_server = $self->get('mysqlServerDev');
  my $db        = $self->get('mysqlDbName');
  my $dev       = $self->get('dev');
  my $root      = $self->get('root');
  my $sys       = $self->get('sys');

  my $cfg = $root . '/bin/c/crms/' . $sys . 'pw.cfg';
  my %d = $self->ReadConfigFile($cfg);
  my $db_user   = $d{'mysqlUser'};
  my $db_passwd = $d{'mysqlPasswd'};
  if (!$dev)
  {
    $db_server = $self->get('mysqlServer');
  }
  elsif ($dev eq 'crmstest')
  {
    $db .= 'test';
  }
  #if ($self->get('verbose')) { $self->Logit("DBI:mysql:crms:$db_server, $db_user, [passwd]"); }
  my $dbh = DBI->connect("DBI:mysql:$db:$db_server", $db_user, $db_passwd,
            { PrintError => 0, AutoCommit => 1 }) || die "Cannot connect: $DBI::errstr";
  $dbh->{mysql_enable_utf8} = 1;
  $dbh->{mysql_auto_reconnect} = 1;
  $dbh->do('SET NAMES "utf8";');
  return $dbh;
}


## ----------------------------------------------------------------------------
##  Function:   connect to the development mysql DB
##  Parameters: nothing
##  Return:     ref to DBI
## ----------------------------------------------------------------------------
sub ConnectToSdrDb
{
  my $self = shift;

  my $db_server = $self->get('mysqlMdpServerDev');
  my $db        = $self->get('mysqlMdpDbName');
  my $dev       = $self->get('dev');
  my $root      = $self->get('root');
  my $sys       = $self->get('sys');

  my $cfg = $root . '/bin/c/crms/' . $sys . 'pw.cfg';
  my %d = $self->ReadConfigFile($cfg);
  my $db_user   = $d{'mysqlMdpUser'};
  my $db_passwd = $d{'mysqlMdpPasswd'};
  if (!$dev)
  {
    $db_server = $self->get('mysqlMdpServer');
  }
  #if ($self->get('verbose')) { $self->Logit("DBI:mysql:mdp:$db_server, $db_user, [passwd]"); }
  my $sdr_dbh = DBI->connect("DBI:mysql:$db:$db_server", $db_user, $db_passwd,
            { PrintError => 0, AutoCommit => 1 });
  if ($sdr_dbh)
  {
    $sdr_dbh->{mysql_auto_reconnect} = 1;
  }
  else
  {
    my $err = $DBI::errstr;
    $self->SetError($err);
    # Number of errors reported in the last 12 hours.
    my $sql = 'SELECT COUNT(*) FROM sdrerror WHERE time > DATE_SUB(NOW(), INTERVAL 12 HOUR)';
    if (0 == $self->SimpleSqlGet($sql))
    {
      $sql = 'INSERT INTO sdrerror (error) VALUES (?)';
      $self->PrepareSubmitSql($sql, $err);
      use Mail::Sender;
      my $me = $self->GetSystemVar('adminEmail', '');
      my $sender = new Mail::Sender({ smtp => 'mail.umdl.umich.edu',
                                      from => $me,
                                      on_errors => 'undef' });
      my $ctype = 'text/plain';
      $sender->OpenMultipart({
        to => $me,
        subject => 'CRMS rights database issue',
        ctype => 'text/plain',
        encoding => 'utf-8'
        });
      $sender->Body();
      my $txt = $err;
      $txt = '' unless $txt;
      my $bytes = encode('utf8', $txt);
      $sender->SendEnc($bytes);
      $sender->Close();
    }
  }
  return $sdr_dbh;
}

# Gets cached dbh, or connects if no connection is made yet.
sub GetSdrDb
{
  my $self = shift;
  
  my $sdr_dbh = $self->get('sdr_dbh');
  my $ping = $self->get('ping');
  if (!$sdr_dbh || !(($ping)? $sdr_dbh->ping():1))
  {
    $sdr_dbh = $self->ConnectToSdrDb();
    $self->set('sdr_dbh', $sdr_dbh);
  }
  return $sdr_dbh;
}

# Gets cached dbh, or connects if no connection is made yet.
sub GetDb
{
  my $self = shift;
  
  my $dbh = $self->get('dbh');
  my $ping = $self->get('ping');
  if (!$dbh || !(($ping)? $dbh->ping():1))
  {
    $dbh = $self->ConnectToDb();
    $self->set('dbh', $dbh);
  }
  return $dbh;
}

sub PrepareSubmitSql
{
  my $self = shift;
  my $sql  = shift;

  my $dbh = $self->GetDb();
  my $sth = $dbh->prepare($sql);
  eval { $sth->execute(@_); };
  if ($@)
  {
    $self->SetError("SQL failed ($sql): " . $sth->errstr);
    return 0;
  }
  return 1;
}

sub SimpleSqlGet
{
  my $self = shift;
  my $sql  = shift;

  my $val = undef;
  my $dbh = $self->GetDb();
  eval {
    my $ref = $dbh->selectall_arrayref($sql, undef, @_);
    $val = $ref->[0]->[0];
  };
  if ($@)
  {
    my $msg = "SQL failed ($sql): " . $@;
    $self->SetError($msg);
    $self->Logit($msg);
  }
  return $val;
}

sub SimpleSqlGetSDR
{
  my $self = shift;
  my $sql  = shift;

  my $val = undef;
  my $dbh = $self->GetSdrDb();
  eval {
    my $ref = $dbh->selectall_arrayref($sql, undef, @_);
    $val = $ref->[0]->[0];
  };
  if ($@)
  {
    my $msg = "SQL failed ($sql): " . $@;
    $self->SetError($msg);
    $self->Logit($msg);
  }
  return $val;
}

sub GetCandidatesSize
{
  my $self = shift;
  my $ns   = shift;

  my $sql = 'SELECT count(*) FROM candidates';
  $sql .= " WHERE id LIKE '$ns%'" if $ns;
  return $self->SimpleSqlGet($sql);
}

sub ProcessReviews
{
  my $self    = shift;
  my $fromcgi = shift;

  # Clear the deleted inheritances, regardless of system status
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
  # Get the underlying system status, ignoring replication delays.
  my ($blah,$stat,$msg) = @{$self->GetSystemStatus(1)};
  my $reason = '';
  # Don't do this if the system is down or if it is Sunday.
  if ($stat ne 'normal')
  {
    $reason = "system status is $stat";
  }
  elsif ($self->GetSystemVar('autoinherit') eq 'disabled')
  {
    $reason = 'automatic inheritance is disabled';
  }
  elsif (!$self->WasYesterdayWorkingDay())
  {
    $reason = 'yesterday was not a working day';
  }
  if ($reason eq '')
  {
    $self->AutoSubmitInheritances($fromcgi);
  }
  else
  {
    print "Not auto-submitting inheritances because $reason.\n" unless $fromcgi;
  }
  $self->SetSystemStatus('partial', 'CRMS is processing reviews. The Review page is temporarily unavailable. Try back in about a minute.');
  my %stati = (2=>0,3=>0,4=>0,8=>0);
  my $dbh = $self->GetDb();
  my $sql = 'SELECT id FROM reviews WHERE id IN (SELECT id FROM queue WHERE status=0) GROUP BY id HAVING count(*) = 2';
  my $ref = $dbh->selectall_arrayref($sql);
  foreach my $row (@{$ref})
  {
    my $id = $row->[0];
    # Don't process anything that las a review less than 8 hours old.
    my $sql = 'SELECT COUNT(*) FROM reviews WHERE id=? AND time>DATE_SUB(NOW(), INTERVAL 8 HOUR)';
    if (0 < $self->SimpleSqlGet($sql, $id))
    {
      print "Not processing $id: it has one or more reviews less than 8 hours old\n" unless $fromcgi;
      next;
    }
    my $data = $self->CalcStatus($id, $stat);
    my $status = $data->{'status'};
    next unless $status > 0;
    my $hold = $data->{'hold'};
    if ($hold)
    {
      print "Not processing $id for $hold: it is held; system status is '$stat'\n" if $stat ne 'normal' and !$fromcgi;
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
    $self->RegisterStatus($id, $status);
    $sql = 'UPDATE reviews SET hold=NULL,sticky_hold=NULL,time=time WHERE id=?';
    $self->PrepareSubmitSql($sql, $id);
    $stati{$status}++;
  }
  $self->SetSystemStatus($stat, $msg);
  if (!$fromcgi)
  {
    my $p1 = $self->SimpleSqlGet('SELECT COUNT(*) FROM queue WHERE priority=1.0 AND status>0 AND status<9');
    if ($p1)
    {
      my $pall = $self->SimpleSqlGet('SELECT COUNT(*) FROM queue WHERE status>0 AND status<9');
      printf "P1 mix is %.1f%% ($p1/$pall)\n", 100.0 * $p1 / $pall;
    }
  }
  # FIXME: need to do a report on old locks that need to be manually cleared.
  $sql = 'INSERT INTO processstatus VALUES ()';
  $self->PrepareSubmitSql($sql);
  my ($s2,$s3,$s4,$s8) = ($stati{2},$stati{3},$stati{4},$stati{8});
  $self->PrepareSubmitSql('DELETE FROM predeterminationsbreakdown WHERE date=DATE(NOW())');
  $sql = 'INSERT INTO predeterminationsbreakdown (date,s2,s3,s4,s8) VALUES (DATE(NOW()),?,?,?,?)';
  $self->PrepareSubmitSql($sql, $s2, $s3, $s4, $s8);
}

# Determines what status a given id should be based on existing reviews and system status.
# Returns a hashref (status,attr,reason,category,note) where attr, reason, note are for status 8
# autocrms dummy reviews.
# In the case of a hold, there will be a 'hold' key pointing to the user with the hold.
sub CalcStatus
{
  my $self = shift;
  
  my $module = 'Validator_' . $self->get('sys') . '.pm';
  require $module;
  unshift @_, $self;
  return Validator::CalcStatus(@_);
}

sub CheckPendingStatus
{
  my $self = shift;
  my $id   = shift;
  
  my $sql = 'SELECT status FROM queue WHERE id=?';
  my $status = $self->SimpleSqlGet($sql, $id);
  my $pstatus = $status;
  if (!$status)
  {
    my $module = 'Validator_' . $self->get('sys') . '.pm';
    require $module;
    unshift @_, $id;
    unshift @_, $self;
    $pstatus = Validator::CalcPendingStatus(@_);
  }
  $self->RegisterPendingStatus($id, $pstatus);
}

# If fromcgi is set, don't try to create the export file, print stuff, or send mail.
sub ClearQueueAndExport
{
  my $self    = shift;
  my $fromcgi = shift;

  my $export = [];
  ## get items > 2, clear these
  my $expert = $self->GetExpertRevItems();
  my $eCount = scalar @{$expert};
  foreach my $row (@{$expert})
  {
    my $id = $row->[0];
    push(@{$export}, $id);
  }
  ## get status 8, clear these
  my $auto = $self->GetAutoResolvedItems();
  my $aCount = scalar @{$auto};
  foreach my $row (@{$auto})
  {
    my $id = $row->[0];
    push(@{$export}, $id);
  }
  ## get status 9, clear these
  my $inh = $self->GetInheritedItems();
  my $iCount = scalar @{$inh};
  foreach my $row (@{$inh})
  {
    my $id = $row->[0];
    push(@{$export}, $id);
  }
  ## get items = 2 and see if they agree
  my $double = $self->GetDoubleRevItemsInAgreement();
  my $dCount = scalar @{$double};
  foreach my $row (@{$double})
  {
    my $id = $row->[0];
    push(@{$export}, $id);
  }
  $self->ExportReviews($export, $fromcgi);
  $self->UpdateExportStats();
  $self->UpdateDeterminationsBreakdown();
  return "Exported: $dCount matching, $eCount expert-reviewed, $aCount auto-resolved, $iCount inherited rights\n";
}

sub GetDoubleRevItemsInAgreement
{
  my $self = shift;
  my $sql  = 'SELECT id FROM queue WHERE status=4';
  return $self->GetDb()->selectall_arrayref($sql);
}

sub GetExpertRevItems
{
  my $self = shift;

  my $stat = $self->GetSystemStatus(1)->[1];
  my $holdSQL = ($stat eq 'normal')? 'CURTIME()<hold':'hold IS NOT NULL';
  my $sql  = 'SELECT id FROM queue WHERE (status>=5 AND status<8) AND id NOT IN ' .
             "(SELECT id FROM reviews WHERE $holdSQL)";
  return $self->GetDb()->selectall_arrayref($sql);
}

sub GetAutoResolvedItems
{
  my $self = shift;
  my $sql  = 'SELECT id FROM queue WHERE status=8';
  return $self->GetDb()->selectall_arrayref($sql);
}

sub GetInheritedItems
{
  my $self = shift;
  my $sql  = 'SELECT id FROM queue WHERE status=9';
  return $self->GetDb()->selectall_arrayref($sql);
}

## ----------------------------------------------------------------------------
##  Function:   create a tab file of reviews to be loaded into the rights table
##              vol id | attr | reason | user | null
##              mdp.123 | ic   | ren    | crms | null
##  Parameters: $list: A reference to a list of volume ids
##              $fromcgi: Suppress printing out progress info if called from CGI
##  Return:     nothing
## ----------------------------------------------------------------------------
sub ExportReviews
{
  my $self    = shift;
  my $list    = shift;
  my $fromcgi = shift;

  if ($self->GetSystemVar('noExport'))
  {
    print ">>> noExport system variable is set; will not create export file or email.\n" unless $fromcgi;
    $fromcgi = 1;
  }
  my $module = 'Candidates_' . $self->get('sys') . '.pm';
  require $module;
  my $count = 0;
  my $user = $self->get('sys');
  my $time = $self->GetTodaysDate();
  my ($fh, $temp, $perm) = $self->GetExportFh() unless $fromcgi;
  print ">>> Exporting to $temp.\n" unless $fromcgi;
  my $start_size = $self->GetCandidatesSize();
  foreach my $id (@{$list})
  {
    my $exported = 1;
    my ($attr,$reason) = $self->GetFinalAttrReason($id);
    my $rq = $self->RightsQuery($id,1);
    my ($attr2,$reason2,$src2,$usr2,$time2,$note2) = @{$rq->[0]};
    # Do not export determination if the volume has gone out of scope,
    # or if exporting und would clobber pdus in World.
    if (!Candidates::HasCorrectRights($self, $attr2, $reason2, $attr, $reason))
    {
      # But, high-priority volumes should always be exported, even if they
      # clobber something like pd/bib.
      my $pri = $self->SimpleSqlGet('SELECT priority FROM queue WHERE id=?', $id);
      if ($pri >= 4.0)
      {
        print "Exporting priority $pri $id as $attr/$reason even though it is out of scope ($attr2/$reason2)\n" unless $fromcgi;
      }
      else
      {
        print "Not exporting $id as $attr/$reason; it is out of scope ($attr2/$reason2)\n" unless $fromcgi;
        $exported = 0;
      }
    }
    if ($exported)
    {
      print $fh "$id\t$attr\t$reason\t$user\tnull\n" unless $fromcgi;
    }
    my $src = $self->SimpleSqlGet('SELECT source FROM queue WHERE id=?', $id);
    my $sql = 'INSERT INTO  exportdata (time,id,attr,reason,user,src,exported) VALUES (?,?,?,?,?,?,?)';
    $self->PrepareSubmitSql($sql, $time, $id, $attr, $reason, $user, $src, $exported);
    my $gid = $self->SimpleSqlGet('SELECT MAX(gid) FROM exportdata WHERE id=?', $id);
    $self->MoveFromReviewsToHistoricalReviews($id, $gid);
    $self->RemoveFromQueue($id);
    $self->RemoveFromCandidates($id);
    $count++;
  }
  if (!$fromcgi)
  {
    close $fh;
    print ">>> Moving to $perm.\n";
    rename $temp, $perm;
  }
  # Update correctness/validation now that everything is in historical
  foreach my $id (@{$list})
  {
    my $sql = 'SELECT user,time,validated FROM historicalreviews WHERE id=?';
    my $ref = $self->GetDb()->selectall_arrayref($sql, undef, $id);
    foreach my $row (@{$ref})
    {
      my $user = $row->[0];
      my $time = $row->[1];
      my $val  = $row->[2];
      my $val2 = $self->IsReviewCorrect($id, $user, $time);
      if ($val != $val2)
      {
        $sql = 'UPDATE historicalreviews SET validated=? WHERE id=? AND user=? AND time=?';
        $self->PrepareSubmitSql($sql, $val2, $id, $user, $time);
      }
    }
  }
  my $sql = 'INSERT INTO exportrecord (itemcount) VALUES (?)';
  $self->PrepareSubmitSql($sql, $count);
  if (!$fromcgi)
  {
    printf "After export, removed %d volumes from candidates.\n", $start_size-$self->GetCandidatesSize();
    eval { $self->EmailReport($count, $perm); };
    $self->SetError("EmailReport() failed: $@") if $@;
  }
}

# Send email (to Greg) with rights export data.
sub EmailReport
{
  my $self    = shift;
  my $count   = shift;
  my $file    = shift;

  my $where = ($self->WhereAmI() or 'Prod');
  if ($where eq 'Prod')
  {
    my $subject = sprintf('CRMS %s: %d volumes exported to rights db', $where, $count);
    use Mail::Sender;
    my $sender = new Mail::Sender
      {smtp => 'mail.umdl.umich.edu',
       from => $self->GetSystemVar('exportEmailFrom')};
    $sender->MailFile({to => $self->GetSystemVar('exportEmailTo'),
             subject => $subject,
             msg => 'See attachment.',
             file => $file});
    $sender->Close;
  }
}

# Returns a triplet of (filehandle, temp name, permanent name)
# Filehande is to the temp file; after it is closed it needs
# to be renamed to the permanent name.
sub GetExportFh
{
  my $self = shift;
  my $date = $self->GetTodaysDate();
  $date    =~ s/:/_/g;
  $date    =~ s/ /_/g;

  my $perm = $self->get('root') . '/prep/c/crms/' . $self->get('sys') . '_' . $date . '.rights';
  my $temp = $perm . '.tmp';
  if (-f $temp) { die "file already exists: $temp\n"; }
  open (my $fh, '>', $temp) || die "failed to open exported file ($temp): $!\n";
  return ($fh, $temp, $perm);
}

sub RemoveFromQueue
{
  my $self = shift;
  my $id   = shift;

  my $sql = 'DELETE FROM queue WHERE id=?';
  $self->PrepareSubmitSql($sql, $id);
}

sub RemoveFromCandidates
{
  my $self = shift;
  my $id   = shift;

  $self->PrepareSubmitSql('DELETE FROM candidates WHERE id=?', $id);
  $self->PrepareSubmitSql('DELETE FROM und WHERE id=?', $id);
}

sub LoadNewItemsInCandidates
{
  my $self   = shift;
  my $skipnm = shift;
  my $start  = shift;
  my $end    = shift;

  $self->set('nosystem', 'nosystem');
  my $now = (defined $end)? $end : $self->GetTodaysDate();
  $start = $self->SimpleSqlGet('SELECT max(time) FROM candidatesrecord') unless $start;
  my $start_size = $self->GetCandidatesSize();
  print "Candidates size is $start_size, last load time was $start\n";
  if (!$skipnm)
  {
    my $sql = 'SELECT id FROM und WHERE src="no meta"';
    my $dbh = $self->GetDb();
    my $ref = $dbh->selectall_arrayref($sql);
    my $n = scalar @{$ref};
    if ($n)
    {
      print "Checking $n possible no-meta additions to candidates\n";
      $self->CheckAndLoadItemIntoCandidates($_->[0]) for @{$ref};
      $n = $self->SimpleSqlGet('SELECT COUNT(*) FROM und WHERE src="no meta"');
      print "Number of no-meta volumes now $n.\n";
    }
  }
  my $module = 'Candidates_' . $self->get('sys') . '.pm';
  require $module;
  my $endclause = ($end)? " AND time<='$end' ":'';
  my $sql = 'SELECT namespace,id FROM rights_current WHERE time>?' . $endclause . 'ORDER BY time ASC';
  my $dbh = $self->GetSdrDb();
  my $ref = $dbh->selectall_arrayref($sql, undef, $start);
  my $n = scalar @{$ref};
  print "Checking $n possible additions to candidates from rights DB\n";
  foreach my $row (@{$ref})
  {
    my $id = $row->[0] . '.' . $row->[1];
    $self->CheckAndLoadItemIntoCandidates($id);
  }
  my $end_size = $self->GetCandidatesSize();
  my $diff = $end_size - $start_size;
  print "After load, candidates has $end_size items. Added $diff.\n\n";
  # Record the update
  $sql = 'INSERT INTO candidatesrecord (time,addedamount) VALUES (?,?)';
  $self->PrepareSubmitSql($sql, $now, $diff);
  $self->set('nosystem', undef);
}

# Does all checks to see if a volume should be in the candidates or und tables, removing
# it from either table if it is already in one and no longer qualifies.
# If necessary, updates the system table with a new sysid.
# If noop is defined, does nothing that would actually alter the table.
# If purge is defined, does not abort if volume is already in candidates.
sub CheckAndLoadItemIntoCandidates
{
  my $self  = shift;
  my $id    = shift;
  my $noop  = shift;
  my $purge = shift;

  my $incand = $self->SimpleSqlGet('SELECT id FROM candidates WHERE id=?', $id);
  my $inund  = $self->SimpleSqlGet('SELECT src FROM und WHERE id=?', $id);
  my $inq    = $self->IsVolumeInQueue($id);
  my ($attr,$reason,$src,$usr,$time,$note) = @{$self->RightsQuery($id,1)->[0]};
  my $module = 'Candidates_' . $self->get('sys') . '.pm';
  require $module;
  my $sysid;
  my $record;
  my $oldSysid = $self->SimpleSqlGet('SELECT sysid FROM system WHERE id=?', $id);
  if (defined $oldSysid)
  {
    $record = $self->GetMetadata($id, \$sysid);
    if (defined $sysid && $sysid ne $oldSysid)
    {
      print "Update system ID on $id -- old $oldSysid, new $sysid\n";
      $self->UpdateMetadata($id, 1, $record) unless defined $noop;
    }
  }
  if (!Candidates::HasCorrectRights($self, $attr, $reason))
  {
    if (defined $incand && $reason eq 'gfv')
    {
      print "Filter $id as gfv\n";
      $self->Filter($id, 'gfv') unless defined $noop;
    }
    elsif (defined $incand && !$inq)
    {
      print "Remove $id -- (rights now $attr/$reason)\n";
      $self->RemoveFromCandidates($id) unless defined $noop;
    }
    return;
  }
  # If it was a gfv and it reverted to ic/bib, remove it from und, alert, and continue.
  if ($reason ne 'gfv' &&
      $self->SimpleSqlGet('SELECT COUNT(*) FROM und WHERE id=? AND src="gfv"', $id) > 0)
  {
    print "Unfilter $id -- reverted from pdus/gfv\n";
    $self->PrepareSubmitSql('DELETE FROM und WHERE id=?', $id) unless defined $noop;
  }
  if ($self->SimpleSqlGet('SELECT COUNT(*) FROM historicalreviews WHERE id=?', $id) > 0)
  {
    print "Skip $id -- already in historical reviews\n";
    return;
  }
  if (defined $incand && !$purge)
  {
    print "Skip $id -- already in candidates\n";
    $self->PrepareSubmitSql('DELETE FROM und WHERE id=?', $id) if defined $inund and !defined $noop;
    return;
  }
  $record = $self->GetMetadata($id, \$sysid) unless defined $record;
  if (!defined $record)
  {
    $self->ClearErrors();
    #print "No metadata yet for $id: will try again tomorrow.\n";
    $self->Filter($id, 'no meta') unless defined $noop;
    return;
  }
  my $errs = $self->GetViolations($id, $record);
  if (scalar @{$errs} == 0)
  {
    my $src = Candidates::ShouldVolumeGoInUndTable($self, $id, $record);
    if (defined $src)
    {
      if (!defined $inund || $src ne $inund)
      {
        printf "Skip $id ($src) -- %s in filtered volumes\n",
          (defined $inund)? "updating $inund->$src":'inserting';
        $self->Filter($id, $src) unless defined $noop;
      }
    }
    elsif (!defined $incand)
    {
      $self->AddItemToCandidates($id, $time, $record, $sysid, $noop);
    }
  }
  else
  {
    if ((defined $inund || defined $incand) && !$inq)
    {
      printf "Remove $id %s (%s)\n", (defined $incand)? '--':'from und', $errs->[0];
      $self->RemoveFromCandidates($id) unless defined $noop;
    }
  }
}

sub AddItemToCandidates
{
  my $self   = shift;
  my $id     = shift;
  my $time   = shift;
  my $record = shift;
  my $sysid  = shift;
  my $noop   = shift;

  $record = $self->GetMetadata($id, \$sysid) unless $record;
  return unless defined $record and defined $sysid;
  # Are there duplicates? Filter the oldest duplicates and add the newest to candidates.
  if (!$self->DoesRecordHaveChron($sysid, $record))
  {
    my $rows = $self->VolumeIDsQuery($sysid, $record);
    last if scalar @{$rows} <= 1;
    my %map;
    foreach my $line (@{$rows})
    {
      my ($id2,$chron2,$rights2) = split '__', $line;
      if ($self->IsVolumeInCandidates($id2) || $self->IsFiltered($id2))
      {
        my ($ns,$n) = split m/\./, $id2, 2;
        my $sql2 = 'SELECT time FROM rights_current WHERE namespace=? AND id=?';
        my $time2 = $self->SimpleSqlGetSDR($sql2, $ns, $n);
        $map{$id2} = $time2;
      }
    }
    my @sorted = sort {$map{$b} cmp $map{$a}} keys %map;
    $id = shift @sorted;
    $time = $map{$id};
    foreach my $id2 (@sorted)
    {
      if ($self->IsVolumeInCandidates($id2))
      {
        print "Filter $id2 as duplicate of $id\n";
        $self->Filter($id2, 'duplicate') unless defined $noop;
      }
    }
  }
  if (!$self->IsVolumeInCandidates($id))
  {
    print "Add $id to candidates\n";
    if (!defined $noop)
    {
      my $date = $self->GetRecordPubDate($id, $record);
      my $sql = 'REPLACE INTO candidates (id, time, pub_date) VALUES (?,?,?)';
      $self->PrepareSubmitSql($sql, $id, $time, $date);
      $self->PrepareSubmitSql('DELETE FROM und WHERE id=?', $id);
    }
  }
}

sub Filter
{
  my $self = shift;
  my $id   = shift;
  my $src  = shift;

  return if $src eq 'duplicate' && $self->SimpleSqlGet('SELECT COUNT(*) FROM und WHERE id=?', $id);
  $self->PrepareSubmitSql('REPLACE INTO und (id,src) VALUES (?,?)', $id, $src);
  $self->PrepareSubmitSql('DELETE FROM candidates WHERE id=?', $id);
}

sub Unfilter
{
  my $self = shift;
  my $id   = shift;

  if ($self->SimpleSqlGet('SELECT COUNT(*) FROM und WHERE id=?', $id))
  {
    $self->PrepareSubmitSql('DELETE FROM und WHERE id=?', $id);
    $self->CheckAndLoadItemIntoCandidates($id);
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
    my $module = 'Candidates_' . $self->get('sys') . '.pm';
    require $module;
    @errs = Candidates::GetViolations($self, $id, $record, $priority, $override);
  }
  return \@errs;
}

sub GetCutoffYear
{
  my $self = shift;
  my $name = shift;

  my $module = 'Candidates_' . $self->get('sys') . '.pm';
  require $module;
  return Candidates::GetCutoffYear($self, undef, $name);
}

# Returns a und table src code if the volume belongs in the und table instead of candidates.
sub ShouldVolumeGoInUndTable
{
  my $self   = shift;
  my $id     = shift;
  my $record = shift;

  $record = $self->GetMetadata($id) unless $record;
  return 'no meta' unless $record;
  my $module = 'Candidates_' . $self->get('sys') . '.pm';
  require $module;
  return Candidates::ShouldVolumeGoInUndTable($self, $id, $record);
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
  my $targetQueueSize = $self->GetSystemVar('queueSize');
  print "Before load, the queue has $queuesize volumes, $priZeroSize priority 0.\n";
  if ($needed)
  {
    $needed = $needed - $queuesize;
    return if $needed < 0;
  }
  else
  {
    $needed = max($targetQueueSize - $queuesize, 500 - $priZeroSize);
  }
  printf "Need $needed volumes (max of %d and %d).\n", $targetQueueSize - $queuesize, 500 - $priZeroSize;
  return if $needed <= 0;
  my $count = 0;
  my $min = $self->GetCutoffYear('minYear');
  my $max = $self->GetCutoffYear('maxYear');
  my $y = $min + int(rand($max - $min));
  my %dels = ();
  while (1)
  {
    my $sql = 'SELECT id,pub_date FROM candidates' .
              ' WHERE id NOT IN (SELECT DISTINCT id FROM inherit)' .
              ' AND id NOT IN (SELECT DISTINCT id FROM queue)' .
              ' AND id NOT IN (SELECT DISTINCT id FROM reviews)' .
              ' ORDER BY pub_date ASC, time DESC';
    my $ref = $self->GetDb()->selectall_arrayref($sql);
    # This can happen in the testsuite.
    last unless scalar @{$ref};
    my $oldcount = $count;
    foreach my $row (@{$ref})
    {
      my $id = $row->[0];
      next if $dels{$id};
      next if 0 < $self->SimpleSqlGet('SELECT COUNT(*) FROM historicalreviews WHERE id=?', $id);
      my $pub_date = $row->[1];
      next if $pub_date ne "$y-01-01";
      my $sysid;
      my $record = $self->GetMetadata($id, \$sysid);
      if (!$record)
      {
        print "Filtering $id: can't get metadata for queue\n";
        $self->Filter($id, 'no meta');
        next;
      }
      $pub_date = $self->GetRecordPubDate($id, $record);
      my @errs = @{ $self->GetViolations($id, $record) };
      if (scalar @errs)
      {
        printf "Will delete $id: %s\n", join '; ', @errs;
        $dels{$id} = 1;
        next;
      }
      my $dup = $self->IsRecordInQueue($sysid, $record);
      if ($dup && !$self->DoesRecordHaveChron($sysid, $record))
      {
        print "Filtering $id: queue has $dup on $sysid (no chron/enum)\n";
        $self->Filter($id, 'duplicate');
        next;
      }
      if ($self->AddItemToQueue($id, $record))
      {
        printf "Added to queue: $id published %s\n", substr($pub_date, 0, 4);
        $count++;
        last if $count >= $needed;
        $y++;
        $y = $min if $y > $max;
      }
    }
    if ($oldcount == $count)
    {
      $y++;
      $y = $min if $y > $max;
    }
    last if $count >= $needed;
  }
  $self->RemoveFromCandidates($_) for keys %dels;
  #Record the update to the queue
  my $sql = 'INSERT INTO queuerecord (itemcount,source) VALUES (?,"RIGHTSDB")';
  $self->PrepareSubmitSql($sql, $count);
}

sub IsRecordInQueue
{
  my $self   = shift;
  my $sysid  = shift;
  my $record = shift;

  my $rows = $self->VolumeIDsQuery($sysid, $record);
  foreach my $line (@{$rows})
  {
    my ($id,$chron,$rights) = split '__', $line;
    return $id if $self->SimpleSqlGet('SELECT COUNT(*) FROM queue WHERE id=?', $id);
  }
  return undef;
}

sub DoesRecordHaveChron
{
  my $self   = shift;
  my $sysid  = shift;
  my $record = shift;
  
  my $rows = $self->VolumeIDsQuery($sysid, $record);
  foreach my $line (@{$rows})
  {
    my ($id,$chron,$rights) = split '__', $line;
    return 1 if $chron;
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
  my $record   = shift;

  return 0 if $self->IsVolumeInQueue($id);
  # queue table has priority and status default to 0, time to current timestamp.
  $self->PrepareSubmitSql('INSERT INTO queue (id) VALUES (?)', $id);
  $self->UpdateMetadata($id, 1, $record);
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
  my $user     = shift;

  $user = $self->get('user') unless $user;
  $id = lc $id;
  $src = 'adminui' unless $src;
  my $stat = 0;
  my @msgs = ();
  my $admin = $self->IsUserAdmin($user);
  $override = 1 if $priority == 4;
  if ($priority == 4 && !$admin)
  {
    push @msgs, 'Only an admin can set priority 4';
    $stat = 1;
  }
  ## give the existing item higher or lower priority
  elsif ($self->IsVolumeInQueue($id))
  {
    my $sql = 'SELECT COUNT(*) FROM reviews WHERE id=?';
    my $n = $self->SimpleSqlGet($sql, $id);
    my $oldpri = $self->GetPriority($id);
    if ($oldpri == $priority)
    {
      push @msgs, 'already in queue with the same priority';
      $stat = 2;
    }
    elsif ($oldpri > $priority && !$admin)
    {
      push @msgs, 'already in queue with a higher priority';
      $stat = 2;
    }
    else
    {
      $sql = 'UPDATE queue SET priority=?, time=NOW() WHERE id=?';
      $self->PrepareSubmitSql($sql, $priority, $id);
      push @msgs, "changed priority from $oldpri to $priority";
      if ($n)
      {
        $sql = 'UPDATE reviews SET priority=?, time=time WHERE id=?';
        $self->PrepareSubmitSql($sql, $priority, $id);
      }
      $stat = 3;
    }
    if ($n)
    {
      my $rlink = sprintf("already has $n <a href='?p=adminReviews;search1=Identifier;search1value=$id' target='_blank'>%s</a>",
                          $self->Pluralize('review', $n));
      push @msgs, $rlink;
    }
  }
  else
  {
    my $record = $self->GetMetadata($id);
    @msgs = @{ $self->GetViolations($id, $record, $priority, $override) };
    if (scalar @msgs && !$override)
    {
      $stat = 1;
    }
    else
    {
      my $sql = 'INSERT INTO queue (id,priority,source) VALUES (?,?,?)';
      $self->PrepareSubmitSql($sql, $id, $priority, $src);
      $self->UpdateMetadata($id, 1, $record);
      $sql = 'INSERT INTO queuerecord (itemcount,source) VALUES (1,?)';
      $self->PrepareSubmitSql($sql, $src);
    }
  }
  if ($user && ($stat == 0 || $stat == 3))
  {
    my $sql = 'UPDATE queue SET added_by=? WHERE id=?';
    $self->PrepareSubmitSql($sql, $user, $id);
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
  my $sql = 'SELECT COUNT(*) FROM queue WHERE id=?';
  my $count = $self->SimpleSqlGet($sql, $id);
  if ($count == 1)
  {
    $sql = 'UPDATE queue SET priority=1 WHERE id=?';
    $self->PrepareSubmitSql($sql, $id);
  }
  else
  {
    $sql = 'INSERT INTO queue (id,time,status,priority,source) VALUES (?,?,?,?,?)';
    $self->PrepareSubmitSql($sql, $id, $time, $status, $priority, $source);
    $self->UpdateMetadata($id, 1, $record);
    # Accumulate counts for items added at the 'same time'.
    # Otherwise queuerecord will have a zillion kabillion single-item entries when importing
    # e.g. 2007 reviews for reprocessing.
    # We see if there is another ADMINSCRIPT entry for the current time; if so increment.
    # If not, add a new one.
    $sql = 'SELECT itemcount FROM queuerecord WHERE time=? AND source="ADMINSCRIPT" LIMIT 1';
    my $itemcount = $self->SimpleSqlGet($sql, $time);
    if ($itemcount)
    {
      $itemcount++;
      $sql = 'UPDATE queuerecord SET itemcount=? WHERE time=? AND source="ADMINSCRIPT"';
    }
    else
    {
      $itemcount = 1;
      $sql = 'INSERT INTO queuerecord (itemcount,time,source) values (?,?,"ADMINSCRIPT")';
    }
    $self->PrepareSubmitSql($sql, $itemcount, $time);
  }
  return 1;
}

# Valid for DB reviews/historicalreviews
sub IsValidCategory
{
  my $self = shift;
  my $cat = shift;

  my $sql = 'SELECT name FROM categories';
  my $rows = $self->GetDb()->selectall_arrayref($sql);
  foreach my $row (@{$rows})
  {
    return 1 if $row->[0] eq $cat;
  }
  return 0;
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
    my $sql = 'SELECT attr,reason,renNum,renDate FROM reviews WHERE id=?';
    my $rows = $self->GetDb()->selectall_arrayref($sql, undef, $id);
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

sub SubmitReview
{
  my $self = shift;
  my ($id, $user, $attr, $reason, $note, $renNum, $exp, $renDate, $category, $swiss, $hold) = @_;

  if (!$self->IsVolumeInQueue($id))                    { $self->SetError("$id is not in the queue");       return 0; }
  if (!$self->CheckReviewer($user, $exp))              { $self->SetError("reviewer ($user) check failed"); return 0; }
  # ValidateAttrReasonCombo sets error internally on fail.
  if (!$self->ValidateAttrReasonCombo($attr, $reason)) { return 0; }
  #remove any blanks from renNum
  $renNum =~ s/\s+//gs;
  # Javascript code inserts the string 'searching...' into the review text box.
  # This in once case got submitted as the renDate in production
  $renDate = '' if $renDate =~ m/searching.*/i;
  my $priority = $self->GetPriority($id);
  my @fields = qw(id user attr reason note renNum renDate category priority);
  my @values = ($id, $user, $attr, $reason, $note, $renNum, $renDate, $category, $priority);
  if ($hold)
  {
    $hold = $self->HoldExpiry($id, $user, 0);
    my $note = "hold from $user on $id";
    $self->PrepareSubmitSql('INSERT INTO note (note) VALUES (?)', $note);
    push(@fields, 'hold');
    push(@values, $hold);
  }
  else
  {
    # Stash their hold if they are cancelling it
    my $sql = 'SELECT hold FROM reviews WHERE id=? AND user=?';
    my $oldhold = $self->SimpleSqlGet($sql, $id, $user);
    if ($oldhold)
    {
      push(@fields, 'sticky_hold');
      push(@values, $oldhold);
    }
  }
  my $sql = 'SELECT duration FROM reviews WHERE user=? AND id=?';
  my $dur = $self->SimpleSqlGet($sql, $user, $id);
  if ($dur)
  {
    push(@fields, 'duration');
    push(@values, $dur);
  }
  if ($exp)
  {
    $swiss = ($swiss)? 1:0;
    push(@fields, 'expert');
    push(@values, 1);
    push(@fields, 'swiss');
    push(@values, $swiss);
  }
  my $wcs = $self->WildcardList(scalar @values);
  $sql = 'REPLACE INTO reviews (' . join(',', @fields) . ') VALUES ' . $wcs;
  my $result = $self->PrepareSubmitSql($sql, @values);
  if ($result)
  {
    if ($exp)
    {
      $sql = 'SELECT COUNT(*) FROM reviews WHERE id=? AND expert=1';
      my $expcnt = $self->SimpleSqlGet($sql, $id);
      $sql = 'UPDATE queue SET expcnt=? WHERE id=?';
      $result = $self->PrepareSubmitSql($sql, $expcnt, $id);
      my $status = $self->GetStatusForExpertReview($id, $user, $attr, $reason, $category, $renNum, $renDate);
      #We have decided to register the expert decision right away.
      $self->RegisterStatus($id, $status);
      # Clear all non-expert holds
      $sql = 'UPDATE reviews SET hold=NULL,sticky_hold=NULL,time=time WHERE id=? AND expert!=1';
      $self->PrepareSubmitSql($sql, $id);
    }
    $self->CheckPendingStatus($id);
    $self->EndTimer($id, $user);
    $self->UnlockItem($id, $user);
  }
  return $result;
}

# Returns a parenthesized comma separated list of n question marks.
sub WildcardList
{
  my $self = shift;
  my $n    = shift;

  my $qs = '(' . ('?,' x ($n-1)) . '?)';
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
  my $sql = 'SELECT attr,reason,renNum,renDate FROM reviews WHERE id=?' .
            ' AND user IN (SELECT id FROM users WHERE expert=0 AND advanced=0)';
  my $ref = $self->GetDb()->selectall_arrayref($sql, undef, $id);
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

  my $pri = $self->SimpleSqlGet('SELECT priority FROM queue WHERE id=?', $id);
  $pri = $self->StripDecimal($pri) if defined $pri;
  return $pri;
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
  $attr = $self->TranslateAttr($attr);
  if (!$attr) { $self->SetError("bad attr: $attr"); return 0; }
  $reason = $self->TranslateReason($reason);
  if (!$reason) { $self->SetError("bad reason: $reason"); return 0; }
  if (!$self->ValidateAttrReasonCombo($attr, $reason)) { $self->SetError("bad attr/reason $attr/$reason"); return 0; }
  if (!$self->CheckReviewer($user, 0))                 { $self->SetError("reviewer ($user) check failed"); return 0; }
  if (!$noop)
  {
    ## all good, INSERT
    my $sql = 'REPLACE INTO reviews (id,user,time,attr,reason,legacy,priority)' .
              ' VALUES(?,?,?,?,?,1,1)';
    $self->PrepareSubmitSql($sql, $id, $user, $date, $attr, $reason);
    $sql = 'UPDATE queue SET pending_status=1 WHERE id=?';
    $self->PrepareSubmitSql($sql, $id);
    #Now load this info into the bibdata table.
    $self->UpdateMetadata($id, 1);
  }
  return 1;
}

sub MoveFromReviewsToHistoricalReviews
{
  my $self = shift;
  my $id   = shift;
  my $gid  = shift;

  my $status = $self->GetStatus($id);
  my $sql = 'INSERT INTO historicalreviews (id,time,user,attr,reason,note,' .
            'renNum,expert,duration,legacy,renDate,category,priority,swiss,status,gid)' .
            ' SELECT id,time,user,attr,reason,note,renNum,expert,duration,legacy,' .
            'renDate,category,priority,swiss,?,? FROM reviews WHERE id=?';
  $self->PrepareSubmitSql($sql, $status, $gid, $id);
  $sql = 'DELETE FROM reviews WHERE id=?';
  $self->PrepareSubmitSql($sql, $id);
}

sub GetFinalAttrReason
{
  my $self = shift;
  my $id   = shift;

  ## order by expert so that if there is an expert review, return that one
  my $sql = 'SELECT attr,reason FROM reviews WHERE id=? ORDER BY expert DESC, time DESC LIMIT 1';
  my $ref = $self->GetDb()->selectall_arrayref($sql, undef, $id);
  if (!$ref->[0]->[0])
  {
    $self->SetError("$id not found in review table");
  }
  my $attr   = $self->TranslateAttr($ref->[0]->[0]);
  my $reason = $self->TranslateReason($ref->[0]->[1]);
  return ($attr, $reason);
}

sub RegisterStatus
{
  my $self   = shift;
  my $id     = shift;
  my $status = shift;

  my $sql = 'UPDATE queue SET status=? WHERE id=?';
  $self->PrepareSubmitSql($sql, $status, $id);
}

sub RegisterPendingStatus
{
  my $self   = shift;
  my $id     = shift;
  my $status = shift;

  my $sql = 'UPDATE queue SET pending_status=? WHERE id=?';
  $self->PrepareSubmitSql($sql, $status, $id);
}

sub GetYesterday
{
  my $self = shift;

  my $yd = $self->SimpleSqlGet('SELECT DATE_SUB(NOW(), INTERVAL 1 DAY)');
  return substr($yd, 0, 10);
}

sub HoldForItem
{
  my $self = shift;
  my $id   = shift;
  my $user = shift;

  return $self->SimpleSqlGet('SELECT hold FROM reviews WHERE id=? AND user=?', $id, $user);
}

sub StickyHoldForItem
{
  my $self = shift;
  my $id   = shift;
  my $user = shift;

  return $self->SimpleSqlGet('SELECT sticky_hold FROM reviews WHERE id=? AND user=?', $id, $user);
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
  use UMCalendar;
  my $self = shift;
  my $time = shift;
  
  $time = $self->GetTodaysDate() unless $time;
  my $cal = Date::Calendar->new($UMCalendar::UMCal);
  my @parts = split '-', substr($time, 0, 10);
  my $date = $cal->add_delta_workdays($parts[0],$parts[1],$parts[2],2);
  $date = sprintf '%s-%s-%s 23:59:59', substr($date,0,4), substr($date,4,2), substr($date,6,2);
  return $date;
}

sub WasYesterdayWorkingDay
{
  my $self = shift;
  my $time = shift;

  $time = $self->GetTodaysDate() unless $time;
  my @parts = split '-', substr($time, 0, 10);
  #printf "Add_Delta_Days(%s,%s,%s,-2)\n", $parts[0],$parts[1],$parts[2];
  my ($y,$m,$d) = Date::Calc::Add_Delta_Days($parts[0],$parts[1],$parts[2],-1);
  return $self->IsWorkingDay("$y-$m-$d");
}

# Today is a working day if today is one working day from yesterday
sub IsWorkingDay
{
  use UMCalendar;
  my $self = shift;
  my $time = shift;

  $time = $self->GetTodaysDate() unless $time;
  my $cal = Date::Calendar->new($UMCalendar::UMCal);
  my @parts = split '-', substr($time, 0, 10);
  my $is = ($cal->is_full($parts[0],$parts[1],$parts[2]))? 0:1;
  #printf "is_work(%s,%s,%s) -> %d\n", $parts[0],$parts[1],$parts[2], $is;
  return $is;
}

sub FormatDate
{
  my $self = shift;
  my $date = shift;
  
  my $sql = 'SELECT DATE_FORMAT(?, "%a, %M %e, %Y")';
  return $self->SimpleSqlGet($sql, $date);
}

sub FormatTime
{
  my $self = shift;
  my $time = shift;
  
  my $sql = 'SELECT DATE_FORMAT(?, "%a, %M %e, %Y at %l:%i %p")';
  return $self->SimpleSqlGet($sql, $time);
}

sub ConvertToSearchTerm
{
  my $self           = shift;
  my $search         = shift;
  my $page           = shift;

  my $new_search = $search;
  if (!$search || $search eq 'Identifier')
  {
    $new_search = ($page eq 'queue')? 'q.id':'r.id';
  }
  if ($search eq 'Time')
  {
    $new_search = ($page eq 'queue')? 'q.time':'r.time';
  }
  elsif ($search eq 'UserId') { $new_search = 'r.user'; }
  elsif ($search eq 'Status')
  {
    if ($page eq 'adminHistoricalReviews') { $new_search = 'r.status'; }
    else { $new_search = 'q.status'; }
  }
  elsif ($search eq 'Attribute') { $new_search = 'r.attr'; }
  elsif ($search eq 'Reason') { $new_search = 'r.reason'; }
  elsif ($search eq 'NoteCategory') { $new_search = 'r.category'; }
  elsif ($search eq 'Note') { $new_search = 'r.note'; }
  elsif ($search eq 'Legacy') { $new_search = 'r.legacy'; }
  elsif ($search eq 'Title') { $new_search = 'b.title'; }
  elsif ($search eq 'Author') { $new_search = 'b.author'; }
  elsif ($search eq 'Priority')
  {
    if ($page eq 'queue') { $new_search = 'q.priority'; }
    else { $new_search = 'r.priority'; }
  }
  elsif ($search eq 'Validated') { $new_search = 'r.validated'; }
  elsif ($search eq 'PubDate') { $new_search = 'b.pub_date'; }
  elsif ($search eq 'ReviewDate') { $new_search = 'r.time'; }
  elsif ($search eq 'Locked') { $new_search = 'q.locked'; }
  elsif ($search eq 'ExpertCount') { $new_search = 'q.expcnt'; }
  elsif ($search eq 'Reviews')
  {
    $new_search = '(SELECT COUNT(*) FROM reviews r WHERE r.id=q.id)';
  }
  elsif ($search eq 'Swiss') { $new_search = 'r.swiss'; }
  elsif ($search eq 'Hold Thru') { $new_search = 'r.hold'; }
  elsif ($search eq 'SysID') { $new_search = 's.sysid'; }
  elsif ($search eq 'Holds')
  {
    $new_search = '(SELECT COUNT(*) FROM reviews r WHERE r.id=q.id AND r.hold IS NOT NULL)';
  }
  elsif ($search eq 'Source') { $new_search = 'r.src'; }
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

  $order = $self->ConvertToSearchTerm($order, $page);
  $search1 = $self->ConvertToSearchTerm($search1, $page);
  $search2 = $self->ConvertToSearchTerm($search2, $page);
  $search3 = $self->ConvertToSearchTerm($search3, $page);
  $dir = 'DESC' unless $dir;
  $offset = 0 unless $offset;
  $pagesize = 20 unless $pagesize > 0;
  my $sql = 'SELECT r.id,r.time,r.duration,r.user,r.attr,r.reason,r.note,r.renNum,r.expert,r.category,r.legacy,r.renDate,r.priority,r.swiss,';
  if ($page eq 'adminReviews')
  {
    $sql .= 'q.status,b.title,b.author,DATE(r.hold) FROM reviews r, queue q, bibdata b WHERE q.id=r.id AND q.id=b.id';
  }
  elsif ($page eq 'holds')
  {
    my $user = $self->get('user');
    $sql .= 'q.status,b.title,b.author,DATE(r.hold) FROM reviews r, queue q, bibdata b WHERE q.id=r.id AND q.id=b.id';
    $sql .= " AND r.user='$user' AND r.hold IS NOT NULL";
  }
  elsif ($page eq 'adminHolds')
  {
    $sql .= 'q.status,b.title,b.author,DATE(r.hold) FROM reviews r, queue q, bibdata b WHERE q.id=r.id AND q.id=b.id';
    $sql .= " AND r.hold IS NOT NULL";
  }
  elsif ($page eq 'expert')
  {
    $sql .= 'q.status,b.title,b.author,DATE(r.hold) FROM reviews r, queue q, bibdata b WHERE q.id=r.id AND q.id=b.id';
    $sql .= ' AND q.status=2';
  }
  elsif ($page eq 'adminHistoricalReviews')
  {
    my $doS = 'LEFT JOIN system s ON r.id=s.id';
    $doS = '' unless ($search1 . $search2 . $search3 . $order) =~ m/sysid/;
    my $doB = 'LEFT JOIN bibdata b ON r.id=b.id';
    $doB = '' unless ($search1 . $search2 . $search3 . $order) =~ m/b\./;
    $sql .= "r.status,r.validated FROM historicalreviews r $doB $doS WHERE r.id IS NOT NULL";
  }
  elsif ($page eq 'undReviews')
  {
    $sql .= 'q.status,b.title,b.author,DATE(r.hold) FROM reviews r, queue q, bibdata b WHERE q.id=r.id AND q.id=b.id';
    $sql .= ' AND q.status=3';
  }
  elsif ($page eq 'userReviews')
  {
    my $user = $self->get('user');
    $sql = 'SELECT r.id, r.time, r.duration, r.user, r.attr, r.reason, r.note, r.renNum, r.expert, ' .
           'r.category, r.legacy, r.renDate, r.priority, r.swiss, q.status, b.title, b.author ' .
           "FROM reviews r, queue q, bibdata b WHERE q.id=r.id AND q.id=b.id AND r.user='$user' AND q.status>0";
  }
  elsif ($page eq 'editReviews')
  {
    my $user = $self->get('user');
    my $today = $self->SimpleSqlGet('SELECT DATE(NOW())') . ' 00:00:00';
    # Experts need to see stuff with any status; non-expert should only see stuff that hasn't been processed yet.
    my $restrict = ($self->IsUserExpert($user))? '':'AND q.status=0';
    $sql .= 'q.status, b.title, b.author, DATE(r.hold) FROM reviews r, queue q, bibdata b WHERE q.id=r.id AND q.id=b.id ' .
            "AND r.user='$user' AND (r.time>='$today' OR r.hold IS NOT NULL) $restrict";
  }
  my $terms = $self->SearchTermsToSQL($search1, $search1value, $op1, $search2, $search2value, $op2, $search3, $search3value);
  $sql .= " AND $terms" if $terms;
  my $which = ($page eq 'holds')? 'r.hold':'r.time';
  if ($startDate) { $sql .= " AND $which >='$startDate 00:00:00' "; }
  if ($endDate) { $sql .= " AND $which <='$endDate 23:59:59' "; }
  my $limit = ($download)? '':"LIMIT $offset, $pagesize";
  $sql .= " ORDER BY $order $dir $limit ";
  #print "$sql<br/>\n";
  my $countSql = $sql;
  $countSql =~ s/(SELECT\s+).+?(FROM.+)/$1 COUNT(r.id),COUNT(DISTINCT r.id) $2/i;
  $countSql =~ s/(LIMIT\s\d+(,\s*\d+)?)//;
  my $ref = $self->GetDb()->selectall_arrayref($countSql);
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
  $search1 = $self->ConvertToSearchTerm($search1, $page);
  $search2 = $self->ConvertToSearchTerm($search2, $page);
  $search3 = $self->ConvertToSearchTerm($search3, $page);
  $order = $self->ConvertToSearchTerm($order, $page);
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
  elsif ($page eq 'editReviews')
  {
    my $user = $self->get('user');
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
  $sql = "SELECT foo.id FROM (SELECT r.id as id, $order2($order) AS ord FROM $table r LEFT JOIN bibdata b ON r.id=b.id" .
         " $doQ $doS $restrict GROUP BY r.id) AS foo ORDER BY ord $dir $limit";
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
  $search1 = $self->ConvertToSearchTerm($search1, $page);
  $search2 = $self->ConvertToSearchTerm($search2, $page);
  $search3 = $self->ConvertToSearchTerm($search3, $page);
  $order = $self->ConvertToSearchTerm($order, $page);
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
  elsif ($page eq 'editReviews')
  {
    my $user = $self->get('user');
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
  my $dbh = $self->GetDb();
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
  $search1 = "YEAR($search1)" if $search1 eq 'b.pub_date';
  $search2 = "YEAR($search2)" if $search2 eq 'b.pub_date';
  $search3 = "YEAR($search3)" if $search3 eq 'b.pub_date';
  $search1value = $self->TranslateAttr($search1value) if $search1 eq 'r.attr';
  $search2value = $self->TranslateAttr($search2value) if $search2 eq 'r.attr';
  $search3value = $self->TranslateAttr($search3value) if $search3 eq 'r.attr';
  $search1value = $self->TranslateReason($search1value) if $search1 eq 'r.reason';
  $search2value = $self->TranslateReason($search2value) if $search2 eq 'r.reason';
  $search3value = $self->TranslateReason($search3value) if $search3 eq 'r.reason';
  $search1value = $dbh->quote($search1value) if length $search1value;
  $search2value = $dbh->quote($search2value) if length $search2value;
  $search3value = $dbh->quote($search3value) if length $search3value;

  if ($search1value =~ m/.*\*.*/)
  {
    $search1value =~ s/\*/_____/gs;
    $search1term = "$search1 LIKE $search1value";
  }
  elsif (length $search1value)
  {
    $search1term = "$search1 = $search1value";
  }
  if ($search2value =~ m/.*\*.*/)
  {
    $search2value =~ s/\*/_____/gs;
    $search2term = sprintf("$search2 %sLIKE $search2value", ($op1 eq 'NOT')? 'NOT ':'');
  }
  elsif (length $search2value)
  {
    $search2term = sprintf("$search2 %s= $search2value", ($op1 eq 'NOT')? '!':'');
  }

  if ($search3value =~ m/.*\*.*/)
  {
    $search3value =~ s/\*/_____/gs;
    $search3term = sprintf("$search3 %sLIKE $search3value", ($op2 eq 'NOT')? 'NOT ':'');
  }
  elsif (length $search3value)
  {
    $search3term = sprintf("$search3 %s= $search3value", ($op2 eq 'NOT')? '!':'');
  }

  if ($search1value =~ m/([<>]=?)\s*(\d+)\s*/)
  {
    $search1term = "$search1 $1 $2";
  }
  if ($search2value =~ m/([<>]=?)\s*(\d+)\s*/)
  {
    my $op = $1;
    $op =~ y/<>/></ if $op1 eq 'NOT';
    $search2term = "$search2 $op $2";
  }
  if ($search3value =~ m/([<>]=?)\s*(\d+)\s*/)
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
  my $dbh = $self->GetDb();
  my ($search1, $search1value, $op1, $search2, $search2value, $op2, $search3, $search3value, $table) = @_;
  $op1 = 'AND' unless $op1;
  $op2 = 'AND' unless $op2;
  $search1value = $self->TranslateAttr($search1value) if $search1 eq 'r.attr';
  $search2value = $self->TranslateAttr($search2value) if $search2 eq 'r.attr';
  $search3value = $self->TranslateAttr($search3value) if $search3 eq 'r.attr';
  $search1value = $self->TranslateReason($search1value) if $search1 eq 'r.reason';
  $search2value = $self->TranslateReason($search2value) if $search2 eq 'r.reason';
  $search3value = $self->TranslateReason($search3value) if $search3 eq 'r.reason';
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
  $search1 = "YEAR($search1)" if $search1 eq 'b.pub_date';
  $search1 = "YEAR($search2)" if $search2 eq 'b.pub_date';
  $search1 = "YEAR($search3)" if $search3 eq 'b.pub_date';
  $search1value = $dbh->quote($search1value) if length $search1value;
  $search2value = $dbh->quote($search2value) if length $search2value;
  $search3value = $dbh->quote($search3value) if length $search3value;
  if ($search1value =~ m/.*\*.*/)
  {
    $search1value =~ s/\*/_____/gs;
    $search1term = "$search1 LIKE $search1value";
    $search1term =~ s/_____/%/g;
  }
  elsif (length $search1value)
  {
    $search1term = "$search1 = $search1value";
  }
  if ($search2value =~ m/.*\*.*/)
  {
    $search2value =~ s/\*/_____/gs;
    $search2term = sprintf("$search2 %sLIKE $search2value", ($op1 eq 'NOT')? 'NOT ':'');
    $search2term =~ s/_____/%/g;
  }
  elsif (length $search2value)
  {
    $search2term = sprintf("$search2 %s= $search2value", ($op1 eq 'NOT')? '!':'');
  }
  if ($search3value =~ m/.*\*.*/)
  {
    $search3value =~ s/\*/_____/gs;
    $search3term = sprintf("$search3 %sLIKE $search3value", ($op2 eq 'NOT')? 'NOT ':'');
    $search3term =~ s/_____/%/g;
  }
  elsif (length $search3value)
  {
    $search3term = sprintf("$search3 %s= $search3value", ($op2 eq 'NOT')? '!':'');
  }
  if ($search1value =~ m/([<>]=?)\s*(\d+)\s*/)
  {
    $search1term = "$search1 $1 $2";
  }
  if ($search2value =~ m/([<>]=?)\s*(\d+)\s*/)
  {
    my $op = $1;
    $op =~ y/<>/></ if $op1 eq 'NOT';
    $search2term = "$search2 $op $2";
  }
  if ($search3value =~ m/([<>]=?)\s*(\d+)\s*/)
  {
    my $op = $1;
    $op =~ y/<>/></ if $op2 eq 'NOT';
    $search3term = "$search3 $op $2";
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
  my $table = 'reviews';
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
  my ($sql,$totalReviews,$totalVolumes,$n,$of) = $self->CreateSQL($stype, $page, $order, $dir, $search1,
                                                                  $search1value, $op1, $search2, $search2value,
                                                                  $op2, $search3, $search3value, $startDate,
                                                                  $endDate, 0, 0, 1);
  my $ref = $self->GetDb()->selectall_arrayref($sql);
  my $buff = '';
  if (scalar @{$ref} == 0)
  {
    $buff = 'No Results Found.';
  }
  else
  {
    if ($page eq 'userReviews')
    {
      $buff .= qq{id\ttitle\tauthor\ttime\tattr\treason\tcategory\tnote};
    }
    elsif ($page eq 'editReviews')
    {
      $buff .= qq{id\ttitle\tauthor\ttime\tattr\treason\tcategory\tnote};
    }
    elsif ($page eq 'undReviews')
    {
      $buff .= qq{id\ttitle\tauthor\ttime\tstatus\tuser\tattr\treason\tcategory\tnote}
    }
    elsif ($page eq 'expert')
    {
      $buff .= qq{id\ttitle\tauthor\ttime\tstatus\tuser\tattr\treason\tcategory\tnote};
    }
    elsif ($page eq 'adminReviews' || $page eq 'adminHolds')
    {
      $buff .= qq{id\ttitle\tauthor\ttime\tstatus\tuser\tattr\treason\tcategory\tnote\tswiss\thold thru};
    }
    elsif ($page eq 'adminHistoricalReviews')
    {
      $buff .= qq{id\tsystem id\ttitle\tauthor\tpub date\ttime\tstatus\tlegacy\tuser\tattr\treason\tcategory\tnote\tvalidated\tswiss};
    }
    $buff .= sprintf("%s\n", ($self->IsUserAdmin())? "\tpriority":'');
    if ($stype eq 'reviews')
    {
      $buff .= $self->UnpackResults($page, $ref);
    }
    else
    {
      $order = 'Identifier' if $order eq 'SysID';
      $order = $self->ConvertToSearchTerm($order);
      foreach my $row (@{$ref})
      {
        my $id = $row->[0];
        my $qrest = ($page ne 'adminHistoricalReviews')? ' AND r.id=q.id':'';
        $sql = 'SELECT r.id,r.time,r.duration,r.user,r.attr,r.reason,r.note,r.renNum,r.expert,' .
               "r.category,r.legacy,r.renDate,r.priority,r.swiss,$status," .
               (($page eq 'adminHistoricalReviews')?
                 'r.validated ':'b.title,b.author,r.hold ') .
               "FROM $top INNER JOIN $table r ON b.id=r.id " .
               "WHERE r.id='$id' $qrest ORDER BY $order $dir";
        #print "$sql<br/>\n";
        my $ref2;
        eval{$ref2 = $self->GetDb()->selectall_arrayref($sql);};
        if ($@)
        {
          $self->SetError("SQL failed: '$sql' ($@)");
          $self->DownloadSpreadSheet("SQL failed: '$sql' ($@)");
          return 0;
        }
        $buff .= $self->UnpackResults($page, $ref2);
      }
    }
  }
  $self->DownloadSpreadSheet($buff);
  return ($buff)? 1:0;
}

sub UnpackResults
{
  my $self = shift;
  my $page = shift;
  my $ref  = shift;
  
  my $buff = '';
  foreach my $row (@{$ref})
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
    my $attr       = $self->TranslateAttr($row->[4]);
    my $reason     = $self->TranslateReason($row->[5]);
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
    
    if ($page eq 'userReviews')
    {
      #for reviews
      #id, title, author, review date, attr, reason, category, note.
      $buff .= qq{$id\t$title\t$author\t$time\t$attr\t$reason\t$category\t$note};
    }
    elsif ($page eq 'editReviews' || $page eq 'holds')
    {
      #for editReviews
      #id, title, author, review date, attr, reason, category, note.
      $buff .= qq{$id\t$title\t$author\t$time\t$attr\t$reason\t$category\t$note\t$hold};
    }
    elsif ($page eq 'undReviews')
    {
      #for und/nfi
      #id, title, author, review date, status, user, attr, reason, category, note.
      $buff .= qq{$id\t$title\t$author\t$time\t$status\t$user\t$attr\t$reason\t$category\t$note}
    }
    elsif ($page eq 'expert')
    {
      #for expert
      #id, title, author, review date, status, user, attr, reason, category, note.
      $buff .= qq{$id\t$title\t$author\t$time\t$status\t$user\t$attr\t$reason\t$category\t$note};
    }
    elsif ($page eq 'adminReviews' || $page eq 'adminHolds')
    {
      #for adminReviews
      #id, title, author, review date, status, user, attr, reason, category, note.
      $buff .= qq{$id\t$title\t$author\t$time\t$status\t$user\t$attr\t$reason\t$category\t$note\t$swiss\t$hold};
    }
    elsif ($page eq 'adminHistoricalReviews')
    {
      $author = $self->SimpleSqlGet("SELECT author FROM bibdata WHERE id='$id'");
      $title = $self->SimpleSqlGet("SELECT title FROM bibdata WHERE id='$id'");
      my $pubdate = $self->SimpleSqlGet("SELECT YEAR(pub_date) FROM bibdata WHERE id='$id'");
      $pubdate = '?' unless $pubdate;
      my $validated = $row->[15];
      #id, title, author, review date, status, user, attr, reason, category, note, validated
      my $sysid = $self->SimpleSqlGet("SELECT sysid FROM system WHERE id='$id'");
      $buff .= qq{$id\t$sysid\t$title\t$author\t$pubdate\t$time\t$status\t$legacy\t$user\t$attr\t$reason\t$category\t$note\t$validated\t$swiss};
    }
    $buff .= sprintf("%s\n", ($self->IsUserAdmin())? "\t$priority":'');
  }
  return $buff;
}

sub SearchAndDownloadDeterminationStats
{
  my $self      = shift;
  my $startDate = shift;
  my $endDate   = shift;
  my $monthly   = shift;
  my $priority  = shift;
  my $pre       = shift;
  
  my $buff;
  if ($pre)
  {
    $buff = $self->CreatePreDeterminationsBreakdownData("\t", $startDate, $endDate, $monthly, undef, $priority);
  }
  else
  {
    $buff = $self->CreateDeterminationsBreakdownData("\t", $startDate, $endDate, $monthly, undef, $priority);
  }
  $self->DownloadSpreadSheet($buff);
  return ($buff)? 1:0;
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
  
  my $buff = $self->GetQueueRef($order, $dir, $search1, $search1Value, $op1, $search2, $search2Value, $startDate, $endDate, 0, 0, 1);
  $self->DownloadSpreadSheet($buff);
  return ($buff)? 1:0;
}

sub SearchAndDownloadExportData
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
  
  my $buff = $self->GetExportDataRef($order, $dir, $search1, $search1Value, $op1, $search2, $search2Value, $startDate, $endDate, 0, 0, 1);
  $self->DownloadSpreadSheet($buff);
  return ($buff)? 1:0;
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
  eval { $ref = $self->GetDb()->selectall_arrayref($sql); };
  if ($@)
  {
    $self->SetError("SQL failed: '$sql' ($@)");
    return;
  }
  my $return = [];
  foreach my $row (@{$ref})
  {
      my $date = $row->[1];
      $date =~ s/(.*) .*/$1/;
      my $id = $row->[0];
      my $item = {id         => $id,
                  time       => $row->[1],
                  date       => $date,
                  duration   => $row->[2],
                  user       => $row->[3],
                  attr       => $self->TranslateAttr($row->[4]),
                  reason     => $self->TranslateReason($row->[5]),
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
        my $pubdate = $self->SimpleSqlGet('SELECT YEAR(pub_date) FROM bibdata WHERE id=?', $id);
        $pubdate = '?' unless $pubdate;
        ${$item}{'pubdate'} = $pubdate;
        ${$item}{'author'} = $self->SimpleSqlGet('SELECT author FROM bibdata WHERE id=?', $id);
        ${$item}{'title'} = $self->SimpleSqlGet('SELECT title FROM bibdata WHERE id=?', $id);
        ${$item}{'sysid'} = $self->SimpleSqlGet('SELECT sysid FROM system WHERE id=?', $id);
        ${$item}{'validated'} = $row->[15];
      }
      push(@{$return}, $item);
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
  eval { $ref = $self->GetDb()->selectall_arrayref($sql); };
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
  foreach my $row (@{$ref})
  {
    my $id = $row->[0];
    $sql = 'SELECT r.id, r.time, r.duration, r.user, r.attr, r.reason, r.note, r.renNum, r.expert, ' .
           "r.category, r.legacy, r.renDate, r.priority, r.swiss, $status, b.title, b.author" .
           (($page eq 'adminHistoricalReviews')? ', YEAR(b.pub_date), r.validated, s.sysid ':' ') .
           (($page eq 'adminReviews' || $page eq 'editReviews' || $page eq 'holds' || $page eq 'adminHolds')? ', DATE(r.hold) ':' ') .
           "FROM $table r LEFT JOIN bibdata b ON r.id=b.id $doQ $doS " .
           "WHERE r.id='$id' ORDER BY $order $dir";
    #print "$sql<br/>\n";
    my $ref2 = $self->GetDb()->selectall_arrayref($sql);
    foreach my $row (@{$ref2})
    {
      my $date = $row->[1];
      $date =~ s/(.*) .*/$1/;
      my $item = {id         => $row->[0],
                  time       => $row->[1],
                  date       => $date,
                  duration   => $row->[2],
                  user       => $row->[3],
                  attr       => $self->TranslateAttr($row->[4]),
                  reason     => $self->TranslateReason($row->[5]),
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
        ${$item}{'sysid'} = $self->SimpleSqlGet('SELECT sysid FROM system WHERE id=?', $id);
      }
      push(@{$return}, $item);
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
  eval { $ref = $self->GetDb()->selectall_arrayref($sql); };
  if ($@)
  {
    $self->SetError("SQL failed: '$sql' ($@)");
    return;
  }
  my $return = ();
  foreach my $row (@{$ref})
  {
    my $id = $row->[0];
    $sql = 'SELECT r.id, r.time, r.duration, r.user, r.attr, r.reason, r.note, r.renNum, r.expert, ' .
           "r.category, r.legacy, r.renDate, r.priority, r.swiss, $status, b.title, b.author" .
           (($page eq 'adminHistoricalReviews')? ', YEAR(b.pub_date), r.validated, s.sysid ':' ') .
           (($page eq 'adminReviews' || $page eq 'editReviews' || $page eq 'holds' || $page eq 'adminHolds')? ', DATE(r.hold) ':' ') .
           "FROM $table r LEFT JOIN bibdata b ON r.id=b.id $doQ $doS " .
           "WHERE r.id='$id' ORDER BY $order $dir";
    #print "$sql<br/>\n";
    my $ref2 = $self->GetDb()->selectall_arrayref($sql);
    foreach my $row (@{$ref2})
    {
      my $date = $row->[1];
      $date =~ s/(.*) .*/$1/;
      my $item = {id         => $row->[0],
                  time       => $row->[1],
                  date       => $date,
                  duration   => $row->[2],
                  user       => $row->[3],
                  attr       => $self->TranslateAttr($row->[4]),
                  reason     => $self->TranslateReason($row->[5]),
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
        ${$item}{'sysid'} = $self->SimpleSqlGet('SELECT sysid FROM system WHERE id=?', $id);
      }
      push(@{$return}, $item);
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

  my ($sql,$totalReviews,$totalVolumes,$n,$of) = $self->CreateSQL($stype, $page, undef, 'ASC', $search1, $search1value, $op1, $search2, $search2value, $op2, $search3, $search3value, $startDate, $endDate, $stype);
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
  $search1 = $self->ConvertToSearchTerm($search1, 'queue');
  $search2 = $self->ConvertToSearchTerm($search2, 'queue');
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
  if ($search1Value =~ m/.*\*.*/)
  {
    $search1Value =~ s/\*/%/gs;
    $tester1 = ' LIKE ';
  }
  if ($search2Value =~ m/.*\*.*/)
  {
    $search2Value =~ s/\*/%/gs;
    $tester2 = ' LIKE ';
  }
  if ($search1Value =~ m/([<>!]=?)\s*(\d+)\s*/)
  {
    $search1Value = $2;
    $tester1 = $1;
  }
  if ($search2Value =~ m/([<>!]=?)\s*(\d+)\s*/)
  {
    $search2Value = $2;
    $tester2 = $1;
  }
  push @rest, "q.time >= '$startDate'" if $startDate;
  push @rest, "q.time <= '$endDate'" if $endDate;
  if ($search1Value ne '' && $search2Value ne '')
  {
    push @rest, "($search1 $tester1 '$search1Value' $op1 $search2 $tester2 '$search2Value')";
  }
  else
  {
    push @rest, "$search1 $tester1 '$search1Value'" if $search1Value ne '';
    push @rest, "$search2 $tester2 '$search2Value'" if $search2Value ne '';
  }
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
    $ref = $self->GetDb()->selectall_arrayref($sql);
  };
  if ($@)
  {
    $self->SetError($@);
  }
  my $data = join "\t", ('ID','Title','Author','Pub Date','Date Added','Status','Locked','Priority','Reviews','Expert Reviews','Holds');
  foreach my $row (@{$ref})
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

sub GetExportDataRef
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
  $search1 = $self->ConvertToSearchTerm($search1, 'exportData');
  $search2 = $self->ConvertToSearchTerm($search2, 'exportData');
  if ($order eq 'author' || $order eq 'title' || $order eq 'pub_date') { $order = 'b.' . $order; }
  else { $order = 'r.' . $order; }
  my @rest = ();
  my $tester1 = '=';
  my $tester2 = '=';
  if ($search1Value =~ m/.*\*.*/)
  {
    $search1Value =~ s/\*/%/gs;
    $tester1 = ' LIKE ';
  }
  if ($search2Value =~ m/.*\*.*/)
  {
    $search2Value =~ s/\*/%/gs;
    $tester2 = ' LIKE ';
  }
  if ($search1Value =~ m/([<>!]=?)\s*(\d+)\s*/)
  {
    $search1Value = $2;
    $tester1 = $1;
  }
  if ($search2Value =~ m/([<>!]=?)\s*(\d+)\s*/)
  {
    $search2Value = $2;
    $tester2 = $1;
  }
  push @rest, "r.time >= '$startDate'" if $startDate;
  push @rest, "r.time <= '$endDate'" if $endDate;
  if ($search1Value ne '' && $search2Value ne '')
  {
    push @rest, "($search1 $tester1 '$search1Value' $op1 $search2 $tester2 '$search2Value')";
  }
  else
  {
    push @rest, "$search1 $tester1 '$search1Value'" if $search1Value ne '';
    push @rest, "$search2 $tester2 '$search2Value'" if $search2Value ne '';
  }
  my $restrict = ((scalar @rest)? 'WHERE ':'') . join(' AND ', @rest);
  my $sql = "SELECT COUNT(r.id) FROM exportdata r LEFT JOIN bibdata b ON r.id=b.id $restrict";
  #print "$sql<br/>\n";
  my $totalVolumes = $self->SimpleSqlGet($sql);
  $offset = $totalVolumes-($totalVolumes % $pagesize) if $offset >= $totalVolumes;
  my $limit = ($download)? '':"LIMIT $offset, $pagesize";
  my @return = ();
  $sql = 'SELECT r.id,r.time,r.attr,r.reason,r.src,b.title,b.author,YEAR(b.pub_date),r.exported ' .
         "FROM exportdata r LEFT JOIN bibdata b ON r.id=b.id $restrict ORDER BY $order $dir $limit";
  #print "$sql<br/>\n";
  my $ref = undef;
  eval {
    $ref = $self->GetDb()->selectall_arrayref($sql);
  };
  if ($@)
  {
    $self->SetError($@);
  }
  my $data = join "\t", ('ID','Title','Author','Pub Date','Date Exported','Source');
  foreach my $row (@{$ref})
  {
    my $id = $row->[0];
    my $date = $row->[1];
    $date =~ s/(.*?) .*/$1/;
    my $pubdate = $row->[7];
    $pubdate = '?' unless $pubdate;
    my $item = {id         => $id,
                time       => $row->[1],
                date       => $date,
                attr       => $row->[2],
                reason     => $row->[3],
                src        => $row->[4],
                title      => $row->[5],
                author     => $row->[6],
                exported   => $row->[8],
                pubdate    => $pubdate
               };
    push @return, $item;
    if ($download)
    {
      $data .= sprintf("\n$id\t%s\t%s\t$pubdate\t$date\t%s",
                       $row->[5], $row->[6], $row->[4]);
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

sub GetPublisherDataRef
{
  my $self = shift;

  require 'Publisher.pm';
  unshift @_, $self;
  return Publisher::GetPublisherDataRef(@_);
}

sub PublisherDataSearchMenu
{
  my $self = shift;

  require 'Publisher.pm';
  unshift @_, $self;
  return Publisher::PublisherDataSearchMenu(@_);
}

sub Linkify
{
  my $self = shift;
  my $txt  = shift;

  $txt =~ s!(((https?|ftp)://|(www|ftp)\.)[a-z0-9-]+(\.[a-z0-9-]+)+([/?][^\(\)\s]*)?)!<a target='_blank' href='$1'>$1</a>!ig;
  $txt =~ s!(\b.+?\@.+?\..+?\b)!<a href="mailto:$1">$1<\/a>!ig; 
  return $txt;
}

sub PTAddress
{
  my $self = shift;
  my $id   = shift;
  
  my $pt = 'babel.hathitrust.org';
  my $syspt = $self->SimpleSqlGet('SELECT value FROM systemvars WHERE name="pt"');
  $pt = $syspt if $syspt;
  return 'https://' . $pt . '/cgi/pt?debug=super;id=' . $id;
}

sub LinkToPT
{
  my $self  = shift;
  my $id    = shift;
  my $title = shift;

  $title = $self->GetTitle($id) unless $title;
  $title = CGI::escapeHTML($title);
  my $url = $self->PTAddress($id);
  $self->ClearErrors();
  return '<a href="' . $url . '" target="_blank">' . $title . '</a>';
}

sub LinkToReview
{
  my $self  = shift;
  my $id    = shift;
  my $title = shift;
  my $user  = shift;

  $title = $self->GetTitle($id) unless $title;
  $title = CGI::escapeHTML($title);
  my $url = $self->Sysify("/cgi/c/crms/crms?p=review;barcode=$id;editing=1");
  $url .= ";importUser=$user" if $user;
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

  my $url = $self->Sysify("/cgi/c/crms/crms?p=detailInfo;id=$id;user=$user;page=$page");
  $url .= ';review=1' if $review;
  return "<a href='$url' target='_blank'>$id</a>";
}

sub GetStatus
{
  my $self = shift;
  my $id   = shift;

  my $sql = 'SELECT status FROM queue WHERE id=?';
  return $self->SimpleSqlGet($sql, $id);
}

sub IsVolumeInCandidates
{
  my $self = shift;
  my $id   = shift;

  my $sql = 'SELECT COUNT(id) FROM candidates WHERE id=?';
  return ($self->SimpleSqlGet($sql, $id) > 0);
}

sub IsVolumeInQueue
{
  my $self = shift;
  my $id   = shift;

  my $sql = 'SELECT COUNT(id) FROM queue WHERE id=?';
  return ($self->SimpleSqlGet($sql, $id) > 0);
}

sub ValidateAttrReasonCombo
{
  my $self = shift;
  my $a    = shift;
  my $r    = shift;

  my $code = $self->GetCodeFromAttrReason($a,$r);
  $self->SetError("bad attr/reason: $a/$r") unless $code;
  return $code;
}

sub GetAttrReasonFromCode
{
  my $self = shift;
  my $code = shift;

  my $sql = 'SELECT attr,reason FROM rights WHERE id=?';
  my $ref = $self->GetDb()->selectall_arrayref($sql, undef, $code);
  my $a = $ref->[0]->[0];
  my $r = $ref->[0]->[1];
  return ($a,$r);
}

sub GetCodeFromAttrReason
{
  my $self = shift;
  my $a    = shift;
  my $r    = shift;

  return $self->SimpleSqlGet('SELECT id FROM rights WHERE attr=? AND reason=?', $a, $r);
}

sub GetAttrReasonCode
{
  my $self = shift;
  my $id   = shift;
  my $user = shift;

  my $sql = 'SELECT attr,reason FROM reviews WHERE id=? AND user=?';
  my $ref = $self->GetDb()->selectall_arrayref($sql, undef, $id, $user);
  my $a = $ref->[0]->[0];
  my $r = $ref->[0]->[1];
  if ($a && $r)
  {
    return $self->SimpleSqlGet('SELECT id FROM rights WHERE attr=? AND reason=?', $a, $r);
  }
  return undef;
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
  $kerberos = $self->SimpleSqlGet('SELECT kerberos FROM users WHERE id=?', $id) unless $kerberos;
  $name = $self->SimpleSqlGet('SELECT name FROM users WHERE id=?', $id) unless $name;
  $note = $self->SimpleSqlGet('SELECT note FROM users WHERE id=?', $id) unless $note;
  my $wcs = $self->WildcardList(10);
  my $sql = "REPLACE INTO users (id,kerberos,name,reviewer,advanced,expert,extadmin,admin,superadmin,note)" .
            ' VALUES ' . $wcs;
  $self->PrepareSubmitSql($sql, $id, $kerberos, $name, $reviewer, $advanced,
                          $expert, $extadmin, $admin, $superadmin, $note);
}

sub DeleteUser
{
  my $self = shift;
  my $id   = shift;
  
  my $sql = 'DELETE FROM users WHERE id=?';
  $self->PrepareSubmitSql($sql, $id);
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
  my $sql = 'SELECT name FROM users WHERE id=?';
  return $self->SimpleSqlGet($sql, $user);
}

sub GetUserNote
{
  my $self = shift;
  my $user = shift;

  $user = $self->get('user') unless $user;
  my $sql = 'SELECT note FROM users WHERE id=?';
  return $self->SimpleSqlGet($sql, $user);
}

sub GetUserKerberosID
{
  my $self = shift;
  my $user = shift;

  $user = $self->get('user') unless $user;
  my $sql = 'SELECT kerberos FROM users WHERE id=?';
  return $self->SimpleSqlGet($sql, $user);
}

sub GetAliasUserName
{
  my $self = shift;
  my $user = shift;

  $user = $self->get('user') unless $user;
  my $sql = 'SELECT alias FROM users WHERE id=?';
  return $self->SimpleSqlGet($sql, $user);
}

sub ChangeAliasUserName
{
  my $self     = shift;
  my $user     = shift;
  my $new_user = shift;

  $user = $self->get('user') unless $user;
  my $sql = 'UPDATE users SET alias=? WHERE id=?';
  $self->PrepareSubmitSql($sql, $new_user, $user);
}

sub SameUser
{
  my $self = shift;
  my $u1   = shift;
  my $u2   = shift;

  $u1 = $self->SimpleSqlGet('SELECT kerberos FROM users WHERE id=?', $u1);
  $u2 = $self->SimpleSqlGet('SELECT kerberos FROM users WHERE id=?', $u2);
  return ($u1 ne '' && $self->TolerantCompare($u1, $u2))? 1:0;
}

sub CanChangeToUser
{
  my $self = shift;
  my $me   = shift;
  my $him  = shift;
  
  return 0 if $me eq $him;
  return 1 if $self->SameUser($me, $him);
  return 0 if not ($self->IsUserAdmin($me) && $self->WhereAmI());
  my $sql = 'SELECT reviewer,advanced,expert,admin,superadmin FROM users WHERE id=?';
  my $ref1 = $self->GetDb()->selectall_arrayref($sql, undef, $me);
  $ref1 = $ref1->[0];
  $sql = 'SELECT reviewer,advanced,expert,admin,superadmin FROM users WHERE id=?';
  my $ref2 = $self->GetDb()->selectall_arrayref($sql, undef, $him);
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
  my $sql = 'SELECT reviewer FROM users WHERE id=?';
  return $self->SimpleSqlGet($sql, $user);
}

sub IsUserAdvanced
{
  my $self = shift;
  my $user = shift;

  $user = $self->get('user') unless $user;
  my $sql = 'SELECT advanced FROM users WHERE id=?';
  return $self->SimpleSqlGet($sql, $user);
}

sub IsUserExpert
{
  my $self = shift;
  my $user = shift;

  $user = $self->get('user') unless $user;
  my $sql = 'SELECT expert FROM users WHERE id=?';
  return $self->SimpleSqlGet($sql, $user);
}

sub IsUserExtAdmin
{
  my $self = shift;
  my $user = shift;

  $user = $self->get('user') unless $user;
  my $sql = 'SELECT extadmin FROM users WHERE id=?';
  return $self->SimpleSqlGet($sql, $user);
}

sub IsUserAdmin
{
  my $self = shift;
  my $user = shift;

  $user = $self->get('user') unless $user;
  my $sql = 'SELECT (admin OR superadmin) FROM users WHERE id=?';
  return $self->SimpleSqlGet($sql, $user);
}

sub IsUserSuperAdmin
{
  my $self = shift;
  my $user = shift;

  $user = $self->get('user') unless $user;
  my $sql = 'SELECT superadmin FROM users WHERE id=?';
  return $self->SimpleSqlGet($sql, $user);
}

# If order, orders by privilege level from low to high
sub GetUsers
{
  my $self  = shift;
  my $order = shift;

  my $dbh  = $self->GetDb();
  $order = ($order)? 'ORDER BY expert ASC, name ASC':
                     'ORDER BY (reviewer OR advanced OR extadmin OR admin OR superadmin) DESC, name ASC';
  my $sql = "SELECT id FROM users $order";
  my $ref = $dbh->selectall_arrayref($sql);
  my @users = map { $_->[0]; } @{ $ref };
  return \@users;
}

sub IsUserIncarnationExpertOrHigher
{
  my $self = shift;
  my $user = shift;

  $user = $self->get('user') unless $user;
  my $sql = 'SELECT MAX(expert+admin+superadmin) FROM users WHERE kerberos!=""' .
            ' AND kerberos IN (SELECT DISTINCT kerberos FROM users WHERE id=?)';
  return 0 < $self->SimpleSqlGet($sql, $user);
}

# FIXME: this should go in the database, but need mechanism for exclusing UM from
# the institutional stats menu/nav.
# Suggest CREATE TABLE institutions id, name, code, report BOOL
# ex. 1, "Indiana University", "IU", TRUE
#     2, "University of Michigan", "UM", FALSE
# and link entries in the users table to the inst id.
# FIXME: use the term institution or affiliation, not both.
sub GetAffiliations
{
  my $self = shift;
  
  return ['UM-ERAU','COL','IU','UMN','UW'];
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
    return 'COL' if $suff eq 'columbia.edu';
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
  foreach my $user (@{$users})
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
  my $start = 1;
  # FIXME: this could be put in the config file.
  if ($self->get('sys') eq 'crmsworld')
  {
    $start = 5 if $year == 2012;
  }
  else
  {
    $start = 7 if $year == 2009;
  }
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
  my $dbh = $self->GetDb();
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
    my $sql = 'SELECT DISTINCT(DATE_FORMAT(date,"%Y-%m")) FROM exportstats' .
              ' WHERE DATE_FORMAT(date,"%Y-%m")>=?' .
              ' AND DATE_FORMAT(date,"%Y-%m")<=? ORDER BY date ASC';
    @dates = map {$_->[0];} @{$dbh->selectall_arrayref($sql, undef, $start, $end)};
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
  
  my $sql = 'SELECT DISTINCT attr,reason FROM exportdata ORDER BY (attr="pd" OR attr="pdus") DESC, attr, reason DESC';
  my $ref = $dbh->selectall_arrayref($sql);
  my @allRights = map { $_->[0] . '_' . $_->[1]; } @{$ref};
  my $nRights = scalar @allRights;
  foreach my $date (@dates)
  {
    last if $date eq $now and !$doCurrentMonth;
    push @usedates, $date;
    $report .= "$delimiter$date";
    my %cats = ();
    my @sums = ();
    foreach my $right (@allRights)
    {
      my ($a,$r) = split '_', $right;
      $cats{"$a/$r"} = 0;
      push @sums, "SUM(e.$right)";
    }
    my $lastDay;
    if (!$cumulative)
    {
      my ($year,$month) = split '-', $date;
      $lastDay = Days_in_Month($year,$month);
    }
    $sql = sprintf('SELECT %s, SUM(d.s4),SUM(d.s5),SUM(d.s6),SUM(d.s7),SUM(d.s8),SUM(d.s9) ' .
                   'FROM exportstats e LEFT JOIN determinationsbreakdown d ON DATE(e.date)=d.date WHERE ' .
                   "e.date LIKE '$date%'", join ',', @sums);
    #print "$date: $sql<br/>\n";
    my $ref = $dbh->selectall_arrayref($sql);
    #printf "$date: $sql : %d items<br/>\n", scalar @{$ref};
    my $n = 0;
    foreach my $right (@allRights)
    {
      my ($a,$r) = split '_', $right;
      $stats{"$a/$r"}{$date} += $ref->[0]->[$n];
      $n++;
    }
    $stats{'Status 4'}{$date} += $ref->[0]->[$n];
    $stats{'Status 5'}{$date} += $ref->[0]->[$n+1];
    $stats{'Status 6'}{$date} += $ref->[0]->[$n+2];
    $stats{'Status 7'}{$date} += $ref->[0]->[$n+3];
    $stats{'Status 8'}{$date} += $ref->[0]->[$n+4];
    $stats{'Status 9'}{$date} += $ref->[0]->[$n+5];
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
  my @titles = ('Total','Status 4', 'Status 5', 'Status 6', 'Status 7', 'Status 8', 'Status 9');
  my @pdTitles = ('All PD');
  my @icTitles = ('All IC');
  my @undTitles = ('All UND');
  foreach my $right (@allRights)
  {
    my ($a,$r) = split '_', $right;
    my $right = "$a/$r";
    push @pdTitles, $right if $a =~ m/^pd/;
    push @icTitles, $right if $a =~ m/^ic/;
    push @undTitles, $right if $a =~ m/^und/;
  }
  
  unshift @titles, @undTitles;
  unshift @titles, @icTitles;
  unshift @titles, @pdTitles;
  
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
  my $type  = shift;
  my $start = shift;
  my $end   = shift;
  
  my $data = $self->CreateExportData(',', $type == 2, 0, $start, $end);
  #printf "CreateExportData(',', %d, 0, $start, $end)\n", ($type == 2);
  #print "$data\n";
  my @lines = split m/\n/, $data;
  my $title = shift @lines;
  #$title .= '*' if $type == 2;
  $title =~ s/Cumulative/Monthly Breakdown/ if $type == 0;
  $title =~ s/Cumulative/Monthly Totals/ if $type == 1;
  my @dates = split(',', shift @lines);
  #printf "%d dates\n", scalar @dates;
  # Shift off the Categories and GT headers
  shift @dates; shift @dates;
  # Now the data is just the categories and numbers...
  my @titles = ($type == 1)? ('Total'):('All PD','All IC','All UND');
  my %titleh = ();
  foreach my $line (@lines)
  {
    $titleh{'All PD'} = $line if $line =~ m/^All\sPD/i;
    $titleh{'All IC'} = $line if $line =~ m/^All\sIC/i;
    $titleh{'All UND'} = $line if $line =~ m/^All\sUND/i;
    $titleh{'Total'} = $line if $line =~ m/^Total/i;
  }
  my @elements = ();
  my %colors = ('All PD' => '#22BB00', 'All IC' => '#FF2200', 'All UND' => '#0088FF', 'Total' => '#FFFF00');
  my %totals = ('All PD' => 0, 'All IC' => 0, 'All UND' => 0);
  my $ceiling = 100;
  my @totalline = split ',',$titleh{'Total'};
  shift @totalline;
  my $gt = shift @totalline;
  foreach my $title (@titles)
  {
    # Extract the total,n1,n2... data
    my @line = split(',',$titleh{$title});
    shift @line;
    #printf "$title: '%s' from %s\n", join(',', @line), $titleh{$title};
    my $total = int(shift @line);
    $totals{$title} = $total;
    foreach my $n (@line) { $ceiling = int($n) if int($n) > $ceiling && $type == 1; }
    my $color = $colors{$title};
    $title = 'Monthly Totals' if $type == 1;
    my $attrs = sprintf('"dot-style":{"type":"solid-dot","dot-size":3,"colour":"%s"},"colour":"%s","on-show":{"type":"pop-up","cascade":1,"delay":0.2}',
                        $color, $color);
    $attrs .= sprintf(',"text":"%s"', $title) unless $type == 1;
    my @vals = @line;
    if ($type == 0)
    {
      for (my $i = 0; $i < scalar @line; $i++)
      {
        my $pct = 0.0;
        eval { $pct = 100.0*$line[$i]/$totalline[$i]; };
        $line[$i] = $pct;
      }
      @vals = map(sprintf('{"value":%.1f,"tip":"%.1f%%"}', $_, $_), @line);
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
  my $sql = "SELECT DISTINCT($what) FROM predeterminationsbreakdown WHERE date>=? AND date<=?";
  #print "$sql<br/>\n";
  my @dates = map {$_->[0];} @{$self->GetDb()->selectall_arrayref($sql, undef, $start, $end)};
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
    my ($s2,$s3,$s4,$s8,$sum) = @{$self->GetDb()->selectall_arrayref($sql)->[0]};
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
  my $sql = "SELECT DISTINCT($what) FROM determinationsbreakdown WHERE date>=? AND date<=?";
  #print "$sql<br/>\n";
  my @dates = map {$_->[0];} @{$self->GetDb()->selectall_arrayref($sql, undef, $start, $end)};
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
    $sql = 'SELECT SUM(s4),SUM(s5),SUM(s6),SUM(s7),SUM(s8),SUM(s4+s5+s6+s7+s8),SUM(s9),SUM(s4+s5+s6+s7+s8+s9)' .
           ' FROM determinationsbreakdown WHERE date>=? AND date<=?';
    #print "$sql<br/>\n";
    my ($s4,$s5,$s6,$s7,$s8,$sum1,$s9,$sum2) = @{$self->GetDb()->selectall_arrayref($sql, undef, $date1, $date2)->[0]};
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
  my $url = $self->Sysify(sprintf("?p=determinationStats;startDate=$start;endDate=$end;%sdownload=1;pre=$pre",($monthly)?'monthly=on;':''));
  my $link = sprintf("<a href='$url' target='_blank'>Download</a>",);
  my $report = "<h3>$title&nbsp;&nbsp;&nbsp;&nbsp;$link</h3>\n";
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
        my $pct = eval { 100.0*$count/$line[5]; } or 0.0;
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
  $report .= sprintf('%s]', join ',', @elements);
  $report .= sprintf(',"y_axis":{"max":%d,"steps":%d,"colour":"#888888","grid-colour":"#888888","labels":{%s"colour":"#FFFFFF"}}', $ceil, $ceil/10, $valfmt);
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
  my $ref = $self->GetDb()->selectall_arrayref($sql);
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
  my $dbh = $self->GetDb();
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
    my $sql = 'SELECT SUM(total_pd), SUM(total_ic), SUM(total_und),SUM(total_reviews),' .
              '1, SUM(total_neutral),' . $which . ', 1, SUM(total_time),' .
              'SUM(total_time)/(SUM(total_reviews)-SUM(total_outliers)),' .
              '(SUM(total_reviews)-SUM(total_outliers))/SUM(total_time)*60.0, SUM(total_outliers)' .
              ' FROM userstats WHERE monthyear>=? AND monthyear<=?';
    if ($instusers) { $sql .= " AND user IN ($instusers)"; }
    elsif ($user ne 'all') { $sql .= " AND user='$user'"; }
    #print "$sql<br/>\n";
    my $rows = $dbh->selectall_arrayref($sql, undef, $mintime, $maxtime);
    my $row = $rows->[0];
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
    my @params = ();
    my $sql = 'SELECT SUM(total_pd),SUM(total_ic), SUM(total_und), SUM(total_reviews),' .
              '1, SUM(total_neutral),' . $which . ', 1, SUM(total_time),' .
              'SUM(total_time)/(SUM(total_reviews)-SUM(total_outliers)),' .
              '(SUM(total_reviews)-SUM(total_outliers))/SUM(total_time)*60.0, SUM(total_outliers)' .
              ' FROM userstats WHERE monthyear >= "2009-07"';
    # FIXME: use inst table in place of $instusers.
    if ($instusers) { $sql .= " AND user IN ($instusers)"; }
    elsif ($user ne 'all')
    {
      $sql .= ' AND user=?';
      push @params, $user;
    }
    #print "$sql<br/>\n";
    my $rows = $dbh->selectall_arrayref($sql, undef, @params);
    my $row = $rows->[0];
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
  my $url = $self->Sysify("crms?p=$page;download=1;user=$user;cumulative=$cumulative;year=$year;inval=$inval;nne=$nononexpert");
  my $dllink = <<END;
  <a href='$url' target='_blank'>Download</a>
  <a class='tip' href='#'>
    <img width="16" height="16" alt="Rights/Reason Help" src="/c/crms/help.png"/>
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
  $self->DownloadSpreadSheet($report);
  return ($report)? 1:0;
}

sub CreateCandidatesData
{
  my $self = shift;
  
  my $cnt = $self->GetCandidatesSize();
  my $sql = 'SELECT cd.ym,cd.cnt,ed.cnt FROM' .
            ' (SELECT EXTRACT(YEAR_MONTH FROM c.time) AS ym,SUM(c.addedamount) AS cnt FROM candidatesrecord c GROUP BY ym) cd' .
            ' RIGHT JOIN' .
            ' (SELECT EXTRACT(YEAR_MONTH FROM e.time) AS ym,COUNT(e.id) AS cnt FROM exportdata e' .
            '  WHERE e.src="candidates" OR src="inherited" GROUP BY EXTRACT(YEAR_MONTH FROM e.time)) ed' .
            ' ON (ed.ym=cd.ym) ORDER BY cd.ym DESC';
  my $ref = $self->GetDb()->selectall_arrayref($sql);
  my $report = '';
  foreach my $row (@{$ref})
  {
    my $ym = $row->[0];
    my $added = $row->[1];
    my $exported = $row->[2];
    $exported = 0 unless $exported;
    #print "$ym $added $exported\n";
    $ym = $self->YearMonthToEnglish(substr($ym, 0, 4) . '-' . substr($ym, 4, 2));
    $report = "$ym\t$cnt\n" . $report;
    $cnt -= $added;
    $cnt += $exported;
  }
  return "Volumes in Candidates\n" . $report;
}

sub CreateCandidatesGraph
{
  my $self  = shift;
  
  my $data = $self->CreateCandidatesData();
  my @lines = split m/\n/, $data;
  my $title = shift @lines;
  my @titles;
  my @vals;
  my $ceil = 0;
  my $attrs = '"dot-style":{"type":"solid-dot","dot-size":3},"on-show":{"type":"pop-up","cascade":1,"delay":0.2}';
  foreach my $line (@lines)
  {
    my ($ym,$val) = split "\t", $line;
    push @titles, $ym;
    push @vals, $val;
    $ceil = $val if $val > $ceil;
  }
  $ceil = 1000 * POSIX::ceil($ceil/1000.0);
  my $report = '{"bg_colour":"#000000"';
  $report .= sprintf(',"title":{"text":"%s","style":"{color:#FFFFFF;font-family:Helvetica;font-size:15px;font-weight:bold;text-align:center;}"}', $title);
  $report .= sprintf(',"elements":[{"type":"line","colour":"#22BB00","values":[%s],%s}]', join(',', @vals), $attrs);
  $report .= sprintf(',"y_axis":{"max":%d,"steps":%d,"colour":"#888888","grid-colour":"#888888","labels":{"colour":"#FFFFFF"}}',
                     $ceil, $ceil/10,);
  $report .= sprintf(',"x_axis":{"colour":"#888888","grid-colour":"#888888","labels":{"labels":["%s"],"rotate":40,"colour":"#FFFFFF"}}',
                     join('","',@titles));
  $report .= '}';
  return $report;
}

sub CreateCountriesGraph
{
  my $self  = shift;
  # FIXME: should do only for exports?
  my $sql = 'SELECT COUNT(*) FROM exportdata';
  my $of = $self->SimpleSqlGet($sql);
  $sql = 'SELECT b.country,COUNT(DISTINCT e.id) FROM bibdata b INNER JOIN exportdata e ON b.id=e.id' .
         ' GROUP BY b.country ORDER BY b.country ASC';
  my $ref = $self->GetDb()->selectall_arrayref($sql);
  my $report = '';
  my @colorlist = ('#22BB00','#BB2200','#2200BB','#444444');
  my @vals = ();
  foreach my $row (@{$ref})
  {
    my $country = $row->[0];
    my $n = $row->[1];
    push @vals, sprintf('{"value":%d,"label":"%s\n%.1f%%"}', $n, $country, $n / $of * 100.0);
  }
  my $report = '{"bg_colour":"#000000"' .
               ',"title":{"text":"Countries",' .
                         '"style":"{color:#FFFFFF;font-family:Helvetica;font-size:15px;font-weight:bold;text-align:center;}"}' .
               ',"elements":[' .
                 '{"type":"pie","start-angle":35,"animate":[{"type":"fade"}],"gradient-fill":true' .
                 ',"colours":["#22BB00","#FF2200","#0088FF","#22BBBB"]' .
                 sprintf(',"values":[%s]}]}', join(',', @vals));
  return $report;
}

sub CreateUndGraph
{
  my $self  = shift;
  # FIXME: should do only for exports?
  my $sql = 'SELECT COUNT(*) FROM und';
  my $of = $self->SimpleSqlGet($sql);
  $sql = 'SELECT src,COUNT(id) FROM und GROUP BY src ORDER BY src ASC';
  my $ref = $self->GetDb()->selectall_arrayref($sql);
  my @colorlist = ('#22BB00','#BB2200','#2200BB','#444444');
  my @vals = ();
  foreach my $row (@{$ref})
  {
    my $country = $row->[0];
    my $n = $row->[1];
    push @vals, sprintf('{"value":%d,"label":"%s\n%.1f%%"}', $n, $country, $n / $of * 100.0);
  }
  my $report = '{"bg_colour":"#000000"' .
               ',"title":{"text":"Filtered Volumes",' .
                         '"style":"{color:#FFFFFF;font-family:Helvetica;font-size:15px;font-weight:bold;text-align:center;}"}' .
               ',"elements":[' .
                 '{"type":"pie","start-angle":35,"animate":[{"type":"fade"}],"gradient-fill":true' .
                 ',"colours":["#22BB00","#FF2200","#0088FF","#22BBBB","#BB22BB","#BBBB22","#BBBBBB","#888888"]' .
                 sprintf(',"values":[%s]}]}', join(',', @vals));
  return $report;
}

sub CreateNamespaceGraph
{
  my $self = shift;

  my @data = ();
  my $ceil = 0;
  foreach my $ns (sort $self->Namespaces())
  {
    my $sql = "SELECT COUNT(DISTINCT id) FROM exportdata WHERE id LIKE '$ns.%'";
    #print "$sql\n";
    my $n = $self->SimpleSqlGet($sql);
    next unless $n;
    push @data, [$ns,$n];
    $ceil = $n if $n > $ceil;
  }
  @data = sort {$b->[1] <=> $a->[1]} @data;
  @data = @data[0 .. 9] if scalar @data > 10;
  my @labels = map {$_->[0]} @data;
  my @vals = map {$_->[1]} @data;
  $ceil = 100 * POSIX::ceil($ceil/100.0);
  my $report = '{"bg_colour":"#000000","elements":[{"type":"bar","colour":"#BBBB22","on-show":{"type":"grow-up","cascade":1,"delay":0.5}' .
            sprintf(',"values":[%s]}]', join(',',@vals)) . 
            ',"title":{"text":"Exports by Namespace",' .
                      '"style":"{color:#FFFFFF;font-family:Helvetica;font-size:15px;font-weight:bold;text-align:center;}"}' .
            sprintf(',"y_axis":{"max":%d,"steps":%d,"colour":"#888888","grid-colour":"#888888",%s}',
                     $ceil, $ceil/10,
                     '"labels":{"colour":"#FFFFFF"}') .
            sprintf(',"x_axis":{"colour":"#888888","grid-colour":"#888888","labels":{"labels":["%s"],"rotate":40,"colour":"#FFFFFF"}}',
                       join('","',@labels)) .
            '}';
  return $report;
}

sub CreateCountryReviewTimeData
{
  my $self  = shift;
  my $limit = shift;

  my $data = '';
  my $sql = 'SELECT COALESCE(b.country,"Undetermined"),SUM(COALESCE(TIME_TO_SEC(h.duration),0))/COUNT(b.country) s' .
          ' FROM bibdata b INNER JOIN historicalreviews h ON b.id=h.id WHERE legacy!=1 AND user!="crmstest"' .
          ' GROUP BY COALESCE(b.country,"Undetermined") ORDER BY s DESC';
  $sql .= ' LIMIT ' . $limit if $limit;
  my $ref = $self->GetDb()->selectall_arrayref($sql);
  foreach my $row (@{$ref})
  {
    my $cat = $row->[0];
    my $dur = $row->[1];
    next if $dur <= 0;
    $data .= "$cat\t$dur\n";
  }
  return $data;
}

sub CreateCountryReviewTimeGraph
{
  my $self = shift;

  my $txt = $self->CreateCountryReviewTimeData();
  my $ceil = 0;
  my @data;
  foreach my $row (split "\n", $txt)
  {
    my ($cat,$dur) = split "\t", $row;
    push @data, [$cat,$dur];
    $ceil = $dur if $dur > $ceil;
  }
  @data = sort {$b->[1] <=> $a->[1]} @data;
  @data = @data[0 .. 9] if scalar @data > 10;
  my @labels = map {$_->[0]} @data;
  my @vals = map {$_->[1]} @data;
  $ceil = 100 * POSIX::ceil($ceil/100.0);
  my $report = '{"bg_colour":"#000000","elements":[{"type":"bar","colour":"#BBBB22","on-show":{"type":"grow-up","cascade":1,"delay":0.5}' .
            sprintf(',"values":[%s]}]', join(',',@vals)) . 
            ',"title":{"text":"Review Time by Country",' .
                      '"style":"{color:#FFFFFF;font-family:Helvetica;font-size:15px;font-weight:bold;text-align:center;}"}' .
            sprintf(',"y_axis":{"max":%d,"steps":%d,"colour":"#888888","grid-colour":"#888888",%s}',
                     $ceil, $ceil/10,
                     '"labels":{"colour":"#FFFFFF"}') .
            sprintf(',"x_axis":{"colour":"#888888","grid-colour":"#888888","labels":{"labels":["%s"],"rotate":40,"colour":"#FFFFFF"}}',
                       join('","',@labels)) .
            '}';
  return $report;
}

sub CreateReviewInstitutionGraph
{
  my $self  = shift;

  my $sql = 'SELECT COUNT(*) FROM historicalreviews WHERE legacy=0 AND user!="autocrms"';
  my $of = $self->SimpleSqlGet($sql);
  $sql = 'SELECT user,COUNT(id) FROM historicalreviews WHERE legacy=0 AND user!="autocrms" GROUP BY user';
  my $ref = $self->GetDb()->selectall_arrayref($sql);
  my %totals = ();
  foreach my $row (@{$ref})
  {
    my $user = $row->[0];
    my $n = $row->[1];
    my $inst = 'umich.edu';
    $inst = $1 if $user =~ m/@(.+)/;
    $totals{$inst} += $n;
  }
  my @vals;
  foreach my $inst (sort keys %totals)
  {
    my $n = $totals{$inst};
    push @vals, sprintf('{"value":%d,"label":"%s\n%.1f%%"}', $n, $inst, $n / $of * 100.0);
  }
  my $report = '{"bg_colour":"#000000"' .
               ',"title":{"text":"Reviews by Institution",' .
                         '"style":"{color:#FFFFFF;font-family:Helvetica;font-size:15px;font-weight:bold;text-align:center;}"}' .
               ',"elements":[' .
                 '{"type":"pie","start-angle":35,"animate":[{"type":"fade"}],"gradient-fill":true' .
                 ',"colours":["#22BB00","#FF2200","#0088FF","#22BBBB","#BB22BB","#BBBB22","#BBBBBB","#888888"]' .
                 sprintf(',"values":[%s]}]}', join(',', @vals));
  return $report;
}

sub UpdateStats
{
  my $self = shift;

  # Get the underlying system status, ignoring replication delays.
  my ($blah,$stat,$msg) = @{$self->GetSystemStatus(1)};
  $self->SetSystemStatus($stat, 'CRMS is updating user stats, so they may not display correctly. This usually takes five minutes or so to complete.');
  $self->PrepareSubmitSql('DELETE from userstats');
  my $users = $self->GetUsers();
  foreach my $user (@{$users})
  {
    my $sql = 'SELECT DISTINCT DATE_FORMAT(time,"%Y-%m") AS ym FROM historicalreviews' .
              ' WHERE legacy!=1 AND user=? ORDER BY ym ASC';
    my $ref = $self->GetDb()->selectall_arrayref($sql, undef, $user);
    foreach my $row (@{$ref})
    {
      my ($y,$m) = split '-', $row->[0];
      $self->GetMonthStats($user, $y, $m);
    }
  }
  $self->SetSystemStatus($stat, $msg);
}

sub GetMonthStats
{
  my $self = shift;
  my $user = shift;
  my $y    = shift;
  my $m    = shift;

  my $sql = 'SELECT count(*) FROM historicalreviews WHERE user=? AND legacy!=1' . 
            ' AND EXTRACT(YEAR FROM time)=? AND EXTRACT(MONTH FROM time)=?';
  my $total_reviews = $self->SimpleSqlGet($sql, $user, $y, $m);
  #pd/pdus
  $sql = 'SELECT count(*) FROM historicalreviews WHERE user=? AND legacy!=1 AND (attr=1 OR attr=9)' .
         ' AND EXTRACT(YEAR FROM time)=? AND EXTRACT(MONTH FROM time)=?';
  my $total_pd = $self->SimpleSqlGet($sql, $user, $y, $m);
  #ic
  $sql = 'SELECT count(*) FROM historicalreviews WHERE user=? AND legacy!=1 AND attr=2' .
         ' AND EXTRACT(YEAR FROM time)=? AND EXTRACT(MONTH FROM time)=?';
  my $total_ic = $self->SimpleSqlGet($sql, $user, $y, $m);
  #und
  $sql = 'SELECT count(*) FROM historicalreviews WHERE user=? AND legacy!=1 AND attr=5' .
         ' AND EXTRACT(YEAR FROM time)=? AND EXTRACT(MONTH FROM time)=?';
  my $total_und = $self->SimpleSqlGet($sql, $user, $y, $m);
  #time reviewing ( in minutes ) - not including outliers
  $sql = 'SELECT COALESCE(SUM(TIME_TO_SEC(duration)),0)/60.0 FROM historicalreviews' .
         ' WHERE user=? AND legacy!=1 AND EXTRACT(YEAR FROM time)=?' .
         ' AND EXTRACT(MONTH FROM time)=? AND duration<="00:05:00"';
  my $total_time = $self->SimpleSqlGet($sql, $user, $y, $m);
  #total outliers
  $sql = 'SELECT COUNT(*) FROM historicalreviews WHERE user=? AND legacy!=1' .
         ' AND EXTRACT(YEAR FROM time)=? AND EXTRACT(MONTH FROM time)=?' .
         ' AND duration>"00:05:00"';
  my $total_outliers = $self->SimpleSqlGet($sql, $user);
  my $time_per_review = 0;
  if ($total_reviews - $total_outliers > 0)
  {
    $time_per_review = ($total_time/($total_reviews - $total_outliers));
  }
  my $reviews_per_hour = 0;
  if ($time_per_review > 0)
  {
    $reviews_per_hour = (60/$time_per_review);
  }
  my $lastDay = Days_in_Month($y, $m);
  my $mintime = "$y-$m-01 00:00:00";
  my $maxtime = "$y-$m-$lastDay 23:59:59";
  my ($total_correct,$total_incorrect,$total_neutral) = $self->CountCorrectReviews($user, $mintime, $maxtime);
  $sql = 'INSERT INTO userstats (user,month,year,monthyear,total_reviews,total_pd,' .
         'total_ic,total_und,total_time,time_per_review,reviews_per_hour,' .
         'total_outliers,total_correct,total_incorrect,total_neutral)' .
         ' VALUES ' . $self->WildcardList(15);
  $self->PrepareSubmitSql($sql, $user, $m, $y, $y . '-' . $m, $total_reviews, $total_pd,
                          $total_ic, $total_und, $total_time, $time_per_review, $reviews_per_hour,
                          $total_outliers, $total_correct, $total_incorrect, $total_neutral);
}

sub UpdateDeterminationsBreakdown
{
  my $self = shift;
  my $date = shift;

  $date = $self->SimpleSqlGet('SELECT CURDATE()') unless $date;
  my @vals;
  foreach my $status (4..9)
  {
    my $sql = 'SELECT COUNT(DISTINCT e.gid) FROM exportdata e INNER JOIN historicalreviews r' .
              ' ON e.gid=r.gid WHERE r.legacy!=1 AND DATE(e.time)=? AND r.status=?';
    push @vals, $self->SimpleSqlGet($sql, $date, $status);
  }
  unshift @vals, $date;
  my $wcs = $self->WildcardList(scalar @vals);
  my $sql = 'REPLACE INTO determinationsbreakdown (date,s4,s5,s6,s7,s8,s9) VALUES ' . $wcs;
  $self->PrepareSubmitSql($sql, @vals);
}

sub UpdateExportStats
{
  my $self = shift;
  my $date = shift;

  my %counts;
  $date = $self->SimpleSqlGet('SELECT CURDATE()') unless $date;
  my $sql = 'SELECT attr,reason FROM exportdata WHERE DATE(time)=? AND exported=1';
  #print "$sql\n";
  my $ref = $self->GetDb()->selectall_arrayref($sql, undef, $date);
  foreach my $row (@{$ref})
  {
    my $attr = $row->[0];
    my $reason = $row->[1];
    $counts{$attr . '_' . $reason}++;
  }
  my @keys = keys %counts;
  my @vals = map {$counts{$_}} @keys;
  return unless scalar @keys;
  unshift @keys, 'date';
  unshift @vals, $date;
  my $wcs = $self->WildcardList(scalar @vals);
  $sql = 'REPLACE INTO exportstats (' . join(',', @keys) . ') VALUES ' . $wcs;
  $self->PrepareSubmitSql($sql, @vals);
}

sub HasItemBeenReviewedByTwoReviewers
{
  my $self = shift;
  my $id   = shift;
  my $user = shift;

  my $msg = '';
  if ($self->IsUserExpert($user))
  {
    if ($self->HasItemBeenReviewedByAnotherExpert($id,$user))
    {
      $msg = 'This volume does not need to be reviewed. An expert has already reviewed it. Please Cancel.';
    }
  }
  else
  {
    my $sql = 'SELECT count(*) FROM reviews WHERE id=? AND user!=?';
    my $count = $self->SimpleSqlGet($sql, $id, $user);
    if ($count >= 2)
    {
      $msg = 'This volume does not need to be reviewed. Two reviewers or an expert have already reviewed it. Please Cancel.';
    }
    $sql = 'SELECT count(*) FROM queue WHERE id =? AND status!=0';
    $count = $self->SimpleSqlGet($sql, $id);
    if ($count >= 1) { $msg = 'This item has been processed already. Please Cancel.'; }
  }
  return $msg;
}

sub ValidateSubmission
{
  my $self = shift;
  my ($id, $user, $attr, $reason, $note, $category, $renNum, $renDate) = @_;
  my $errorMsg = '';
  ## Someone else has the item locked?
  $errorMsg = 'This item has been locked by another reviewer. Please Cancel.' if $self->IsLockedForOtherUser($id);
  ## check user
  if (!$self->IsUserReviewer($user) && !$self->IsUserAdvanced($user))
  {
    $errorMsg .= 'Not a reviewer.';
  }
  if (!$attr || !$reason)
  {
    $errorMsg .= 'rights/reason designation required.';
  }
  if (!$errorMsg)
  {
    my $module = 'Validator_' . $self->get('sys') . '.pm';
    require $module;
    unshift @_, $self;
    $errorMsg = Validator::ValidateSubmission(@_);
  }
  return $errorMsg;
}

sub IsFormatBK
{
  my $self   = shift;
  my $id     = shift;
  my $record = shift;

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
  if (!$record) { $self->SetError("no record in IsThesis($id)"); return 0; }
  eval {
    my $xpath = "//*[local-name()='datafield' and \@tag='502']/*[local-name()='subfield' and \@code='a']";
    my $doc  = $record->findvalue($xpath);
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
  if (!$record) { $self->SetError("no record in IsTranslation($id)"); return 0; }
  eval {
    my $xpath = "//*[local-name()='datafield' and \@tag='041' and \@ind1='1']/*[local-name()='subfield' and \@code='a']";
    my $lang  = $record->findvalue($xpath);
    $xpath = "//*[local-name()='datafield' and \@tag='041' and \@ind1='1']/*[local-name()='subfield' and \@code='h']";
    my $orig  = $record->findvalue($xpath);
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
      my $doc  = $record->findvalue($xpath);
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

## ----------------------------------------------------------------------------
##  Function:   get the publ date (260|c)for a specific vol.
##  Parameters: volume id
##  Return:     date string
## ----------------------------------------------------------------------------
sub GetRecordPubDate
{
  my $self   = shift;
  my $id     = shift;
  my $record = shift;
  my $date2  = shift;

  $record = $self->GetMetadata($id) unless $record;
  return 'unknown' unless $record;
  ## my $xpath = q{//*[local-name()='oai_marc']/*[local-name()='fixfield' and @id='008']};
  my $xpath   = q{//*[local-name()='controlfield' and @tag='008']};
  my $leader  = $record->findvalue($xpath);
  return substr($leader, ($date2)? 11:7, 4);
}

sub GetRecordPubLanguage
{
  my $self   = shift;
  my $id     = shift;
  my $record = shift;

  $record = $self->GetMetadata($id) unless $record;
  if (!$record) { return 0; }
  ## my $xpath = q{//*[local-name()='oai_marc']/*[local-name()='fixfield' and @id='008']};
  my $xpath   = q{//*[local-name()='controlfield' and @tag='008']};
  my $leader  = $record->findvalue($xpath);
  return substr($leader, 35, 3);
}

sub GetRecordPubCountry
{
  my $self   = shift;
  my $id     = shift;
  my $record = shift;
  my $long   = shift;

  $record = $self->GetMetadata($id) unless $record;
  return unless $record;
  my $code;
  eval {
    my $xpath = "//*[local-name()='controlfield' and \@tag='008']";
    $code  = substr($record->findvalue($xpath), 15, 3);
    $code =~ s/[^a-z]//gi;
  };
  $self->SetError("failed in GetCountry($id): $@") if $@;
  use Countries;
  return Countries::TranslateCountry($code, $long);
}

sub GetMarcFixfield
{
  my $self  = shift;
  my $id    = shift;
  my $field = shift;

  my $record = $self->GetMetadata($id);
  if (!$record) { $self->Logit("failed in GetMarcFixfield: $id"); }
  my $xpath = qq{//*[local-name()='oai_marc']/*[local-name()='fixfield' and \@id='$field']};
  return $record->findvalue($xpath);
}

sub GetMarcVarfield
{
  my $self  = shift;
  my $id    = shift;
  my $field = shift;
  my $label = shift;

  my $record = $self->GetMetadata($id);
  if (!$record) { $self->Logit("failed in GetMarcVarfield: $id"); }
  my $xpath = qq{//*[local-name()='oai_marc']/*[local-name()='varfield' and \@id='$field']} .
              qq{/*[local-name()='subfield' and \@label='$label']};
  return $record->findvalue($xpath);
}

sub GetMarcControlfield
{
  my $self  = shift;
  my $id    = shift;
  my $field = shift;

  my $record = $self->GetMetadata($id);
  if (!$record) { $self->Logit("failed in GetMarcControlfield: $id"); }
  my $xpath = qq{//*[local-name()='controlfield' and \@tag='$field']};
  return $record->findvalue($xpath);
}

sub GetMarcDatafield
{
  my $self   = shift;
  my $id     = shift;
  my $field  = shift;
  my $code   = shift;
  my $record = shift;
  my $index  = shift;

  $index = 1 unless defined $index;
  $record = $self->GetMetadata($id) unless $record;
  if (!$record) { $self->Logit("failed in GetMarcDatafield: $id"); }
  my $xpath = qq{//*[local-name()='datafield' and \@tag='$field'][$index]} .
              qq{/*[local-name()='subfield'  and \@code='$code'][$index]};
  my $data;
  eval{ $data = $record->findvalue($xpath); };
  if ($@) { $self->Logit("failed to parse metadata for $id: $@"); }
  my $len = length $data;
  if ($len && $len % 3 == 0)
  {
    my $s = $len / 3;
    my $f1 = substr $data, 0, $s;
    my $f2 = substr $data, $s, $s;
    my $f3 = substr $data, 2*$s, $s;
    #print "Warning: possible triplet from '$data' ($id)\n" if $f1 eq $f2 and $f2 eq $f3;
    $data = $f1 if $f1 eq $f2 and $f2 eq $f3;
  }
  return $data;
}

sub CountMarcDatafields
{
  my $self   = shift;
  my $id     = shift;
  my $field  = shift;
  my $record = shift;

  my $n = 0;
  eval {
    $record = $self->GetMetadata($id) unless $record;
    my $nodes = $record->findnodes("//*[local-name()='datafield' and \@tag='$field']");
    $n = scalar $nodes->get_nodelist();
  };
  $self->SetError('CountMarcDatafields: ' . $@) if $@;
  return $n;
}

# The long param includes the author dates in the 100d field if present.
sub GetRecordAuthor
{
  my $self   = shift;
  my $id     = shift;
  my $record = shift;
  my $long   = shift;

  $record = $self->GetMetadata($id) unless $record;
  my $data = $self->GetRecordSubfields($id, '100', $record, 1, 'a', 'b', 'c', ($long)? 'd':undef);
  $data = $self->GetRecordSubfields($id, '110', $record, 1, 'a', 'b') unless defined $data;
  $data = $self->GetRecordSubfields($id, '111', $record, 1, 'a', 'c') unless defined $data;
  $data = $self->GetRecordSubfields($id, '700', $record, 1, 'a', 'b', 'c', ($long)? 'd':undef) unless defined $data;
  $data = $self->GetRecordSubfields($id, '710', $record, 1, 'a') unless defined $data;
  if (defined $data)
  {
    $data =~ s/\n+//gs;
    $data =~ s/\s*[,:;]*\s*$//;
    $data =~ s/^\s+//;
  }
  return $data;
}

sub GetRecordAdditionalAuthors
{
  my $self   = shift;
  my $id     = shift;
  my $record = shift;

  $record = $self->GetMetadata($id) unless $record;
  my @aus = ();
  my $n = $self->CountMarcDatafields($id, '700', $record);
  foreach my $i (1 .. $n)
  {
    my $data = $self->GetRecordSubfields($id, '700', $record, $i, 'a', 'b', 'c', 'd');
    push @aus, $data if defined $data;
  }
  $n = $self->CountMarcDatafields($id, '710', $record);
  foreach my $i (1 .. $n)
  {
    my $data = $self->GetRecordSubfields($id, '710', $record, $i, 'a', 'b');
    push @aus, $data if defined $data;
  }
  return @aus;
}

sub GetRecordSubfields
{
  my $self   = shift;
  my $id     = shift;
  my $field  = shift;
  my $record = shift;
  my $index  = shift;
  my @subfields = @_;

  my $data = undef;
  foreach my $subfield (@subfields)
  {
    my $data2 = $self->GetMarcDatafield($id, $field, $subfield, $record, $index);
    $data2 =~ s/(^\s+)|(\s+$)//g if $data2;
    $data .= ' ' . $data2 if $data2;
  }
  if (defined $data)
  {
    $data =~ s/\n+//gs;
    $data =~ s/\s*[,:;]*\s*$//;
    $data =~ s/^\s+//;
  }
  return $data;
}

# Removes paren/brace/brack and backslash-escape single quote
sub GetEncTitle
{
  my $self = shift;
  my $bar  = shift;

  my $ti = $self->GetTitle($bar);
  $ti =~ s,\',\\\',g; ## escape '
  $ti =~ s/[()[\]{}]//g;
  return $ti;
}

sub GetTitle
{
  my $self = shift;
  my $id   = shift;

  my $ti = $self->SimpleSqlGet("SELECT title FROM bibdata WHERE id='$id'");
  if (!$ti)
  {
    $self->UpdateMetadata($id, 1);
    $ti = $self->SimpleSqlGet("SELECT title FROM bibdata WHERE id='$id'");
  }
  return $ti;
}

sub GetRecordTitle
{
  my $self   = shift;
  my $id     = shift;
  my $record = shift;

  $record = $self->GetMetadata($id) unless $record;
  my $xpath = "//*[local-name()='datafield' and \@tag='245']/*[local-name()='subfield' and \@code='a']";
  my $title = '';
  eval{ $title = $record->findvalue($xpath); };
  if ($@) { $self->Logit("failed to parse metadata for $id: $@"); }
  # Get rid of trailing punctuation
  $title =~ s/\s*([:\/,;]*\s*)+$// if $title;
  return $title;
}

sub GetPubDate
{
  my $self = shift;
  my $id   = shift;
  my $do2  = shift;

  my $sql = "SELECT YEAR(pub_date) FROM bibdata WHERE id='$id'";
  my $date = $self->SimpleSqlGet($sql);
  if (!$date)
  {
    $self->UpdateMetadata($id, 1);
    $date = $self->SimpleSqlGet($sql);
  }
  if ($date && $do2)
  {
    my $date2 = $self->GetRecordPubDate($id, undef, 1);
    $date = "$date-$date2" if $date2 && $date2 =~ m/^\d\d\d\d$/ && $date2 > $date && $date2 <= $self->GetTheYear();
  }
  return $date;
}

sub GetPubCountry
{
  my $self = shift;
  my $id   = shift;

  my $sql = "SELECT country FROM bibdata WHERE id='$id'";
  my $date = $self->SimpleSqlGet($sql);
  if (!$date)
  {
    $self->UpdateMetadata($id, 1);
    $date = $self->SimpleSqlGet($sql);
  }
  return $date;
}

sub GetEncAuthor
{
  my $self = shift;
  my $id   = shift;

  my $au = $self->GetEncAuthorForReview($id);
  $au =~ s,\",\\\",g; ## escape "
  return $au;
}

sub GetEncAuthorForReview
{
  my $self = shift;
  my $id   = shift;

  my $au = $self->GetAuthor($id);
  $au =~ s/\'/\\\'/g; ## escape '
  return $au;
}

sub GetAuthor
{
  my $self = shift;
  my $id   = shift;

  my $au = $self->SimpleSqlGet('SELECT author FROM bibdata WHERE id=?', $id);
  if (!$au)
  {
    $self->UpdateMetadata($id, 1);
    $au = $self->SimpleSqlGet('SELECT author FROM bibdata WHERE id=?', $id);
  }
  #$au =~ s,(.*[A-Za-z]).*,$1,;
  $au =~ s/^[([{]+(.*?)[)\]}]+\s*$/$1/;
  return $au;
}

## ----------------------------------------------------------------------------
##  Function:   get the metadata record (MARC21)
##  Parameters: volume id or system id
##  Return:     XML::LibXML record doc
## ----------------------------------------------------------------------------
sub GetMetadata
{
  my $self   = shift;
  my $id     = shift;
  my $osysid = shift;

  if (!$id) { $self->SetError("GetMetadata: no id given: '$id'"); return; }
  #return $self->get($id) if $self->get($id);
  # If it has a period, it's a volume ID
  my $url = ($id =~ m/\./)? "http://catalog.hathitrust.org/api/volumes/full/htid/$id.json" :
                            "http://catalog.hathitrust.org/api/volumes/full/recordnumber/$id.json";
  my $ua = LWP::UserAgent->new;
  $ua->timeout(1000);
  my $req = HTTP::Request->new(GET => $url);
  my $res = $ua->request($req);
  if (!$res->is_success)
  {
    $self->SetError($url . ' failed: ' . $res->message());
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
      $$osysid = $keys[0] if $osysid;
      $xml = $records->{$keys[0]}->{'marc-xml'};
    }
    else { $self->SetError("HT Bib API found no data for '$id' (got '$content')"); return; }
  };
  if ($@) { $self->SetError("failed to parse ($content) for $id:$@"); return; }
  my $parser = $self->get('parser');
  if (!$parser)
  {
    $parser = XML::LibXML->new();
    $self->set('parser',$parser);
  }
  my $source;
  eval {
    $source = $parser->parse_string($xml);
  };
  if ($@) { $self->SetError("failed to parse ($xml) for $id: $@"); return; }
  my $xpc = XML::LibXML::XPathContext->new($source);
  my $ns = 'http://www.loc.gov/MARC21/slim';
  $xpc->registerNs(ns => $ns);
  my @records = $xpc->findnodes('//ns:record');
  #$self->set($id,$records[0]);
  return $records[0];
}

# Update sysid and author,title,pubdate fields in bibdata.
# Only updates existing rows (does not INSERT) unless the force param is set.
sub UpdateMetadata
{
  my $self   = shift;
  my $id     = shift;
  my $force  = shift;
  my $record = shift;

  if (!defined $id)
  {
    $self->SetError("Trying to update metadata for empty volume id!\n");
    return;
  }
  my $cnt = $self->SimpleSqlGet('SELECT COUNT(*) FROM bibdata WHERE id=?', $id);
  if ($cnt || $force)
  {
    $self->PrepareSubmitSql('INSERT INTO bibdata (id) VALUES (?)', $id) unless $cnt > 0;
    my $sysid = $self->BarcodeToId($id, 1);
    if ($sysid)
    {
      $record = $self->GetMetadata($id) unless defined $record;
      my $title = $self->GetRecordTitle($id, $record);
      my $author = $self->GetRecordAuthor($id, $record);
      my $date = $self->GetRecordPubDate($id, $record) . '-01-01';
      my $country = $self->GetRecordPubCountry($id, $record);
      my $sql = 'UPDATE bibdata SET author=?,title=?,pub_date=?,country=? WHERE id=?';
      $self->PrepareSubmitSql($sql, $author, $title, $date, $country, $id);
    }
  }
  return $record;
}

# Get the usRightsString field of the item record for the
# given volume id from the HT Bib API.
sub GetRightsString
{
  my $self = shift;
  my $id   = shift;

  if (!$id) { $self->SetError("GetRightsString: no id given: '$id'"); return; }
  # If it has a period, it's a volume ID
  my $url = "http://catalog.hathitrust.org/api/volumes/brief/htid/$id.json";
  my $ua = LWP::UserAgent->new;
  $ua->timeout(1000);
  my $req = HTTP::Request->new(GET => $url);
  my $res = $ua->request($req);
  if (!$res->is_success)
  {
    $self->SetError($url . ' failed: ' . $res->message());
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
  if ($@) { $self->SetError("failed to parse ($content) for $id:$@"); return; }
  return $rightsString;
}

## ----------------------------------------------------------------------------
##  Function:   get the mirlyn ID for a given volume id using the HT Bib API
##              update local system table if necessary.
##  Parameters: volume id, force to get from metadata bypassing system table
##  Return:     system id
## ----------------------------------------------------------------------------
sub BarcodeToId
{
  my $self  = shift;
  my $id    = shift;
  my $force = shift;

  my $sysid = undef;
  my $sql = 'SELECT sysid FROM system WHERE id=?';
  $sysid = $self->SimpleSqlGet($sql, $id) unless $force;
  if (!$sysid)
  {
    my $url = "http://catalog.hathitrust.org/api/volumes/brief/htid/$id.json";
    my $ua = LWP::UserAgent->new;
    $ua->timeout(1000);
    my $req = HTTP::Request->new(GET => $url);
    my $res = $ua->request($req);
    if (!$res->is_success)
    {
      $self->SetError($url . ' failed: ' . $res->message());
      return;
    }
    my $content = $res->content;
    my $records = undef;
    eval {
      my $json = JSON::XS->new;
      $records = $json->decode($content)->{'records'};
    };
    if ($@ || !$records) { $self->SetError("failed to parse JSON for $id: $@"); return; }
    elsif ('HASH' eq ref $records)
    {
      my @keys = keys %$records;
      $sysid = $keys[0];
      if ($sysid && $self->get('nosystem') ne 'nosystem')
      {
        $sql = 'REPLACE INTO system (id,sysid) VALUES (?,?)';
        $self->PrepareSubmitSql($sql, $id, $sysid);
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

  return $self->SimpleSqlGet("SELECT $field FROM reviews WHERE id=? AND user=? LIMIT 1", $id, $user);
}

sub HasLockedItem
{
  my $self = shift;
  my $user = shift;

  my $sql = 'SELECT COUNT(*) FROM queue WHERE locked=? LIMIT 1';
  return ($self->SimpleSqlGet($sql, $user))? 1:0;
}

sub GetLockedItem
{
  my $self = shift;
  my $user = shift;

  my $sql = 'SELECT id FROM queue WHERE locked=? LIMIT 1';
  return $self->SimpleSqlGet($sql, $user);
}

sub IsLocked
{
  my $self = shift;
  my $id   = shift;

  my $sql = 'SELECT id FROM queue WHERE locked IS NOT NULL AND id=?';
  return ($self->SimpleSqlGet($sql, $id))? 1:0;
}

sub IsLockedForUser
{
  my $self = shift;
  my $id   = shift;
  my $user = shift;

  my $sql = 'SELECT COUNT(*) FROM queue WHERE id=? AND locked=?';
  return 1 == $self->SimpleSqlGet($sql, $id, $user);
}

sub IsLockedForOtherUser
{
  my $self = shift;
  my $id   = shift;
  my $user = shift;

  $user = $self->get('user') unless $user;
  my $lock = $self->SimpleSqlGet('SELECT locked FROM queue WHERE id=?', $id);
  return ($lock && $lock ne $user);
}

sub RemoveOldLocks
{
  my $self = shift;
  my $time = shift;

  # By default, GetPrevDate() returns the date/time 24 hours ago.
  $time = $self->GetPrevDate($time);
  my $lockedRef = $self->GetLockedItems();
  foreach my $item (keys %{$lockedRef})
  {
    my $id = $lockedRef->{$item}->{id};
    my $user = $lockedRef->{$item}->{locked};
    my $since = $self->ItemLockedSince($id, $user);
    my $sql = 'SELECT id FROM queue WHERE id=? AND time<?';
    my $old = $self->SimpleSqlGet($sql, $id, $time);
    if ($old)
    {
      #$self->Logit("REMOVING OLD LOCK:\t$id, $user: $since | $time");
      $self->UnlockItem($id, $user);
    }
  }
}

sub PreviouslyReviewed
{
  my $self = shift;
  my $id   = shift;
  my $user = shift;

  ## expert reviewers can edit any time
  return 0 if $self->IsUserExpert($user);
  my $limit = $self->GetYesterday();
  my $sql = 'SELECT id FROM reviews WHERE id=? AND user=? AND time<? AND hold IS NULL';
  my $found = $self->SimpleSqlGet($sql, $id, $user, $limit);
  return ($found)? 1:0;
}

# Returns 0 on success, error message on error.
sub LockItem
{
  my $self     = shift;
  my $id       = shift;
  my $user     = shift;
  my $override = shift;

  ## if already locked for this user, that's OK
  return 0 if $self->IsLockedForUser($id, $user);
  # Not locked for user, maybe someone else
  if ($self->IsLocked($id)) { return 'Volume has been locked by another user'; }
  ## can only have 1 item locked at a time (unless override)
  if (!$override)
  {
    my $locked = $self->HasLockedItem($user);
    return 0 if $locked eq $id; ## already locked
    return "You already have a locked item ($locked)." if $locked;
  }
  my $sql = 'UPDATE queue SET locked=? WHERE id=?';
  $self->PrepareSubmitSql($sql, $user, $id);
  $self->StartTimer($id, $user);
  return 0;
}

sub UnlockItem
{
  my $self = shift;
  my $id   = shift;
  my $user = shift;

  $user = $self->get('user') unless defined $user;
  my $sql = 'UPDATE queue SET locked=NULL WHERE id=? AND locked=?';
  $self->PrepareSubmitSql($sql, $id, $user);
  $self->RemoveFromTimer($id, $user);
}

sub UnlockItemEvenIfNotLocked
{
  my $self = shift;
  my $id   = shift;
  my $user = shift;

  my $sql = 'UPDATE queue SET locked=NULL WHERE id=?';
  if (!$self->PrepareSubmitSql($sql, $id)) { return 0; }
  $self->RemoveFromTimer($id, $user);
  return 1;
}

sub UnlockAllItemsForUser
{
  my $self = shift;
  my $user = shift;

  $self->PrepareSubmitSql('UPDATE queue SET locked=NULL WHERE locked=?', $user);
  $self->PrepareSubmitSql('DELETE FROM timer WHERE user=?', $user);
}

sub GetLockedItems
{
  my $self = shift;
  my $user = shift;

  my $restrict = ($user)? "='$user'":'IS NOT NULL';
  my $sql = "SELECT id, locked FROM queue WHERE locked $restrict";
  my $ref = $self->GetDb()->selectall_arrayref($sql);
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

  my $sql = 'SELECT start_time FROM timer WHERE id=? AND user=?';
  return $self->SimpleSqlGet($sql, $id, $user);
}

sub StartTimer
{
  my $self = shift;
  my $id   = shift;
  my $user = shift;

  my $sql = 'REPLACE INTO timer SET start_time=NOW(), id=?, user=?';
  $self->PrepareSubmitSql($sql, $id, $user);
}

sub EndTimer
{
  my $self = shift;
  my $id   = shift;
  my $user = shift;

  my $sql = 'UPDATE timer SET end_time=NOW() WHERE id=? AND user=?';
  if (!$self->PrepareSubmitSql($sql, $id, $user)) { return 0; }
  ## add duration to reviews table
  $self->SetDuration($id, $user);
}

sub RemoveFromTimer
{
  my $self = shift;
  my $id   = shift;
  my $user = shift;

  ## clear entry in table
  my $sql = 'DELETE FROM timer WHERE id=? AND user=?';
  $self->PrepareSubmitSql($sql, $id, $user);
}

sub GetDuration
{
  my $self = shift;
  my $id   = shift;
  my $user = shift;

  my $sql = 'SELECT duration FROM reviews WHERE user=? AND id=?';
  return $self->SimpleSqlGet($sql, $user, $id);
}

sub SetDuration
{
  my $self = shift;
  my $id   = shift;
  my $user = shift;

  my $sql = 'SELECT TIMEDIFF(end_time,start_time) FROM timer where id=? AND user=?';
  my $dur = $self->SimpleSqlGet($sql, $id, $user);
  if ($dur)
  {
    ## insert time
    $sql = 'UPDATE reviews SET duration=ADDTIME(duration,?),time=time WHERE user=? AND id=?';
    $self->PrepareSubmitSql($sql, $dur, $user, $id);
  }
  $self->RemoveFromTimer($id, $user);
}

sub HasItemBeenReviewedByAnotherExpert
{
  my $self = shift;
  my $id   = shift;
  my $user = shift;

  my $stat = $self->GetStatus($id) ;
  if ($stat == 5 || $stat == 7)
  {
    my $sql = 'SELECT COUNT(*) FROM reviews WHERE id=? AND user=?';
    my $count = $self->SimpleSqlGet($sql, $id, $user);
    return ($count)? 0:1;
  }
  return 0;
}

sub HasItemBeenReviewedByUser
{
  my $self = shift;
  my $id   = shift;
  my $user = shift;

  my $sql = 'SELECT COUNT(*) FROM reviews WHERE id=? AND user=?';
  my $count = $self->SimpleSqlGet($sql, $id, $user);
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
  my $err = undef;
  my $sql = undef;
  eval{
    $sql = 'LOCK TABLES queue WRITE, queue AS q WRITE, reviews READ, reviews AS r READ, users READ, timer WRITE, systemvars READ';
    $self->PrepareSubmitSql($sql);
    my $exclude = 'q.priority<3 AND ';
    if ($self->IsUserAdmin($user))
    {
      # Only admin+ reviews P4+
      $exclude = '';
    }
    # If user is expert, get priority 3 items.
    elsif ($self->IsUserExpert($user))
    {
      $exclude = 'q.priority<4 AND ';
    }
    my $p1f = $self->GetPriority1Frequency();
    # Exclude priority 1 if our d100 roll is over the P1 threshold or user is not advanced
    my $exclude1 = (rand() >= $p1f || !$self->IsUserAdvanced($user))? 'q.priority!=1 AND ':'';
    $sql = 'SELECT q.id,(SELECT COUNT(*) FROM reviews r WHERE r.id=q.id) AS cnt FROM queue q' .
           ' WHERE ' . $exclude . $exclude1 . 'q.expcnt=0 AND q.locked IS NULL' .
           ' ORDER BY q.priority DESC, cnt DESC, q.time ASC';
    #print "$sql<br/>\n";
    my $ref = $self->GetDb()->selectall_arrayref($sql);
    foreach my $row (@{$ref})
    {
      my $id2 = $row->[0];
      my $cnt = $row->[1];
      $sql = 'SELECT COUNT(*) FROM reviews WHERE id=?';
      next if 1 < $self->SimpleSqlGet($sql, $id2);
      $sql = 'SELECT COUNT(*) FROM reviews WHERE id=? AND user=?';
      next if 0 < $self->SimpleSqlGet($sql, $id2, $user);
      $err = $self->LockItem($id2, $user);
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
    $err = sprintf "Could not get a volume for $user to review%s.", ($err)? " ($err)":'';
    $err .= "\n$sql" if $sql;
    $self->SetError($err);
  }
  return $id;
}

# Alternate single-query version that needs extensive testing
# before replacing the above version.
sub GetNextItemForReviewSQ
{
  my $self = shift;
  my $user = shift;
  
  my $id = undef;
  my $err = undef;
  my $sql = undef;
  eval{
    $sql = 'LOCK TABLES queue WRITE, queue AS q WRITE, reviews READ, reviews AS r READ,' .
           ' reviews AS r2 READ, users READ, timer WRITE, systemvars READ';
    $self->PrepareSubmitSql($sql);
    my $exclude = 'q.priority<3 AND ';
    if ($self->IsUserAdmin($user))
    {
      # Only admin+ reviews P4+
      $exclude = '';
    }
    # If user is expert, get priority 3 items.
    elsif ($self->IsUserExpert($user))
    {
      $exclude = 'q.priority<4 AND ';
    }
    my $p1f = $self->GetPriority1Frequency();
    # Exclude priority 1 if our d100 roll is over the P1 threshold or user is not advanced
    my $exclude1 = (rand() >= $p1f || !$self->IsUserAdvanced($user))? 'q.priority!=1 AND ':'';
    $sql = 'SELECT q.id,(SELECT COUNT(*) FROM reviews r WHERE r.id=q.id) AS cnt' .
           ' FROM queue q WHERE ' . $exclude . $exclude1 . 'q.expcnt=0 AND q.locked IS NULL' .
           ' AND NOT EXISTS (SELECT * FROM reviews r2 WHERE r2.id=q.id AND r2.user=?)' .
           ' HAVING cnt<2 ORDER BY q.priority DESC, cnt DESC, q.time ASC';
    #print "$sql<br/>\n";
    my $ref = $self->GetDb()->selectall_arrayref($sql, undef, $user);
    foreach my $row (@{$ref})
    {
      my $id2 = $row->[0];
      $err = $self->LockItem($id2, $user);
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
    $err = sprintf "Could not get a volume for $user to review%s.", ($err)? " ($err)":'';
    $err .= "\n$sql" if $sql;
    $self->SetError($err);
  }
  return $id;
}

sub GetPriority1Frequency
{
  my $self = shift;
  
  return $self->GetSystemVar('priority1Frequency', 0.3, '$_>=0.0 and $_<1.0');
}

sub TranslateAttr
{
  my $self = shift;
  my $a    = shift;
  
  my $sql = "SELECT id FROM attributes WHERE name='$a'";
  $sql = "SELECT name FROM attributes WHERE id=$a" if $a =~ m/[0-9]+/;
  my $val = $self->SimpleSqlGetSDR($sql);
  if (!$val)
  {
    my %t1 = (1  => 'pd',       2  => 'ic',          3  => 'op',        4  => 'orph',        5  => 'und',
              6  => 'umall',    7  => 'ic-world',    8  => 'nobody',    9  => 'pdus',        10 => 'cc-by',
              11 => 'cc-by-nd', 12 => 'cc-by-nc-nd', 13 => 'cc-by-nc',  14 => 'cc-by-nc-sa', 15 => 'cc-by-sa',
              16 => 'orphcand', 17 => 'cc-zero',     18 => 'und-world', 19 => 'icus');
    my %t2 = ('pd'       => 1,  'ic'          => 2,  'op'        => 3,  'orph'        => 4,  'und'      => 5,
              'umall'    => 6,  'ic-world'    => 7,  'nobody'    => 8,  'pdus'        => 9,  'cc-by'    => 10,
              'cc-by-nd' => 11, 'cc-by-nc-nd' => 12, 'cc-by-nc'  => 13, 'cc-by-nc-sa' => 14, 'cc-by-sa' => 15,
              'orphcand' => 16, 'cc-zero'     => 17, 'und-world' => 18, 'icus'        => 19);
    $val = ($a =~ m/[0-9]+/)? $t1{$a}:$t2{$a};
  }
  $a = $val if $val;
  return $a;
}

sub TranslateReason
{
  my $self = shift;
  my $r    = shift;
  
  my $sql = "SELECT id FROM reasons WHERE name='$r'";
  $sql = "SELECT name FROM reasons WHERE id=$r" if $r =~ m/[0-9]+/;
  my $val = $self->SimpleSqlGetSDR($sql);
  if (!$val)
  {
    my %t1 = ( 1  => 'bib', 2   => 'ncn', 3  => 'con',  4  => 'ddd',  5  => 'man', 6  => 'pvt',
               7  => 'ren', 8   => 'nfi', 9  => 'cdpp', 10 => 'ipma', 11 => 'unp', 12 => 'gfv',
               13 => 'crms', 14 => 'add', 15 => 'exp',  16 => 'del',  17 => 'gatt');
    my %t2 = ('bib'  => 1,  'ncn' => 2,  'con'  => 3,  'ddd'  => 4,  'man'  => 5,  'pvt' => 6,
              'ren'  => 7,  'nfi' => 8,  'cdpp' => 9,  'ipma' => 10, 'unp'  => 11, 'gfv' => 12,
              'crms' => 13, 'add' => 14, 'exp'  => 15, 'del'  => 16, 'gatt' => 17);
    $val = ($r =~ m/[0-9]+/)? $t1{$r}:$t2{$r};
  }
  $r = $val if $val;
  return $r;
}

sub GetRenDate
{
  my $self = shift;
  my $id   = shift;

  $id =~ s, ,,gs;
  my $sql = 'SELECT DREG FROM stanford WHERE ID=?';
  return $self->SimpleSqlGet($sql, $id);
}

sub GetPrevDate
{
  my $self = shift;
  my $prev = shift;

  ## default 1 day (86,400 sec.)
  if (!$prev) { $prev = 86400; }

  my @p = localtime(time() - $prev);
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
    my @p = localtime(time());
    $p[4] = ($p[4]+1);
    $p[5] = ($p[5]+1900);
    foreach (0,1,2,3,4) { $p[$_] = sprintf("%0*d", "2", $p[$_]); }

    ## DB format (YYYY-MM-DD HH:MM:SS)
    return "$p[5]-$p[4]-$p[3] $p[2]:$p[1]:$p[0]";
}

sub OpenErrorLog
{
  my $self = shift;
  my $logFile = $self->get('logFile');

  if ($logFile)
  {
    open(my $fh, ">>", $logFile);
    if (!defined $fh) { die "failed to open log: $logFile \n"; }
    my $oldfh = select($fh); $| = 1; select($oldfh); ## flush out
    $self->set('logFh', $fh);
  }
}

sub CloseErrorLog
{
  my $self = shift;
  
  my $fh = $self->get('logFh');
  close $fh if $fh;
}

sub Logit
{
  my $self = shift;
  my $str  = shift;

  $self->OpenErrorLog();

  my $date = $self->GetTodaysDate();
  my $fh = $self->get('logFh');
  if ($fh)
  {
    print $fh "$date: $str\n";
    $self->CloseErrorLog();
  }
}

## ----------------------------------------------------------------------------
##  Function:   add to and get errors
##              $self->SetError("foo");
##              my $r = $self->GetErrors();
##              if (defined $r) { $self->Logit(join(", ", @{$r})); }
##  Parameters: 
##  Return:     
## ----------------------------------------------------------------------------
sub SetError
{
  my $self   = shift;
  my $error  = shift;

  $error .= "\n";
  $error .= $self->StackTrace();
  my $errors = $self->get('errors');
  push @{$errors}, $error;
}

sub GetErrors
{
    my $self = shift;
    return $self->get('errors');
}

# The cgi footer prints all errors. If already processed and displayed, no need to repeat.
sub ClearErrors
{
  my $self = shift;
  
  my $errors = [];
  $self->set('errors', $errors);
}

sub GetQueueSize
{
  my $self     = shift;
  my $priority = shift;

  my $restrict = (defined $priority)? "WHERE priority=$priority":'';
  my $sql = "SELECT COUNT(*) FROM queue $restrict";
  return $self->SimpleSqlGet($sql);
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
  my $dbh = $self->GetDb();
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
    my $sql = "SELECT COUNT(*) FROM queue $statusClause";
    my $count = $self->SimpleSqlGet($sql);
    $status = 'All' if $status == -1;
    my $class = ($status eq 'All')?' class="total"':'';
    $class = ' style="background-color:#999999;"' if $status == 6;
    $report .= sprintf("<tr><td%s>$status%s</td><td%s>$count</td>", $class, ($status == 6)? '*':'', $class);
    $sql = "SELECT priority FROM queue $statusClause";
    my $ref = $dbh->selectall_arrayref($sql);
    $report .= $self->DoPriorityBreakdown($ref,$class,\@pris);
    $report .= "</tr>\n";
  }
  my $sql = "SELECT priority FROM queue WHERE status=0 AND id NOT IN (SELECT id FROM reviews)";
  my $ref = $dbh->selectall_arrayref($sql);
  my $count = $self->GetTotalAwaitingReview();
  my $class = ' class="major"';
  $report .= sprintf("<tr><td%s>Not&nbsp;Yet&nbsp;Active</td><td%s>$count</td>", $class, $class);
  $report .= $self->DoPriorityBreakdown($ref,$class,\@pris);
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
  my ($time,$n) = $self->GetLastQueueInfo();
  if ($time)
  {
    $time =~ s/\s/&nbsp;/g;
    $n = $n . '&nbsp;(' . $time . ')';
  }
  else
  {
    $n = 'n/a';
  }
  $report .= '<tr><th>Last&nbsp;Queue&nbsp;Update</th><td>' . $n . "</td></tr>\n";
  $report .= sprintf("<tr><th>Cumulative&nbsp;Volumes&nbsp;in&nbsp;Queue&nbsp;(ever*)</th><td>%s</td></tr>\n", $self->GetTotalEverInQueue());
  $report .= sprintf("<tr><th>Volumes&nbsp;in&nbsp;Candidates</th><td>%s</td></tr>\n", $self->GetCandidatesSize());
  $time = $self->GetLastLoadTimeToCandidates();
  $n = $self->GetLastLoadSizeToCandidates();
  if ($time)
  {
    $time =~ s/\s/&nbsp;/g;
    $n = $n . '&nbsp;(' . $time . ')';
  }
  else
  {
    $n = 'n/a';
  }
  $report .= '<tr><th>Last&nbsp;Candidates&nbsp;Update</th><td>' . $n . "</td></tr>";
  my $count = $self->SimpleSqlGet('SELECT COUNT(*) FROM und WHERE src!="no meta" AND src!="duplicate"');
  $report .= "<tr><th>Volumes&nbsp;Filtered**</th><td>$count</td></tr>\n";
  if ($count)
  {
    my $ref = $self->GetDb()->selectall_arrayref('SELECT src,COUNT(src) FROM und WHERE src!="no meta" AND src!="duplicate" GROUP BY src ORDER BY src');
    foreach my $row (@{ $ref})
    {
      my $src = $row->[0];
      $n = $row->[1];
      $report .= sprintf("<tr><th>&nbsp;&nbsp;&nbsp;&nbsp;$src</th><td>$n&nbsp;(%0.1f%%)</td></tr>\n", 100.0*$n/$count);
    }
  }
  my $count = $self->SimpleSqlGet('SELECT COUNT(*) FROM und WHERE src="no meta" OR src="duplicate"');
  $report .= "<tr><th>Volumes&nbsp;Temporarily&nbsp;Filtered**</th><td>$count</td></tr>\n";
  if ($count)
  {
    my $ref = $self->GetDb()->selectall_arrayref('SELECT src,COUNT(src) FROM und WHERE src="no meta" OR src="duplicate" GROUP BY src ORDER BY src');
    foreach my $row (@{ $ref})
    {
      my $src = $row->[0];
      $n = $row->[1];
      $report .= "<tr><th>&nbsp;&nbsp;&nbsp;&nbsp;$src</th><td>$n</td></tr>\n";
    }
  }
  my $host = $self->Hostname();
  my ($delay,$since) = $self->ReplicationDelay();
  my $alert = $delay >= 5;
  if ($delay == 999999)
  {
    $delay = 'Disabled';
  }
  else
  {
    $delay .= '&nbsp;' . $self->Pluralize('second', $delay);
  }
  $delay = "<span style='color:#CC0000;font-weight:bold;'>$delay&nbsp;since&nbsp;$since</span>" if $alert;
  $report .= "<tr><th>Database&nbsp;Replication&nbsp;Delay</th><td>$delay&nbsp;on&nbsp;$host</td></tr>\n";
  $report .= '<tr><td colspan="2">';
  $report .= '<span class="smallishText">* Not including legacy data (reviews/determinations made prior to July 2009).</span><br/>';
  $report .= '<span class="smallishText">** This number is not included in the "Volumes in Candidates" count above.</span>';
  $report .= "</td></tr></table>\n";
  return $report;
}

sub CreateDeterminationReport
{
  my $self = shift;

  my $dbh = $self->GetDb();
  my ($count,$time) = $self->GetLastExport();
  my %cts = ();
  my %pcts = ();
  my $priheaders = '';
  my $sql = 'SELECT DISTINCT h.priority FROM exportdata e INNER JOIN historicalreviews h ON e.gid=h.gid' .
            ' WHERE e.time>=date_sub(?, INTERVAL 1 MINUTE) ORDER BY h.priority ASC';
  my @pris = map {$_->[0]} @{ $dbh->selectall_arrayref($sql, undef, $time) };
  $sql = 'SELECT COUNT(DISTINCT h.id) FROM exportdata e, historicalreviews h' .
         ' WHERE e.gid=h.gid AND e.time>=date_sub(?, INTERVAL 1 MINUTE)';
  my $total = $self->SimpleSqlGet($sql, $time);
  foreach my $pri (@pris)
  {
    $pri = $self->StripDecimal($pri);
    $priheaders .= "<th>Priority&nbsp;$pri</th>";
  }
  my $report = "<table class='exportStats'>\n<tr><th/><th>Total</th>$priheaders</tr>\n";
  foreach my $status (4 .. 9)
  {
    $sql = 'SELECT COUNT(DISTINCT h.id) FROM exportdata e, historicalreviews h' .
          ' WHERE e.gid=h.gid AND h.status=? AND e.time>=date_sub(?, INTERVAL 1 MINUTE)';
    my $ct = $self->SimpleSqlGet($sql, $status, $time);
    my $pct = 0.0;
    eval {$pct = 100.0*$ct/$total;};
    $cts{$status} = $ct;
    $pcts{$status} = $pct;
  }
  my $colspan = 1 + scalar @pris;
  my $legacy = $self->GetTotalLegacyCount();
  my %sources;
  $sql = 'SELECT src,COUNT(gid) FROM exportdata WHERE src IS NOT NULL GROUP BY src';
  my $rows = $dbh->selectall_arrayref($sql);
  foreach my $row (@{$rows})
  {
    $sources{ $row->[0] } = $row->[1];
  }
  my ($count2,$time2) = $self->GetLastExport(1);
  $time2 =~ s/\s/&nbsp;/g;
  $count = 'None' unless $count;
  $time = 'record' unless $time2;
  my $exported = $self->SimpleSqlGet('SELECT COUNT(DISTINCT gid) FROM exportdata');
  $report .= "<tr><th>Last&nbsp;CRMS&nbsp;Export</th><td colspan='$colspan'>$time2</td></tr>";
  foreach my $status (sort keys %cts)
  {
    my $thstyle = ($status == 6)? " style='color:#999999;'":'';
    my $tdstyle = ($status == 6)? " style='background-color:#999999;'":'';
    $report .= sprintf("<tr><th$thstyle>&nbsp;&nbsp;&nbsp;&nbsp;Status&nbsp;%d</th><td $tdstyle>%d&nbsp;(%.1f%%)</td>",
                       $status, $cts{$status}, $pcts{$status});
    $sql = 'SELECT h.priority,h.gid FROM exportdata e INNER JOIN historicalreviews h ON e.gid=h.gid ' .
           "WHERE h.status=$status AND e.time>=date_sub('$time', INTERVAL 1 MINUTE)";
    my $ref = $dbh->selectall_arrayref($sql);
    #print "$sql<br/>\n";
    $report .= $self->DoPriorityBreakdown($ref, $tdstyle, \@pris, $cts{$status});
    $report .= '</tr>';
  }
  $report .= "<tr><th>&nbsp;&nbsp;&nbsp;&nbsp;Total</th><td>$count</td>";
  $sql = 'SELECT h.priority,h.gid FROM exportdata e INNER JOIN historicalreviews h ON e.gid=h.gid' .
         ' WHERE e.time>=date_sub(?, INTERVAL 1 MINUTE)';
  my $ref = $dbh->selectall_arrayref($sql, undef, $time);
  #print "$sql<br/>\n";
  $report .= $self->DoPriorityBreakdown($ref, '', \@pris, $count);
  $report .= '</tr>';
  $report .= sprintf("<tr><th>Total&nbsp;CRMS&nbsp;Determinations</th><td colspan='$colspan'>%s</td></tr>", $exported);
  foreach my $source (sort keys %sources)
  {
    my $n = $sources{$source};
    $report .= sprintf("<tr><th>&nbsp;&nbsp;&nbsp;&nbsp;%s</th><td colspan='$colspan'>$n</td></tr>", $self->ExportSrcToEnglish($source));
  }
  $report .= sprintf("<tr><th>Total&nbsp;Legacy&nbsp;Determinations</th><td colspan='$colspan'>%s</td></tr>", $legacy);
  $report .= sprintf("<tr><th>Total&nbsp;Determinations</th><td colspan='$colspan'>%s</td></tr>", $exported + $legacy);
  $report .= sprintf("<tr><td colspan='%d'><span class='smallishText'>* Status 6 no longer in use as of 4/19/2010.</span></td></tr>\n", $colspan+1);
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
  my $dbh = $self->GetDb();
  
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
  my $ref = $dbh->selectall_arrayref($sql);
  my $count = scalar @{$ref};
  $report .= "<tr><td class='total'>Active</td><td class='total'>$count</td>";
  $report .= $self->DoPriorityBreakdown($ref,' class="total"',\@pris) . "</tr>\n";
  
  # Unprocessed
  $sql = 'SELECT priority FROM queue WHERE status=0 AND pending_status>0';
  $ref = $dbh->selectall_arrayref($sql);
  $count = scalar @{$ref};
  $report .= "<tr><td class='minor'>Unprocessed</td><td class='minor'>$count</td>";
  $report .= $self->DoPriorityBreakdown($ref,' class="minor"',\@pris) . "</tr>\n";
  
  # Unprocessed - single review
  $sql = 'SELECT priority from queue WHERE status=0 AND pending_status=1';
  $ref = $dbh->selectall_arrayref($sql);
  $count = scalar @{$ref};
  $report .= "<tr><td>&nbsp;&nbsp;&nbsp;Single&nbsp;Review</td><td>$count</td>";
  $report .= $self->DoPriorityBreakdown($ref,undef,\@pris) . "</tr>\n";
  
  # Unprocessed - match
  $sql = 'SELECT priority from queue WHERE status=0 AND pending_status=4';
  $ref = $dbh->selectall_arrayref($sql);
  $count = scalar @{$ref};
  $report .= "<tr><td>&nbsp;&nbsp;&nbsp;Match</td><td>$count</td>";
  $report .= $self->DoPriorityBreakdown($ref,undef,\@pris) . "</tr>\n";
  
  # Unprocessed - conflict
  $sql = 'SELECT priority from queue WHERE status=0 AND pending_status=2';
  $ref = $dbh->selectall_arrayref($sql);
  $count = scalar @{$ref};
  $report .= "<tr><td>&nbsp;&nbsp;&nbsp;Conflict</td><td>$count</td>";
  $report .= $self->DoPriorityBreakdown($ref,undef,\@pris) . "</tr>\n";
  
  # Unprocessed - provisional match
  $sql = 'SELECT priority from queue WHERE status=0 AND pending_status=3';
  $ref = $dbh->selectall_arrayref($sql);
  $count = scalar @{$ref};
  $report .= "<tr><td>&nbsp;&nbsp;&nbsp;Provisional&nbsp;Match</td><td>$count</td>";
  $report .= $self->DoPriorityBreakdown($ref,undef,\@pris) . "</tr>\n";
  
  # Unprocessed - auto-resolved
  $sql = 'SELECT priority from queue WHERE status=0 AND pending_status=8';
  $ref = $dbh->selectall_arrayref($sql);
  $count = scalar @{$ref};
  $report .= "<tr><td>&nbsp;&nbsp;&nbsp;Auto-Resolved</td><td>$count</td>";
  $report .= $self->DoPriorityBreakdown($ref,undef,\@pris) . "</tr>\n";
  
  # Inheriting
  $sql = 'SELECT COUNT(*) FROM queue WHERE status=9';
  my $s9count = $self->SimpleSqlGet($sql);
  $sql = 'SELECT COUNT(*) FROM inherit';
  $count = $s9count + $self->SimpleSqlGet($sql);
  $report .= sprintf("<tr class='inherit'><td>Can&nbsp;Inherit</td><td colspan='%d'>$count</td>", 1+scalar @pris);
  #$report .= "<td/>" for @pris;
  $report .= '</tr>';
  
  # Inheriting Automatically
  $sql = 'SELECT COUNT(*) FROM inherit WHERE del!=1 AND (reason=1 OR reason=12)';
  $count = $self->SimpleSqlGet($sql);
  $report .= sprintf("<tr><td>&nbsp;&nbsp;&nbsp;Automatically</td><td colspan='%d'>$count</td>", 1+scalar @pris);
  #$report .= "<td/>" for @pris;
  $report .= '</tr>';
  
  # Inheriting Pending Approval
  $sql = 'SELECT COUNT(*) FROM inherit WHERE del!=1 AND (reason!=1 AND reason!=12)';
  $count = $self->SimpleSqlGet($sql);
  $report .= sprintf("<tr><td>&nbsp;&nbsp;&nbsp;Pending&nbsp;Approval</td><td colspan='%d'>$count</td>", 1+scalar @pris);
  #$report .= "<td/>" for @pris;
  $report .= '</tr>';
  
  # Approved
  $report .= sprintf("<tr><td>&nbsp;&nbsp;&nbsp;Approved</td><td colspan='%d'>$s9count</td>", 1+scalar @pris);
  #$report .= "<td/>" for @pris;
  $report .= '</tr>';
  
  # Deleted
  $sql = 'SELECT COUNT(*) FROM inherit WHERE del=1';
  $count = $self->SimpleSqlGet($sql);
  $report .= sprintf("<tr><td>&nbsp;&nbsp;&nbsp;Deleted</td><td colspan='%d'>$count</td>", 1+scalar @pris);
  #$report .= "<td/>" for @pris;
  $report .= '</tr>';
  
  # Processed
  $sql = 'SELECT priority FROM queue WHERE status!=0';
  $ref = $dbh->selectall_arrayref($sql);
  $count = scalar @{$ref};
  $report .= "<tr><td class='minor'>Processed</td><td class='minor'>$count</td>";
  $report .= $self->DoPriorityBreakdown($ref,' class="minor"',\@pris) . "</tr>\n";
  
  $sql = 'SELECT priority from queue WHERE status=2';
  $ref = $dbh->selectall_arrayref($sql);
  $count = scalar @{$ref};
  $report .= "<tr><td>&nbsp;&nbsp;&nbsp;Conflict</td><td>$count</td>";
  $report .= $self->DoPriorityBreakdown($ref,'',\@pris) . "</tr>\n";

  $sql = 'SELECT priority from queue WHERE status=3';
  $ref = $dbh->selectall_arrayref($sql);
  $count = scalar @{$ref};
  $report .= "<tr><td>&nbsp;&nbsp;&nbsp;Provisional&nbsp;Match</td><td>$count</td>";
  $report .= $self->DoPriorityBreakdown($ref,'',\@pris) . "</tr>\n";
  
  $sql = 'SELECT priority from queue WHERE status>=4';
  $ref = $dbh->selectall_arrayref($sql);
  $count = scalar @{$ref};
  $report .= "<tr><td>&nbsp;&nbsp;&nbsp;Awaiting&nbsp;Export</td><td>$count</td>";
  $report .= $self->DoPriorityBreakdown($ref,'',\@pris) . "</tr>\n";
  
  if ($count > 0)
  {
    for my $status (4..9)
    {
      $sql = 'SELECT priority from queue WHERE status=?';
      $ref = $dbh->selectall_arrayref($sql, undef, $status);
      $count = scalar @{$ref};
      $report .= "<tr><td>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Status&nbsp;$status</td><td>$count</td>";
      $report .= $self->DoPriorityBreakdown($ref,'',\@pris) . "</tr>\n";
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
  my $pris  = shift;
  my $total = shift;

  my %breakdown;
  $breakdown{$_} = 0 for @{$pris};
  my %h = ();
  foreach my $row (@{$ref})
  {
    my $pri = $self->StripDecimal($row->[0]);
    if (scalar @{$row} > 1)
    {
      my $uvalue = $row->[1];
      next if $h{$uvalue};
      $h{$uvalue} = 1;
    }
    #print "Pri $pri<br/>\n";
    $breakdown{$pri}++;
  }
  my $bd = '';
  foreach my $key (sort keys %breakdown)
  {
    my $ct = $breakdown{$key};
    my $pct = '';
    if (defined $total)
    {
      $pct = 0.0;
      eval {$pct = 100.0*$ct/$total;};
      $pct = sprintf '&nbsp;(%.1f%%)', $pct;
    }
    $bd .= "<td$class>$ct$pct</td>";
  }
  #printf "%d priorities: %s <!-- $bd --><br/>\n"; scalar keys %breakdown, join ',', keys %breakdown;
  return $bd;
}

sub GetTotalAwaitingReview
{
  my $self = shift;

  my $sql = 'SELECT COUNT(id) FROM queue WHERE status=0 AND id NOT IN (SELECT DISTINCT id FROM reviews)';
  my $count = $self->SimpleSqlGet($sql);
  return ($count)? $count:0;
}

sub GetLastLoadSizeToCandidates
{
  my $self = shift;

  my $sql = 'SELECT addedamount FROM candidatesrecord ORDER BY time DESC LIMIT 1';
  return $self->SimpleSqlGet($sql);
}

sub GetLastLoadTimeToCandidates
{
  my $self = shift;

  my $sql = 'SELECT MAX(time) FROM candidatesrecord';
  return $self->FormatTime($self->SimpleSqlGet($sql));
}

sub GetTotalExported
{
  my $self = shift;

  my $sql = "SELECT SUM(itemcount) FROM exportrecord";
  return $self->SimpleSqlGet($sql);
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
  my $self     = shift;
  my $readable = shift;

  my $sql = "SELECT itemcount,time FROM exportrecord WHERE itemcount>0 ORDER BY time DESC LIMIT 1";
  my $ref = $self->GetDb()->selectall_arrayref($sql);
  my $count = $ref->[0]->[0];
  my $time = $ref->[0]->[1];
  $time = $self->FormatTime($time) if $readable;
  return ($count,$time);
}

sub GetTotalLegacyCount
{
  my $self = shift;

  my $sql = "SELECT COUNT(DISTINCT id) FROM historicalreviews WHERE legacy=1 AND priority!=1";
  return $self->SimpleSqlGet($sql);
}

sub GetTotalNonLegacyReviewCount
{
  my $self = shift;

  my $sql = 'SELECT COUNT(*) FROM historicalreviews WHERE legacy!=1';
  return $self->SimpleSqlGet($sql);
}

sub GetTotalLegacyReviewCount
{
  my $self = shift;

  my $sql = 'SELECT COUNT(*) FROM historicalreviews WHERE legacy=1';
  return $self->SimpleSqlGet($sql);
}

sub GetTotalHistoricalReviewCount
{
  my $self = shift;

  my $sql = 'SELECT COUNT(*) FROM historicalreviews';
  return $self->SimpleSqlGet($sql);
}

# Gets the (time,count) of last queue addition.
sub GetLastQueueInfo
{
  my $self = shift;
  
  my $sql = 'SELECT time,itemcount FROM queuerecord WHERE source="RIGHTSDB" ORDER BY time DESC LIMIT 1';
  my $row = $self->GetDb()->selectall_arrayref($sql)->[0];
  my $time = $self->FormatTime($row->[0]);
  my $cnt = $row->[1];
  $time = 'Never' unless $time;
  $cnt = 0 unless $cnt;
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
  my $buff = shift;

  if ($buff)
  {
    print &CGI::header(-type => 'text/plain', -charset => 'utf-8');
    print $buff;
  }
}

sub CountReviews
{
  my $self = shift;
  my $id   = shift;

  my $sql = 'SELECT COUNT(*) FROM reviews WHERE id=?';
  return $self->SimpleSqlGet($sql, $id);
}

sub CountReviewsForUser
{
  my $self = shift;
  my $user = shift;

  my $sql = 'SELECT COUNT(*) FROM reviews WHERE user=?';
  return $self->SimpleSqlGet($sql, $user);
}

sub CountHistoricalReviewsForUser
{
  my $self = shift;
  my $user = shift;
  my $year = shift;

  my $ysql = ($year)? ' AND time LIKE "' . $year . '%"':'';
  my $sql = 'SELECT COUNT(*) FROM historicalreviews WHERE user=?' . $ysql;
  return $self->SimpleSqlGet($sql, $user);
}

sub CountAllReviewsForUser
{
  my $self = shift;
  my $user = shift;

  my $sql = 'SELECT COUNT(*) FROM reviews WHERE user=?';
  my $n = $self->SimpleSqlGet($sql, $user);
  $sql = 'SELECT COUNT(*) FROM historicalreviews WHERE user=?';
  $n += $self->SimpleSqlGet($sql, $user);
  return $n;
}

sub IsReviewCorrect
{
  my $self = shift;
  my $id   = shift;
  my $user = shift;
  my $time = shift;
  
  # Has there ever been a swiss review for this volume?
  my $sql = 'SELECT COUNT(id) FROM historicalreviews WHERE id=? AND swiss=1';
  my $swiss = $self->SimpleSqlGet($sql, $id);
  # Get the review
  $sql = 'SELECT attr,reason,renNum,renDate,expert,status,time FROM historicalreviews' .
         " WHERE id=? AND user=? AND time LIKE '$time%'";
  my $r = $self->GetDb()->selectall_arrayref($sql, undef, $id, $user);
  my $row = $r->[0];
  my $attr    = $row->[0];
  my $reason  = $row->[1];
  my $renNum  = $row->[2];
  my $renDate = $row->[3];
  my $expert  = $row->[4];
  my $status  = $row->[5];
  my $time    = $row->[6];
  #print "$attr, $reason, $renNum, $renDate, $expert, $swiss, $status\n";
  # A non-expert with status 7/8 is protected rather like Swiss.
  return 1 if ($status == 7 && !$expert);
  return 1 if ($status == 8 && !$expert);
  # Get the most recent non-autocrms expert review.
  $sql = 'SELECT attr,reason,renNum,renDate,user,swiss FROM historicalreviews' .
         ' WHERE id=? AND expert>0 AND time>? ORDER BY time DESC';
  $r = $self->GetDb()->selectall_arrayref($sql, undef, $id, $time);
  return 1 unless scalar @{$r};
  $row = $r->[0];
  my $eattr    = $row->[0];
  my $ereason  = $row->[1];
  my $erenNum  = $row->[2];
  my $erenDate = $row->[3];
  my $euser    = $row->[4];
  my $eswiss   = $row->[5];
  #print "$eattr, $ereason, $erenNum, $erenDate, $euser, $eswiss\n";
  if ($attr != $eattr)
  {
    # A later status 8 might mismatch against a previous status 4.
    # It's OK if the reason is crms and the mismatch is und vs ic.
    return 1 if ($ereason == 13 && $attr == 2 && $eattr == 5);
    return (($swiss && !$expert) || ($eswiss && $euser eq 'autocrms'))? 2:0;
  }
  if ($reason != $ereason ||
      ($attr == 2 && $reason == 7 && ($renNum ne $erenNum || $renDate ne $erenDate)))
  {
    # It's OK if the reason is crms; it can't match anyway.
    return 1 if $ereason == 13;
    return (($swiss && !$expert) || ($eswiss && $euser eq 'autocrms'))? 2:0;
  }
  return 1;
}

sub UpdateCorrectness
{
  my $self = shift;
  my $id   = shift;

  my $sql = 'SELECT user,time,validated FROM historicalreviews WHERE id=?';
  my $r = $self->GetDb()->selectall_arrayref($sql, undef, $id);
  foreach my $row (@{$r})
  {
    my $user = $row->[0];
    my $time = $row->[1];
    my $val = $row->[2];
    my $val2 = $self->IsReviewCorrect($id, $user, $time);
    if ($val != $val2)
    {
      $sql = 'UPDATE historicalreviews SET validated=? WHERE id=? AND user=? AND time=?';
      $self->PrepareSubmitSql($sql, $val2, $id, $user, $time);
    }
  }
}

sub CountCorrectReviews
{
  my $self  = shift;
  my $user  = shift;
  my $start = shift;
  my $end   = shift;

  my $correct = 0;
  my $incorrect = 0;
  my $neutral = 0;
  my $sql = 'SELECT validated,COUNT(id) FROM historicalreviews' .
            ' WHERE legacy!=1 AND user=? AND time>=? AND time<=? GROUP BY validated';
  my $ref = $self->GetDb()->selectall_arrayref($sql, undef, $user, $start, $end);
  foreach my $row (@{$ref})
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
  my $self = shift;
  $_       = shift;

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
  my $dbh = $self->GetDb();
  my $sql = 'SELECT id FROM users WHERE id NOT LIKE "rereport%" AND expert=0';
  return map {$_->[0]} @{$dbh->selectall_arrayref($sql)};
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
  my $sql = 'SELECT SUM(total_reviews),SUM(total_correct),SUM(total_incorrect),SUM(total_neutral) FROM userstats' .
            " WHERE monthyear>=? AND monthyear<=? AND user IN ($users)";
  #print "$sql<br/>\n";
  my $ref = $self->GetDb()->selectall_arrayref($sql, undef, $start, $end);
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
  if ($page ne 'adminHistoricalReviews' || $self->TolerantCompare(1,$self->GetSystemVar('noLegacy')))
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

# Generates HTML to get the field type menu on the Export Data page.
sub ExportDataSearchMenu
{
  my $self = shift;
  my $searchName = shift;
  my $searchVal = shift;
  
  my @keys = qw(Identifier Title Author PubDate Attribute Reason Source);
  my @labs = ('Identifier','Title','Author','Pub Date','Attribute','Reason','Source');
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
               'exportData' => 'final determinations',
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
               'track' => 'track volumes',
               'undReviews' => 'provisional matches',
               'userRate' => 'my review stats',
               'userReviews' => 'my processed reviews',
              );
  return $pages{$page};
}

sub Namespaces
{
  my $self = shift;

  my $sql = 'SELECT distinct namespace FROM rights_current';
  my $ref = undef;
  eval { $ref = $self->GetSdrDb()->selectall_arrayref($sql); };
  $self->SetError("Rights query for namespaces failed: $@") if $@;
  return map {$_->[0];} @{$ref};
}

# Query the production rights database. This returns an array ref of entries for the volume, oldest first.
# Returns: aref to aref of ($attr,$reason,$src,$usr,$time,$note)
# FIXME: should use rights_log but different ORDER BY.
sub RightsQuery
{
  my $self   = shift;
  my $id     = shift;
  my $latest = shift;
  
  my ($ns,$n) = split m/\./, $id, 2;
  my $table = ($latest)? 'rights_current':'rights_log';
  my $sql = "SELECT a.name,rs.name,s.name,r.user,r.time,r.note FROM $table r, attributes a, reasons rs, sources s" .
            ' WHERE r.namespace=? AND r.id=? AND s.id=r.source AND a.id=r.attr AND rs.id=r.reason' .
            ' ORDER BY r.time ASC';
  my $ref = undef;
  eval { $ref = $self->GetSdrDb()->selectall_arrayref($sql, undef, $ns, $n); };
  $self->SetError("Rights query for $id failed: $@") if $@;
  return $ref;
}

sub RightsDBAvailable
{
  my $self = shift;
  
  my $dbh = undef;
  eval {
    $dbh = $self->GetSdrDb();
  };
  $self->ClearErrors();
  return ($dbh)? 1:0;
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
  
  my $buff = (join "\t", qw (ID Chron Rights Attr Reason Source User Time Note)) . "\n";
  my $rows = $self->VolumeIDsQuery($sysid);
  foreach my $line (@{$rows})
  {
    my ($id,$chron,$rights) = split '__', $line;
    $buff .= (join "\t", (($id,$chron,$rights), @{$self->RightsQuery($id,1)->[0]})) . "\n";
  }
  $self->DownloadSpreadSheet($buff);
  return (1 == scalar @{$self->GetErrors()});
}

sub CRMSQuery
{
  my $self = shift;
  my $id   = shift;

  my @ids;
  my $sysid;
  my $record = $self->GetMetadata($id, \$sysid);
  my $title = $self->GetRecordTitle($id, $record);
  my $rows = $self->VolumeIDsQuery($id, $record);
  foreach my $line (@{$rows})
  {
    my ($id2,$chron2,$rights2) = split '__', $line;
    
    push @ids, $id2 . '__' . $title . '__' . $self->GetTrackingInfo($id2, 1);
  }
  return \@ids;
}

sub GetTrackingInfo
{
  my $self    = shift;
  my $id      = shift;
  my $inherit = shift;

  my @stati = ();
  my $inQ = $self->IsVolumeInQueue($id);
  if ($inQ)
  {
    my $status = $self->GetStatus($id);
    my $n = $self->CountReviews($id);
    my $reviews = $self->Pluralize('review', $n);
    my $pri = $self->GetPriority($id);
    push @stati, "in Queue (P$pri, status $status, $n $reviews)";
  }
  elsif ($self->SimpleSqlGet('SELECT COUNT(*) FROM candidates WHERE id=?', $id))
  {
    push @stati, 'in Candidates';
  }
  my $src = $self->SimpleSqlGet('SELECT src FROM und WHERE id=?', $id);
  if ($self->SimpleSqlGet('SELECT COUNT(*) FROM und WHERE id=? AND (src="no meta" OR src="duplicate")', $id))
  {
    push @stati, "temporarily filtered ($src)";
  }
  elsif ($self->SimpleSqlGet('SELECT COUNT(*) FROM und WHERE id=? AND src!="no meta" AND src!="duplicate"', $id))
  {
    push @stati, "filtered ($src)";
  }
  if ($self->SimpleSqlGet('SELECT COUNT(*) FROM exportdata WHERE id=?', $id))
  {
    my $sql = 'SELECT attr,reason,DATE(time),src FROM exportdata WHERE id=? ORDER BY time DESC LIMIT 1';
    my $ref = $self->GetDb()->selectall_arrayref($sql, undef, $id);
    my $a = $ref->[0]->[0];
    my $r = $ref->[0]->[1];
    my $t = $ref->[0]->[2];
    my $src = $ref->[0]->[3];
    #$t = $self->FormatDate($t);
    my $action = ($src eq 'inherited')? ' (inherited)':'';
    push @stati, "exported$action $a/$r $t";
  }
  #else
  {
    my $n = $self->SimpleSqlGet('SELECT COUNT(*) FROM historicalreviews WHERE id=? AND legacy=1', $id);
    my $reviews = $self->Pluralize('review', $n);
    push @stati, "$n legacy $reviews" if $n;
  }
  if ($inherit && $self->SimpleSqlGet('SELECT COUNT(*) FROM inherit WHERE id=? AND del=0', $id))
  {
    my $sql = 'SELECT e.id,e.attr,e.reason FROM exportdata e INNER JOIN inherit i ON e.gid=i.gid WHERE i.id=?';
    my $ref = $self->GetDb()->selectall_arrayref($sql, undef, $id);
    my $src = $ref->[0]->[0];
    my $a = $ref->[0]->[1];
    my $r = $ref->[0]->[2];
    push @stati, "inheriting $a/$r from $src";
  }
  if (0 == scalar @stati)
  {
    # See if it has a pre-CRMS determination.
    my $rq = $self->RightsQuery($id,1);
    if (!$rq)
    {
      $self->ClearErrors();
      return 'Rights info unavailable';
    }
    my ($attr,$reason,$src,$usr,$time,$note) = @{$rq->[0]};
    my %okattr = $self->AllCRMSRights();
    my $rights = $attr.'/'.$reason;
    if ($okattr{$rights} == 1)
    {
      $time =~ s/(\d\d\d\d-\d\d-\d\d).*/$1/;
      push @stati, "Pre-legacy review ($rights $time by $usr)";
    }
  }
  return ucfirst join '; ', @stati;
}

sub Pluralize
{
  my $self = shift;
  my $word = shift;
  my $n    = shift;
  
  return $word . (($n == 1)? '':'s');
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
  my $r = $self->GetDb()->selectall_arrayref($sql);
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
  my $sql = "INSERT INTO systemstatus (status,message) VALUES (?,?)";
  $self->PrepareSubmitSql($sql, $status, $msg);
}

# How many items for this user have outstanding holds.
sub CountUserHolds
{
  my $self = shift;
  my $user = shift;

  my $sql = 'SELECT COUNT(*) FROM reviews WHERE user=? AND hold IS NOT NULL';
  return $self->SimpleSqlGet($sql, $user);
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

sub SelfURL
{
  my $self = shift;

  my $url = 'https://';
  my $dev = $self->get('dev');
  if ($dev)
  {
    if ($dev eq 'crmstest') {$url .= 'crmstest.dev.umdl.umich.edu';}
    elsif ($dev eq 'moseshll') {$url .= 'moseshll.dev.umdl.umich.edu';}
    else {$url .= 'dev.umdl.umich.edu';}
  }
  else {$url .= 'quod.lib.umich.edu';}
  return $url;
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
    my $ref = $self->GetDb()->selectall_arrayref('SELECT id FROM queue WHERE status<4 AND id IN (SELECT DISTINCT id FROM reviews)');
    foreach my $row (@{$ref})
    {
      my $id = $row->[0];
      $self->RemoveFromQueue($id);
      $self->PrepareSubmitSql('DELETE FROM reviews WHERE id=?', $id);
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
  my $sql = 'SELECT seconds,DATE_SUB(time, INTERVAL seconds SECOND) FROM mysqlrep.delay WHERE client=?';
  my $ref = $self->GetDb()->selectall_arrayref($sql, undef, $host);
  my @return = ($ref->[0]->[0],$self->FormatTime($ref->[0]->[1]));
  return @return;
}

sub StackTrace
{
  my $self = shift;
  
  my ($path, $line, $subr);
  my $max_depth = 30;
  my $i = 1;
  my $trace = "--- Begin stack trace ---\n";
  while ((my @call_details = (caller($i++))) && ($i<$max_depth))
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
    my $url = $self->Sysify("/cgi/c/crms/crms?p=adminHistoricalReviews;stype=reviews;search1=SysID;search1value=$1");
    $note =~ s/(See\sall\sreviews\sfor\sSys\s#)(\d+)/$1<a href="$url" target="_blank">$2<\/a>/;
  }
  return $note;
}

sub InheritanceSelectionMenu
{
  my $self = shift;
  my $searchName = shift;
  my $searchVal = shift;
  my $auto = shift;
  
  my @keys = ('date','idate','src','id','sysid','change','prior','prior5','title');
  my @labs = ('Export Date','Inherit Date','Source Volume','Volume Inheriting','System ID','Access Change',
              'Prior CRMS Determination','Prior Status 5 Determination','Title');
  if ($auto)
  {
    splice @keys, 6, 2;
    splice @labs, 6, 2;
  }
  push @keys, 'source';
  push @labs, 'Source';
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
  $new_search = 'DATE(i.time)' if $search eq 'idate';
  $new_search = 'e.id' if (!$search || $search eq 'src');
  $new_search = 's.sysid' if $search eq 'sysid';
  $new_search = 'i.id' if $search eq 'id';
  $new_search = '(i.attr=1 && (e.attr="ic" || e.attr="und") || (e.attr="pd" && (i.attr=2 || i.attr=5)))' if $search eq 'change';
  $new_search = 'IF(i.reason=1 || i.reason=12,0,1)' if $search eq 'prior';
  $new_search = 'IF((SELECT COUNT(*) FROM historicalreviews WHERE id=i.id AND status=5)>0,1,0)' if $search eq 'prior5';
  $new_search = 'b.title' if $search eq 'title';
  $new_search = 'i.src' if $search eq 'source';
  return $new_search;
}

sub GetInheritanceRef
{
  my $self         = shift;
  my $order        = shift;
  my $dir          = shift;
  my $order2       = shift;
  my $dir2         = shift;
  my $search1      = shift;
  my $search1Value = shift;
  my $startDate    = shift;
  my $endDate      = shift;
  my $dateType     = shift;
  my $n            = shift;
  my $pagesize     = shift;
  my $auto         = shift;

  $self->UpdateInheritanceRights();
  $n = 1 unless $n;
  $dateType = 'date' unless $dateType;
  my $offset = 0;
  $offset = ($n - 1) * $pagesize;
  #print("GetInheritanceRef('$order','$dir','$search1','$search1Value','$startDate','$endDate','$offset','$pagesize','$auto');<br/>\n");
  $pagesize = 20 unless $pagesize > 0;
  $order = 'idate' unless $order;
  $order2 = 'title' unless $order2;
  $search1 = $self->ConvertToInheritanceSearchTerm($search1);
  $order = $self->ConvertToInheritanceSearchTerm($order);
  $order2 = $self->ConvertToInheritanceSearchTerm($order2);
  my @rest = ('i.del=0');
  my $tester1 = '=';
  if ($search1Value =~ m/.*\*.*/)
  {
    $search1Value =~ s/\*/%/gs;
    $tester1 = ' LIKE ';
  }
  if ($search1Value =~ m/([<>!]=?)\s*(\d+)\s*/)
  {
    $search1Value = $2;
    $tester1 = $1;
  }
  my $doS = ' LEFT JOIN system s ON s.id=e.id ';
  my $datesrc = ($dateType eq 'date')? 'DATE(e.time)':'DATE(i.time)';
  push @rest, "$datesrc >= '$startDate'" if $startDate;
  push @rest, "$datesrc <= '$endDate'" if $endDate;
  push @rest, "$search1 $tester1 '$search1Value'" if $search1Value or $search1Value eq '0';
  my $prior = $self->ConvertToInheritanceSearchTerm('prior');
  push @rest, sprintf "$prior=%d", ($auto)? 0:1;
  my $restrict = ((scalar @rest)? 'WHERE ':'') . join(' AND ', @rest);
  my $sql = 'SELECT COUNT(DISTINCT e.id),COUNT(DISTINCT i.id) FROM inherit i ' .
            'LEFT JOIN exportdata e ON i.gid=e.gid ' .
            "LEFT JOIN bibdata b ON e.id=b.id $doS $restrict";
  my $ref;
  #print "$sql<br/>\n";
  eval {
    $ref = $self->GetDb()->selectall_arrayref($sql);
  };
  if ($@)
  {
    $self->SetError($@);
  }
  my $totalVolumes = $ref->[0]->[0];
  my $inheritingVolumes = $ref->[0]->[1];
  my $of = POSIX::ceil($inheritingVolumes/$pagesize);
  $n = $of if $n > $of;
  my $return = ();
  $sql = 'SELECT i.id,i.attr,i.reason,i.gid,e.id,e.attr,e.reason,b.title,DATE(e.time),i.src,DATE(i.time) ' .
         'FROM inherit i LEFT JOIN exportdata e ON i.gid=e.gid ' .
         "LEFT JOIN bibdata b ON e.id=b.id $doS $restrict ORDER BY $order $dir, $order2 $dir2 LIMIT $offset, $pagesize";
  #print "$sql<br/>\n";
  $ref = undef;
  eval {
    $ref = $self->GetDb()->selectall_arrayref($sql);
  };
  if ($@)
  {
    $self->SetError($@);
  }
  my $data = join "\t", ('ID','Title','Author','Pub Date','Date Added','Status','Locked','Priority','Reviews','Expert Reviews','Holds');
  my $i = $offset;
  my @return = ();
  foreach my $row (@{$ref})
  {
    $i++;
    my $id = $row->[0];
    my $sysid = $self->BarcodeToId($id);
    my $attr = $self->TranslateAttr($row->[1]);
    my $reason = $self->TranslateReason($row->[2]);
    my $gid = $row->[3];
    my $id2 = $row->[4] || '';
    my $attr2 = $row->[5];
    my $reason2 = $row->[6];
    my $title = $row->[7];
    my $date = $row->[8];
    my $src = $row->[9];
    my $idate = $row->[10]; # Date added to inherit table
    $title =~ s/&/&amp;/g;
    #my ($attr,$reason,$src3,$usr3,$time3,$note3) = @{$self->RightsQuery($id,1)->[0]};
    my ($pd,$pdus,$icund) = (0,0,0);
    $pd = 1 if ($attr eq 'pd' || $attr2 eq 'pd');
    $pdus = 1 if ($attr eq 'pdus' || $attr2 eq 'pdus');
    $icund = 1 if ($attr eq 'ic' || $attr2 eq 'ic');
    $icund = 1 if ($attr eq 'und' || $attr2 eq 'und');
    my $incrms = (($attr eq 'ic' && $reason eq 'bib') || $reason eq 'gfv')? undef:1;
    my $h5 = undef;
    if ($incrms)
    {
      my $sql = "SELECT COUNT(*) FROM historicalreviews WHERE id='$id' AND status=5";
      $h5 = 1 if $self->SimpleSqlGet($sql) > 0;
    }
    my $change = (($pd == 1 && $icund == 1) || ($pd == 1 && $pdus == 1) || ($icund == 1 && $pdus == 1));
    my $summary = '';
    if ($self->IsVolumeInQueue($id))
    {
      $summary = sprintf "in queue (P%s)", $self->GetPriority($id);
      $sql = "SELECT user FROM reviews WHERE id='$id'";
      my $ref2 = $self->GetDb()->selectall_arrayref($sql);
      my $users = join ', ', (map {$_->[0]} @{$ref2});
      $summary .= "; reviewed by $users" if $users;
      my $locked = $self->SimpleSqlGet("SELECT locked FROM queue WHERE id='$id'");
      $summary .= "; locked for $locked" if $locked;
    }
    my %dic = ('i'=>$i, 'inheriting'=>$id, 'sysid'=>$sysid, 'rights'=>"$attr/$reason",
               'newrights'=>"$attr2/$reason2", 'incrms'=>$incrms, 'change'=>$change, 'from'=>$id2,
               'title'=>$title, 'gid'=>$gid, 'date'=>$date, 'summary'=>ucfirst $summary,
               'src'=>ucfirst $src, 'h5'=>$h5, 'idate'=>$idate);
    push @return, \%dic;
    #if ($download)
    #{
      #$data .= sprintf("\n$id\t%s\t%s\t%s\t$date\t%s\t%s\t%s\t$reviews\t%s\t$holds",
      #                 $row->[7], $row->[8], $row->[4], $row->[2], $row->[3], $self->StripDecimal($row->[5]), $row->[6]);
    #}
  }
  #if (!$download)
  {
    $data = {'rows' => \@return,
             'source' => $totalVolumes,
             'inheriting' => $inheritingVolumes,
             'n' => $n,
             'of' => $of
            };
  }
  return $data;
}

sub HasMissingOrWrongRecord
{
  my $self  = shift;
  my $id    = shift;
  my $sysid = shift;
  my $rows  = shift;

  $rows = $self->VolumeIDsQuery($sysid) unless $rows;
  foreach my $line (@{$rows})
  {
    my ($id2,$chron2,$rights2) = split '__', $line;
    my $sql = 'SELECT COUNT(*) FROM historicalreviews WHERE id=? AND (category="Wrong Record" OR category="Missing")';
    return $id2 if ($self->SimpleSqlGet($sql, $id2) > 0);
  }
  # In case source volume has been corrected for wrong record and is now on a new record,
  # check it explicitly.
  my $sql = 'SELECT COUNT(*) FROM historicalreviews WHERE id=? AND (category="Wrong Record" OR category="Missing")';
  return $id if ($self->SimpleSqlGet($sql, $id) > 0);
}

sub IsFiltered
{
  my $self = shift;
  my $id   = shift;
  my $src  = shift;

  my $sql = 'SELECT COUNT(*) FROM und WHERE id=?';
  $sql .= " AND src='$src'" if $src;
  return $self->SimpleSqlGet($sql, $id);
}

sub DeleteInheritance
{
  my $self = shift;
  my $id  = shift;

  return 'skip' if $self->SimpleSqlGet('SELECT COUNT(*) FROM inherit WHERE id=? AND del=1', $id);
  return 'skip' unless $self->SimpleSqlGet('SELECT COUNT(*) FROM inherit WHERE id=?', $id);
  $self->PrepareSubmitSql('UPDATE inherit SET del=1 WHERE id=?', $id);
  # Only unfilter if the und src is 'duplicate' because duplicate filtration
  # does not override other sources like gfv
  $self->Unfilter($id) if $self->IsFiltered($id, 'duplicate');
  return 0;
}

sub GetDeletedInheritance
{
  my $self = shift;

  my $sql = 'SELECT id FROM inherit WHERE del=1';
  return $self->GetDb()->selectall_arrayref($sql);
}

sub UpdateInheritanceRights
{
  my $self = shift;

  my $sql = 'SELECT id,attr,reason FROM inherit';
  my $ref = $self->GetDb()->selectall_arrayref($sql);
  foreach my $row (@{$ref})
  {
    my $id = $row->[0];
    my $a = $row->[1];
    my $r = $row->[2];
    my $rq = $self->RightsQuery($id,1);
    if (!$rq)
    {
      $self->ClearErrors();
      return;
    }
    my ($attr,$reason,$src,$usr,$time,$note) = @{$rq->[0]};
    if ($self->TranslateAttr($a) ne $attr || $self->TranslateReason($r) ne $reason)
    {
      $a = $self->TranslateAttr($attr);
      $r = $self->TranslateReason($reason);
      my $sql = 'UPDATE inherit SET attr=?,reason=? WHERE id=?';
      $self->PrepareSubmitSql($sql, $a, $r, $id);
    }
  }
}

sub AutoSubmitInheritances
{
  my $self    = shift;
  my $fromcgi = shift;

  my $sql = 'SELECT id FROM inherit WHERE del=0';
  my $ref = $self->GetDb()->selectall_arrayref($sql);
  foreach my $row (@{$ref})
  {
    my $id = $row->[0];
    my ($attr,$reason,$src,$usr,$time,$note) = @{$self->RightsQuery($id,1)->[0]};
    if ($reason eq 'bib' || $reason eq 'gfv')
    {
      my $rights = "$attr/$reason";
      print "Submitting inheritance for $id ($rights)\n" unless $fromcgi;
      $self->SubmitInheritance($id);
    }
  }
}

sub SubmitInheritance
{
  my $self = shift;
  my $id   = shift;

  my $sql = 'SELECT COUNT(*) FROM reviews r INNER JOIN queue q ON r.id=q.id WHERE r.id=? AND r.user="autocrms" AND q.status=9';
  return 'skip' if $self->SimpleSqlGet($sql, $id);
  $sql = 'SELECT e.attr,e.reason,i.gid FROM inherit i INNER JOIN exportdata e ON i.gid=e.gid WHERE i.id=?';
  my $row = $self->GetDb()->selectall_arrayref($sql, undef, $id)->[0];
  return "$id is no longer available for inheritance (has it been processed?)" unless $row;
  my $attr = $self->TranslateAttr($row->[0]);
  my $reason = $self->TranslateReason($row->[1]);
  my $gid = $row->[2];
  my $category = 'Rights Inherited';
  # Returns a status code (0=Add, 1=Error) followed by optional text.
  my $res = $self->AddInheritanceToQueue($id);
  my $code = substr $res, 0, 1;
  if ($code ne '0')
  {
    return $id . ': ' . substr $res, 1, length $res;
  }
  $self->PrepareSubmitSql('DELETE FROM reviews WHERE id=?', $id);
  my $sysid = $self->BarcodeToId($id);
  my $note = "See all reviews for Sys #$sysid";
  my $swiss = ($self->SimpleSqlGet('SELECT COUNT(*) FROM historicalreviews WHERE id=?', $id)>0)? 1:0;
  $self->SubmitReview($id,'autocrms',$attr,$reason,$note,undef,1,undef,$category,$swiss);
  $self->PrepareSubmitSql('DELETE FROM inherit WHERE id=?', $id);
  return 0;
}

# Returns a status code (0=Add, 1=Error) followed by optional text.
sub AddInheritanceToQueue
{
  my $self = shift;
  my $id   = shift;

  my $stat = 0;
  my @msgs = ();
  if ($self->IsVolumeInQueue($id))
  {
    my $err = $self->LockItem($id, 'autocrms');
    if ($err)
    {
      push @msgs, $err;
      $stat = 1;
    }
    else
    {
      my $sql = 'SELECT COUNT(*) FROM reviews WHERE id=? AND user NOT LIKE "rereport%"';
      my $n = $self->SimpleSqlGet($sql, $id);
      if ($n)
      {
        my $url = $self->Sysify("?p=adminReviews;search1=Identifier;search1value=$id");
        my $msg = sprintf "already has $n <a href='$url' target='_blank'>%s</a>", $self->Pluralize('review',$n);
        push @msgs, $msg;
        $stat = 1;
      }
      else
      {
        $self->PrepareSubmitSql('UPDATE queue SET source="inherited" WHERE id=?', $id);
      }
    }
    $self->UnlockItem($id, 'autocrms');
  }
  else
  {
    my $sql = 'INSERT INTO queue (id,priority,source) VALUES (?,0,"inherited")';
    $self->PrepareSubmitSql($sql, $id);
    $self->UpdateMetadata($id, 1);
    $sql = 'INSERT INTO queuerecord (itemcount,source) VALUES (1,"inheritance")';
    $self->PrepareSubmitSql($sql);
  }
  return $stat . join '; ', @msgs;
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
  my $full  = shift;

  my $url = $self->Sysify("/cgi/c/crms/crms?p=adminHistoricalReviews;search1=SysID;search1value=$sysid");
  $url = $self->SelfURL() . $url if $full;
  return $url;
}

sub LinkToRetrieve
{
  my $self  = shift;
  my $sysid = shift;
  my $full  = shift;

  my $url = $self->Sysify("/cgi/c/crms/crms?p=track;query=$sysid");
  $url = $self->SelfURL() . $url if $full;
  return $url;
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
  my $record = shift;

  my %okattr = $self->AllCRMSRights();
  my $rows = $self->VolumeIDsQuery($sysid, $record);
  $self->ClearErrors();
  if (!scalar @{$rows})
  {
    $data->{'unavailable'}->{$id} = 1;
    return;
  }
  if (1 == scalar @{$rows})
  {
    $data->{'nodups'}->{$id} .= "$sysid\n";
    return;
  }
  $data->{'titles'}->{$id} = $self->GetRecordTitle($id, $record);
  # Get most recent CRMS determination for any volume on this record
  # and see if it's more recent that what we're exporting.
  my $candidate = $id;
  my $candidateTime = $self->SimpleSqlGet('SELECT MAX(time) FROM historicalreviews WHERE id=?', $id);
  foreach my $line (@{$rows})
  {
    my ($id2,$chron2,$rights2) = split '__', $line;
    if ($chron2)
    {
      $data->{'chron'}->{$id} = "$id2\t$sysid\n";
      delete $data->{'unneeded'}->{$id};
      delete $data->{'inherit'}->{$id};
      delete $data->{'disallowed'}->{$id};
      return;
    }
    my $time = $self->SimpleSqlGet('SELECT MAX(time) FROM historicalreviews WHERE id=?', $id2);
    if ($time && $time gt $candidateTime)
    {
      $candidate = $id2;
      $candidateTime = $time;
    }
  }
  my $wrong = $self->HasMissingOrWrongRecord($id, $sysid, $rows);
  foreach my $line (@{$rows})
  {
    my ($id2,$chron2,$rights2) = split '__', $line;
    next if $id eq $id2;
    my ($attr2,$reason2,$src2,$usr2,$time2,$note2) = @{$self->RightsQuery($id2,1)->[0]};
    # In case we have a more recent export that has not made it into the rights DB...
    if ($self->SimpleSqlGet('SELECT COUNT(*) FROM exportdata WHERE id=? AND time>=?', $id2, $time2))
    {
      my $sql = 'SELECT attr,reason FROM exportdata WHERE id=? ORDER BY time DESC LIMIT 1';
      ($attr2,$reason2) = @{$self->GetDb()->selectall_arrayref($sql, undef, $id2)->[0]};
    }
    my $newrights = "$attr/$reason";
    my $oldrights = "$attr2/$reason2";
    if ($newrights eq 'pd/ncn')
    {
      $data->{'disallowed'}->{$id} .= "$id2\t$sysid\t$oldrights\t$newrights\t$id\tCan't inherit from pd/ncn\n";
    }
    elsif ($okattr{$oldrights} ||
           ($oldrights eq 'pdus/gfv' && $attr =~ m/^pd/) ||
           $oldrights eq 'ic/bib' ||
           ($self->get('sys') eq 'crmsworld' && $oldrights =~ m/^pdus/))
    {
      # Always inherit onto a single-review priority 1
      my $rereps = $self->SimpleSqlGet('SELECT COUNT(*) FROM reviews WHERE id=? AND user LIKE "rereport%"', $id2);
      if ($attr2 eq $attr && $reason2 ne 'bib' && $rereps == 0)
      {
        $data->{'unneeded'}->{$id} .= "$id2\t$sysid\t$oldrights\t$newrights\t$id\n";
      }
      elsif ($wrong)
      {
        $data->{'disallowed'}->{$id} .= "$id2\t$sysid\t$oldrights\t$newrights\t$id\tMissing/Wrong Record on $wrong\n";
        delete $data->{'unneeded'}->{$id};
        delete $data->{'inherit'}->{$id};
      }
      # CRMS World can't inherit und onto pdus or pd
      elsif ($self->get('sys') eq 'crmsworld' && $newrights =~ m/^und/ && $oldrights =~ m/^pd/)
      {
        $data->{'disallowed'}->{$id} .= "$id2\t$sysid\t$oldrights\t$newrights\t$id\tCan't inherit und onto pdus\n";
        delete $data->{'unneeded'}->{$id};
        delete $data->{'inherit'}->{$id};
      }
      elsif ($candidate ne $id)
      {
        $data->{'disallowed'}->{$id} = "$id2\t$sysid\t$oldrights\t$newrights\t$id\t$candidate has newer review ($candidateTime)\n";
        delete $data->{'unneeded'}->{$id};
        delete $data->{'inherit'}->{$id};
        return;
      }
      elsif ($self->SimpleSqlGet('SELECT COUNT(*) FROM reviews WHERE id=? AND user NOT LIKE "rereport%"', $id2))
      {
        my $user = $self->SimpleSqlGet('SELECT user FROM reviews WHERE id=? AND user NOT LIKE "rereport%" LIMIT 1', $id2);
        $data->{'disallowed'}->{$id} .= "$id2\t$sysid\t$oldrights\t$newrights\t$id\tHas an active review by $user\n";
      }
      else
      {
        $data->{'inherit'}->{$id} .= "$id2\t$sysid\t$attr2\t$reason2\t$attr\t$reason\t$gid\n";
      }
    }
    else
    {
      $data->{'disallowed'}->{$id} .= "$id2\t$sysid\t$oldrights\t$newrights\t$id\tRights\n";
    }
  }
}

sub AllCRMSRights
{
  my $self = shift;
  
  my $sql = 'SELECT attr,reason FROM rights';
  my $ref = $self->GetDb()->selectall_arrayref($sql);
  my %okattr;
  foreach my $row (@{$ref})
  {
    my $a = $self->TranslateAttr($row->[0]);
    my $r = $self->TranslateReason($row->[1]);
    $okattr{"$a/$r"} = 1;
  }
  return %okattr;
}

sub DuplicateVolumesFromCandidates
{
  my $self   = shift;
  my $id     = shift;
  my $sysid  = shift;
  my $data   = shift;
  my $record = shift;

  my $rows = $self->VolumeIDsQuery($sysid, $record);
  if (1 == scalar @{$rows})
  {
    $data->{'nodups'}->{$id} .= "$sysid\n";
    return;
  }
  $data->{'titles'}->{$id} = $self->GetRecordTitle($id, $record);
  my $cid = undef;
  my $cgid = undef;
  my $cattr = undef;
  my $creason = undef;
  my $ctime = undef;
  foreach my $line (@{$rows})
  {
    my ($id2,$chron2,$rights2) = split '__', $line;
    if ($chron2)
    {
      $data->{'chron'}->{$id} = "$id2\t$sysid\n";
      delete $data->{'already'}->{$id};
      delete $data->{'unneeded'}->{$id};
      delete $data->{'inherit'}->{$id};
      delete $data->{'noexport'}->{$id};
      delete $data->{'disallowed'}->{$id};
      return;
    }
    next if $id eq $id2;
    # id may be in und, so only apply this check if id is in candidates.
    my $sql = 'SELECT COUNT(*) FROM candidates WHERE id=?';
    if ($self->SimpleSqlGet($sql, $id) && !$data->{'already'}->{$id2} &&
        $self->SimpleSqlGet($sql, $id2))
    {
      $data->{'already'}->{$id} .= "$id2\t$sysid\n";
    }
    else
    {
      $sql = 'SELECT attr,reason,gid,time FROM exportdata WHERE id=?' .
             ' AND time>="2010-06-02 00:00:00" ORDER BY time DESC LIMIT 1';
      my $ref = $self->GetDb()->selectall_arrayref($sql, undef, $id2);
      foreach my $row (@{$ref})
      {
        my $attr2   = $row->[0];
        my $reason2 = $row->[1];
        my $gid2    = $row->[2];
        my $time2   = $row->[3];
        if (!$ctime || $time2 gt $ctime)
        {
          $cid = $id2;
          $cgid = $gid2;
          $cattr = $attr2;
          $creason = $reason2;
          $ctime = $time2;
        }
      }
    }
  }
  if ($cid)
  {
    my ($attr2,$reason2,$src2,$usr2,$time2,$note2);
    eval {
      ($attr2,$reason2,$src2,$usr2,$time2,$note2) = @{$self->RightsQuery($id,1)->[0]};
    };
    if ($@)
    {
      $data->{'unavailable'}->{$id} = 1;
      $self->ClearErrors();
      return;
    }
    my $oldrights = "$attr2/$reason2";
    my $newrights = "$cattr/$creason";
    my $wrong = $self->HasMissingOrWrongRecord($id, $sysid, $rows);
    if ($newrights eq 'pd/ncn')
    {
      $data->{'disallowed'}->{$id} .= "$cid\t$sysid\t$oldrights\t$newrights\t$id\tCan't inherit from pd/ncn\n";
    }
    # CRMS World can't inherit und onto pdus
    elsif ($self->get('sys') eq 'crmsworld' && $newrights =~ m/^und/ && $oldrights =~ m/^pdus/)
    {
      $data->{'disallowed'}->{$id} .= "$cid\t$sysid\t$oldrights\t$newrights\t$id\tCan't inherit und onto pdus\n";
    }
    elsif ($wrong)
    {
      $data->{'disallowed'}->{$id} .= "$cid\t$sysid\t$oldrights\t$newrights\t$id\tMissing/Wrong Record on $wrong\n";
    }
    elsif ($oldrights eq 'ic/bib' ||
           ($oldrights eq 'pdus/gfv' && $cattr =~ m/^pd/) ||
           ($self->get('sys') eq 'crmsworld' && $oldrights =~ m/^pdus/))
    {
      $data->{'inherit'}->{$cid} .= "$id\t$sysid\t$attr2\t$reason2\t$cattr\t$creason\t$cgid\n";
    }
    else
    {
      $data->{'disallowed'}->{$id} .= "$cid\t$sysid\t$oldrights\t$newrights\t$id\tRights\n";
    }
  }
  else
  {
    $data->{'noexport'}->{$id} .= "$sysid\n";
  }
}

sub GetDuplicates
{
  my $self = shift;
  my $id   = shift;

  my @dupes = ();
  my $sysid;
  my $record = $self->GetMetadata($id, \$sysid);
  my $rows = $self->VolumeIDsQuery($sysid, $record);
  foreach my $line (@{$rows})
  {
    my ($id2,$chron2,$rights2) = split '__', $line;
    push @dupes, $id2 if $id2 ne $id;
  }
  return @dupes;
}

sub ExportSrcToEnglish
{
  my $self = shift;
  my $src  = shift;

  my %srces = ('adminui'  => 'Added to Queue',
               'rereport' => 'Rereports',
               'newyear'  => 'Expired ADD');
  my $eng = $srces{$src};
  $eng = ucfirst $src unless $eng;
  return $eng;
}

# Prevent multiple volumes from getting in the queue.
# If possible (if not already in queue) filter oldVol as src=duplicate
# Otherwise filter (if possible) newVol.
sub FilterCandidates
{
  my $self   = shift;
  my $oldVol = shift;
  my $newVol = shift;

  if ($self->SimpleSqlGet('SELECT COUNT(*) FROM queue WHERE id=?', $oldVol) == 0)
  {
    $self->Filter($oldVol, 'duplicate');
  }
  elsif ($self->SimpleSqlGet('SELECT COUNT(*) FROM queue WHERE id=?', $newVol) == 0)
  {
    $self->Filter($newVol, 'duplicate');
  }
}

# Retrieves a system var from the DB if possible, otherwise use the value from the config file.
# If ck is specified, it should be of the form "$_ >= 0 && $_ <= 100" which checks the DB value
# and uses the config file value if the check is failed.
# If default is specified, returns it if otherwise the return value would be undefined.
sub GetSystemVar
{
  my $self    = shift;
  my $name    = shift;
  my $default = shift;
  my $ck      = shift;

  my $sql = 'SELECT value FROM systemvars WHERE name=?';
  my $var = $self->SimpleSqlGet($sql, $name);
  if ($var && $ck)
  {
    $_ = $var;
    $var = undef unless (eval $ck);
  }
  $var = $self->get($name) unless defined $var;
  $var = $default unless defined $var;
  return $var;
}

sub SetSystemVar
{
  my $self  = shift;
  my $name  = shift;
  my $value = shift;

  my $sql = 'REPLACE INTO systemvars (name,value) VALUES (?,?)';
  $self->PrepareSubmitSql($sql, $name, $value);
}

sub Menus
{
  my $self = shift;

  my $e = $self->IsUserExpert();
  my $i = $self->IsUserIncarnationExpertOrHigher();
  my $r = ($e || $self->IsUserReviewer() || $self->IsUserAdvanced());
  my $x = $self->IsUserExtAdmin();
  my $a = $self->IsUserAdmin();
  my $s = $self->IsUserSuperAdmin();
  my $sql = "SELECT id,name,class,restricted FROM menus ORDER BY n";
  #print "$sql\n<br/>";
  my $ref = $self->GetDb()->selectall_arrayref($sql);
  my @all = ();
  foreach my $row (@{$ref})
  {
    if (!$row->[3] ||
        ($row->[3] &&
         (($e && $row->[3] =~ m/e/) ||
          ($i && $row->[3] =~ m/i/) ||
          ($r && $row->[3] =~ m/r/) ||
          ($x && $row->[3] =~ m/x/) ||
          ($a && $row->[3] =~ m/a/) ||
          ($s && $row->[3] =~ m/s/))))
    {
      push @all, $row;
    }
  }
  return \@all;
}

sub MenuItems
{
  my $self = shift;
  my $menu = shift;

  $menu = $self->SimpleSqlGet('SELECT id FROM menus WHERE docs=1 LIMIT 1') if $menu eq 'docs';
  my $e = $self->IsUserExpert();
  my $i = $self->IsUserIncarnationExpertOrHigher();
  my $r = ($e || $self->IsUserReviewer() || $self->IsUserAdvanced());
  my $x = $self->IsUserExtAdmin();
  my $a = $self->IsUserAdmin();
  my $s = $self->IsUserSuperAdmin();
  my $sql = 'SELECT name,href,institution,restricted,target FROM menuitems WHERE menu=? ORDER BY n ASC';
  #print "$sql\n<br/>";
  my $ref = $self->GetDb()->selectall_arrayref($sql, undef, $menu);
  my @all = ();
  foreach my $row (@{$ref})
  {
    next if ($row->[2] && !$self->CanUserSeeInstitutionalStats($row->[2]));
    if (!$row->[3] ||
        ($row->[3] &&
         (($e && $row->[3] =~ m/e/) ||
          ($i && $row->[3] =~ m/i/) ||
          ($r && $row->[3] =~ m/r/) ||
          ($x && $row->[3] =~ m/x/) ||
          ($a && $row->[3] =~ m/a/) ||
          ($s && $row->[3] =~ m/s/))))
    {
      push @all, $row;
    }
  }
  return \@all;
}

# interface=1 means just the categories used in the review page
sub Categories
{
  my $self      = shift;
  my $interface = shift;

  my $e = $self->IsUserExpert();
  my $r = ($e || $self->IsUserReviewer() || $self->IsUserAdvanced());
  my $x = $self->IsUserExtAdmin();
  my $a = $self->IsUserAdmin();
  my $s = $self->IsUserSuperAdmin();
  my $sql = 'SELECT id,name,restricted,interface,need_note FROM categories ORDER BY name ASC';
  #print "$sql\n<br/>";
  my $ref = $self->GetDb()->selectall_arrayref($sql);
  my @all = ();
  foreach my $row (@{$ref})
  {
    next if $interface and $row->[3] == 0;
    if (!$row->[2] ||
        ($row->[2] &&
         (($e && $row->[2] =~ m/e/) ||
          ($r && $row->[2] =~ m/r/) ||
          ($x && $row->[2] =~ m/x/) ||
          ($a && $row->[2] =~ m/a/) ||
          ($s && $row->[2] =~ m/s/))))
    {
      push @all, $row;
    }
  }
  return \@all;
}

sub Rights
{
  my $self = shift;
  my $exp  = shift;

  my $e = $self->IsUserExpert();
  my $r = ($e || $self->IsUserReviewer() || $self->IsUserAdvanced());
  my $x = $self->IsUserExtAdmin();
  my $a = $self->IsUserAdmin();
  my $s = $self->IsUserSuperAdmin();
  my $sql = 'SELECT id,attr,reason,restricted,description FROM rights ORDER BY id ASC';
  #print "$sql\n<br/>";
  my $ref = $self->GetDb()->selectall_arrayref($sql);
  my @all = ();
  foreach my $row (@{$ref})
  {
    my $restricted = $row->[3];
    next if ($restricted && !$exp);
    next if ($exp && !$restricted);
    next if ($restricted eq 'i');
    if (!$restricted ||
        ($restricted &&
         (($e && $restricted =~ m/e/) ||
          ($r && $restricted =~ m/r/) ||
          ($x && $restricted =~ m/x/) ||
          ($a && $restricted =~ m/a/) ||
          ($s && $restricted =~ m/s/))))
    {
      push @all, $row;
    }
  }
  return \@all;
}

sub Sources
{
  my $self = shift;
  my $id   = shift;
  my $mag  = shift;
  my $view = shift;
  
  $mag = '100' unless $mag;
  $view = 'image' unless $view;
  my $sql = 'SELECT id,name,url,accesskey,menu,initial FROM sources ORDER BY n ASC, name ASC';
  #print "$sql\n<br/>";
  my $ref = $self->GetDb()->selectall_arrayref($sql);
  my @all = ();
  foreach my $row (@{$ref})
  {
    my $name = $row->[1];
    my $url = $row->[2];
    $url =~ s/__HTID__/$id/g;
    $url =~ s/__MAG__/$mag/g;
    $url =~ s/__VIEW__/$view/g;
    if ($url =~ m/__SYSID__/)
    {
      my $sysid = $self->BarcodeToId($id);
      $url =~ s/__SYSID__/$sysid/g;
    }
    if ($url =~ m/__AUTHOR__/)
    {
      my $a = $self->GetEncAuthorForReview($id);
      $url =~ s/__AUTHOR__/$a/g;
    }
    if ($url =~ m/__AUTHOR_(\d+)__/)
    {
      my $a = $self->GetEncAuthorForReview($id);
      if ($name eq 'NGCOBA' && $a =~ m/^ma?c(.)/i)
      {
        $a = 'm1';
        my $x = lc $1;
        $a = 'm14' if $x le 'z';
        $a = 'm13' if $x le 'r';
        $a = 'm12' if $x le 'n';
        $a = 'm11' if $x le 'e';
      }
      else
      {
        $a = lc substr($a, 0, $1);
      }
      $url =~ s/__AUTHOR_\d+__/$a/g;
    }
    if ($url =~ m/__AUTHOR_F__/)
    {
      my $a = $self->GetEncAuthorForReview($id);
      $a = $1 if $a =~ m/^.*?([A-Za-z]+)/;
      $url =~ s/__AUTHOR_F__/$a/g;
    }
    if ($url =~ m/__TITLE__/)
    {
      my $t = $self->GetEncTitle($id);
      $url =~ s/__TITLE__/$t/g;
    }
    $url =~ s/\s+/+/g;
    push @all, [$row->[0], $name, $url, $row->[3], $row->[4], $row->[5]];
  }
  return \@all;
}

# Makes sure a URL has the correct sys param if needed.
sub Sysify
{
  my $self = shift;
  my $url  = shift;

  my $sys = $self->get('sys');
  if ($sys ne 'crms')
  {
    if ($url !~ m/sys=$sys/i)
    {
      $url .= '?' unless $url =~ m/\?/;
      $url .= ';' unless $url =~ m/[;?]$/;
      $url .= "sys=$sys";
    }
  }
  return $url;
}

# Used to simplify the search results page links.
# Makes URL params for all values defined in the CGI,
# ignoring those that are valueless.
# All subsequent parameters to this routine are left out of the
# resulting string; it is assumed they will appended by the caller.
sub URLify
{
  my $self = shift;
  my $cgi  = shift;

  my %exceptions = ();
  $exceptions{$_} = 1 for @_;
  my @comps = ();
  foreach my $key ($cgi->param)
  {
    my $val = $cgi->param($key);
    push @comps, "$key=$val" if $val and not $exceptions{$key};
  }
  return join ';',@comps;
}

# Creates a chunk of HTML with hidden inputs based on the CGI params,
# ignoring those that are valueless.
# All subsequent parameters to this routine are left out of the
# resulting string; it is assumed they will be appended by the caller.
sub Hiddenify
{
  my $self = shift;
  my $cgi  = shift;
  
  my %exceptions = ();
  $exceptions{$_} = 1 for @_;
  my @comps = ();
  foreach my $key ($cgi->param)
  {
    my $val = $cgi->param($key);
    push @comps, "<input type='hidden' name='$key' value='$val'/>" if $val and not $exceptions{$key};
  }
  return join "\n", @comps;
}

# If necessary, emits a hidden input with the sys name
sub HiddenSys
{
  my $self = shift;

  my $sys = $self->get('sys');
  return "<input type='hidden' name='sys' value='$sys'/>" if $sys && $sys ne 'crms';
  return '';
}

# Compares 2 strings or undefs
sub TolerantCompare
{
  my $self = shift;
  my $s1   = shift;
  my $s2   = shift;
  
  return 1 if (!defined $s1) && (!defined $s2);
  return 0 if (!defined $s1) && (defined $s2);
  return 0 if (defined $s1) && (!defined $s2);
  return ($s1 eq $s2)?1:0; 
}

# CRMS World specific. Predict best radio button (rights combo)
# to choose based on user selections.
sub PredictRights
{
  my $self   = shift;
  my $id     = shift; # Volume id
  my $year   = shift; # ADD or Pub entered by user
  my $ispub  = shift; # Pub date checkbox
  my $crown  = shift; # Crown copyright note category
  my $record = shift; # Metadata (optional) so we don't spam bibdata table for volumes not in queue.

  return 0 if $year !~ m/^-?\d+$/; # Punt if the year is not exclusively 1 or more decimal digits with optional minus.
  my $pub = undef;
  $pub = $year if $ispub;
  if (! defined $pub)
  {
    $pub = $self->GetRecordPubDate($id, $record) if $record;
    $pub = $self->GetPubDate($id) unless defined $pub;
  }
  return 0 unless defined $pub;
  my $where = undef;
  $where = $self->GetRecordPubCountry($id, $record) if $record;
  $where = $self->GetPubCountry($id) unless $where;
  my ($attr, $reason) = (0,0);
  my $now = $self->GetTheYear();
  my $when = $year + (($where eq 'United Kingdom')? ($crown? 50:70):50);
  if ($when < $now)
  {
    if ($when >= 1996 && $pub >= 1923)
    {
      $attr = 'icus';
      $reason = 'gatt';
    }
    else
    {
      $attr = 'pd';
      $reason = ($ispub)? 'exp':'add';
    }
  }
  else
  {
    $attr = (int $pub < 1923)? 'pdus':'ic';
    $reason = 'add';
  }
  my $sql = 'SELECT id FROM rights WHERE attr=? AND reason=?';
  return $self->SimpleSqlGet($sql, $self->TranslateAttr($attr),
                             $self->TranslateReason($reason));
}

sub Unescape
{
  my $self = shift;

  use URI::Escape;
  return uri_unescape(shift);
}

# Return the email address to send catalogue problems
# which can be overridden in the DB.
sub MDPCorrections
{
  my $self = shift;

  return $self->GetSystemVar('MDPCorrections','mdpcorrections@umich.edu');
}

sub GetADDFromAuthor
{
  my $self = shift;
  my $id   = shift;
  my $a    = shift; # For testing

  my $add = undef;
  eval {
    $a = $self->GetRecordAuthor($id, undef, 1) unless defined $a;
  };
  if ($@)
  {
    $self->ClearErrors();
    return;
  }
  my $regex = '\d?\d\d\d\??\s*-\s*(\d?\d\d\d)[.,;) ]*$';
  if (defined $a && $a =~ m/$regex/)
  {
    $add = $1;
    $add = undef if $a =~ m/(fl\.*|active)\s*$regex/i;
  }
  return $add;
}

# If successful, returns a hash ref that contains values for some subset of
# the following keys: 'add', 'author' (the VIAF author name), and 'country'.
# Returns undef if none of that data could be found.
sub GetVIAFData
{
  my $self   = shift;
  my $id     = shift;
  my $author = shift;

  my %ret;
  my $add;
  my $a;
  $a = $author if defined $author;
  $a = $self->GetAuthor($id) unless defined $a;
  #print "Looking for $a\n";
  if (defined $a && length $a)
  {
    my $sql = 'SELECT viaf_author,year,country FROM viaf WHERE author=?';
    my $ref = $self->GetDb()->selectall_arrayref($sql, undef, $a);
    if (scalar @{$ref} > 0)
    {
      $ret{'country'} = $ref->[0]->[2];
      $ret{'author'}  = $ref->[0]->[0];
      $ret{'add'} = $ref->[0]->[1];
      return \%ret;
    }
    my $a2 = $a;
    $a2 =~ s/[^A-Za-z]//g;
    my %adds;
    my %names;
    my $name;
    my $url = 'http://viaf.org/viaf/search?query=local.personalNames+all+%22' . $a .
              '%22+&maximumRecords=10&startRecord=1&sortKeys=holdingscount&httpAccept=text/xml';
    my $ua = LWP::UserAgent->new;
    $ua->timeout(1000);
    my $req = HTTP::Request->new(GET => $url);
    my $res = $ua->request($req);
    return unless $res->is_success;
    my $xml = $res->content;
    my $parser = XML::LibXML->new();
    my $doc;
    eval {
      $doc = $parser->parse_string($xml);
    };
    if ($@) { $self->SetError("failed to parse ($xml): $@"); return; }
    my $xpc = XML::LibXML::XPathContext->new($doc);
    #open my $pipe, '|xmllint --format -' or die '...';
    #print $pipe $xml;
    #close $pipe;
    my $n = 0;
    my $i = 1;
    my $pref = "/*[local-name()='searchRetrieveResponse']/*[local-name()='records']/*[local-name()='record']";
    my $xpath = "*[local-name()='recordData']/*[local-name()='VIAFCluster']/*[local-name()='mainHeadings']/*[local-name()='data']/*[local-name()='text']";
    my $regex = '\d?\d\d\d\??\s*-\s*(\d?\d\d\d)[.,;)\s]*$';
    foreach my $node ($xpc->findnodes($pref))
    {
      my @vals = $node->findnodes($xpath);
      my $name2;
      foreach my $node2 (@vals)
      {
        my $val = $node2->string_value();
        my $val2 = $val;
        $val2 =~ s/[^A-Za-z]//g;
        #print "  Val $val\n";
        if ($val =~ m/$regex/)
        {
          my $add = $1;
          $add = undef if $val =~ m/(fl\.*|active)\s*$regex/i;
          if (defined $add)
          {
            ${$adds{$i}}{$add} = 1;
            $name2 = $val;
          }
        }
        if (length $a2 && $val2 =~ m/^$a2/)
        {
          $name = $name2 if $name2 =~ m/[A-Za-z]/;
          $name = $val unless defined $name;
          #print "    Name set to $name\n";
          $n = $i;
        }
      }
      $i++;
      last if $n > 0;
    }
    if ($n > 0)
    {
      $pref = "/*[local-name()='searchRetrieveResponse']/*[local-name()='records']/*[local-name()='record'][$n]/*[local-name()='recordData']";
      $xpath = "$pref/*[local-name()='VIAFCluster']/*[local-name()='nationalityOfEntity']/*[local-name()='data']/*[local-name()='text']";
      my @vals = $xpc->findnodes($xpath);
      if (@vals)
      {
        foreach my $val (@vals)
        {
          my $where = $val->string_value();
          if (defined $where && $where ne 'US' && $where ne 'XX')
          {
            $ret{'country'} = $where;
            last;
          }
        }
      }
    }
    if ($n > 0 && 1 == scalar keys %{$adds{$n}})
    {
      $ret{'add'} = (keys %{$adds{$n}})[0];
      $ret{'author'} = $name if defined $name;
    }
    if (defined $name)
    {
      $sql = 'INSERT INTO viaf (author,viaf_author,year,country) VALUES (?,?,?,?)';
      $self->PrepareSubmitSql($sql, $a, $ret{'author'}, $ret{'add'}, $ret{'country'});
    }
  }
  return (scalar keys %ret > 0)? \%ret:undef;
}

sub VIAFWarning
{
  my $self   = shift;
  my $id     = shift;
  my $record = shift;

  my %warnings;
  my @aus;
  $record = $self->GetMetadata($id) unless defined $record;
  my $au = $self->GetRecordAuthor($id, $record, 1);
  push @aus, $au if defined $au;
  my @add = $self->GetRecordAdditionalAuthors($id, $record);
  push @aus, $_ for @add;
  foreach $au (@aus)
  {
    my $data = $self->GetVIAFData($id, $au);
    if (defined $data and scalar keys %{$data} > 0)
    {
      my $country = $data->{'country'};
      if (defined $country && substr($country, 0, 2) ne 'US' &&
          substr($country, 0, 2) ne 'XX')
      {
        my $add = $data->{'add'};
        next if defined $add and $add <= 1895;
        my $last = $au;
        $last = $1 if $last =~ m/^(.+?),.*/;
        $warnings{"$last ($country)"} = 1;
      }
    }
  }
  return (scalar keys %warnings)? join '; ', keys %warnings:undef;
}

1;
