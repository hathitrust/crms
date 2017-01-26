package CRMS;

## ----------------------------------------------------------
## Object of shared code for the CRMS DB CGI and BIN scripts.
## ----------------------------------------------------------

#use warnings;
use strict;
use LWP::UserAgent;
use XML::LibXML;
use Encode;
use Date::Calc qw(:all);
use POSIX;
use DBI qw(:sql_types);
use List::Util qw(min max);
use CGI;
use Utilities;
use Time::HiRes;

binmode(STDOUT, ':utf8'); #prints characters in utf8

## -------------------------------------------------
##  Top level CRMS object. This guy does everything.
## -------------------------------------------------
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
  $self->set('errors',   $errors);
  $self->set('verbose',  $args{'verbose'});
  $self->set('root',     $root);
  $self->set('dev',      $args{'dev'});
  $self->set('pdb',      $args{'pdb'});
  $self->set('tdb',      $args{'tdb'});
  $self->set('debugSql', $args{'debugSql'});
  $self->set('debugVar', $args{'debugVar'});
  $self->set('sys',      $sys);
  my $user = $ENV{'REMOTE_USER'};
  $self->set('remote_user', $user);
  my $alias = $self->GetAlias($user);
  $user = $alias if defined $alias and length $alias and $alias ne $user;
  $self->set('user', $user);
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
  return '6.0.1';
}

# Is this CRMS-US or CRMS-World (or something else entirely)?
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
  my $dev       = $self->get('dev');
  my $root      = $self->get('root');
  my $sys       = $self->Sys();

  my $cfg = $root . '/bin/c/crms/' . $sys . 'pw.cfg';
  my %d = $self->ReadConfigFile($cfg);
  my $db_user   = $d{'mysqlUser'};
  my $db_passwd = $d{'mysqlPasswd'};
  if (!$dev || $self->get('pdb'))
  {
    $db_server = $self->get('mysqlServer');
  }
  my $db = $self->DbName();
  #if ($self->get('verbose')) { $self->Logit("DBI:mysql:crms:$db_server, $db_user, [passwd]"); }
  my $dbh = DBI->connect("DBI:mysql:$db:$db_server", $db_user, $db_passwd,
            { PrintError => 0, RaiseError => 1, AutoCommit => 1 }) || die "Cannot connect: $DBI::errstr";
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
  my $db   = shift;

  my $db_server = $self->get('mysqlMdpServerDev');
  my $dev       = $self->get('dev');
  my $root      = $self->get('root');
  my $sys       = $self->Sys();

  $db = $self->get('mysqlMdpDbName') unless defined $db;
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

sub DbName
{
  my $self = shift;

  my $dev = $self->get('dev');
  my $tdb = $self->get('tdb');
  my $db = $self->get('mysqlDbName');
  $db .= '_training' if $dev && ($dev eq 'crms-training' or $tdb);
  return $db;
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
  my $t1 = Time::HiRes::time();
  my $sth = $dbh->prepare($sql);
  eval { $sth->execute(@_); };
  my $t2 = Time::HiRes::time();
  $self->DebugSql($sql, 1000.0*($t2-$t1), @_);
  if ($@)
  {
    my $msg = sprintf 'SQL failed (%s): %s', Utilities::StringifySql($sql, @_), $sth->errstr;
    $self->SetError($msg);
    return 0;
  }
  return 1;
}

sub SimpleSqlGet
{
  my $self = shift;
  my $sql  = shift;

  my $ref = $self->SelectAll($sql, @_);
  return $ref->[0]->[0];
}

sub SimpleSqlGetSDR
{
  my $self = shift;
  my $sql  = shift;

  my $ref = $self->SelectAllSDR($sql, @_);
  return $ref->[0]->[0];
}

sub SelectAll
{
  my $self = shift;
  my $sql  = shift;

  my $ref = undef;
  my $dbh = $self->GetDb();
  my $t1 = Time::HiRes::time();
  eval {
    $ref = $dbh->selectall_arrayref($sql, undef, @_);
  };
  my $t2 = Time::HiRes::time();
  $self->DebugSql($sql, 1000.0*($t2-$t1), @_);
  if ($@)
  {
    my $msg = sprintf 'SQL failed (%s): %s', Utilities::StringifySql($sql, @_), $@;
    $self->SetError($msg);
    $self->Logit($msg);
  }
  return $ref;
}

sub SelectAllSDR
{
  my $self = shift;
  my $sql  = shift;

  my $ref = undef;
  my $dbh = $self->GetSdrDb();
  my $t1 = Time::HiRes::time();
  eval {
    $ref = $dbh->selectall_arrayref($sql, undef, @_);
  };
  my $t2 = Time::HiRes::time();
  $self->DebugSql($sql, 1000.0*($t2-$t1), @_);
  if ($@)
  {
    my $msg = sprintf 'SQL failed (%s): %s', Utilities::StringifySql($sql, @_), $@;
    $self->SetError($msg);
    $self->Logit($msg);
  }
  return $ref;
}

sub DebugSql
{
  my $self = shift;
  my $sql  = shift;
  my $time = shift;

  my $debug = $self->get('debugSql');
  if ($debug && $self->get('headerLoaded') == 1)
  {
    my $ct = $self->get('debugCount');
    $ct = 0 unless $ct;
    my @parts = split m/\s+/, $sql;
    my $type = uc $parts[0];
    my $trace = Utilities::LocalCallChain();
    $trace = join '<br>', @{$trace};
	  my $html = <<END;
    <div class="debug">
      <div class="debugSql" onClick="ToggleDiv('details$ct');">
        SQL QUERY [$type] ($ct)
      </div>
      <div id="details$ct" class="divHide"
           style="background-color: #9c9;" onClick="ToggleDiv('details$ct');">
        $sql <strong>{%s}</strong> <i>(%.3fms)</i><br/>
        <i>$trace</i>
      </div>
    </div>
END
    printf $html, join(',', @_), $time;
    $ct++;
    $self->set('debugCount', $ct);
  }
}

sub DebugVar
{
  my $self = shift;
  my $var  = shift;
  my $val  = shift;

  my $debug = $self->get('debugVar');
  if ($debug && $self->get('headerLoaded') == 1)
  {
    my $ct = $self->get('debugCount');
    $ct = 0 unless $ct;
	  my $html = <<END;
    <div class="debug">
      <div class="debugVar" onClick="ToggleDiv('details$ct');">
        VAR $var
      </div>
      <div id="details$ct" class="divHide"
           style="background-color: #fcc;" onClick="ToggleDiv('details$ct');">
        %s
      </div>
    </div>
END
    use Data::Dumper;
    printf $html, Dumper($val);
    $ct++;
    $self->set('debugCount', $ct);
  }
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
  my $self  = shift;
  my $quiet = shift;

  # Clear the deleted inheritances, regardless of system status
  my $sql = 'SELECT COUNT(*) FROM inherit WHERE status=0';
  my $dels = $self->SimpleSqlGet($sql);
  if ($dels)
  {
    print "Deleted inheritances to be removed: $dels\n" unless $quiet;
    $self->DeleteInheritances($quiet);
  }
  else
  {
    print "No deleted inheritances to remove.\n" unless $quiet;
  }
  # Get the underlying system status, ignoring replication delays.
  my ($blah, $stat, $msg) = @{$self->GetSystemStatus(1)};
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
    $self->SubmitInheritances($quiet);
  }
  else
  {
    print "Not auto-submitting inheritances because $reason.\n" unless $quiet;
  }
  $self->SetSystemStatus('partial', 'CRMS is processing reviews. The Review page is temporarily unavailable. Try back in about a minute.');
  my %stati = (2=>0,3=>0,4=>0,8=>0);
  $sql = 'SELECT id FROM reviews WHERE id IN (SELECT id FROM queue WHERE status=0) GROUP BY id HAVING count(*) = 2';
  my $ref = $self->SelectAll($sql);
  foreach my $row (@{$ref})
  {
    my $id = $row->[0];
    # Don't process anything that las a review less than 8 hours old.
    my $sql = 'SELECT COUNT(*) FROM reviews WHERE id=? AND time>DATE_SUB(NOW(), INTERVAL 8 HOUR)';
    if (0 < $self->SimpleSqlGet($sql, $id))
    {
      print "Not processing $id: it has one or more reviews less than 8 hours old\n" unless $quiet;
      next;
    }
    my $data = $self->CalcStatus($id, $stat);
    my $status = $data->{'status'};
    next unless $status > 0;
    my $hold = $data->{'hold'};
    if ($hold)
    {
      print "Not processing $id for $hold: it is held; system status is '$stat'\n" unless $quiet;
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
    $sql = 'UPDATE reviews SET hold=0,time=time WHERE id=?';
    $self->PrepareSubmitSql($sql, $id);
    $stati{$status}++;
  }
  print "Setting system status back to '$stat'\n" unless $quiet;
  $self->SetSystemStatus($stat, $msg);
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

  my $module = 'Validator_' . $self->Sys() . '.pm';
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
    my $module = 'Validator_' . $self->Sys() . '.pm';
    require $module;
    unshift @_, $id;
    unshift @_, $self;
    $pstatus = Validator::CalcPendingStatus(@_);
  }
  $self->RegisterPendingStatus($id, $pstatus);
}

# If quiet is set, don't try to create the export file, print stuff, or send mail.
sub ClearQueueAndExport
{
  my $self  = shift;
  my $quiet = shift;

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
  $self->ExportReviews($export, $quiet);
  $self->UpdateExportStats();
  $self->UpdateDeterminationsBreakdown();
  return "Removed from queue: $dCount matching, $eCount expert-reviewed, $aCount auto-resolved, $iCount inherited rights\n";
}

sub GetDoubleRevItemsInAgreement
{
  my $self = shift;
  my $sql  = 'SELECT id FROM queue WHERE status=4';
  return $self->SelectAll($sql);
}

sub GetExpertRevItems
{
  my $self = shift;
  my $sql  = 'SELECT id FROM queue WHERE status>=5 AND status<8 AND id IN'.
             ' (SELECT id FROM reviews WHERE hold=0)';
  return $self->SelectAll($sql);
}

sub GetAutoResolvedItems
{
  my $self = shift;
  my $sql  = 'SELECT id FROM queue WHERE status=8';
  return $self->SelectAll($sql);
}

sub GetInheritedItems
{
  my $self = shift;
  my $sql  = 'SELECT id FROM queue WHERE status=9';
  return $self->SelectAll($sql);
}

## ----------------------------------------------------------------------------
##  Function:   create a tab file of reviews to be loaded into the rights table
##              vol id | attr | reason | user | null
##              mdp.123 | ic   | ren    | crms | null
##  Parameters: $list: A reference to a list of volume ids
##              $quiet: Suppress printing out progress info if called from CGI
##  Return:     nothing
## ----------------------------------------------------------------------------
sub ExportReviews
{
  my $self  = shift;
  my $list  = shift;
  my $quiet = shift;

  if ($self->GetSystemVar('noExport') && !$quiet)
  {
    print ">>> noExport system variable is set; will only export high-priority volumes.\n";
  }
  my $count = 0;
  my $user = $self->Sys();
  my ($fh, $temp, $perm) = $self->GetExportFh() unless $quiet;
  print ">>> Exporting to $temp.\n" unless $quiet;
  my $start_size = $self->GetCandidatesSize();
  foreach my $id (@{$list})
  {
    my ($attr,$reason) = $self->GetFinalAttrReason($id);
    my $export = $self->CanExportVolume($id, $attr, $reason, $quiet);
    if ($export)
    {
      print $fh "$id\t$attr\t$reason\t$user\tnull\n" unless $quiet;
    }
    my $sql = 'SELECT status,priority,source,added_by,newproject,ticket FROM queue WHERE id=?';
    my $ref = $self->SelectAll($sql, $id);
    my $status = $ref->[0]->[0];
    my $pri = $ref->[0]->[1];
    my $src = $ref->[0]->[2];
    my $added_by = $ref->[0]->[3];
    my $proj = $ref->[0]->[4];
    my $tx = $ref->[0]->[5];
    $sql = 'INSERT INTO exportdata (id,attr,reason,status,priority,src,added_by,newproject,ticket,exported)'.
           ' VALUES (?,?,?,?,?,?,?,?,?,?)';
    $self->PrepareSubmitSql($sql, $id, $attr, $reason, $status, $pri, $src, $added_by, $proj, $tx, $export);
    my $gid = $self->SimpleSqlGet('SELECT MAX(gid) FROM exportdata WHERE id=?', $id);
    $self->MoveFromReviewsToHistoricalReviews($id, $gid);
    $self->RemoveFromQueue($id);
    $self->RemoveFromCandidates($id);
    $count++;
  }
  if (!$quiet)
  {
    close $fh;
    print ">>> Moving to $perm.\n";
    rename $temp, $perm;
  }
  # Update correctness/validation now that everything is in historical
  foreach my $id (@{$list})
  {
    my $sql = 'SELECT user,time,validated FROM historicalreviews WHERE id=?';
    my $ref = $self->SelectAll($sql, $id);
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
  if (!$quiet)
  {
    printf "After export, removed %d volumes from candidates.\n", $start_size-$self->GetCandidatesSize();
    eval { $self->EmailReport($count, $perm); };
    $self->SetError("EmailReport() failed: $@") if $@;
  }
}

# In overnight processing this is called BEFORE queue deletion and move to historical
sub CanExportVolume
{
  my $self   = shift;
  my $id     = shift;
  my $attr   = shift;
  my $reason = shift;
  my $quiet  = shift;
  my $gid    = shift; # Optional
  my $time   = shift; # Optional

  my $export = 1;
  # Do not export Status 6, since they are not really final determinations.
  my $status = $self->SimpleSqlGet('SELECT status FROM queue WHERE id=?', $id);
  if (!defined $status && defined $gid)
  {
    my $sql = 'SELECT COUNT(*) FROM historicalreviews WHERE gid=? AND status=6';
    $status = ($self->SimpleSqlGet($sql, $gid))? 6:4;
  }
  if ($status == 6)
  {
    print "Not exporting $id; it is status 6\n" unless $quiet;
    return 0;
  }
  my $pri = $self->SimpleSqlGet('SELECT priority FROM queue WHERE id=?', $id);
  if (defined $gid && !defined $pri)
  {
    my $sql = 'SELECT MAX(priority) FROM historicalreviews WHERE gid=?';
    $pri = $self->SimpleSqlGet($sql, $gid);
  }
  if ($self->GetSystemVar('noExport'))
  {
    if ($pri>=3)
    {
      print "Exporting $id; noExport is on but it is priority $pri\n" unless $quiet;
      return 1;
    }
    else
    {
      print "Not exporting $id; noExport is on and it is priority $pri\n" unless $quiet;
      return 0;
    }
  }
  my $rq = $self->RightsQuery($id, 1);
  return 0 unless defined $rq;
  my ($attr2,$reason2,$src2,$usr2,$time2,$note2) = @{$rq->[0]};
  my $cm = $self->CandidatesModule();
  # Do not export determination if the volume has gone out of scope,
  # or if exporting und would clobber pdus in World.
  if (!$cm->HasCorrectRights($attr2, $reason2, $attr, $reason))
  {
    # But, we clobber OOS if any of the following conditions hold:
    # 1. Current rights are pdus/gfv (which per rrotter in Core Services never overrides pd/bib)
    #    and determination is not und.
    # 2. Current rights are */bib (unless a und would clobber pdus/bib).
    # 3. Priority 3 or higher.
    # 4. Previous rights were by user crms*.
    # 5. The determination is pd* (unless a pdus would clobber pd/bib).
    if (($reason2 eq 'gfv' && $attr ne 'und')
        || ($reason2 eq 'bib' && !($attr eq 'und' && $attr2 =~ m/^pd/))
        || $pri >= 3.0
        || $usr2 =~ m/^crms/i
        || ($attr =~ m/^pd/ && !($attr eq 'pdus' && $attr2 eq 'pd')))
    {
      # This is used for cleanup purposes
      if (defined $time)
      {
        if ($usr2 =~ m/^crms/ && $time lt $time2)
        {
          print "Not exporting $id as $attr/$reason; there is a newer CRMS export ($attr2/$reason2 by $usr2 [$time2])\n" unless $quiet;
          $export = 0;
        }
      }
      print "Exporting priority $pri $id as $attr/$reason even though it is out of scope ($attr2/$reason2 by $usr2 [$time2])\n"
            unless $quiet or $export == 0;
    }
    else
    {
      print "Not exporting $id as $attr/$reason; it is out of scope ($attr2/$reason2)\n" unless $quiet;
      $export = 0;
    }
  }
  return $export;
}

# Send email with rights export data.
sub EmailReport
{
  my $self    = shift;
  my $count   = shift;
  my $file    = shift;

  my $where = ($self->WhereAmI() || 'Prod');
  if ($where eq 'Prod')
  {
    my $subject = sprintf('%s %s: %d volumes exported to rights db', $self->System(), $where, $count);
    use Mail::Sender;
    my $sender = new Mail::Sender
      {smtp => 'mail.umdl.umich.edu',
       from => $self->GetSystemVar('adminEmail')};
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
  my $perm = $self->get('root'). $self->get('dataDir'). '/'. $self->Sys(). '_'. $date. '.rights';
  my $temp = $perm . '.tmp';
  if (-f $temp) { die "file already exists: $temp\n"; }
  open (my $fh, '>', $temp) || die "failed to open exported file ($temp): $!\n";
  return ($fh, $temp, $perm);
}

# Remove from the queue only if the volume is untouched.
# Optionally filters volume if $filter is specified.
# Returns 1 if successful, undef otherwise.
sub SafeRemoveFromQueue
{
  my $self   = shift;
  my $id     = shift;
  my $filter = shift;

  my $sql = 'UPDATE queue SET priority=-2 WHERE id=? AND priority<3'.
            ' AND locked IS NULL AND status=0 AND pending_status=0';
  $self->PrepareSubmitSql($sql, $id);
  $sql = 'DELETE FROM queue WHERE id=? AND priority=-2'.
         ' AND locked IS NULL AND status=0 AND pending_status=0';
  $self->PrepareSubmitSql($sql, $id);
  $self->Filter($id, $filter) if defined $filter;
  $sql = 'SELECT COUNT(*) FROM queue WHERE id=?';
  return ($self->SimpleSqlGet($sql, $id) == 0)? 1:undef;
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
  my $start  = shift;
  my $end    = shift;

  my $now = (defined $end)? $end : $self->GetTodaysDate();
  $start = $self->SimpleSqlGet('SELECT max(time) FROM candidatesrecord') unless $start;
  my $start_size = $self->GetCandidatesSize();
  print "Candidates size is $start_size, last load time was $start\n";
  my $sql = 'SELECT id FROM und WHERE src="no meta"';
  my $ref = $self->SelectAll($sql);
  my $n = scalar @{$ref};
  if ($n)
  {
    print "Checking $n possible no-meta additions to candidates\n";
    $self->CheckAndLoadItemIntoCandidates($_->[0]) for @{$ref};
    $n = $self->SimpleSqlGet('SELECT COUNT(*) FROM und WHERE src="no meta"');
    print "Number of no-meta volumes now $n.\n";
  }
  my $endclause = ($end)? " AND time<='$end' ":' ';
  $sql = 'SELECT namespace,id FROM rights_current WHERE time>?' . $endclause . 'ORDER BY time ASC';
  my $ref = $self->SelectAllSDR($sql, $start);
  my $n = scalar @{$ref};
  print "Checking $n possible additions to candidates from rights DB\n";
  foreach my $row (@{$ref})
  {
    my $id = $row->[0] . '.' . $row->[1];
    $self->CheckAndLoadItemIntoCandidates($id);
  }
  my $end_size = $self->GetCandidatesSize();
  my $diff = $end_size - $start_size;
  print "After load, candidates has $end_size volumes. Added $diff.\n\n";
  # Record the update
  $sql = 'INSERT INTO candidatesrecord (time,addedamount) VALUES (?,?)';
  $self->PrepareSubmitSql($sql, $now, $diff);
}

# Does all checks to see if a volume should be in the candidates or und tables, removing
# it from either table if it is already in one and no longer qualifies.
# If necessary, updates the system table with a new sysid.
# If noop is defined, does nothing that would actually alter the table.
sub CheckAndLoadItemIntoCandidates
{
  my $self   = shift;
  my $id     = shift;
  my $noop   = shift;
  my $record = shift;

  my $incand = $self->SimpleSqlGet('SELECT id FROM candidates WHERE id=?', $id);
  my $inund  = $self->SimpleSqlGet('SELECT src FROM und WHERE id=?', $id);
  my $inq    = $self->IsVolumeInQueue($id);
  my $rq = $self->RightsQuery($id, 1);
  if (!defined $rq)
  {
    print "Can't get rights for $id, filtering\n";
    $self->Filter($id, 'no meta') unless $noop;
    return;
  }
  my ($attr,$reason,$src,$usr,$time,$note) = @{$rq->[0]};
  my $cm = $self->CandidatesModule();
  my $oldSysid = $self->SimpleSqlGet('SELECT sysid FROM bibdata WHERE id=?', $id);
  if (defined $oldSysid)
  {
    $record = $self->GetMetadata($id);
    if (defined $record)
    {
      my $sysid = $record->sysid;
      if (defined $sysid && defined $oldSysid && $sysid ne $oldSysid)
      {
        print "Update system IDs from $oldSysid to $sysid\n";
        $self->UpdateSysids($record) unless defined $noop;
      }
    }
  }
  if (!$cm->HasCorrectRights($attr, $reason))
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
    if ($inund)
    {
      $self->PrepareSubmitSql('DELETE FROM und WHERE id=?', $id);
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
  if ($self->SimpleSqlGet('SELECT COUNT(*) FROM inherit WHERE id=?', $id) > 0)
  {
    print "Skip $id -- already inheriting\n";
    return;
  }
  if (defined $incand)
  {
    print "Skip $id -- already in candidates\n";
    $self->PrepareSubmitSql('DELETE FROM und WHERE id=?', $id) if defined $inund and !defined $noop;
    return;
  }
  $record = $self->GetMetadata($id) unless defined $record;
  if (!defined $record)
  {
    $self->Filter($id, 'no meta') unless defined $noop;
    $self->ClearErrors();
    return;
  }
  my $errs = $self->GetViolations($id, $record);
  if (scalar @{$errs} == 0)
  {
    my $src = $self->ShouldVolumeBeFiltered($id, $record);
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
      $self->AddItemToCandidates($id, $time, $record, $noop);
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
  my $record = shift || $self->GetMetadata($id);
  my $noop   = shift;
  my $quiet  = shift;

  return unless defined $record;
  # Are there duplicates w/ nonmatching enumchron? Filter those.
  my $chron = $record->enumchron($id) || '';
  my $sysid = $record->sysid;
  my $rows = $self->VolumeIDsQuery($sysid, $record);
  foreach my $ref (@{$rows})
  {
    my $id2 = $ref->{'id'};
    next if $id2 eq $id;
    next unless $self->IsVolumeInCandidates($id2);
    if ($record->doEnumchronMatch($id, $id2))
    {
      my $chron2 = $record->enumchron($id2) || '';
      printf "Filter $id2%s as duplicate of $id%s\n",
            (length $chron)? " ($chron)":'', (length $chron2)? " ($chron2)":'' unless $quiet;
      $self->Filter($id2, 'duplicate') unless $noop;
    }
  }
  if (!$self->IsVolumeInCandidates($id))
  {
    my $project = $self->GetCandidateProject($id, $record);
    my $proj = $self->SimpleSqlGet('SELECT id FROM projects WHERE name=?', $project);
    $proj = 1 unless defined $proj;
    printf "Add $id to candidates for project '$project' ($proj)\n" unless $quiet;
    my $sql = 'INSERT INTO candidates (id,time,newproject) VALUES (?,?,?)';
    $self->PrepareSubmitSql($sql, $id, $time, $proj) unless $noop;
    $self->PrepareSubmitSql('DELETE FROM und WHERE id=?', $id) unless $noop;
  }
  if ($self->GetSystemVar('cri') && defined $self->CheckForCRI($id, $noop, $quiet))
  {
    print "Filter $id as CRI\n" unless $quiet;
    $self->Filter($id, 'cross-record inheritance') unless $noop;
  }
  else
  {
    $self->PrepareSubmitSql('DELETE FROM und WHERE id=?', $id) unless $noop;
  }
  $self->UpdateMetadata($id, 1, $record) unless $noop;
}

# Returns the gid of the determination inheriting from, or undef if no inheritance.
sub CheckForCRI
{
  my $self  = shift;
  my $id    = shift;
  my $noop  = shift;
  my $quiet = shift;

  my $cri = $self->get('criModule');
  if (!defined $cri)
  {
    use CRI;
    $cri = CRI->new('crms' => $self);
    $self->set('criModule', $cri);
  }
  my $gid = $cri->CheckVolume($id);
  if (defined $gid)
  {
    print "Adding CRI for $id ($gid)\n" unless $quiet;
    my $sql = 'INSERT INTO cri (id,gid) VALUES (?,?)';
    $self->PrepareSubmitSql($sql, $id, $gid) unless $noop;
    return $gid;
  }
  return undef;
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

# Returns concatenated error messages (reasons for unsuitability for CRMS) for a volume.
# Checks everything including current rights, but ignores rights if currently und;
# also checks for a latest expert non-und determination.
# This is for evaluating corrections.
sub IsVolumeInScope
{
  my $self   = shift;
  my $id     = shift;
  my $record = shift;

  $record = $self->GetMetadata($id) unless defined $record;
  return 'No metadata' unless defined $record;
  my $errs = $self->GetViolations($id, $record);
  if (scalar @{$errs})
  {
    my $joined = join '; ', @{$errs};
    $errs = [] if $joined =~ m/^current\srights\sund\/[a-z]+$/i;
  }
  my $und = $self->ShouldVolumeBeFiltered($id, $record);
  push @{$errs}, 'should be filtered (' . $und . ')' if defined $und;
  push @{$errs}, 'already in the queue' if $self->IsVolumeInQueue($id);
  my $sql = 'SELECT COUNT(*) FROM exportdata e INNER JOIN historicalreviews r' .
            ' ON e.gid=r.gid WHERE e.id=? AND e.attr!="und" AND r.expert IS NOT NULL' .
            ' AND r.expert>0';
  my $cnt = $self->SimpleSqlGet($sql, $id);
  push @{$errs}, 'non-und expert review' if $cnt > 0;
  return ucfirst join '; ', @{$errs} if scalar @{$errs} > 0;
  return undef;
}

sub CandidatesModule
{
  my $self = shift;

  my $mod = $self->get('Candidates');
  if (!defined $mod)
  {
    my $class = 'Candidates_' . $self->Sys();
    require $class . '.pm';
    $mod =  $class->new($self);
    if (!defined $mod || $@)
    {
      $self->SetError("Could not load module $class\n");
      return;
    }
    $self->set('Candidates', $mod);
  }
  return $mod;
}

# Returns an array of error messages (reasons for unsuitability for CRMS) for a volume.
# Used by candidates loading to ignore inappropriate items.
# Used by Add to Queue page for filtering non-overrides.
sub GetViolations
{
  my $self     = shift;
  my $id       = shift;
  my $record   = shift || $self->GetMetadata($id);
  my $priority = shift;
  my $override = shift;

  $priority = 0 unless $priority;
  my @errs = ();
  if (!$record)
  {
    push @errs, 'not found in HathiTrust';
  }
  elsif ($priority < 4 || !$override)
  {
    @errs = $self->CandidatesModule()->GetViolations($id, $record, $priority, $override);
  }
  my $ref = $self->RightsQuery($id, 1);
  $ref = $ref->[0] if $ref;
  if ($ref)
  {
    my ($attr,$reason,$src,$usr,$time,$note) = @{$ref};
    push @errs, "current rights $attr/$reason" unless $self->CandidatesModule()->HasCorrectRights($attr, $reason) or
                                                ($override and $priority >= 3) or
                                                $priority == 4;
  }
  else
  {
    push @errs, "rights query for $id failed";
  }
  return \@errs;
}

sub GetCutoffYear
{
  my $self = shift;
  my $name = shift;

  return $self->CandidatesModule()->GetCutoffYear(undef, $name);
}

# Returns a hash ref of Country name => 1 covered by the system.
# If oneoff is set, return undef to indicate this is the
# catch-all system.
sub GetCountries
{
  my $self   = shift;
  my $oneoff = shift;

  return $self->CandidatesModule()->Countries($oneoff);
}

# Returns a und table src code if the volume belongs in the und table instead of candidates.
sub ShouldVolumeBeFiltered
{
  my $self   = shift;
  my $id     = shift;
  my $record = shift;

  $record = $self->GetMetadata($id) unless $record;
  return 'no meta' unless defined $record;
  return $self->CandidatesModule()->ShouldVolumeBeFiltered($id, $record);
}

# Returns a project name string or undef.
sub GetCandidateProject
{
  my $self   = shift;
  my $id     = shift;
  my $record = shift || $self->GetMetadata($id);

  return $self->CandidatesModule()->GetProject($id, $record);
}

sub GetQueueSize
{
  my $self = shift;

  return $self->SimpleSqlGet('SELECT COUNT(*) FROM queue');
}

sub UpdateQueueRecord
{
  my $self  = shift;
  my $count = shift;
  my $src   = shift;

  my $sql = 'SELECT MAX(time) FROM queuerecord WHERE source=? AND time>=DATE_SUB(NOW(),INTERVAL 1 MINUTE)';
  my $then = $self->SimpleSqlGet($sql, $src);
  if ($then)
  {
    $sql = 'UPDATE queuerecord SET itemcount=itemcount+?,time=NOW() WHERE source=? AND time=? LIMIT 1';
    $self->PrepareSubmitSql($sql, $count, $src, $then);
  }
  else
  {
    $sql = 'INSERT INTO queuerecord (itemcount,source) VALUES (?,?)';
    $self->PrepareSubmitSql($sql, $count, $src);
  }
}

sub LoadQueue
{
  my $self = shift;

  my $before = $self->GetQueueSize();
  my $sql = 'SELECT DISTINCT newproject FROM candidates';
  $self->LoadQueueForProject($_->[0]) for @{$self->SelectAll($sql)};
  my $after = $self->SimpleSqlGet('SELECT COUNT(*) FROM queue');
  $self->UpdateQueueRecord($after - $before, 'candidates');
}

# Load candidates into queue for a given project (which may be NULL/undef).
sub LoadQueueForProject
{
  my $self    = shift;
  my $project = shift;

  # WHERE NULL handling derived from CPAN DBI documentation.
  my $sql = 'SELECT COUNT(*) FROM queue WHERE newproject=?';
  my $queueSize = $self->SimpleSqlGet($sql, $project);
  my $targetQueueSize = $self->GetSystemVar('queueSize');
  my $needed = $targetQueueSize - $queueSize;
  printf "Before load, the queue has $queueSize volumes%s -- need $needed for project '$project'";
  return if $needed <= 0;
  my $count = 0;
  my %dels = ();
  $sql = 'SELECT id FROM candidates'.
         ' WHERE id NOT IN (SELECT DISTINCT id FROM inherit)'.
         ' AND id NOT IN (SELECT DISTINCT id FROM queue)'.
         ' AND id NOT IN (SELECT DISTINCT id FROM reviews)'.
         ' AND id NOT IN (SELECT DISTINCT id FROM historicalreviews)'.
         ' AND time<=DATE_SUB(NOW(), INTERVAL 1 WEEK) AND project=?'.
         ' ORDER BY time DESC';
  #print "$sql\n";
  my $ref = $self->SelectAll($sql, $project);
  foreach my $row (@{$ref})
  {
    my $id = $row->[0];
    next if $dels{$id};
    my $record = $self->GetMetadata($id);
    if (!defined $record)
    {
      print "Filtering $id: can't get metadata for queue\n";
      $self->Filter($id, 'no meta');
      next;
    }
    my @errs = @{ $self->GetViolations($id, $record) };
    if (scalar @errs)
    {
      printf "Will delete $id: %s\n", join '; ', @errs;
      $dels{$id} = 1;
      next;
    }
    # FIXME: this is the wrong place to do this.
    if (!$record->countEnumchron)
    {
      my $dup = $self->IsRecordInQueue($record->sysid, $record);
      if ($dup)
      {
        my $sysid = $record->sysid;
        print "Filtering $id: queue has $dup on $sysid (no chron/enum)\n";
        $self->Filter($id, 'duplicate');
        next;
      }
    }
    if ($self->AddItemToQueue($id, $record, $project))
    {
      print "Added to queue: $id\n";
      $count++;
    }
    last if $count >= $needed;
  }
  $self->RemoveFromCandidates($_) for keys %dels;
}

sub IsRecordInQueue
{
  my $self   = shift;
  my $sysid  = shift;
  my $record = shift;

  my $rows = $self->VolumeIDsQuery($sysid, $record);
  foreach my $ref (@{$rows})
  {
    my $id = $ref->{'id'};
    return $id if $self->SimpleSqlGet('SELECT COUNT(*) FROM queue WHERE id=?', $id);
  }
  return undef;
}

# Plain vanilla code for adding an item with status 0, priority 0
# Returns 1 if item was added, 0 if not added because it was already in the queue.
sub AddItemToQueue
{
  my $self     = shift;
  my $id       = shift;
  my $record   = shift;
  my $project  = shift;

  return 0 if $self->IsVolumeInQueue($id);
  $record = $self->GetMetadata($id) unless defined $record;
  # queue table has priority and status default to 0, time to current timestamp.
  $self->PrepareSubmitSql('INSERT INTO queue (id,newproject) VALUES (?,?)', $id, $project);
  $self->UpdateMetadata($id, 1, $record);
  return 1;
}

# Returns a hashref with 'status' => {0=Add, 1=Error, 2=Modify}
# and optional 'msg' with human-readable text.
# FiXME: merge this with AddItemToQueue() to include a project.
sub AddItemToQueueOrSetItemActive
{
  my $self     = shift;
  my $id       = shift;
  my $priority = shift;
  my $override = shift;
  my $src      = shift || 'adminui';
  my $user     = shift || $self->get('user');
  my $noop     = shift || undef;
  my $record   = shift || undef;
  my $project  = shift || undef;
  my $ticket   = shift || undef;

  my $stat = 0;
  my @msgs = ();
  ## give the existing item higher or lower priority
  if ($self->IsVolumeInQueue($id))
  {
    my $sql = 'SELECT COUNT(*) FROM reviews WHERE id=?';
    my $n = $self->SimpleSqlGet($sql, $id);
    $sql = 'UPDATE queue SET priority=?, time=NOW(), source=?, newproject=?, added_by=?, ticket=? WHERE id=?';
    $self->PrepareSubmitSql($sql, $priority, $src, $project, $user, $ticket, $id) unless $noop;
    push @msgs, 'queue item updated';
    $stat = 2;
    if ($n)
    {
      my $rlink = sprintf("already has $n <a href='?p=adminReviews;search1=Identifier;search1value=$id' target='_blank'>%s</a>",
                          $self->Pluralize('review', $n));
      push @msgs, $rlink;
    }
  }
  else
  {
    $record = $self->GetMetadata($id) unless defined $record;
    if (!defined $record)
    {
      $self->ClearErrors();
      return {'status' => 1, 'msg' => 'not a valid HathiTrust identifier'};
    }
    my $issues = '';
    @msgs = @{ $self->GetViolations($id, $record, $priority, $override) };
    $issues = join '; ', @msgs if scalar @msgs;
    if (scalar @msgs && !$override && $issues !~ m/not\sfound/i)
    {
      $stat = 1;
    }
    else
    {
      my $existing = $self->SimpleSqlGet('SELECT issues FROM queue WHERE id=?', $id);
      $issues = $existing if defined $existing;
      my $sql = 'INSERT INTO queue (id,priority,source,issues,newproject,added_by,ticket) VALUES (?,?,?,?,?,?,?)';
      $self->PrepareSubmitSql($sql, $id, $priority, $src, $issues, $project, $user, $ticket) unless $noop;
      $self->UpdateMetadata($id, 1, $record) unless $noop;
      $self->UpdateQueueRecord(1, $src) unless $noop;
    }
  }
  return {'status' => $stat, 'msg' => join '; ', @msgs};
}

# Used by experts to approve a review made by a reviewer.
# Returns an error message.
sub CloneReview
{
  my $self = shift;
  my $id   = shift;
  my $user = shift;

  my $result = $self->LockItem($id, $user, 1);
  return $result if $result;
  # SubmitReview unlocks it if it succeeds.
  if ($self->HasItemBeenReviewedByUser($id, $user))
  {
    $result = "Could not approve review for $id because you already reviewed it.";
    $self->UnlockItem($id, $user);
  }
  elsif ($self->HasItemBeenReviewedByAnotherExpert($id, $user))
  {
    $result = "Could not approve review for $id because it has already been reviewed by an expert.";
  }
  else
  {
    my $note = undef;
    my $sql = 'SELECT attr,reason,renNum,renDate FROM reviews WHERE id=?';
    my $rows = $self->SelectAll($sql, $id);
    my $attr = $rows->[0]->[0];
    my $reason = $rows->[0]->[1];
    if ($attr == 2 && $reason == 7 &&
        ($rows->[0]->[2] ne $rows->[1]->[2] ||
         $rows->[0]->[3] ne $rows->[1]->[3]))
    {
      $note = sprintf 'Nonmatching renewals: %s (%s) vs %s (%s)',
                      $rows->[0]->[2], $rows->[0]->[3], $rows->[1]->[2], $rows->[1]->[3];
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
  my ($id, $user, $attr, $reason, $note, $renNum, $exp,
      $renDate, $category, $swiss, $hold, $pre, $start) = @_;

  if (!$self->CheckReviewer($user, $exp))              { $self->SetError("reviewer ($user) check failed"); return 0; }
  # ValidateAttrReasonCombo sets error internally on fail.
  if (!$self->ValidateAttrReasonCombo($attr, $reason)) { return 0; }
  #remove any blanks from renNum
  $renNum =~ s/\s+//gs;
  # Javascript code inserts the string 'searching...' into the review text box.
  # This in once case got submitted as the renDate in production
  $renDate = '' if $renDate =~ m/searching.*/i;
  $renDate =~ s/^\s+|\s+$//gs;
  my @fields = qw(id user attr reason note renNum renDate category);
  my @values = ($id, $user, $attr, $reason, $note, $renNum, $renDate, $category);
  push(@fields, 'hold');
  push(@values, ($hold)? 1:0);
  my $dur = $self->SimpleSqlGet('SELECT TIMEDIFF(NOW(),?)', $start);
  my $sql = 'SELECT duration FROM reviews WHERE user=? AND id=?';
  my $dur2 = $self->SimpleSqlGet($sql, $user, $id);
  if (defined $dur2)
  {
    $dur = $self->SimpleSqlGet('SELECT ADDTIME(?,?)', $dur, $dur2);
  }
  if (defined $dur)
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
  if (defined $pre)
  {
    push(@fields, 'prepopulated');
    push(@values, $pre);
  }
  my $wcs = $self->WildcardList(scalar @values);
  $sql = 'REPLACE INTO reviews (' . join(',', @fields) . ') VALUES ' . $wcs;
  my $result = $self->PrepareSubmitSql($sql, @values);
  if ($result)
  {
    if ($exp ||
        (defined $category &&
         ($category eq 'Missing' || $category eq 'Wrong Record')))
    {
      $sql = 'SELECT COUNT(*) FROM reviews WHERE id=? AND expert=1';
      my $expcnt = $self->SimpleSqlGet($sql, $id);
      $sql = 'UPDATE queue SET expcnt=? WHERE id=?';
      $result = $self->PrepareSubmitSql($sql, $expcnt, $id);
      my $status = $self->GetStatusForExpertReview($id, $user, $attr, $reason, $category, $renNum, $renDate);
      $self->RegisterStatus($id, $status);
      # Clear all non-expert holds
      $sql = 'UPDATE reviews SET hold=0,time=time WHERE id=?'.
             ' AND user NOT IN (SELECT id FROM users WHERE expert=1)';
      $self->PrepareSubmitSql($sql, $id);
    }
    $self->CheckPendingStatus($id);
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

  return 6 if $category eq 'Missing' or $category eq 'Wrong Record';
  return 7 if $category eq 'Expert Accepted';
  return 9 if $category eq 'Rights Inherited';
  my $status = 5;
  # See if it's a provisional match and expert agreed with both of existing non-advanced reviews. If so, status 7.
  my $sql = 'SELECT attr,reason,renNum,renDate FROM reviews WHERE id=?' .
            ' AND user IN (SELECT id FROM users WHERE expert=0 AND advanced=0)';
  my $ref = $self->SelectAll($sql, $id);
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

sub GetProject
{
  my $self = shift;
  my $id   = shift;
  my $name = shift;

  my $sql = 'SELECT '. (($name)? 'p.name':'p.id').
            ' FROM queue q INNER JOIN projects p ON q.newproject=p.id WHERE q.id=?';
  return $self->SimpleSqlGet($sql, $id);
}

sub MoveFromReviewsToHistoricalReviews
{
  my $self = shift;
  my $id   = shift;
  my $gid  = shift;

  my $sql = 'INSERT INTO historicalreviews (id,time,user,attr,reason,note,' .
            'renNum,expert,duration,legacy,renDate,category,swiss,prepopulated,gid)' .
            ' SELECT id,time,user,attr,reason,note,renNum,expert,duration,legacy,' .
            'renDate,category,swiss,prepopulated,? FROM reviews WHERE id=?';
  $self->PrepareSubmitSql($sql, $gid, $id);
  $sql = 'DELETE FROM reviews WHERE id=?';
  $self->PrepareSubmitSql($sql, $id);
  $sql = 'SELECT user FROM historicalreviews WHERE gid=?';
  my $ref = $self->SelectAll($sql, $gid);
  foreach my $row (@{$ref})
  {
    my $user = $row->[0];
    my $flag = $self->ShouldReviewBeFlagged($gid, $user);
    if (defined $flag)
    {
      $sql = 'UPDATE historicalreviews SET flagged=? WHERE gid=? AND user=?';
      $self->PrepareSubmitSql($sql, $flag, $gid, $user);
    }
  }
}

sub GetFinalAttrReason
{
  my $self = shift;
  my $id   = shift;

  ## order by expert so that if there is an expert review, return that one
  my $sql = 'SELECT a.name,rs.name FROM reviews r'.
            ' INNER JOIN attributes a ON r.attr=a.id'.
            ' INNER JOIN reasons rs ON r.reason=rs.id'.
            ' WHERE r.id=? ORDER BY r.expert DESC, r.time DESC LIMIT 1';
  #print "$sql\n";
  my $ref = $self->SelectAll($sql, $id);
  if (!$ref->[0]->[0])
  {
    $self->SetError("$id not found in review table");
  }
  my $attr   = $ref->[0]->[0];
  my $reason = $ref->[0]->[1];
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

sub CountHolds
{
  my $self = shift;
  my $user = shift || $self->get('user');

  return $self->SimpleSqlGet('SELECT COUNT(*) FROM reviews WHERE user=? AND hold=1', $user);
}

sub HoldForItem
{
  my $self = shift;
  my $id   = shift;
  my $user = shift;

  return $self->SimpleSqlGet('SELECT hold FROM reviews WHERE id=? AND user=?', $id, $user);
}

sub WasYesterdayWorkingDay
{
  my $self = shift;
  my $time = shift;

  $time = $self->GetTodaysDate() unless $time;
  my @parts = split '-', substr($time, 0, 10);
  my ($y,$m,$d) = Date::Calc::Add_Delta_Days($parts[0], $parts[1], $parts[2], -1);
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
  return ($cal->is_full($parts[0], $parts[1], $parts[2]))? 0:1;
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
  my $self   = shift;
  my $search = shift;
  my $page   = shift;
  my $order  = shift;

  my $prefix = ($page eq 'queue' || $page eq 'exportData')? 'q.':'r.';
  my $new_search = $search;
  if (!$search || $search eq 'Identifier')
  {
    $new_search = $prefix. 'id';
  }
  if ($search eq 'Date')
  {
    $new_search = $prefix. 'time';
    $new_search = "DATE($new_search)" unless $order;
  }
  elsif ($search eq 'UserId') { $new_search = 'r.user'; }
  elsif ($search eq 'Status') { $new_search = 'q.status'; }
  elsif ($search eq 'Attribute') { $new_search = $prefix. 'attr'; }
  elsif ($search eq 'Reason') { $new_search = $prefix. 'reason'; }
  elsif ($search eq 'NoteCategory') { $new_search = 'r.category'; }
  elsif ($search eq 'Note') { $new_search = 'r.note'; }
  elsif ($search eq 'Legacy') { $new_search = 'r.legacy'; }
  elsif ($search eq 'Title') { $new_search = 'b.title'; }
  elsif ($search eq 'Author') { $new_search = 'b.author'; }
  elsif ($search eq 'Priority') { $new_search = 'q.priority'; }
  elsif ($search eq 'Validated') { $new_search = 'r.validated'; }
  elsif ($search eq 'PubDate') { $new_search = 'b.pub_date'; }
  elsif ($search eq 'Locked') { $new_search = 'q.locked'; }
  elsif ($search eq 'ExpertCount') { $new_search = 'q.expcnt'; }
  elsif ($search eq 'Reviews')
  {
    $new_search = '(SELECT COUNT(*) FROM reviews r WHERE r.id=q.id)';
  }
  elsif ($search eq 'Swiss') { $new_search = 'r.swiss'; }
  elsif ($search eq 'SysID') { $new_search = 'b.sysid'; }
  elsif ($search eq 'Holds')
  {
    $new_search = '(SELECT COUNT(*) FROM reviews r WHERE r.id=q.id AND r.hold=1)';
  }
  elsif ($search eq 'Source')
  {
    $new_search = ($page eq 'queue')? 'q.source':'q.src';
  }
  elsif ($search eq 'Project') { $new_search = 'p.name'; }
  elsif ($search eq 'GID') { $new_search = $prefix. 'gid'; }
  elsif ($search eq 'AddedBy') { $new_search = 'q.added_by'; }
  elsif ($search eq 'Ticket') { $new_search = 'q.ticket'; }
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

  $search1 = $self->ConvertToSearchTerm($search1, $page);
  $search2 = $self->ConvertToSearchTerm($search2, $page);
  $search3 = $self->ConvertToSearchTerm($search3, $page);
  $order = $self->ConvertToSearchTerm($order, $page, 1);
  $dir = 'DESC' unless $dir;
  $offset = 0 unless $offset;
  $pagesize = 20 unless $pagesize > 0;
  my $user = $self->get('user');
  my $sql = 'SELECT r.id,DATE(r.time),r.duration,r.user,r.attr,r.reason,r.note,'.
            'r.renNum,r.expert,r.category,r.legacy,r.renDate,q.priority,r.swiss,'.
            'q.status,b.title,b.author,r.hold FROM reviews r'.
            ' INNER JOIN queue q ON r.id=q.id'.
            ' INNER JOIN bibdata b ON r.id=b.id'.
            ' LEFT JOIN projects p ON q.newproject=p.id WHERE ';
  if ($page eq 'adminReviews')
  {
    $sql .= 'r.id=r.id';
  }
  elsif ($page eq 'holds')
  {
    $sql .= "r.user='$user' AND r.hold=1";
  }
  elsif ($page eq 'adminHolds')
  {
    $sql .= 'r.hold=1';
  }
  elsif ($page eq 'expert')
  {
    my $proj = $self->GetUserProperty($user, 'newproject');
    $sql .= 'q.status=2 AND q.newproject'. ((defined $proj)? "=$proj":' IS NULL');
  }
  elsif ($page eq 'adminHistoricalReviews')
  {
    $sql = 'SELECT r.id,DATE(r.time),r.duration,r.user,r.attr,r.reason,r.note,'.
           'r.renNum,r.expert,r.category,r.legacy,r.renDate,q.priority,r.swiss,'.
           'q.status,b.title,b.author,r.validated,q.src,q.gid'.
           ' FROM historicalreviews r'.
           ' LEFT JOIN exportdata q ON r.gid=q.gid'.
           ' LEFT JOIN bibdata b ON r.id=b.id'.
           ' LEFT JOIN projects p ON q.newproject=p.id WHERE r.id IS NOT NULL';
  }
  elsif ($page eq 'undReviews')
  {
    my $proj = $self->GetUserProperty($user, 'newproject');
    $sql .= 'q.status=3 AND q.newproject'. ((defined $proj)? "=$proj":' IS NULL');
  }
  elsif ($page eq 'userReviews')
  {
    $sql .= "r.user='$user' AND q.status>0";
  }
  elsif ($page eq 'editReviews')
  {
    my $today = $self->SimpleSqlGet('SELECT DATE(NOW())') . ' 00:00:00';
    # Experts need to see stuff with any status; non-expert should only see stuff that hasn't been processed yet.
    my $restrict = ($self->IsUserExpert($user))? '':'AND q.status=0';
    $sql .= "r.user='$user' AND (r.time>='$today' OR r.hold=1) AND q.status!=6 $restrict";
  }
  my $terms = $self->SearchTermsToSQL($search1, $search1value, $op1, $search2, $search2value, $op2, $search3, $search3value);
  $sql .= " AND $terms" if $terms;
  if ($startDate) { $sql .= " AND DATE(r.time) >='$startDate' "; }
  if ($endDate) { $sql .= " AND DATE(r.time) <='$endDate' "; }
  $sql .= " ORDER BY $order $dir";
  $sql .= ', r.time ASC' unless $order eq 'r.time';
  $sql .= " LIMIT $offset, $pagesize";
  #print "$sql<br/>\n";
  my $countSql = $sql;
  $countSql =~ s/(SELECT\s+).+?(FROM.+)/$1 COUNT(r.id),COUNT(DISTINCT r.id) $2/i;
  $countSql =~ s/(LIMIT\s\d+(,\s*\d+)?)//;
  my $ref = $self->SelectAll($countSql);
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
  $order = $self->ConvertToSearchTerm($order, $page, 1);
  $search1 = 'r.id' unless $search1;
  my $order2 = ($dir eq 'ASC')? 'min':'max';
  my @rest = ();
  my $table = 'reviews';
  my $doQ = '';
  if ($page eq 'adminHistoricalReviews')
  {
    $table = 'historicalreviews';
    $doQ = 'LEFT JOIN exportdata q ON r.gid=q.gid';
  }
  else
  {
    $doQ = 'INNER JOIN queue q ON r.id=q.id';
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
    push @rest, 'q.status=0' unless $self->IsUserAtLeastExpert($user);
  }
  my $terms = $self->SearchTermsToSQL($search1, $search1value, $op1, $search2, $search2value, $op2, $search3, $search3value);
  push @rest, $terms if $terms;
  push @rest, "date(r.time) >= '$startDate'" if $startDate;
  push @rest, "date(r.time) <= '$endDate'" if $endDate;
  my $restrict = join(' AND ', @rest);
  $restrict = 'WHERE '. $restrict if $restrict;
  my $sql = 'SELECT COUNT(r2.id) FROM '. $table. ' r2'.
            ' WHERE r2.id IN (SELECT r.id FROM '. $table. ' r'.
            ' LEFT JOIN bibdata b ON r.id=b.id '. $doQ. ' '. $restrict. ')';
  #print "$sql<br/>\n";
  my $totalReviews = $self->SimpleSqlGet($sql);
  $sql = "SELECT COUNT(DISTINCT r.id) FROM $table r LEFT JOIN bibdata b ON r.id=b.id $doQ $restrict";
  #print "$sql<br/>\n";
  my $totalVolumes = $self->SimpleSqlGet($sql);
  my $limit = ($download)? '':"LIMIT $offset, $pagesize";
  $offset = $totalVolumes-($totalVolumes % $pagesize) if $offset >= $totalVolumes;
  $sql = "SELECT foo.id FROM (SELECT r.id as id, $order2($order) AS ord FROM $table r LEFT JOIN bibdata b ON r.id=b.id".
         " $doQ $restrict GROUP BY r.id) AS foo ORDER BY ord $dir $limit";
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
  my $joins;
  if ($page eq 'adminHistoricalReviews')
  {
    $table = 'historicalreviews';
    $joins = 'exportdata q ON r.gid=q.gid LEFT JOIN bibdata b ON q.id=b.id';
  }
  else
  {
    $joins = 'queue q ON r.id=q.id LEFT JOIN bibdata b ON q.id=b.id';
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
  my ($joins2,@rest2) = $self->SearchTermsToSQLWide($search1, $search1value, $op1, $search2, $search2value, $op2, $search3, $search3value, $table);
  push @rest, @rest2;
  push @rest, "date(r.time) >= '$startDate'" if $startDate;
  push @rest, "date(r.time) <= '$endDate'" if $endDate;
  my $restrict = join(' AND ', @rest);
  $restrict = 'WHERE '.$restrict if $restrict;
  #my $sql = "SELECT COUNT(r.id) FROM $top INNER JOIN $table r ON b.id=r.id $joins $restrict";
  my $sql = "SELECT COUNT(r2.id) FROM $table r2 WHERE r2.id IN (SELECT DISTINCT r.id FROM $table r LEFT JOIN $joins $joins2 $restrict)";
  #print "$sql<br/>\n";
  my $totalReviews = $self->SimpleSqlGet($sql);
  $sql = "SELECT COUNT(DISTINCT r.id) FROM $table r LEFT JOIN $joins $joins2 $restrict";
  #print "$sql<br/>\n";
  my $totalVolumes = $self->SimpleSqlGet($sql);
  $offset = $totalVolumes-($totalVolumes % $pagesize) if $offset >= $totalVolumes;
  my $limit = ($download)? '':"LIMIT $offset, $pagesize";
  $sql = "SELECT r.id as id, $order2($order) AS ord FROM $table r LEFT JOIN $joins $joins2 $restrict GROUP BY r.id " .
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
  my %pref2table = ('b'=>'bibdata','r'=>$table,'q'=>'queue');
  $pref2table{'q'} = 'exportdata' if $table eq 'historicalreviews';
  my $table1 = $pref2table{substr $search1,0,1};
  my $table2 = $pref2table{substr $search2,0,1};
  my $table3 = $pref2table{substr $search3,0,1};
  $table1 = 'historicalreviews' if $search1 =~ m/^DATE/;
  $table2 = 'historicalreviews' if $search2 =~ m/^DATE/;
  $table3 = 'historicalreviews' if $search3 =~ m/^DATE/;
  my ($search1term,$search2term,$search3term);
  $search1 = "YEAR($search1)" if $search1 eq 'b.pub_date';
  $search2 = "YEAR($search2)" if $search2 eq 'b.pub_date';
  $search3 = "YEAR($search3)" if $search3 eq 'b.pub_date';
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
    my $id = ($table eq 'historicalreviews' && $table1 != 'bibdata')? 'gid':'id';
    $search1term =~ s/[a-z]\./t1./;
    if ($op1 eq 'AND' || !length $search2term)
    {
      $joins = "INNER JOIN $table1 t1 ON t1.$id=r.$id";
      push @rest, $search1term;
    }
    elsif ($op2 ne 'OR' || !length $search3term)
    {
      $search2term =~ s/[a-z]\./t2./;
      $joins = "INNER JOIN (SELECT t1.id FROM $table1 t1 WHERE $search1term".
               " UNION SELECT t2.id FROM $table2 t2 WHERE $search2term) AS or1 ON or1.$id=r.$id";
      $did2 = 1;
    }
    else
    {
      $search2term =~ s/[a-z]\./t2./;
      $search3term =~ s/[a-z]\./t3./;
      $joins = "INNER JOIN (SELECT t1.id FROM $table1 t1 WHERE $search1term".
               " UNION SELECT t2.id FROM $table2 t2 WHERE $search2term".
               " UNION SELECT t3.id FROM $table3 t3 WHERE $search3term) AS or1 ON or1.$id=r.$id";
      $did2 = 1;
      $did3 = 1;
    }
  }
  if (length $search2term && !$did2)
  {
    my $id = ($table eq 'historicalreviews' && $table2 != 'bibdata')? 'gid':'id';
    $search2term =~ s/[a-z]\./t2./;
    if ($op2 eq 'AND' || !length $search3term)
    {
      $joins .= " INNER JOIN $table2 t2 ON t2.$id=r.$id";
      push @rest, $search2term;
    }
    else
    {
      $search3term =~ s/[a-z]\./t3./;
      $joins .= " INNER JOIN (SELECT t2.id FROM $table2 t2 WHERE $search2term".
                " UNION SELECT t3.id FROM $table3 t3 WHERE $search3term) AS or2 ON or2.$id=r.$id";
      $did3 = 1;
    }
  }
  if (length $search3term && !$did3)
  {
    my $id = ($table eq 'historicalreviews' && $table3 != 'bibdata')? 'gid':'id';
    $search3term =~ s/[a-z]\./t3./;
    $joins .= " INNER JOIN $table3 t3 ON t3.$id=r.$id";
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
  if ($page eq 'adminHistoricalReviews')
  {
    $table = 'historicalreviews';
    $top = 'exportdata q INNER JOIN bibdata b ON q.id=b.id';
  }
  else
  {
    $top = 'queue q INNER JOIN bibdata b ON q.id=b.id';
  }
  my ($sql,$totalReviews,$totalVolumes,$n,$of) = $self->CreateSQL($stype, $page, $order, $dir, $search1,
                                                                  $search1value, $op1, $search2, $search2value,
                                                                  $op2, $search3, $search3value, $startDate,
                                                                  $endDate, 0, 0, 1);
  my $ref = $self->SelectAll($sql);
  my $buff = '';
  if (scalar @{$ref} == 0)
  {
    $buff = 'No Results Found.';
  }
  else
  {
    if ($page eq 'userReviews')
    {
      $buff .= qq{id\ttitle\tauthor\tdate\tattr\treason\tcategory\tnote};
    }
    elsif ($page eq 'editReviews' || $page eq 'holds')
    {
      $buff .= qq{id\ttitle\tauthor\tdate\tattr\treason\tcategory\tnote\thold};
    }
    elsif ($page eq 'expert' || $page eq 'undReviews')
    {
      $buff .= qq{id\ttitle\tauthor\tdate\tstatus\tuser\tattr\treason\tcategory\tnote}
    }
    elsif ($page eq 'adminReviews' || $page eq 'adminHolds')
    {
      $buff .= qq{id\ttitle\tauthor\tdate\tstatus\tuser\tattr\treason\tcategory\tnote\tswiss\thold};
    }
    elsif ($page eq 'adminHistoricalReviews')
    {
      $buff .= qq{id\tsystem id\ttitle\tauthor\tpub date\tdate\tstatus\tlegacy\tuser\tattr\treason\tcategory\tnote\tvalidated\tswiss};
    }
    $buff .= sprintf("%s\n", ($self->IsUserAdmin())? "\tpriority":'');
    if ($stype eq 'reviews')
    {
      $buff .= $self->UnpackResults($page, $ref);
    }
    else
    {
      #$order = 'Identifier' if $order eq 'SysID';
      $order = $self->ConvertToSearchTerm($order, 1);
      foreach my $row (@{$ref})
      {
        my $id = $row->[0];
        my $qrest = ($page ne 'adminHistoricalReviews')? ' AND r.id=q.id':'';
        $sql = 'SELECT r.id,r.time,r.duration,r.user,r.attr,r.reason,r.note,r.renNum,r.expert,'.
               'r.category,r.legacy,r.renDate,q.priority,r.swiss,q.status,b.title,b.author,'.
               (($page eq 'adminHistoricalReviews')?'r.validated':'r.hold ').
               " FROM $top INNER JOIN $table r ON b.id=r.id".
               " WHERE r.id='$id' $qrest ORDER BY $order $dir";
        #print "$sql<br/>\n";
        my $ref2;
        eval { $ref2 = $self->SelectAll($sql); };
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
    my $title      = $row->[15];
    my $author     = $row->[16];
    my $holdval    = $row->[17];
    if ($page eq 'userReviews') # FIXME: is this ever used??
    {
      $buff .= qq{$id\t$title\t$author\t$time\t$attr\t$reason\t$category\t$note};
    }
    elsif ($page eq 'editReviews' || $page eq 'holds')
    {
      $buff .= qq{$id\t$title\t$author\t$time\t$attr\t$reason\t$category\t$note\t$holdval};
    }
    elsif ($page eq 'expert' || $page eq 'undReviews')
    {
      $buff .= qq{$id\t$title\t$author\t$time\t$status\t$user\t$attr\t$reason\t$category\t$note}
    }
    elsif ($page eq 'adminReviews' || $page eq 'adminHolds')
    {
      $buff .= qq{$id\t$title\t$author\t$time\t$status\t$user\t$attr\t$reason\t$category\t$note\t$swiss\t$holdval};
    }
    elsif ($page eq 'adminHistoricalReviews')
    {
      my $pubdate = $self->SimpleSqlGet('SELECT YEAR(pub_date) FROM bibdata WHERE id=?', $id);
      $pubdate = '?' unless $pubdate;
      my $sysid = $self->SimpleSqlGet('SELECT sysid FROM bibdata WHERE id=?', $id);
      #id, title, author, review date, status, user, attr, reason, category, note, validated
      $buff .= qq{$id\t$sysid\t$title\t$author\t$pubdate\t$time\t$status\t$legacy\t$user\t$attr\t$reason\t$category\t$note\t$holdval\t$swiss};
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
    $buff = $self->CreatePreDeterminationsBreakdownData($startDate, $endDate, $monthly, undef, $priority);
  }
  else
  {
    $buff = $self->CreateDeterminationsBreakdownData($startDate, $endDate, $monthly, undef, $priority);
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
  my $self         = shift;
  my $page         = shift;
  my $order        = shift;
  my $dir          = shift;
  my $search1      = shift;
  my $search1Value = shift;
  my $op1          = shift;
  my $search2      = shift;
  my $search2Value = shift;
  my $op2          = shift;
  my $search3      = shift;
  my $search3Value = shift;
  my $startDate    = shift;
  my $endDate      = shift;
  my $offset       = shift;
  my $pagesize     = shift;

  $pagesize = 20 unless $pagesize > 0;
  $offset = 0 unless $offset > 0;
  my ($sql,$totalReviews,$totalVolumes) = $self->CreateSQLForReviews($page, $order, $dir, $search1, $search1Value, $op1, $search2, $search2Value, $op2, $search3, $search3Value, $startDate, $endDate, $offset, $pagesize);
  #print "$sql<br/>\n";
  my $ref = undef;
  eval { $ref = $self->SelectAll($sql); };
  if ($@)
  {
    $self->SetError("SQL failed: '$sql' ($@)");
    return;
  }
  my $return = [];
  foreach my $row (@{$ref})
  {
      my $id = $row->[0];
      my $item = {id         => $id,
                  date       => $row->[1],
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
                  author     => $row->[16],
                  hold       => $row->[17]
                 };
      if ($page eq 'adminHistoricalReviews')
      {
        my $pubdate = $self->SimpleSqlGet('SELECT YEAR(pub_date) FROM bibdata WHERE id=?', $id);
        $pubdate = '?' unless $pubdate;
        ${$item}{'pubdate'} = $pubdate;
        ${$item}{'sysid'} = $self->SimpleSqlGet('SELECT sysid FROM bibdata WHERE id=?', $id);
        ${$item}{'validated'} = $row->[17];
        ${$item}{'src'} = $row->[18];
        ${$item}{'gid'} = $row->[19];
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
  eval { $ref = $self->SelectAll($sql); };
  if ($@)
  {
    $self->SetError("SQL failed: '$sql' ($@)");
    return;
  }
  my $table = 'reviews';
  my $doQ;
  if ($page eq 'adminHistoricalReviews')
  {
    $table = 'historicalreviews';
    $doQ = 'LEFT JOIN exportdata q ON r.gid=q.gid';
  }
  else
  {
    $doQ = 'LEFT JOIN queue q ON r.id=q.id';
  }
  my $return = ();
  foreach my $row (@{$ref})
  {
    my $id = $row->[0];
    $sql = 'SELECT r.id,DATE(r.time),r.duration,r.user,r.attr,r.reason,r.note,r.renNum,r.expert,'.
           'r.category,r.legacy,r.renDate,q.priority,r.swiss,q.status,b.title,b.author'.
           (($page eq 'adminHistoricalReviews')? ',YEAR(b.pub_date),r.validated,b.sysid,q.src,q.gid':'') .
           (($page eq 'adminReviews' || $page eq 'editReviews' || $page eq 'holds' || $page eq 'adminHolds')? ',r.hold':'') .
           " FROM $table r LEFT JOIN bibdata b ON r.id=b.id $doQ " .
           " WHERE r.id='$id' ORDER BY $order $dir";
    $sql .= ', r.time ASC' unless $order eq 'r.time';
    #print "$sql<br/>\n";
    my $ref2 = $self->SelectAll($sql);
    foreach my $row (@{$ref2})
    {
      my $item = {id         => $row->[0],
                  date       => $row->[1],
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
                  author     => $row->[16],
                  hold       => $row->[17]
                 };
      if ($page eq 'adminHistoricalReviews')
      {
        my $pubdate = $row->[17];
        $pubdate = '?' unless $pubdate;
        ${$item}{'pubdate'} = $pubdate;
        ${$item}{'validated'} = $row->[18];
        ${$item}{'sysid'} = $row->[19];
        ${$item}{'src'} = $row->[20];
        ${$item}{'gid'} = $row->[21];
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
  my $doQ = 'LEFT JOIN queue q ON r.id=q.id';
  if ($page eq 'adminHistoricalReviews')
  {
    $table = 'historicalreviews';
    $doQ = 'LEFT JOIN exportdata q ON r.gid=q.gid';
  }
  my ($sql,$totalReviews,$totalVolumes,$n,$of) = $self->CreateSQLForVolumesWide(@_);
  my $ref = undef;
  eval { $ref = $self->SelectAll($sql); };
  if ($@)
  {
    $self->SetError("SQL failed: '$sql' ($@)");
    return;
  }
  my $return = ();
  foreach my $row (@{$ref})
  {
    my $id = $row->[0];
    $sql = 'SELECT r.id,DATE(r.time),r.duration,r.user,r.attr,r.reason,r.note,r.renNum,r.expert,'.
           'r.category,r.legacy,r.renDate,q.priority,r.swiss,q.status,b.title,b.author'.
           (($page eq 'adminHistoricalReviews')? ',YEAR(b.pub_date),r.validated,b.sysid,q.src,q.gid':'r.hold').
           " FROM $table r $doQ LEFT JOIN bibdata b ON r.id=b.id".
           " WHERE r.id='$id' ORDER BY $order $dir";
    $sql .= ',r.time ASC' unless $order eq 'r.time';
    #print "$sql<br/>\n";
    my $ref2 = $self->SelectAll($sql);
    foreach my $row (@{$ref2})
    {
      my $item = {id         => $row->[0],
                  date       => $row->[1],
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
                  author     => $row->[16],
                  hold       => $row->[17]
                 };
      if ($page eq 'adminHistoricalReviews')
      {
        my $pubdate = $row->[17];
        $pubdate = '?' unless $pubdate;
        ${$item}{'pubdate'} = $pubdate;
        ${$item}{'validated'} = $row->[18];
        ${$item}{'sysid'} = $row->[19];
        ${$item}{'src'} = $row->[20];
        ${$item}{'gid'} = $row->[21];
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

sub GetReviewCount
{
  my $self = shift;
  my $id   = shift;
  my $hist = shift;

  my $table = ($hist)? 'historicalreviews':'reviews';
  my $sql = 'SELECT COUNT(*) FROM '. $table. ' WHERE id=?';
  return $self->SimpleSqlGet($sql, $id);
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

  $pagesize = 20 unless $pagesize > 0;
  $offset = 0 unless $offset > 0;
  $order = 'id' unless $order;
  $offset = 0 unless $offset;
  $search1 = $self->ConvertToSearchTerm($search1, 'queue');
  $search2 = $self->ConvertToSearchTerm($search2, 'queue');
  $order = $self->ConvertToSearchTerm($order, 'queue');
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
  push @rest, "q.time>='$startDate'" if $startDate;
  push @rest, "q.time<='$endDate'" if $endDate;
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
  my $sql = 'SELECT COUNT(q.id) FROM queue q LEFT JOIN bibdata b ON q.id=b.id'.
            ' INNER JOIN projects p ON q.newproject=p.id '. $restrict;
  #print "$sql<br/>\n";
  my $totalVolumes = $self->SimpleSqlGet($sql);
  $offset = $totalVolumes-($totalVolumes % $pagesize) if $offset >= $totalVolumes;
  my $limit = ($download)? '':"LIMIT $offset, $pagesize";
  my @return = ();
  $sql = 'SELECT q.id,DATE(q.time),q.status,q.locked,YEAR(b.pub_date),q.priority,'.
         ' q.expcnt,b.title,b.author,p.name,q.source,q.ticket,q.added_by'.
         ' FROM queue q LEFT JOIN bibdata b ON q.id=b.id'.
         ' INNER JOIN projects p ON q.newproject=p.id '. $restrict.
         ' ORDER BY '. "$order $dir $limit";
  #print "$sql<br/>\n";
  my $ref = undef;
  eval {
    $ref = $self->SelectAll($sql);
  };
  if ($@)
  {
    $self->SetError($@);
  }
  my $data = join "\t", ('ID','Title','Author','Pub Date','Date Added','Status','Locked','Priority','Reviews','Expert Reviews','Holds','Project');
  foreach my $row (@{$ref})
  {
    my $id = $row->[0];
    
    my $pubdate = $row->[4];
    $pubdate = '?' unless $pubdate;
    $sql = 'SELECT COUNT(*) FROM reviews WHERE id=?';
    #print "$sql<br/>\n";
    my $reviews = $self->SimpleSqlGet($sql, $id);
    $sql = 'SELECT COUNT(*) FROM reviews WHERE id=? AND hold=1';
    #print "$sql<br/>\n";
    my $holds = $self->SimpleSqlGet($sql, $id);
    my $item = {id       => $id,
                date     => $row->[1],
                status   => $row->[2],
                locked   => $row->[3],
                pubdate  => $pubdate,
                priority => $self->StripDecimal($row->[5]),
                expcnt   => $row->[6],
                title    => $row->[7],
                author   => $row->[8],
                reviews  => $reviews,
                holds    => $holds,
                project  => $row->[9],
                source   => $row->[10],
                ticket   => $row->[11],
                added_by => $row->[12]
               };
    push @return, $item;
    if ($download)
    {
      $data .= sprintf("\n$id\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t$reviews\t%s\t$holds",
                       $row->[7], $row->[8], $row->[4], $row->[1], $row->[2], $row->[3], $self->StripDecimal($row->[5]), $row->[6]);
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

  $pagesize = 20 unless $pagesize > 0;
  $offset = 0 unless $offset > 0;
  $order = 'id' unless $order;
  $offset = 0 unless $offset;
  $search1 = $self->ConvertToSearchTerm($search1, 'exportData');
  $search2 = $self->ConvertToSearchTerm($search2, 'exportData');
  $order = $self->ConvertToSearchTerm($order, 'exportData');
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
  push @rest, "DATE(q.time)>='$startDate'" if $startDate;
  push @rest, "DATE(q.time)<='$endDate'" if $endDate;
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
  my $sql = 'SELECT COUNT(q.id) FROM exportdata q LEFT JOIN bibdata b ON q.id=b.id'.
            ' INNER JOIN projects p ON q.newproject=p.id '. $restrict;
  #print "$sql<br/>\n";
  my $totalVolumes = $self->SimpleSqlGet($sql);
  $offset = $totalVolumes-($totalVolumes % $pagesize) if $offset >= $totalVolumes;
  my $limit = ($download)? '':"LIMIT $offset, $pagesize";
  my @return = ();
  $sql = 'SELECT q.id,DATE(q.time),q.attr,q.reason,q.status,q.priority,q.src,b.title,b.author,'.
         'YEAR(b.pub_date),q.exported,p.name,q.gid,q.added_by,q.ticket'.
         ' FROM exportdata q LEFT JOIN bibdata b ON q.id=b.id'.
         ' INNER JOIN projects p ON q.newproject=p.id'.
         " $restrict ORDER BY $order $dir $limit";
  #print "$sql<br/>\n";
  my $ref = undef;
  eval { $ref = $self->SelectAll($sql); };
  if ($@)
  {
    $self->SetError($@);
  }
  my $data = join "\t", ('ID','Title','Author','Pub Date','Date Exported','Source');
  foreach my $row (@{$ref})
  {
    my $id = $row->[0];
    my $pubdate = $row->[9];
    $pubdate = '?' unless $pubdate;
    my $item = {id         => $id,
                date       => $row->[1],
                attr       => $row->[2],
                reason     => $row->[3],
                status     => $row->[4],
                priority   => $self->StripDecimal($row->[5]),
                src        => $row->[6],
                title      => $row->[7],
                author     => $row->[8],
                pubdate    => $pubdate,
                exported   => $row->[10],
                project    => $row->[11],
                gid        => $row->[12],
                added_by   => $row->[13],
                ticket     => $row->[14],
               };
    push @return, $item;
    if ($download)
    {
      $data .= sprintf("\n$id\t%s\t%s\t$pubdate\t%s\t%s",
                       $row->[5], $row->[6], $row->[4], $row->[1]);
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

sub CorrectionsTitles
{
  require 'Corrections.pm';
  return Corrections::CorrectionsTitles();
}

sub CorrectionsFields
{
  require 'Corrections.pm';
  return Corrections::CorrectionsFields();
}

sub GetCorrectionsDataRef
{
  my $self = shift;

  require 'Corrections.pm';
  unshift @_, $self;
  return Corrections::GetCorrectionsDataRef(@_);
}

sub CorrectionsDataSearchMenu
{
  my $self = shift;

  require 'Corrections.pm';
  unshift @_, $self;
  return Corrections::CorrectionsDataSearchMenu(@_);
}

sub IsCorrection
{
  my $self = shift;
  my $id   = shift;

  return $self->SimpleSqlGet('SELECT COUNT(*) FROM corrections WHERE id=?', $id);
}

sub InsertsTitles
{
  require 'Inserts.pm';
  return Inserts::InsertsTitles();
}

sub InsertsFields
{
  require 'Inserts.pm';
  return Inserts::InsertsFields();
}

sub GetInsertsDataRef
{
  require 'Inserts.pm';
  return Inserts::GetInsertsDataRef(@_);
}

sub InsertsDataSearchMenu
{
  require 'Inserts.pm';
  return Inserts::InsertsDataSearchMenu(@_);
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

  my $n = $self->SimpleSqlGet('SELECT COUNT(*) FROM rights WHERE attr=? AND reason=?', $a, $r);
  $self->SetError("bad attr/reason: $a/$r") unless $n;
  return $n;
}

sub GetAttrReasonFromCode
{
  my $self = shift;
  my $code = shift;

  my $sql = 'SELECT attr,reason FROM rights WHERE id=?';
  my $ref = $self->SelectAll($sql, $code);
  my $a = $ref->[0]->[0];
  my $r = $ref->[0]->[1];
  return ($a, $r);
}

sub TranslateAttrReasonFromCode
{
  my $self = shift;
  my $code = shift;

  my ($a, $r) = $self->GetAttrReasonFromCode($code);
  $a = $self->TranslateAttr($a);
  $r = $self->TranslateReason($r);
  return ($a, $r);
}

sub GetCodeFromAttrReason
{
  my $self = shift;
  my $a    = shift;
  my $r    = shift;

  my $sql = 'SELECT id FROM rights WHERE attr=? AND reason=? ORDER BY IF(restricted LIKE "%o%",0,1) DESC LIMIT 1';
  return $self->SimpleSqlGet($sql, $a, $r);
}

sub GetAttrReasonCode
{
  my $self = shift;
  my $id   = shift;
  my $user = shift;

  my $sql = 'SELECT attr,reason FROM reviews WHERE id=? AND user=?';
  my $ref = $self->SelectAll($sql, $id, $user);
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
  my $admin      = shift;
  my $superadmin = shift;
  my $note       = shift;
  my $projects   = shift;
  my $commitment = shift;
  my $disable    = shift;

  my @fields = (\$reviewer,\$advanced,\$expert,\$admin,\$superadmin);
  ${$fields[$_]} = (length ${$fields[$_]} && !$disable)? 1:0 for (0 .. scalar @fields - 1);
  # Preserve existing privileges unless there are some checkboxes checked
  my $checked = 0;
  $checked += ${$fields[$_]} for (0 .. scalar @fields - 1);
  if ($checked == 0 && !$disable)
  {
    my $sql = 'SELECT reviewer,advanced,expert,admin,superadmin FROM users WHERE id=?';
    my $ref = $self->SelectAll($sql, $id);
    #return "Unknown reviewer '$id'" if 0 == scalar @{$ref};
    ${$fields[$_]} = $ref->[0]->[$_] for (0 .. scalar @fields - 1);
  }
  # Remove surrounding whitespace on user id, kerberos, and name.
  $id =~ s/^\s*(.+?)\s*$/$1/;
  $kerberos =~ s/^\s*(.+?)\s*$/$1/;
  $name =~ s/^\s*(.+?)\s*$/$1/;
  $commitment =~ s/^\s*(.+?)\s*$/$1/;
  $kerberos = $self->SimpleSqlGet('SELECT kerberos FROM users WHERE id=?', $id) unless $kerberos;
  $name = $self->SimpleSqlGet('SELECT name FROM users WHERE id=?', $id) unless $name;
  $note = $self->SimpleSqlGet('SELECT note FROM users WHERE id=?', $id) unless $note;
  $commitment = $self->SimpleSqlGet('SELECT commitment FROM users WHERE id=?', $id) unless $commitment;
  # Remove percent sign if it exists and make sure commitment is a valid number.
  # If it's > 1 count it as a percent, otherwise as a decimal.
  # Convert it to decimal as needed for storage.
  if ($commitment)
  {
    $commitment =~ s/%+//g;
    if (length $commitment && ($commitment !~ m/^\d*\.?\d*$/ || $commitment !~ m/\d+/))
    {
      return "Error: commitment '$commitment' not numeric.";
    }
    $commitment /= 100.0 if $commitment > 1;
  }
  my $inst = $self->SimpleSqlGet('SELECT institution FROM users WHERE id=?', $id);
  $inst = $self->PredictUserInstitution($id) unless defined $inst;
  my $wcs = $self->WildcardList(11);
  my $sql = 'REPLACE INTO users (id,kerberos,name,reviewer,advanced,expert,'.
            'admin,superadmin,note,institution,commitment) VALUES '. $wcs;
  $self->PrepareSubmitSql($sql, $id, $kerberos, $name, $reviewer, $advanced, $expert,
                          $admin, $superadmin, $note, $inst, $commitment);
  $self->Note($_) for @{$self->GetErrors()};
  if (defined $projects)
  {
    $self->PrepareSubmitSql('DELETE FROM projectusers WHERE user=?', $id);
    $sql = 'INSERT INTO projectusers (user,newproject) VALUES (?,?)';
    foreach my $proj (@{$projects})
    {
      # No need to store Core unless multiple projects.
      $proj = undef unless int $proj;
      next unless defined $proj or scalar @{$projects} > 1;
      $self->PrepareSubmitSql($sql, $id, $proj);
    }
  }
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

sub GetUserProperty
{
  my $self = shift;
  my $user = shift || $self->get('user');
  my $prop = shift;

  my $sql = 'SELECT '. $prop. ' FROM users WHERE id=?';
  return $self->SimpleSqlGet($sql, $user);
}

# Return the maximum commitment for all user incarnations.
sub GetUserCommitment
{
  my $self   = shift;
  my $user   = shift || $self->get('user');
  my $format = shift;

  my $ids = $self->GetUserIncarnations($user);
  my $wc = $self->WildcardList(scalar @{$ids});
  my $sql = 'SELECT MAX(COALESCE(commitment,0.0)) FROM users WHERE id IN '. $wc;
  my $comm = $self->SimpleSqlGet($sql, @{$ids});
  $comm = 100*$comm . '%' if defined $comm and $format;
  return $comm;
}

sub GetAlias
{
  my $self = shift;
  my $user = shift || $self->get('remote_user');

  my $sql = 'SELECT alias FROM users WHERE id=?';
  return $self->SimpleSqlGet($sql, $user);
}

sub SetAlias
{
  my $self  = shift;
  my $user  = shift || $self->get('remote_user');
  my $alias = shift;

  $alias = undef if $alias eq $user;
  if (!defined $alias || $self->CanChangeToUser($user, $alias))
  {
    my $sql = 'UPDATE users SET alias=? WHERE id=?';
    $self->PrepareSubmitSql($sql, $alias, $user);
    $user = $alias if defined $alias;
    $self->set('user', $user);
  }
}

# Return an arrayref of all user ids that share the same kerberos id.
sub GetUserIncarnations
{
  my $self = shift;
  my $user = shift;

  my $kerb = $self->GetUserProperty($user, 'kerberos');
  my %ids = ($user => 1);
  if ($kerb)
  {
    my $sql = 'SELECT id FROM users WHERE kerberos=?';
    $ids{$_->[0]} = 1 for @{$self->SelectAll($sql, $kerb)};
  }
  my @ids2 = sort keys %ids;
  return \@ids2;
}

# Same kerberos, different user id for "change-to" purposes.
sub SameUser
{
  my $self = shift;
  my $u1   = shift;
  my $u2   = shift;

  my $sql = 'SELECT COUNT(*) FROM users u1 INNER JOIN users u2'.
            ' ON u1.kerberos=u2.kerberos WHERE u1.id=? AND u2.id=?'.
            ' AND u1.id!=u2.id';
  return $self->SimpleSqlGet($sql, $u1, $u2);
}

# In production and training, users can only change to a different user with the
# same kerberos. In dev, an admin can change to anyone.
sub CanChangeToUser
{
  my $self = shift;
  my $me   = shift;
  my $him  = shift;

  return 1 if $self->SameUser($me, $him);
  my $where = $self->WhereAmI();
  if (defined $where && $where !~ /^training/i)
  {
    return 0 if $me eq $him;
    return 1 if $self->IsUserAdmin($me);
  }
  return 0;
}

sub IsUserReviewer
{
  my $self = shift;
  my $user = shift || $self->get('user');

  my $sql = 'SELECT reviewer FROM users WHERE id=?';
  return $self->SimpleSqlGet($sql, $user);
}

sub IsUserAdvanced
{
  my $self = shift;
  my $user = shift || $self->get('user');

  my $sql = 'SELECT advanced FROM users WHERE id=?';
  return $self->SimpleSqlGet($sql, $user);
}

sub IsUserExpert
{
  my $self = shift;
  my $user = shift || $self->get('user');

  my $sql = 'SELECT expert FROM users WHERE id=?';
  return $self->SimpleSqlGet($sql, $user);
}

sub IsUserAtLeastExpert
{
  my $self = shift;
  my $user = shift || $self->get('user');

  my $sql = 'SELECT (expert OR admin OR superadmin) FROM users WHERE id=?';
  return $self->SimpleSqlGet($sql, $user);
}

sub IsUserAdmin
{
  my $self = shift;
  my $user = shift || $self->get('user');

  my $sql = 'SELECT (admin OR superadmin) FROM users WHERE id=?';
  return $self->SimpleSqlGet($sql, $user);
}

sub IsUserSuperAdmin
{
  my $self = shift;
  my $user = shift || $self->get('user');

  my $sql = 'SELECT superadmin FROM users WHERE id=?';
  return $self->SimpleSqlGet($sql, $user);
}

# All orders place inactives last and order by name
# Order 0: by name
# Order 1: by privilege level from low to high (user stats pages)
# Order 2: by institution
# Order 3: by privilege level from high to low
# Order 4: by percentage commitment
sub GetUsers
{
  my $self = shift;
  my $ord  = shift;

  my @users;
  my $order = '(u.reviewer+u.advanced+u.admin+u.superadmin > 0) DESC';
  $order .= ',u.expert ASC' if $ord == 1;
  $order .= ',i.shortname ASC' if $ord == 2;
  $order .= ',(u.reviewer+(2*u.advanced)+(4*u.expert)'.
            '+(8*u.admin)+(16*u.superadmin)) DESC' if $ord == 3;
  $order .= ',u.commitment DESC' if $ord == 4;
  $order .= ',u.name ASC';
  my $sql = 'SELECT u.id,u.name,u.reviewer,u.advanced,u.expert,u.admin,u.superadmin,u.kerberos,'.
            'u.note,i.shortname,u.commitment'.
            ' FROM users u INNER JOIN institutions i'.
            ' ON u.institution=i.id ORDER BY ' . $order;
  my $ref = $self->SelectAll($sql);
  foreach my $row (@{$ref})
  {
    my $id = $row->[0];
    my $expiration = $self->IsUserExpired($id);
    my $progress = 0.0;
    if ($row->[10])
    {
      $sql = 'SELECT s.total_time/60.0 FROM userstats s'.
             ' WHERE s.monthyear=DATE_FORMAT(NOW(),"%Y-%m") AND s.user=?';
      my $hours = $self->SimpleSqlGet($sql, $id);
      $sql = 'SELECT COALESCE(SUM(TIME_TO_SEC(duration)),0)/3600.0 from reviews'.
             ' WHERE user=?';
      $hours += $self->SimpleSqlGet($sql, $id);
      $progress = $hours/(160.0*$row->[10]) ;
      $progress = 0.0 if $progress < 0.0;
      $progress = 1.0 if $progress > 1.0;
    }
    push @users, {'id' => $id, 'name' => $row->[1], 'reviewer' => $row->[2],
                  'advanced' => $row->[3], 'expert' => $row->[4], 'admin' => $row->[5],
                  'superadmin' => $row->[6], 'kerberos' => $row->[7], 'note' => $row->[8],
                  'institution' => $row->[9], 'commitment' => $row->[10],
                  'commitmentFmt' => (100.0 *$row->[10]). '%', 'progress' => $progress,
                  'expiration' => $expiration};
  }
  return \@users;
}

sub IsUserIncarnationExpertOrHigher
{
  my $self = shift;
  my $user = shift || $self->get('user');

  my $sql = 'SELECT MAX(expert+admin+superadmin) FROM users WHERE kerberos!=""' .
            ' AND kerberos IN (SELECT DISTINCT kerberos FROM users WHERE id=?)';
  return 0 < $self->SimpleSqlGet($sql, $user);
}

sub GetInstitutions
{
  my $self = shift;

  my @insts = ();
  push @insts, $_->[0] for @{$self->SelectAll('SELECT id FROM institutions')};
  return \@insts;
}

sub PredictUserInstitution
{
  my $self = shift;
  my $id   = shift;

  my $inst;
  my @parts = split '@', $id;
  if (scalar @parts == 2)
  {
    my $suff = $parts[1];
    $suff =~ s/\-expert//;
    my $sql = 'SELECT id FROM institutions WHERE LOCATE(suffix,?)>0';
    $inst = $self->SimpleSqlGet($sql, $suff);
  }
  $inst = 1 unless defined $inst;
  return $inst;
}

sub GetInstitutionName
{
  my $self = shift;
  my $id   = shift;
  my $long = shift;

  my $col = ($long)? 'name':'shortname';
  return $self->SimpleSqlGet('SELECT ' . $col . ' FROM institutions WHERE id=?', $id);
}

sub GetInstitutionUsers
{
  my $self  = shift;
  my $inst  = shift;
  my $order = shift;

  my $users = $self->GetUsers($order);
  my @ausers = ();
  foreach my $user (@{$users})
  {
    push @ausers, $user if $inst == $self->GetUserProperty($user, 'institution');
  }
  return \@ausers;
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

sub GetNow
{
  my $self = shift;

  return $self->SimpleSqlGet('SELECT NOW()');
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
  if ($self->Sys() eq 'crmsworld')
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

# Returns arrayref of year strings e.g. ('2009','2010') for all years for which we have stats.
sub GetAllExportYears
{
  my $self = shift;

  my @list = ();
  my $min = $self->SimpleSqlGet('SELECT MIN(YEAR(date)) FROM exportstats');
  my $max = $self->SimpleSqlGet('SELECT MAX(YEAR(date)) FROM exportstats');
  @list = ($min..$max) if $min and $max;
  return \@list;
}

# If year is undef, report is project cumulative with one year per column and first is grand total.
# Otherwise report is for a single year with one month per column.
# If pct is set, appends a percentage in parentheses.
sub CreateExportData
{
  my $self = shift;
  my $year = shift;
  my $pct  = shift;

  my @dates;
  my $report;
  my ($fmt, $fmt2);
  if (!defined $year)
  {
    @dates = @{$self->GetAllExportYears()};
    unshift @dates, 'Grand Total';
    $report = "CRMS Project Cumulative\n\t";
    $fmt = 'YEAR(date)=?';
  }
  else
  {
    my $sql = 'SELECT DISTINCT(DATE_FORMAT(date,"%Y-%m")) FROM exportstats'.
              ' WHERE DATE_FORMAT(date,"%Y-%m")>=?'.
              ' AND DATE_FORMAT(date,"%Y-%m")<=? ORDER BY date ASC';
    @dates = map {$_->[0];} @{$self->SelectAll($sql, $year.'-01', $year.'-12')};
    unshift @dates, 'Total';
    $report = "$year Exports\n\t";
    $fmt = 'DATE_FORMAT(date,"%Y-%m")=?';
    $fmt2 = 'DATE_FORMAT(date,"%Y")=?';
  }
  $report .= (join "\t", @dates). "\n";
  my @titles; # Titles in correct order
  my %data; # Unordered map of title to arrayref of cell values
  my @clauses;
  my @params;
  my $sql = 'SELECT DISTINCT CONCAT(attr,"/",reason) FROM exportstats'.
            ((defined $year)? ' WHERE YEAR(date)='.$year:'').
            ' ORDER BY attr LIKE "pd%" DESC,attr,(attr="und" AND reason="nfi") DESC,reason';
  my $ref = $self->SelectAll($sql);
  @titles = map { $_->[0]; } @{$ref};
  my $last = '';
  foreach (my $i = 0; $i < scalar @titles; $i++)
  {
    my $prefix = substr($titles[$i], 0, 2);
    if ($prefix ne $last)
    {
      my $allkey = 'All ' . uc substr $titles[$i], 0, ($prefix =~ m/^un/)? 3:2;
      splice @titles, $i, 0, $allkey;
      $i++;
      $last = $prefix;
    }
  }
  push @titles, 'Total';
  foreach my $title (@titles)
  {
    $data{$title} = [];
    my ($attr,$reason) = split '/', $title;
    $attr = lc $1 if $title =~ m/^all\s(.+)$/i;
    $attr = undef if $title eq 'Total';
    foreach my $date (@dates)
    {
      Utilities::ClearArrays(\@clauses, \@params);
      $sql = 'SELECT COALESCE(SUM(count),0) FROM exportstats';
      if ($attr)
      {
        my $attr2 = $attr;
        push @clauses, '(attr=? OR attr=?)';
        $attr2 .= 'us' if $attr ne 'und' and !$reason;
        push @params, $attr, $attr2;
      }
      if ($reason)
      {
        push @clauses, 'reason=?';
        push @params, $reason;
      }
      if ($date =~ m/^\d+/)
      {
        push @clauses, $fmt;
        push @params, $date;
      }
      elsif ($date eq 'Total' && defined $year)
      {
        push @clauses, $fmt2;
        push @params, $year;
      }
      $sql .= ' WHERE '. join ' AND ', @clauses if scalar @clauses;
      push @{$data{$title}}, $self->SimpleSqlGet($sql, @params);
    }
  }
  # Append in the Status breakdown
  foreach my $status (4 .. 9)
  {
    my $title = 'Status '.$status;
    push @titles, $title;
    $data{$title} = [];
    foreach my $date (@dates)
    {
      Utilities::ClearArrays(\@clauses, \@params);
      $sql = 'SELECT COALESCE(SUM(s'. $status.'),0) FROM determinationsbreakdown';
      if ($date =~ m/^\d+/)
      {
        push @clauses, $fmt;
        push @params, $date;
      }
      elsif ($date eq 'Total' && defined $year)
      {
        push @clauses, $fmt2;
        push @params, $year;
      }
      $sql .= ' WHERE '. join ' AND ', @clauses if scalar @clauses;
      push @{$data{$title}}, $self->SimpleSqlGet($sql, @params);
    }
  }
  # Now that total is available, decorate with percentages.
  if ($pct)
  {
    foreach my $title (@titles)
    {
      next if $title eq 'Total';
      foreach my $i (0 .. scalar @dates - 1)
      {
        my $n = $data{$title}->[$i];
        my $of = $data{'Total'}->[$i];
        if ($of > 0)
        {
          $data{$title}->[$i] = sprintf '%d (%.1f%%)', $n, 100.0 * $n / $of;
        }
      }
    }
  }
  foreach my $title (@titles)
  {
    $report .= "$title\t";
    $report .= join "\t", @{$data{$title}};
    $report .= "\n";
  }
  return $report;
}

# Create an HTML table for the whole year's exports, month by month.
# If cumulative, columns are years, not months.
sub CreateExportReport
{
  my $self = shift;
  my $year = shift;

  my $data = $self->CreateExportData($year, 1);
  my @lines = split m/\n/, $data;
  my $nbsps = '&nbsp;&nbsp;&nbsp;&nbsp;';
  my $title = shift @lines;
  $title .= '*' unless defined $year;
  my $report = sprintf("<table class='exportStats'>\n<tr>\n", $title);
  foreach my $th (split "\t", shift @lines)
  {
    $th = $self->YearMonthToEnglish($th) if $th =~ m/^\d.*/;
    $th =~ s/\s/&nbsp;/g;
    $report .= '<th style="text-align:center;">'. $th. '</th>';
  }
  $report .= "</tr>\n";
  my %majors = ('All PD' => 1, 'All IC' => 1, 'All UND' => 1);
  foreach my $line (@lines)
  {
    my @items = split("\t", $line);
    $title = shift @items;
    my $major = exists $majors{$title};
    $title =~ s/\s/&nbsp;/g;
    my $cstyle = ($title eq 'Total')? 'class="total" style="text-align:right;"':'';
    my $sstyle = ($major)? 'class="major"':
                           (($title =~ m/^Status/)? 'class="minor"':
                                                    ($title eq 'Total')? 'class="total"':''),
    my $padding = ($major)? '':$nbsps;
    my $newline = "<tr><th $cstyle><span $sstyle>$padding$title</span></th>";
    foreach my $n (@items)
    {
      $n =~ s/\s/&nbsp;/g;
      $cstyle = ($major)? 'class="major"':
                          ($title eq 'Total')? 'class="total" style="text-align:center;"':
                                               (($title =~ m/^Status/)? ' class="minor"':'');
      $n = '<strong>'. $n. '</strong>' if $title eq 'Total';
      $newline .= "<td $cstyle>$padding$n</td>", 
    }
    $newline .= "</tr>\n";
    $report .= $newline;
  }
  $report .= "</table>\n";
  return $report;
}

sub CreatePreDeterminationsBreakdownData
{
  my $self    = shift;
  my $start   = shift;
  my $end     = shift;
  my $monthly = shift;
  my $title   = shift;

  my ($year,$month) = $self->GetTheYearMonth();
  my $titleDate = $self->YearMonthToEnglish("$year-$month");
  my $justThisMonth = (!$start && !$end);
  $start = "$year-$month-01" unless $start;
  my $lastDay = Days_in_Month($year,$month);
  $end = "$year-$month-$lastDay" unless $end;
  my $what = 'date';
  $what = 'DATE_FORMAT(date, "%Y-%m")' if $monthly;
  my $sql = 'SELECT DISTINCT(' . $what . ') FROM predeterminationsbreakdown WHERE date>=? AND date<=?';
  #print "$sql<br/>\n";
  my @dates = map {$_->[0];} @{$self->SelectAll($sql, $start, $end)};
  if (scalar @dates && !$justThisMonth)
  {
    my $startEng = $self->YearMonthToEnglish(substr($dates[0],0,7));
    my $endEng = $self->YearMonthToEnglish(substr($dates[-1],0,7));
    $titleDate = ($startEng eq $endEng)? $startEng:sprintf("%s to %s", $startEng, $endEng);
  }
  my $report = ($title)? "$title\n":"Preliminary Determinations Breakdown $titleDate\n";
  my @titles = ('Date','Status 2','Status 3','Status 4','Status 8','Total','Status 2','Status 3','Status 4','Status 8');
  $report .= join("\t", @titles) . "\n";
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
    my $sql = 'SELECT s2,s3,s4,s8,s2+s3+s4+s8 FROM predeterminationsbreakdown WHERE date LIKE "' . $date1 . '%"';
    #print "$sql<br/>\n";
    my ($s2,$s3,$s4,$s8,$sum) = @{$self->SelectAll($sql)->[0]};
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
    $report .= "\t" . join("\t", @line) . "\n";
  }
  my $gt = $totals[0] + $totals[1] + $totals[2] + $totals[3];
  push @totals, $gt;
  for (my $i=0; $i < 5; $i++)
  {
    my $pct = 0.0;
    eval {$pct = 100.0*$totals[$i]/$gt;};
    push @totals, sprintf('%.1f%%', $pct);
  }
  $report .= "Total\t" . join("\t", @totals) . "\n";
  return $report;
}

sub CreateDeterminationsBreakdownData
{
  my $self    = shift;
  my $start   = shift;
  my $end     = shift;
  my $monthly = shift;
  my $title   = shift;

  my ($year,$month) = $self->GetTheYearMonth();
  my $titleDate = $self->YearMonthToEnglish("$year-$month");
  my $justThisMonth = (!$start && !$end);
  $start = "$year-$month-01" unless $start;
  my $lastDay = Days_in_Month($year,$month);
  $end = "$year-$month-$lastDay" unless $end;
  my $what = 'date';
  $what = 'DATE_FORMAT(date, "%Y-%m")' if $monthly;
  my $sql = 'SELECT DISTINCT(' . $what . ') FROM determinationsbreakdown WHERE date>=? AND date<=?'.
            ' ORDER BY date DESC';
  #print "$sql<br/>\n";
  my @dates = map {$_->[0];} @{$self->SelectAll($sql, $start, $end)};
  if (scalar @dates && !$justThisMonth)
  {
    my $startEng = $self->YearMonthToEnglish(substr($dates[0],0,7));
    my $endEng = $self->YearMonthToEnglish(substr($dates[-1],0,7));
    $titleDate = ($startEng eq $endEng)? $startEng:sprintf("%s to %s", $startEng, $endEng);
  }
  my $report = ($title)? "$title\n":"Determinations Breakdown $titleDate\n";
  my @titles = ('Date','Status 4','Status 5','Status 6','Status 7','Status 8','Subtotal',
                'Status 9','Total','Status 4','Status 5','Status 6','Status 7','Status 8');
  $report .= join("\t", @titles) . "\n";
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
    my ($s4,$s5,$s6,$s7,$s8,$sum1,$s9,$sum2) = @{$self->SelectAll($sql, $date1, $date2)->[0]};
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
    $report .= "\t". join("\t", @line). "\n";
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
  $report .= "Total\t" . join("\t", @totals) . "\n";
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
    $data = $self->CreatePreDeterminationsBreakdownData($start, $end, $monthly, $title);
    %whichlines = (4=>1);
    $span1 = 5;
    $span2 = 4;
  }
  else
  {
    $data = $self->CreateDeterminationsBreakdownData($start, $end, $monthly, $title);
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
      my $val = $line[$i];
      $val = '' if $val eq '0' or $val eq '0.0%';
      $report .= "<td $class $style>$val</td>\n";
    }
    $report .= "</tr>\n";
  }
  $report .= "</table>\n";
  return $report;
}

sub GetStatsYears
{
  my $self = shift;
  my $user = shift;

  my $usersql = '';
  $user = '' if $user eq 'all';
  my @params;
  if ($user)
  {
    if ('all__' eq substr $user, 0, 5)
    {
      my $inst = substr $user, 5;
      $usersql = 'AND u.institution=? ';
      push @params, $inst;
    }
    else
    {
      $usersql = 'AND user=? ';
      push @params, $user;
    }
  }
  my $sql = 'SELECT DISTINCT year FROM userstats s INNER JOIN users u ON s.user=u.id' .
            ' WHERE s.total_reviews>0 ' . $usersql . 'ORDER BY year DESC';
  #print "$sql<br/>\n";
  my $ref = $self->SelectAll($sql, @params);
  return unless scalar @{$ref};
  my @years = map {$_->[0];} @{$ref};
  my $thisyear = $self->GetTheYear();
  unshift @years, $thisyear unless $years[0] ge $thisyear;
  return \@years;
}

sub CreateStatsData
{
  my $self        = shift;
  my $page        = shift;
  my $user        = shift;
  my $cumulative  = shift;
  my $year        = shift;
  my $inval       = shift;
  my $nononexpert = shift;
  my $dopercent   = shift;

  my $instusers = undef;
  my $instusersne = undef;
  $year = ($self->GetTheYearMonth())[0] unless $year;
  my @statdates = ($cumulative)? reverse @{$self->GetStatsYears()} : $self->GetAllMonthsInYear($year);
  my $username;
  if ($user eq 'all') { $username = 'All Reviewers'; }
  elsif ('all__' eq substr $user, 0, 5)
  {
    my $inst = substr $user, 5;
    my $name = $self->GetInstitutionName($inst);
    $username = "All $name Reviewers";
    my $affs = $self->GetInstitutionUsers($inst);
    $instusers = sprintf "'%s'", join "','", @{$affs};
    $instusersne = sprintf "'%s'", join "','", map {($self->IsUserExpert($_))? ():$_} @{$affs};
  }
  else
  {
    $username = $self->GetUserProperty($user, 'name');
    if ($page =~ m/^Admin/i && $page !~ m/Inst$/i)
    {
      my $inst = $self->GetUserProperty($user, 'institution');
      my $iname = $self->GetInstitutionName($inst);
      $username .= ' ('. $iname . ')';
    }
  }
  #print "username '$username', instusers $instusers<br/>\n";
  my $label = "$username: " . (($cumulative)? "CRMS&nbsp;Project&nbsp;Cumulative":$year);
  my $report = sprintf("$label\n\tProject Total%s", (!$cumulative)? "\tTotal $year":'');
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
    $report .= "\t" . $date;
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
    my $rows = $self->SelectAll($sql, $mintime, $maxtime);
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
    my $pct = eval {100.0*$whichone/$total;};
    if ('all__' eq substr $user, 0, 5)
    {
      my ($total2,$correct2,$incorrect2,$neutral2) = $self->GetValidation($mintime, $maxtime);
      $pct = eval {100.0*$incorrect2/$total2;};
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
  my ($y, $m) = split '-', $latest;
  my $lastDay = Days_in_Month($y, $m);
  my ($total,$correct,$incorrect,$neutral) = $self->GetValidation($earliest, $latest, $instusersne);
  $correct += $neutral if $page eq 'userRate';
  #print "total $total correct $correct incorrect $incorrect neutral $neutral for $earliest to $latest ($instusersne)<br/>\n";
  my $whichone = ($inval)? $incorrect:$correct;
  my $pct = eval {100.0*$whichone/$total;};
  if ('all__' eq substr $user, 0, 5)
  {
    my ($total2,$correct2,$incorrect2,$neutral2) = $self->GetValidation($earliest, $latest);
    $pct = eval {100.0*$incorrect2/$total2;};
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
    my $rows = $self->SelectAll($sql, @params);
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
    my $pct = eval {100.0*$whichone/$total;};
    if ('all__' eq substr $user, 0, 5)
    {
      my ($total2,$correct2,$incorrect2,$neutral2) = $self->GetValidation($earliest, $latest);
      $pct = eval {100.0*$incorrect2/$total2;};
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
      $report .= "\t" . $n;
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
    $report .= "\t" . $n;
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
      $report .= "\t" . $n;
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
  my $suppressBreakdown = shift; #unused
  my $year              = shift;
  my $inval             = shift;
  my $nononexpert       = shift;

  my $data = $self->CreateStatsData($page, $user, $cumulative, $year, $inval, $nononexpert, 1);
  my @lines = split m/\n/, $data;
  my $url = $self->Sysify("crms?p=$page;download=1;user=$user;cumulative=$cumulative;year=$year;inval=$inval;nne=$nononexpert");
  my $name = shift @lines;
  my $nbsps = '&nbsp;&nbsp;&nbsp;&nbsp;';
  my $dllink = <<END;
  <a href='$url' target='_blank'>Download</a>
  <a class='tip' href='#'>
    <img width="16" height="16" alt="Rights/Reason Help" src="/c/crms/help.png"/>
    <span>
    <strong>To get the downloaded stats into a spreadsheet:</strong><br/>
      &#x2022; Click on the "Download" link (this will open a new page in your browser)<br/>
      &#x2022; Select all of the text on the new page and copy it<br/>
      &#x2022; Switch to Excel<br/>
      &#x2022; Choose the menu item <strong>Edit &#x2192; Paste Special...</strong><br/>
      &#x2022; Choose Unicode in the dialog box<br/>
    </span>
  </a>
END
  my $report = "<span style='font-size:1.3em;'><strong>$name</strong></span>$nbsps $dllink\n<br/>";
  $report .= "<table class='exportStats'>\n<tr>\n";
  foreach my $th (split "\t", shift @lines)
  {
    $th = $self->YearMonthToEnglish($th) if $th =~ m/^\d.*/;
    $th =~ s/\s/&nbsp;/g;
    $report .= "<th style='text-align:center;'>$th</th>\n";
  }
  $report .= "</tr>\n";
  my %majors = ('PD Reviews' => 1, 'IC Reviews' => 1, 'UND/NFI Reviews' => 1, '__TOT__' => 1);
  my %minors = ('Time Reviewing (mins)' => 1, 'Time per Review (mins)' => 1, 'Average Time per Review (mins)' => 1,
                'Reviews per Hour' => 1, 'Average Reviews per Hour' => 1, 'Outlier Reviews' => 1);
  my $exp = $self->IsUserExpert($user);
  foreach my $line (@lines)
  {
    my @items = split("\t", $line);
    my $title = shift @items;
    next if $title eq '__VAL__' and ($exp);
    next if $title eq '__MVAL__' and ($exp);
    next if $title eq '__AVAL__' and ($exp);
    next if $title eq '__NEUT__' && ($exp || $page eq 'userRate');
    next if $title eq '__TOTNE__' and ($user ne 'all' and $user !~ m/all__/ and !$cumulative);
    next if ($cumulative or $user eq 'all' or $user !~ m/all__/) and !exists $majors{$title} and !exists $minors{$title} and $title !~ m/__.+?__/;
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
                         ($title eq '__TOT__')? "<strong>$n</strong>":$n,
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

  my $report = $self->CreateStatsData($page, $user, $cumulative, $year, $inval, $nononexpert);
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

# Returns an array ref of hash refs
# Each hash has keys 'id', 'name', 'active'
# Array is sorted alphabetically with inactive reviewers last.
sub GetInstitutionReviewers
{
  my $self = shift;
  my $inst = shift;

  my @revs;
  my $sql = 'SELECT id,name,reviewer+advanced+expert+admin+superadmin as active,commitment'.
            ' FROM users WHERE institution=?'.
            ' AND (reviewer+advanced+expert>0 OR reviewer+advanced+expert+admin+superadmin=0)'.
            ' ORDER BY active DESC,name';
  my $ref = $self->SelectAll($sql, $inst);
  foreach my $row (@{$ref})
  {
    my $id = $row->[0];
    my $name = $row->[1];
    my $active = ($row->[2] > 0)? 1:0;
    next if $name =~ m/\(|\)/;
    push @revs, {'id'=>$id, 'name'=>$name, 'active'=>$active, 'commitment'=>$row->[3]};
  }
  @revs = sort {$b->{'active'} <=> $a->{'active'}
                || $b->{'commitment'} <=> $a->{'commitment'}
                || $a->{'name'} <=> $b->{'name'};} @revs;
  return \@revs;
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
    my $ref = $self->SelectAll($sql, $user);
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

  my $sql = 'SELECT COUNT(*) FROM historicalreviews WHERE user=? AND legacy!=1' .
            ' AND EXTRACT(YEAR FROM time)=? AND EXTRACT(MONTH FROM time)=?';
  my $total_reviews = $self->SimpleSqlGet($sql, $user, $y, $m);
  #pd/pdus
  $sql = 'SELECT COUNT(*) FROM historicalreviews WHERE user=? AND legacy!=1 AND (attr=1 OR attr=9)' .
         ' AND EXTRACT(YEAR FROM time)=? AND EXTRACT(MONTH FROM time)=?';
  my $total_pd = $self->SimpleSqlGet($sql, $user, $y, $m);
  #ic
  $sql = 'SELECT COUNT(*) FROM historicalreviews WHERE user=? AND legacy!=1 AND attr=2' .
         ' AND EXTRACT(YEAR FROM time)=? AND EXTRACT(MONTH FROM time)=?';
  my $total_ic = $self->SimpleSqlGet($sql, $user, $y, $m);
  #und
  $sql = 'SELECT COUNT(*) FROM historicalreviews WHERE user=? AND legacy!=1 AND attr=5' .
         ' AND EXTRACT(YEAR FROM time)=? AND EXTRACT(MONTH FROM time)=?';
  my $total_und = $self->SimpleSqlGet($sql, $user, $y, $m);
  # time reviewing (in minutes) - not including outliers
  # default outlier seconds is 300 (5 min)
  my $outSec = $self->GetSystemVar('outlierSeconds', 300);
  $sql = 'SELECT COALESCE(SUM(TIME_TO_SEC(duration)),0)/60.0 FROM historicalreviews' .
         ' WHERE user=? AND legacy!=1 AND EXTRACT(YEAR FROM time)=?' .
         ' AND EXTRACT(MONTH FROM time)=? AND TIME(duration)<=SEC_TO_TIME(?)';
  my $total_time = $self->SimpleSqlGet($sql, $user, $y, $m, $outSec);
  # Total outliers
  $sql = 'SELECT COUNT(*) FROM historicalreviews WHERE user=? AND legacy!=1' .
         ' AND EXTRACT(YEAR FROM time)=? AND EXTRACT(MONTH FROM time)=?' .
         ' AND TIME(duration)>SEC_TO_TIME(?)';
  my $total_outliers = $self->SimpleSqlGet($sql, $user, $y, $m, $outSec);
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
  my ($total_correct,$total_incorrect,$total_neutral,$total_flagged) = $self->CountCorrectReviews($user, $mintime, $maxtime);
  $sql = 'INSERT INTO userstats (user,month,year,monthyear,total_reviews,total_pd,'.
         'total_ic,total_und,total_time,time_per_review,reviews_per_hour,'.
         'total_outliers,total_correct,total_incorrect,total_neutral,total_flagged)'.
         ' VALUES ' . $self->WildcardList(16);
  $self->PrepareSubmitSql($sql, $user, $m, $y, $y . '-' . $m, $total_reviews, $total_pd,
                          $total_ic, $total_und, $total_time, $time_per_review, $reviews_per_hour,
                          $total_outliers, $total_correct, $total_incorrect, $total_neutral, $total_flagged);
}

sub UpdateDeterminationsBreakdown
{
  my $self = shift;
  my $date = shift;

  $date = $self->SimpleSqlGet('SELECT CURDATE()') unless $date;
  my @vals = ($date);
  foreach my $status (4..9)
  {
    my $sql = 'SELECT COUNT(gid) FROM exportdata WHERE DATE(time)=? AND status=?';
    push @vals, $self->SimpleSqlGet($sql, $date, $status);
  }
  my $wcs = $self->WildcardList(scalar @vals);
  my $sql = 'REPLACE INTO determinationsbreakdown (date,s4,s5,s6,s7,s8,s9) VALUES '. $wcs;
  $self->PrepareSubmitSql($sql, @vals);
}

sub UpdateExportStats
{
  my $self = shift;
  my $date = shift;

  my %counts;
  $date = $self->SimpleSqlGet('SELECT CURDATE()') unless $date;
  my $sql = 'SELECT attr,reason,COUNT(*) FROM exportdata WHERE DATE(time)=? AND exported=1 GROUP BY CONCAT(attr,reason)';
  #print "$sql\n";
  my $ref = $self->SelectAll($sql, $date);
  foreach my $row (@{$ref})
  {
    $sql = 'REPLACE INTO exportstats (date,attr,reason,count) VALUES (?,?,?,?)';
    $self->PrepareSubmitSql($sql, $date, $row->[0], $row->[1], $row->[2]);
  }
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
    my $sql = 'SELECT COUNT(*) FROM reviews WHERE id=? AND user!=?';
    my $count = $self->SimpleSqlGet($sql, $id, $user);
    if ($count >= 2)
    {
      $msg = 'This volume does not need to be reviewed. Two reviewers or an expert have already reviewed it. Please Cancel.';
    }
    $sql = 'SELECT COUNT(*) FROM queue WHERE id=? AND status!=0';
    $count = $self->SimpleSqlGet($sql, $id);
    if ($count >= 1) { $msg = 'This item has been processed already. Please Cancel.'; }
  }
  return $msg;
}

sub ValidateSubmission
{
  my ($self, $id, $user, $attr, $reason, $note,
      $category, $renNum, $renDate, $oneoff) = @_;
  my $errorMsg = '';
  ## Someone else has the item locked?
  my $lock = $self->IsLockedForOtherUser($id);
  if ($lock)
  {
    $errorMsg = 'This item has been locked by another reviewer. Please Cancel. ';
    my $note = sprintf "Collision for $user on %s: $id locked for $lock", $self->Hostname();
    $self->PrepareSubmitSql('INSERT INTO note (note) VALUES (?)', $note);
  }
  if (!$self->IsVolumeInQueue($id))
  {
    $errorMsg .= 'This volume is not in the queue. Please cancel. ';
  }
  ## check user
  if (!$oneoff && !$self->IsUserReviewer($user) && !$self->IsUserAdvanced($user))
  {
    $errorMsg .= 'Not a reviewer. ';
  }
  elsif ($oneoff && !$self->IsUserSuperAdmin($user))
  {
    $errorMsg .= 'Not a one-off reviewer. ';
  }
  if (!$attr || !$reason)
  {
    $errorMsg .= 'rights/reason designation required. ';
  }
  if (!$errorMsg)
  {
    my $module = 'Validator_' . $self->Sys() . '.pm';
    require $module;
    $errorMsg = Validator::ValidateSubmission(@_);
  }
  if (!$oneoff)
  {
    my $incarn = $self->HasItemBeenReviewedByAnotherIncarnation($id, $user);
    $errorMsg .= "Another expert must do this review because of a review by $incarn. Please cancel. " if $incarn;
  }
  return $errorMsg;
}

sub GetTitle
{
  my $self = shift;
  my $id   = shift;

  my $ti = $self->SimpleSqlGet('SELECT title FROM bibdata WHERE id=?', $id);
  if (!$ti)
  {
    $self->UpdateMetadata($id, 1);
    $ti = $self->SimpleSqlGet('SELECT title FROM bibdata WHERE id=?', $id);
  }
  return $ti;
}

sub GetPubDate
{
  my $self   = shift;
  my $id     = shift;
  my $do2    = shift;
  my $record = shift;

  print "Warning: GetPubDate no longer takes a do2 parameter!\n" if $do2;
  my $sql = 'SELECT YEAR(pub_date) FROM bibdata WHERE id=?';
  my $date = $self->SimpleSqlGet($sql, $id);
  if (!$date)
  {
    $record = $self->UpdateMetadata($id, 1, $record);
    $date = $self->SimpleSqlGet($sql, $id);
  }
  return $date;
}

sub FormatPubDate
{
  my $self   = shift;
  my $id     = shift;
  my $record = shift;

  $record = $self->GetMetadata($id) unless defined $record;
  return $record->formatPubDate() if defined 'record';
  return 'unknown';
}

sub IsDateRange
{
  my $self = shift;
  my $id   = shift;

  my $fmt = $self->FormatPubDate($id);
  return ($fmt =~ m/-/)? 1:0;
}

sub GetPubCountry
{
  my $self = shift;
  my $id   = shift;

  my $sql = 'SELECT country FROM bibdata WHERE id=?';
  my $where = $self->SimpleSqlGet($sql, $id);
  if (!defined $where)
  {
    $self->UpdateMetadata($id, 1);
    $where = $self->SimpleSqlGet($sql, $id);
  }
  return $where;
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

sub GetMetadata
{
  my $self = shift;
  my $id   = shift;

  use Metadata;
  return Metadata->new('id' => $id, 'crms' => $self);
}

sub BarcodeToId
{
  my $self   = shift;
  my $id     = shift;
  my $record = shift;

  my $sys = $self->SimpleSqlGet('SELECT sysid FROM bibdata WHERE id=?', $id);
  if (!$sys)
  {
    $record = $self->GetMetadata($id) unless defined $record;
    $self->ClearErrors();
    $sys = $record->sysid if defined $record;
  }
  return $sys;
}

sub UpdateSysids
{
  my $self   = shift;
  my $record = shift;
  
  my $sql = 'UPDATE bibdata SET sysid=? WHERE id=?';
  $self->PrepareSubmitSql($sql, $record->sysid, $_) for @{$record->allHTIDs};
}

# Update author, title, pubdate, country, sysid fields in bibdata.
# Only updates existing rows (does not INSERT) unless the force param is set.
sub UpdateMetadata
{
  my $self   = shift;
  my $id     = shift;
  my $force  = shift;
  my $record = shift;

  # Bail out if the volume is in historicalreviews and not in the queue,
  # to preserve bid data potentially instrumental to an existing review
  # and possibly clobbered by a bib correction.
  return if $self->SimpleSqlGet('SELECT COUNT(*) FROM historicalreviews WHERE id=?', $id) and
            !$self->SimpleSqlGet('SELECT COUNT(*) FROM queue WHERE id=?', $id);
  my $cnt = $self->SimpleSqlGet('SELECT COUNT(*) FROM bibdata WHERE id=?', $id);
  if ($cnt == 0 || $force)
  {
    $record = $self->GetMetadata($id) unless defined $record;
    if (defined $record)
    {
      my $date = $record->copyrightDate . '-01-01';
      # FIXME: can this ever happen? Why would we update bibdata for a catalog record
      # and not a specific HTID?
      if ($record->id eq $record->sysid)
      {
        my $sql = 'UPDATE bibdata SET author=?,title=?,pub_date=?,country=? WHERE sysid=?';
        $self->PrepareSubmitSql($sql, $record->author, $record->title,
                                $date, $record->country, $record->sysid);
      }
      else
      {
        my $sql = 'REPLACE INTO bibdata (id,author,title,pub_date,country,sysid)' .
                  ' VALUES (?,?,?,?,?,?)';
        $self->PrepareSubmitSql($sql, $id, $record->author, $record->title,
                                $date, $record->country, $record->sysid);
      }
    }
    else
    {
      $self->SetError('Could not get metadata for ' . $id);
    }
  }
  return $record;
}

sub GetReviewField
{
  my $self  = shift;
  my $id    = shift;
  my $user  = shift;
  my $field = shift;

  return $self->SimpleSqlGet('SELECT ' . $field . ' FROM reviews WHERE id=? AND user=? LIMIT 1', $id, $user);
}

sub HasLockedItem
{
  my $self = shift;
  my $user = shift || $self->get('user');
  my $page = shift || 'review';

  my $table = ($page eq 'corrections')? 'corrections':'queue';
  my $sql = 'SELECT COUNT(*) FROM ' . $table . ' WHERE locked=?';
  $sql .= ' LIMIT 1';
  return ($self->SimpleSqlGet($sql, $user))? 1:0;
}

sub GetLockedItem
{
  my $self = shift;
  my $user = shift || $self->get('user');
  my $page = shift || 'review';

  my $table = ($page eq 'corrections')? 'corrections':'queue';
  my $sql = 'SELECT id FROM ' . $table . ' WHERE locked=?';
  $sql .= ' LIMIT 1';
  return $self->SimpleSqlGet($sql, $user);
}

sub IsLocked
{
  my $self = shift;
  my $id   = shift;
  my $page = shift || 'review';

  my $table = ($page eq 'corrections')? 'corrections':'queue';
  my $sql = 'SELECT id FROM ' . $table . ' WHERE locked IS NOT NULL AND id=?';
  return ($self->SimpleSqlGet($sql, $id))? 1:0;
}

sub IsLockedForUser
{
  my $self = shift;
  my $id   = shift;
  my $user = shift || $self->get('user');
  my $page = shift || 'review';

  my $table = ($page eq 'corrections')? 'corrections':'queue';
  my $sql = 'SELECT COUNT(*) FROM ' . $table . ' WHERE id=? AND locked=?';
  return 1 == $self->SimpleSqlGet($sql, $id, $user);
}

sub IsLockedForOtherUser
{
  my $self = shift;
  my $id   = shift;
  my $user = shift || $self->get('user');
  my $page = shift || 'review';

  my $table = ($page eq 'corrections')? 'corrections':'queue';
  my $lock = $self->SimpleSqlGet('SELECT locked FROM ' . $table . ' WHERE id=?', $id);
  return ($lock && $lock ne $user)? $lock:undef;
}

sub RemoveOldLocks
{
  my $self = shift;
  my $time = shift;
  my $page = shift || 'review';

  my $table = ($page eq 'corrections')? 'corrections':'queue';
  # By default, GetPrevDate() returns the date/time 24 hours ago.
  $time = $self->GetPrevDate($time);
  my $lockedRef = $self->GetLockedItems();
  foreach my $item (keys %{$lockedRef})
  {
    my $id = $lockedRef->{$item}->{id};
    my $user = $lockedRef->{$item}->{locked};
    my $sql = 'SELECT id FROM ' . $table . ' WHERE id=? AND time<?';
    my $old = $self->SimpleSqlGet($sql, $id, $time);
    $self->UnlockItem($id, $user, $page) if $old;
  }
}

sub PreviouslyReviewed
{
  my $self = shift;
  my $id   = shift;
  my $user = shift || $self->get('user');

  ## expert reviewers can edit any time
  return 0 if $self->IsUserExpert($user);
  my $limit = $self->GetYesterday();
  my $sql = 'SELECT id FROM reviews WHERE id=? AND user=? AND time<? AND hold=0';
  my $found = $self->SimpleSqlGet($sql, $id, $user, $limit);
  return ($found)? 1:0;
}

# Returns 0 on success, error message on error.
sub LockItem
{
  my $self     = shift;
  my $id       = shift;
  my $user     = shift || $self->get('user');
  my $override = shift;
  my $page     = shift || 'review';

  my $table = ($page eq 'corrections')? 'corrections':'queue';
  ## if already locked for this user, that's OK
  return 0 if $self->IsLockedForUser($id, $user);
  # Not locked for user, maybe someone else
  if ($self->IsLocked($id, $page))
  {
    return 'Volume has been locked by another user';
  }
  ## can only have 1 item locked at a time (unless override)
  if (!$override)
  {
    my $locked = $self->GetLockedItem($user, $page);
    if (defined $locked)
    {
      return 0 if $locked eq $id;
      return "You already have a locked item ($locked).";
    }
  }
  my $sql = 'UPDATE ' . $table . ' SET locked=? WHERE id=?';
  $self->PrepareSubmitSql($sql, $user, $id);
  return 0;
}

sub UnlockItem
{
  my $self = shift;
  my $id   = shift;
  my $user = shift || $self->get('user');
  my $page = shift || 'review';

  my $table = ($page eq 'corrections')? 'corrections':'queue';
  my $sql = 'UPDATE ' . $table . ' SET locked=NULL WHERE id=? AND locked=?';
  $self->PrepareSubmitSql($sql, $id, $user);
}

sub UnlockItemEvenIfNotLocked
{
  my $self = shift;
  my $id   = shift;
  my $user = shift || $self->get('user');

  my $sql = 'UPDATE queue SET locked=NULL WHERE id=?';
  if (!$self->PrepareSubmitSql($sql, $id)) { return 0; }
  return 1;
}

sub UnlockAllItemsForUser
{
  my $self = shift;
  my $user = shift || $self->get('user');
  my $page = shift || 'review';

  my $table = ($page eq 'corrections')? 'corrections':'queue';
  $self->PrepareSubmitSql('UPDATE ' . $table . ' SET locked=NULL WHERE locked=?', $user);
}

sub GetLockedItems
{
  my $self = shift;
  my $user = shift || $self->get('user');
  my $page = shift || 'review';

  my $table = ($page eq 'corrections')? 'corrections':'queue';
  my $restrict = ($user)? "='$user'":'IS NOT NULL';
  my $sql = 'SELECT id, locked FROM ' . $table . ' WHERE locked ' . $restrict;
  my $ref = $self->SelectAll($sql);
  my $return = {};
  foreach my $row (@{$ref})
  {
    my $id = $row->[0];
    my $lo = $row->[1];
    $return->{$id} = {'id' => $id, 'locked' => $lo};
  }
  return $return;
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

sub HasItemBeenReviewedByAnotherIncarnation
{
  my $self = shift;
  my $id   = shift;
  my $user = shift || $self->get('user');

  my $incarns = $self->GetUserIncarnations($user);
  foreach my $incarn (@{$incarns})
  {
    next if $incarn eq $user;
    my $sql = 'SELECT COUNT(*) FROM reviews WHERE id=? AND user=?';
    return $incarn if $self->SimpleSqlGet($sql, $id, $incarn);
  }
}

sub CountExpertHistoricalReviews
{
  my $self = shift;
  my $id   = shift;

  my $sql = 'SELECT COUNT(*) FROM historicalreviews WHERE id=? AND expert>0';
  return $self->SimpleSqlGet($sql, $id);
}

# Code commented out with #### are race condition mitigations
# to be considered for a later release.
# Test param prints debug info and iterates 5 times to test mitigation.
sub GetNextItemForReview
{
  my $self = shift;
  my $user = shift || $self->get('user');
  my $test = shift;

  my $id = undef;
  my $err = undef;
  my $sql = undef;
  eval {
    my @params = ($user);
    my $order = 'q.priority DESC, cnt DESC, hash, q.time ASC';
    ####$order = 'hash';
    #### #Random de-prioritization will interfere withe the CRMS US
    #### #State gov docs project, so this needs a system var to override.
    ####$order = 'q.priority DESC,'.$order if rand()<.25 and !$self->GetSystemVar('alwaysPrioritize');
    ####$order = 'cnt DESC,'.$order if rand()<.25;
    my ($excludeh, $excludei) = ('', '');
    my $inc = $self->GetUserIncarnations($user);
    my $wc = $self->WildcardList(scalar @{$inc});
    $excludei = ' AND NOT EXISTS (SELECT * FROM reviews r2 WHERE r2.id=q.id AND r2.user IN '. $wc. ')';
    push @params, @{$inc};
    if (!$self->IsUserAdmin($user))
    {
      $excludeh = ' AND NOT EXISTS (SELECT * FROM historicalreviews r3 WHERE r3.id=q.id AND r3.user IN '. $wc. ')';
      push @params, @{$inc};
    }
    $sql = 'SELECT q.id,(SELECT COUNT(*) FROM reviews r WHERE r.id=q.id) AS cnt,'.
           'SHA2(CONCAT(?,q.id),0) AS hash,q.priority'.
           ' FROM queue q INNER JOIN users u ON u.newproject=q.newproject'.
           ' AND q.expcnt=0 AND q.locked IS NULL AND q.status<2'.
           $excludei. $excludeh.
           ' HAVING cnt<2 '.
           ' ORDER BY '. $order;
    if (defined $test)
    {
      $sql .= ' LIMIT 5';
      printf "$user: %s\n", Utilities::StringifySql($sql, @params);
    }
    my $ref = $self->SelectAll($sql, @params);
    foreach my $row (@{$ref})
    {
      my $id2 = $row->[0];
      my $cnt = $row->[1];
      my $hash = $row->[2];
      my $pri = $row->[3];
      if (defined $test)
      {
        printf "  $id2 %s %s ($cnt, %s...) (P %s)\n",
               $self->GetAuthor($id2), $self->GetTitle($id2),
               uc substr($hash, 0, 8), $pri;
        $id = $id2 unless defined $id;
      }
      else
      {
        $err = $self->LockItem($id2, $user);
        if (!$err)
        {
          $id = $id2;
          last;
        }
      }
    }
  };
  if ($@ && ! defined $id)
  {
    my $err = "Could not get a volume for $user to review: $@.";
    $err .= "\n$sql" if $sql;
    $self->SetError($err);
  }
  return $id;
}

sub GetNextCorrectionForReview
{
  my $self = shift;
  my $user = shift;

  my $id = undef;
  my $err = undef;
  my $sql = 'SELECT c.id FROM corrections c WHERE c.locked IS NULL AND status IS NULL ORDER BY time DESC';
  eval {
    my $ref = $self->SelectAll($sql);
    foreach my $row (@{$ref})
    {
      my $id2 = $row->[0];
      $err = $self->LockItem($id2, $user, 0, 1);
      if (!$err)
      {
        $id = $id2;
        last;
      }
    }
  };
  $self->SetError($@) if $@;
  if (!$id)
  {
    $err = sprintf "Could not get a correction for $user to review%s.", ($err)? " ($err)":'';
    $err .= "\n$sql" if $sql;
    $self->SetError($err);
  }
  return $id;
}

# Checks whether the attributes and reasons tables are up to date with the Rights DB.
# If not, purges and repopulates any that need an update.
sub AttrReasonSync
{
  my $self = shift;

  my @tables = ('attributes','reasons');
  foreach my $table (@tables)
  {
    my $sql = 'SELECT COUNT(*) FROM '. $table;
    my $count = $self->SimpleSqlGet($sql);
    my $count2 = $self->SimpleSqlGetSDR($sql);
    if ($count != $count2)
    {
      $sql = 'DELETE FROM '. $table;
      $self->PrepareSubmitSql($sql);
      my $sql = 'SELECT * FROM '. $table;
      my $ref = $self->SelectAllSDR($sql);
      my $wc = $self->WildcardList(scalar @{$ref->[0]});
      foreach my $row (@{$ref})
      {
        $sql = 'INSERT INTO '. $table. ' VALUES '. $wc;
        $self->PrepareSubmitSql($sql, @{$row});
      }
    }
  }
}

sub TranslateAttr
{
  my $self = shift;
  my $a    = shift;

  my $sql = 'SELECT id FROM attributes WHERE name=?';
  $sql = 'SELECT name FROM attributes WHERE id=?' if $a =~ m/^\d+$/;
  my $val = $self->SimpleSqlGet($sql, $a);
  $a = $val if $val;
  return $a;
}

sub TranslateReason
{
  my $self = shift;
  my $r    = shift;

  my $sql = 'SELECT id FROM reasons WHERE name=?';
  $sql = 'SELECT name FROM reasons WHERE id=?' if $r =~ m/^\d+$/;
  my $val = $self->SimpleSqlGet($sql, $r);
  $r = $val if $val;
  return $r;
}

sub TranslateRights
{
  my $self   = shift;
  my $rights = shift;

  my $sql = 'SELECT CONCAT(a.name,"/",rs.name) FROM rights r'.
            ' INNER JOIN attributes a ON r.attr=a.id'.
            ' INNER JOIN reasons rs ON r.reason=rs.id'.
            ' WHERE r.id=?';
  my $ref = $self->SelectAll($sql, $rights);
  return $ref->[0]->[0];
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
## ----------------------------------------------------------------------------
sub SetError
{
  my $self   = shift;
  my $error  = shift;

  $error .= "\n";
  $error .= Utilities::StackTrace();
  my $errors = $self->get('errors');
  push @{$errors}, $error;
}

sub CountErrors
{
  my $self = shift;
  my $errs = $self->get('errors');
  return (defined $errs)? scalar @{$errs}:0;
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

  my $sql = 'SELECT DISTINCT priority FROM queue ORDER BY priority ASC';
  my @pris = map {$self->StripDecimal($_->[0])} @{$self->SelectAll($sql)};
  my $priheaders = join '', map {"<th>Priority&nbsp;$_</th>";} @pris;
  my $report = "<table class='exportStats'>
                <tr><th>Status</th><th>Total</th>$priheaders</tr>\n";
  foreach my $status (-1 .. 9)
  {
    my $statusClause = ($status == -1)? '':"WHERE STATUS=$status";
    $status = 'All' if $status == -1;
    my $class = ($status eq 'All')?' class="total"':'';
    $sql = 'SELECT priority,COUNT(id) FROM queue '. $statusClause. 
           ' GROUP BY priority ASC WITH ROLLUP';
    my $ref = $self->SelectAll($sql);
    my $count = (scalar @{$ref})? $ref->[-1]->[1]:0;
    $report .= sprintf("<tr><td%s>$status</td><td%s>$count</td>", $class, $class);
    $report .= $self->DoPriorityBreakdown($ref, $class, \@pris);
    $report .= "</tr>\n";
  }
  $sql = 'SELECT priority,COUNT(id) FROM queue WHERE status=0'.
         ' AND pending_status=0 GROUP BY priority ASC WITH ROLLUP';
  my $ref = $self->SelectAll($sql);
  my $count = (scalar @{$ref})? $ref->[-1]->[1]:0;
  my $class = ' class="major"';
  $report .= sprintf("<tr><td%s>Not&nbsp;Yet&nbsp;Active</td><td%s>$count</td>", $class, $class);
  $report .= $self->DoPriorityBreakdown($ref, $class, \@pris);
  $report .= "</tr>\n";
  #$report .= sprintf("<tr><td class='nowrap' colspan='%d'>
  #                        <span class='smallishText'>Note: includes both active and inactive volumes.</span></td></tr>\n",
  #                        2+scalar @pris);
  $report .= "</table>\n";
  return $report;
}

sub CreateSystemReport
{
  my $self = shift;

  my $report = "<table class='exportStats'>\n";
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
  $report .= '<tr><th class="nowrap">Last Queue Addition</th><td>' . $n . "</td></tr>\n";
  my $count = $self->GetCandidatesSize();
  $report .= "<tr><th class='nowrap'>Volumes in Candidates</th><td>$count</td></tr>\n";
  my $ref = $self->GetProjectsRef(1);
  if (scalar @{$ref})
  {
    foreach my $row (@{$ref})
    {
      my $proj = $row->{'name'};
      $n = $row->{'candidatesCount'};
      next unless $n > 0;
      $report .= sprintf("<tr><th class='nowrap'>&nbsp;&nbsp;&nbsp;&nbsp;$proj</th><td class='nowrap'>$n (%0.1f%%)</td></tr>\n", 100.0*$n/$count);
    }
  }
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
  $report .= '<tr><th class="nowrap">Last Candidates Update</th><td>' . $n . "</td></tr>\n";
  my $sql = 'SELECT COUNT(*) FROM und WHERE src!="no meta" AND src!="duplicate" AND src!="cross-record inheritance"';
  my $count = $self->SimpleSqlGet($sql);
  $report .= "<tr><th class='nowrap'>Volumes Filtered*</th><td>$count</td></tr>\n";
  if ($count)
  {
    $sql = 'SELECT src,COUNT(src) FROM und WHERE src!="no meta"'.
           ' AND src!="duplicate" AND src!="cross-record inheritance" GROUP BY src ORDER BY src';
    my $ref = $self->SelectAll($sql);
    foreach my $row (@{ $ref})
    {
      my $src = $row->[0];
      $n = $row->[1];
      $report .= sprintf("<tr><th>&nbsp;&nbsp;&nbsp;&nbsp;$src</th><td>$n&nbsp;(%0.1f%%)</td></tr>\n", 100.0*$n/$count);
    }
  }
  $sql = 'SELECT COUNT(*) FROM und WHERE src="no meta" OR src="duplicate" OR src="cross-record inheritance"';
  $count = $self->SimpleSqlGet($sql);
  $report .= "<tr><th class='nowrap'>Volumes Temporarily Filtered*</th><td>$count</td></tr>\n";
  if ($count)
  {
    $sql = 'SELECT src,COUNT(src) FROM und WHERE src="no meta" OR src="duplicate"'.
           ' OR src="cross-record inheritance" GROUP BY src ORDER BY src';
    my $ref = $self->SelectAll($sql);
    foreach my $row (@{ $ref})
    {
      my $src = $row->[0];
      $n = $row->[1];
      $report .= sprintf("<tr><th>&nbsp;&nbsp;&nbsp;&nbsp;$src</th><td>$n&nbsp;(%0.1f%%)</td></tr>\n", 100.0*$n/$count);
    }
  }
  my ($delay,$since) = $self->ReplicationDelay();
  if ($delay > 0)
  {
    my $host = $self->Hostname();
    my $alert = $delay >= 5;
    if ($delay == 999999)
    {
      $delay = 'Disabled';
    }
    else
    {
      $delay .= '&nbsp;' . $self->Pluralize('second', $delay);
    }
    $delay = "<span style='color:#CC0000;font-weight:bold;'>$delay&nbsp;since&nbsp;$since</span><br/>" if $alert;
    $report .= "<tr><th class='nowrap'>Database Replication Delay</th><td class='nowrap'>$delay on $host</td></tr>\n";
  }
  $report .= '<tr><td colspan="2">';
  $report .= '<span class="smallishText">* This number is not included in the "Volumes in Candidates" count.</span>';
  $report .= "</td></tr></table>\n";
  return $report;
}

sub CreateDeterminationReport
{
  my $self = shift;

  my ($count,$time) = $self->GetLastExport();
  my %cts = ();
  my %pcts = ();
  my $sql = 'SELECT DISTINCT priority FROM exportdata'.
            ' WHERE DATE(time)=DATE(?) ORDER BY priority ASC';
  my @pris = map {$self->StripDecimal($_->[0])} @{$self->SelectAll($sql, $time)};
  $sql = 'SELECT COUNT(gid) FROM exportdata'.
         ' WHERE DATE(time)=DATE(?) ORDER BY priority ASC';
  my $total = $self->SimpleSqlGet($sql, $time);
  my $priheaders = join '', map {"<th>Priority&nbsp;$_</th>";} @pris;
  my $report = "<table class='exportStats'>\n<tr><th></th><th>Total</th>$priheaders</tr>\n";
  foreach my $status (4 .. 9)
  {
    $sql = 'SELECT COUNT(id) FROM exportdata WHERE status=? AND DATE(time)=DATE(?)';
    my $ct = $self->SimpleSqlGet($sql, $status, $time);
    my $pct = 0.0;
    eval {$pct = 100.0*$ct/$total;};
    $cts{$status} = $ct;
    $pcts{$status} = $pct;
  }
  my $colspan = 1 + scalar @pris;
  my %sources;
  $sql = 'SELECT src,COUNT(gid) FROM exportdata WHERE src IS NOT NULL AND src NOT LIKE "HTS-%" GROUP BY src';
  my $rows = $self->SelectAll($sql);
  foreach my $row (@{$rows})
  {
    $sources{$row->[0]} = $row->[1];
  }
  $sql = 'SELECT COUNT(gid) FROM exportdata WHERE src LIKE "HTS-%"';
  my $cnt = $self->SimpleSqlGet($sql);
  $sources{'One-off from Jira'} = $cnt if $cnt;
  my ($count2,$time2) = $self->GetLastExport(1);
  $time2 =~ s/\s/&nbsp;/g;
  $count = 'None' unless $count;
  my $exported = $self->SimpleSqlGet('SELECT COUNT(gid) FROM exportdata');
  $report .= "<tr><th>Last&nbsp;CRMS&nbsp;Export</th><td colspan='$colspan'>$time2</td></tr>";
  foreach my $status (sort keys %cts)
  {
    $report .= sprintf("<tr><th>&nbsp;&nbsp;&nbsp;&nbsp;Status&nbsp;%d</th><td>%d&nbsp;(%.1f%%)</td>",
                       $status, $cts{$status}, $pcts{$status});
    $sql = 'SELECT priority,COUNT(*) FROM exportdata WHERE status=?'.
           ' AND DATE(time)=DATE(?) GROUP BY priority ASC';
    my $ref = $self->SelectAll($sql, $status, $time);
    $report .= $self->DoPriorityBreakdown($ref, undef, \@pris, $cts{$status});
    $report .= '</tr>';
  }
  $report .= "<tr><th>&nbsp;&nbsp;&nbsp;&nbsp;Total</th><td>$count</td>";
  $sql = 'SELECT priority,COUNT(gid),CONCAT(FORMAT(IF(?=0,0,(COUNT(gid)*100.0)/?),1),"%")'.
         ' FROM exportdata where date(time)=DATE(?) GROUP BY priority ASC';
  my $ref = $self->SelectAll($sql, $total, $total, $time);
  $report .= sprintf('<td class="nowrap">%s (%s)</td>', $_->[1], $_->[2]) for @{$ref};
  $report .= '</tr>';
  $report .= "<tr><th class='nowrap'>Total CRMS Determinations</th><td colspan='$colspan'>$exported</td></tr>";
  foreach my $source (sort keys %sources)
  {
    my $n = $sources{$source};
    $report .= sprintf("<tr><th>&nbsp;&nbsp;&nbsp;&nbsp;%s</th><td colspan='$colspan'>$n</td></tr>", $self->ExportSrcToEnglish($source));
  }
  if ($self->Sys() ne 'crmsworld')
  {
    my $legacy = $self->GetTotalLegacyCount();
    $report .= "<tr><th>Total&nbsp;Legacy&nbsp;Determinations</th><td colspan='$colspan'>$legacy</td></tr>";
    $report .= sprintf("<tr><th>Total&nbsp;Determinations</th><td colspan='$colspan'>%s</td></tr>", $exported + $legacy);
  }
  $report .= "</table>\n";
  return $report;
}

sub CreateReviewReport
{
  my $self = shift;

  my $sql = 'SELECT DISTINCT priority FROM queue ORDER BY priority ASC';
  my @pris = map {$self->StripDecimal($_->[0])} @{$self->SelectAll($sql)};
  my $priheaders = join '', map {"<th>Priority&nbsp;$_</th>";} @pris;
  my $report = "<table class='exportStats'>\n<tr><th>Status</th><th>Total</th>$priheaders</tr>\n";

  $sql = 'SELECT priority,COUNT(id) FROM queue WHERE status>0'.
         ' OR pending_status>0 GROUP BY priority ASC';
  my $ref = $self->SelectAll($sql);
  my $count = (scalar @{$ref})? $ref->[-1]->[1]:0;
  $report .= "<tr><td class='total'>Active</td><td class='total'>$count</td>";
  $report .= $self->DoPriorityBreakdown($ref, ' class="total"', \@pris) . "</tr>\n";

  # Unprocessed
  $sql = 'SELECT priority,COUNT(*) FROM queue WHERE status=0 AND pending_status>0 GROUP BY priority WITH ROLLUP';
  $ref = $self->SelectAll($sql);
  $count = (scalar @{$ref})? $ref->[-1]->[1]:0;
  $report .= "<tr><td class='minor'>Unprocessed</td><td class='minor'>$count</td>";
  $report .= $self->DoPriorityBreakdown($ref, ' class="minor"', \@pris) . "</tr>\n";

  # Unprocessed categories
  my @unprocessed = ({'status'=>1,'name'=>'Single Review'},
                     {'status'=>2,'name'=>'Conflict'},
                     {'status'=>3,'name'=>'Provisional Match'},
                     {'status'=>4,'name'=>'Match'},
                     {'status'=>8,'name'=>'Auto-Resolved'});
  foreach my $row (@unprocessed)
  {
    $sql = 'SELECT priority,COUNT(*) from queue WHERE status=0 AND pending_status=? GROUP BY priority WITH ROLLUP';
    $ref = $self->SelectAll($sql, $row->{'status'});
    $count = (scalar @{$ref})? $ref->[-1]->[1]:0;
    $report .= sprintf "<tr><td>&nbsp;&nbsp;&nbsp;%s</td><td>$count</td>", $row->{'name'};
    $report .= $self->DoPriorityBreakdown($ref, '', \@pris) . "</tr>\n";
  }

  # Inheriting
  $sql = 'SELECT COUNT(*) FROM inherit';
  $count = $self->SimpleSqlGet($sql);
  $report .= sprintf("<tr class='inherit'><td>Can&nbsp;Inherit</td><td colspan='%d'>$count</td>", 1+scalar @pris);
  $report .= '</tr>';

  # Inheriting Automatically
  $sql = 'SELECT COUNT(*) FROM inherit i INNER JOIN exportdata e ON i.gid=e.gid'.
         ' WHERE i.status IS NULL AND (i.reason=1 OR (i.reason=12 AND (e.attr="pd" OR e.attr="pdus")))';
  $count = $self->SimpleSqlGet($sql);
  $report .= sprintf("<tr><td>&nbsp;&nbsp;&nbsp;Automatically</td><td colspan='%d'>$count</td>", 1+scalar @pris);
  $report .= '</tr>';

  # Inheriting Pending Approval
  $sql = 'SELECT COUNT(*) FROM inherit i INNER JOIN exportdata e ON i.gid=e.gid'.
         ' WHERE i.status IS NULL AND (i.reason!=1 AND !(i.reason=12 AND (e.attr="pd" OR e.attr="pdus")))';
  $count = $self->SimpleSqlGet($sql);
  $report .= sprintf("<tr><td>&nbsp;&nbsp;&nbsp;Pending&nbsp;Approval</td><td colspan='%d'>$count</td>", 1+scalar @pris);
  $report .= '</tr>';

  # Approved
  $sql = 'SELECT COUNT(*) FROM inherit WHERE status=1';
  $count = $self->SimpleSqlGet($sql);
  $report .= sprintf("<tr><td>&nbsp;&nbsp;&nbsp;Approved</td><td colspan='%d'>$count</td>", 1+scalar @pris);
  $report .= '</tr>';

  # Deleted
  $sql = 'SELECT COUNT(*) FROM inherit WHERE status=0';
  $count = $self->SimpleSqlGet($sql);
  $report .= sprintf("<tr><td>&nbsp;&nbsp;&nbsp;Deleted</td><td colspan='%d'>$count</td>", 1+scalar @pris);
  $report .= '</tr>';

  # Processed
  my @processed = ({'status'=>2,'name'=>'Conflict'},
                   {'status'=>3,'name'=>'Provisional Match'},
                   #{'status'=>4,'name'=>'Match'}
                   );
  $sql = 'SELECT priority,COUNT(*) FROM queue WHERE status!=0 GROUP BY priority WITH ROLLUP';
  $ref = $self->SelectAll($sql);
  $count = (scalar @{$ref})? $ref->[-1]->[1]:0;
  $report .= "<tr><td class='minor'>Processed</td><td class='minor'>$count</td>";
  $report .= $self->DoPriorityBreakdown($ref, ' class="minor"', \@pris) . "</tr>\n";

  foreach my $row (@processed)
  {
    $sql = 'SELECT priority,COUNT(*) from queue WHERE status=? GROUP BY priority WITH ROLLUP';
    $ref = $self->SelectAll($sql, $row->{'status'});
    $count = (scalar @{$ref})? $ref->[-1]->[1]:0;
    $report .= sprintf "<tr><td>&nbsp;&nbsp;&nbsp;%s</td><td>$count</td>", $row->{'name'};
    $report .= $self->DoPriorityBreakdown($ref, '', \@pris) . "</tr>\n";
  }
  
  $report .= sprintf("<tr><td class='nowrap' colspan='%d'>
                      <span class='smallishText'>Last processed %s</span>
                      </td></tr>\n", 2+scalar @pris, $self->GetLastStatusProcessedTime());
  $report .= "</table>\n";
  return $report;
}

# Takes a SelectAll ref in which each row is priority, count
sub DoPriorityBreakdown
{
  my $self  = shift;
  my $ref   = shift;
  my $class = shift || '';
  my $pris  = shift;
  my $total = shift;

  my %breakdown;
  $breakdown{$_} = 0 for @{$pris};
  foreach my $row (@{$ref})
  {
    my $pri = $row->[0];
    next unless defined $pri;
    $pri = $self->StripDecimal($pri);
    $breakdown{$pri} = $row->[1];
  }
  my $bd = '';
  foreach my $key (sort {$a <=> $b} keys %breakdown)
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
  return $bd;
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

  my $sql = 'SELECT SUM(itemcount) FROM exportrecord';
  return $self->SimpleSqlGet($sql);
}

sub GetLastExport
{
  my $self     = shift;
  my $readable = shift;

  my $sql = 'SELECT itemcount,time FROM exportrecord WHERE itemcount>0 ORDER BY time DESC LIMIT 1';
  my $ref = $self->SelectAll($sql);
  my $count = $ref->[0]->[0];
  my $time = $ref->[0]->[1];
  $time = $self->FormatTime($time) if $readable;
  return ($count,$time);
}

sub GetTotalLegacyCount
{
  my $self = shift;

  my $sql = 'SELECT COUNT(DISTINCT id) FROM historicalreviews WHERE legacy=1 AND priority!=1';
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

  my $sql = 'SELECT time,itemcount FROM queuerecord WHERE source="candidates"'.
            ' AND itemcount>0 ORDER BY time DESC LIMIT 1';
  my $row = $self->SelectAll($sql)->[0];
  my $time = $self->FormatTime($row->[0]) || 'Never';
  my $cnt = $row->[1] || 0;
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
    print CGI::header(-type => 'text/plain', -charset => 'utf-8');
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

sub CountHistoricalReviews
{
  my $self = shift;
  my $id   = shift;

  my $sql = 'SELECT COUNT(*) FROM historicalreviews WHERE id=?';
  return $self->SimpleSqlGet($sql, $id);
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
  $sql = 'SELECT r.attr,r.reason,r.renNum,r.renDate,u.expert,e.status,r.time,r.category,r.gid FROM historicalreviews r'.
         ' INNER JOIN exportdata e ON r.gid=e.gid'.
         ' INNER JOIN users u ON r.user=u.id'.
         " WHERE r.id=? AND r.user=? AND r.time LIKE '$time%'";
  my $r = $self->SelectAll($sql, $id, $user);
  my $row = $r->[0];
  my $attr    = $row->[0];
  my $reason  = $row->[1];
  my $renNum  = $row->[2];
  my $renDate = $row->[3];
  my $expert  = $row->[4];
  my $status  = $row->[5];
  my $time2   = $row->[6];
  my $cat     = $row->[7];
  my $gid     = $row->[8];
  #print "$attr, $reason, $renNum, $renDate, $expert, $swiss, $status\n";
  # A non-expert with status 6/7/8 is protected rather like Swiss.
  return 1 if ($status >=6 && $status <= 8 && !$expert);
  # If there is a newer newyear determination, that also offers blanket protection.
  $sql = 'SELECT COUNT(id) FROM exportdata WHERE id=? AND src="newyear" AND time>?';
  my $newyear = $self->SimpleSqlGet($sql, $id, $time);
  return 1 if $newyear;
  # Get the most recent non-autocrms expert review.
  $sql = 'SELECT attr,reason,renNum,renDate,user,swiss,gid FROM historicalreviews' .
         ' WHERE id=? AND expert>0 AND time>? ORDER BY time DESC';
  $r = $self->SelectAll($sql, $id, $time2);
  return 1 unless scalar @{$r};
  $row = $r->[0];
  my $eattr    = $row->[0];
  my $ereason  = $row->[1];
  my $erenNum  = $row->[2];
  my $erenDate = $row->[3];
  my $euser    = $row->[4];
  my $eswiss   = $row->[5];
  my $egid     = $row->[6];
  # Missing/Wrong record category, if present, offers protection from re-reviews (different gid)
  return 1 if $gid ne $egid and ($cat eq 'Missing' or $cat eq 'Wrong Record');
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
  my $r = $self->SelectAll($sql, $id);
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
  my $ref = $self->SelectAll($sql, $user, $start, $end);
  foreach my $row (@{$ref})
  {
    my $val = $row->[0];
    my $cnt = $row->[1];
    $incorrect = $cnt if $val == 0;
    $correct = $cnt if $val == 1;
    $neutral = $cnt if $val == 2;
  }
  $sql = 'SELECT COUNT(*) FROM historicalreviews'.
         ' WHERE legacy!=1 AND user=? AND time>=? AND time<=? AND flagged IS NOT NULL';
  my $flagged = $self->SimpleSqlGet($sql, $user, $start, $end);
  return ($correct, $incorrect, $neutral, $flagged);
}

# Gets only those reviewers that are not experts
sub GetType1Reviewers
{
  my $self = shift;

  my $sql = 'SELECT id FROM users WHERE id NOT LIKE "rereport%" AND expert=0';
  return map {$_->[0]} @{ $self->SelectAll($sql) };
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
  my $ref = $self->SelectAll($sql, $start, $end);
  my $row = $ref->[0];
  return @{ $row };
}

sub ShouldReviewBeFlagged
{
  my $self = shift;
  my $user = shift;
  my $gid  = shift;

  my ($pd, $icren, $date, $wr);
  my $sql = 'SELECT r.user,a.name,rs.name,r.category,r.validated FROM historicalreviews r'.
            ' INNER JOIN exportdata e ON r.gid=e.gid'.
            ' INNER JOIN attributes a ON r.attr=a.id'.
            ' INNER JOIN reasons rs ON r.reason=rs.id'.
            ' WHERE r.gid=? ORDER BY IF(r.user=?,1,0) DESC';
  my $ref = $self->SelectAll($sql, $gid, $user);
  foreach my $row (@{$ref})
  {
    my ($user2, $attr, $reason, $category, $val) = @{$row};
    if ($user2 eq $user)
    {
      return if $val == 1;
      $pd = 1 if $attr =~ m/^pd/;
    }
    else
    {
      $icren = 1 if $attr eq 'ic' and $reason eq 'ren';
      $date = 1 if $attr eq 'und' and $reason eq 'nfi' and $category eq 'Date';
      $wr = 1 if $attr eq 'und' and $reason eq 'nfi' and $category eq 'Wrong Record';
    }
  }
  return if !$pd;
  return 1 if $icren;
  return 2 if $date;
  return 3 if $wr;
}

sub ReviewSearchMenu
{
  my $self       = shift;
  my $page       = shift;
  my $searchName = shift;
  my $searchVal  = shift;

  my @keys = ('Identifier','SysID',    'Title','Author','PubDate', 'Date', 'Status','Legacy','UserId','Attribute',
              'Reason', 'NoteCategory', 'Note', 'Priority', 'Validated', 'Swiss', 'Project');
  my @labs = ('Identifier','System ID','Title','Author','Pub Date','Review Date', 'Status','Legacy','User',  'Attribute',
              'Reason','Note Category', 'Note', 'Priority', 'Verdict',   'Swiss', 'Project');
  if (!$self->IsUserAtLeastExpert())
  {
    splice @keys, 15, 1; # Swiss
    splice @labs, 15, 1;
  }
  if ($page ne 'adminHistoricalReviews')
  {
    splice @keys, 14, 1;
    splice @labs, 14, 1; # Validated
  }
  if (!$self->IsUserAtLeastExpert())
  {
    splice @keys, 13, 1; # Priority
    splice @labs, 13, 1;
  }
  if ($page ne 'adminHistoricalReviews' || $self->TolerantCompare(1,$self->GetSystemVar('noLegacy')))
  {
    splice @keys, 7, 1; # Legacy
    splice @labs, 7, 1;
  }
  if ($page ne 'adminHistoricalReviews')
  {
    splice @keys, 4, 1; # Pub Date
    splice @labs, 4, 1;
  }
  if ($page ne 'adminHistoricalReviews' || !$self->IsUserAtLeastExpert())
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
  my $self       = shift;
  my $searchName = shift;
  my $searchVal  = shift;

  my @keys = qw(Identifier Title Author PubDate Date Status Locked Priority Reviews
                ExpertCount Holds Source AddedBy Project Ticket);
  my @labs = ('Identifier', 'Title', 'Author', 'Pub Date', 'Date Added', 'Status', 'Locked',
              'Priority', 'Reviews', 'Expert Reviews', 'Holds', 'Source',
              'Added By', 'Project', 'Ticket');
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
  my $self       = shift;
  my $searchName = shift;
  my $searchVal  = shift;

  my @keys = qw(Identifier Title Author PubDate Date Attribute Reason
                Status Priority Source AddedBy Project Ticket GID Exported);
  my @labs = ('Identifier', 'Title', 'Author', 'Pub Date', 'Date', 'Attribute', 'Reason',
              'Status', 'Priority', 'Source', 'Added By', 'Project', 'Ticket', 'GID', 'Exported');
  my $html = "<select title='Search Field' name='$searchName' id='$searchName'>\n";
  foreach my $i (0 .. scalar @keys - 1)
  {
    $html .= sprintf("  <option value='%s'%s>%s</option>\n", $keys[$i],
                     ($searchVal eq $keys[$i])? ' selected="selected"':'', $labs[$i]);
  }
  $html .= "</select>\n";
  return $html;
}

# This is used for the HTML page title.
sub PageToEnglish
{
  my $self = shift;
  my $page = shift;

  return 'Home' unless $page;
  my $eng = $self->SimpleSqlGet('SELECT name FROM menuitems WHERE page=?', $page);
  $eng =~ s/__INST__/Institutional/;
  return $eng;
}

sub Namespaces
{
  my $self = shift;

  my $sql = 'SELECT distinct namespace FROM rights_current';
  my $ref = undef;
  eval { $ref = $self->SelectAllSDR($sql); };
  $self->SetError("Rights query for namespaces failed: $@") if $@;
  return map {$_->[0];} @{$ref};
}

# Query the production rights database. This returns an array ref of entries for the volume, oldest first.
# Returns: aref of aref of ($attr,$reason,$src,$usr,$time,$note,$access_profile)
# of undef if not found.
sub RightsQuery
{
  my $self   = shift;
  my $id     = shift;
  my $latest = shift;

  my ($ns,$n) = split m/\./, $id, 2;
  my $table = ($latest)? 'rights_current':'rights_log';
  my $sql = 'SELECT a.name,rs.name,s.name,r.user,r.time,COALESCE(r.note,""),p.name FROM ' .
            $table . ' r, attributes a, reasons rs, sources s, access_profiles p' .
            ' WHERE r.namespace=? AND r.id=? AND s.id=r.source AND a.id=r.attr' .
            ' AND rs.id=r.reason AND p.id=r.access_profile' .
            ' ORDER BY r.time ASC';
  my $ref;
  eval { $ref = $self->SelectAllSDR($sql, $ns, $n); };
  if ($@)
  {
    $self->SetError("Rights query for $id failed: $@");
    return undef;
  }
  $ref = undef if defined $ref && scalar @{$ref} == 0;
  return $ref;
}

# For completed one-offs in Add to Queue page.
# Shows current rights and, if available, the rights being transitioned to.
sub CurrentRightsQuery
{
  my $self = shift;
  my $id   = shift;

  my $rights = '(unavailable)';
  my $ref = $self->RightsQuery($id, 1);
  return $rights unless defined $ref;
  $rights = $ref->[0]->[0] . '/' . $ref->[0]->[1];
  my ($a, $r) = $self->GetFinalAttrReason($id);
  if (defined $a && defined $r && ($a ne $ref->[0]->[0] || $r ne $ref->[0]->[1]))
  {
    $rights .= ' ' . "\N{U+2192}" . " $a/$r";
  }
  return $rights;
}

# Returns human readable a/r string.
sub GetCurrentRights
{
  my $self = shift;
  my $id   = shift;

  my $rights = '(unavailable)';
  my $ref = $self->RightsQuery($id, 1);
  return $rights unless defined $ref;
  $rights = $ref->[0]->[0] . '/' . $ref->[0]->[1];
  return $rights;
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

sub GetUserIPs
{
  my $self = shift;
  my $user = shift || $self->get('remote_user');

  my $sql = 'SELECT iprestrict FROM ht_users WHERE userid=?';
  my $sdr_dbh = $self->get('ht_repository');
  if (!defined $sdr_dbh)
  {
    $sdr_dbh = $self->ConnectToSdrDb('ht_repository');
    $self->set('ht_repository', $sdr_dbh) if defined $sdr_dbh;
  }
  my $ipr;
  eval {
    my $ref = $sdr_dbh->selectall_arrayref($sql, undef, $user);
    $ipr = $ref->[0]->[0];
  };
  if ($@)
  {
    my $msg = "SQL failed ($sql): " . $@;
    $self->SetError($msg);
  }
  my %ips;
  if (defined $ipr)
  {
    $ipr =~ s/\s//g;
    my @ips2 = split m/\|/, $ipr;
    foreach my $ip (@ips2)
    {
      $ip =~ s/^\^|\$$//g;
      $ip =~ s/\\\././g;
      $ips{$ip} = 1 if $ip =~ m/(\d+\.){3}\d+/;
    }
  }
  $self->ClearErrors();
  return \%ips;
}

sub GetUserRole
{
  my $self = shift;
  my $user = shift || $self->get('user');

  my $sql = 'SELECT role FROM ht_users WHERE userid=?';
  my $sdr_dbh = $self->get('ht_repository');
  if (!defined $sdr_dbh)
  {
    $sdr_dbh = $self->ConnectToSdrDb('ht_repository');
    $self->set('ht_repository', $sdr_dbh) if defined $sdr_dbh;
  }
  my $role;
  eval {
    my $ref = $sdr_dbh->selectall_arrayref($sql, undef, $user);
    $role = $ref->[0]->[0];
  };
  if ($@)
  {
    my $msg = "SQL failed ($sql): " . $@;
    $self->SetError($msg);
  }
  return $role;
}

# Returns a hash ref with 'expires' => expiration date from database, status => {0,1,2}
# where 0 is unexpired, 1 is expired, 2 is expiring soon.
sub IsUserExpired
{
  my $self = shift;
  my $user = shift || $self->get('user');

  my %data;
  my $sql = 'SELECT DATE(expires),IF(expires<NOW(),1,'.
            'IF(DATE_SUB(expires,INTERVAL 10 DAY)<NOW(),2,0))'.
            ' FROM ht_users WHERE userid=?';
  #print "$sql<br/>\n";
  my $sdr_dbh = $self->get('ht_repository');
  if (!defined $sdr_dbh)
  {
    $sdr_dbh = $self->ConnectToSdrDb('ht_repository');
    $self->set('ht_repository', $sdr_dbh) if defined $sdr_dbh;
  }
  eval {
    my $ref = $sdr_dbh->selectall_arrayref($sql, undef, $user);
    $data{'expires'} = $ref->[0]->[0];
    $data{'status'} = $ref->[0]->[1];
  };
  if ($@)
  {
    my $msg = "SQL failed ($sql): " . $@;
    $self->SetError($msg);
  }
  return \%data;
}

sub VolumeIDsQuery
{
  my $self   = shift;
  my $sysid  = shift;
  my $record = shift;

  $record = $self->GetMetadata($sysid) unless defined $record;
  return undef unless defined $record;
  return $record->volumeIDs
}

sub DownloadTracking
{
  my $self = shift;
  my $id   = shift;

  my $syss = $self->GetBothSystems();
  my $buff = (join "\t", ('ID', 'Enum/Chron', 'CRMS-US Status', 'CRMS-World Status',
                          'U.S. Rights', 'Attribute', 'Reason', 'Source', 'User',
                          'Time', 'Note', 'Access Profile')) . "\n";
  my $rows = $self->VolumeIDsQuery($id);
  foreach my $ref (@{$rows})
  {
    $buff .= (join "\t", (($ref->{'id'}, $ref->{'chron'},
                           $syss->[0]->GetTrackingInfo($id, 1, 1),
                           $syss->[1]->GetTrackingInfo($id, 1, 1),
                           $ref->{'rights'}),
                           @{$self->RightsQuery($ref->{'id'}, 1)->[0]})) . "\n";
  }
  $self->DownloadSpreadSheet($buff);
  return (1 == scalar @{$self->GetErrors()});
}

# All volumes in the query (q) are moved to the top of the results.
# The two groups are sorted by enumchron.
sub TrackingQuery
{
  my $self = shift;
  my $id   = shift;
  my $q    = shift;

  my %rest;
  $rest{$_} = 1 for @{$q};
  my $syss = $self->GetBothSystems();
  my %data = ('crms' => $syss->[0], 'crmsworld' => $syss->[1]);
  my @ids;
  my $rows;
  my $record = $self->GetMetadata($id);
  if (defined $record)
  {
    $data{'title'} = $record->title;
    $data{'sysid'} = $record->sysid;
    $rows = $self->VolumeIDsQuery($id, $record);
    foreach my $ref (sort {$a->{'chron'} cmp $b->{'chron'}} @{$rows})
    {
      my $id2 = $ref->{'id'};
      my $data2 = [$id2, $ref->{'chron'},
                   $syss->[0]->GetTrackingInfo($id2, 1, 1),
                   $syss->[1]->GetTrackingInfo($id2, 1, 1),
                   $ref->{'rights'},
                   @{$self->RightsQuery($id2, 1)->[0]}];
      if ($rest{$id2})
      {
        unshift @ids, $data2;
      }
      else
      {
        push @ids, $data2;
      }
    }
  }
  $data{'data'} = \@ids;
  return \%data;
}

# inherit, correction, and rights allow inclusion of information that is not
# redundant to the page.
sub GetTrackingInfo
{
  my $self       = shift;
  my $id         = shift;
  my $inherit    = shift;
  my $correction = shift;
  my $rights     = shift;

  my @stati = ();
  my $inQ = $self->IsVolumeInQueue($id);
  if ($inQ)
  {
    my $status = $self->GetStatus($id);
    my $n = $self->CountReviews($id);
    my $reviews = $self->Pluralize('review', $n);
    my $pri = $self->GetPriority($id);
    my $sql = 'SELECT p.name FROM queue q LEFT JOIN projects p'.
              ' ON p.newproject=p.id WHERE q.id=?';
    my $proj = $self->SimpleSqlGet($sql, $id);
    my $projinfo = (defined $proj)? ", project '$proj'":'';
    push @stati, "in Queue (P$pri, status $status, $n $reviews$projinfo)";
  }
  elsif ($self->SimpleSqlGet('SELECT COUNT(*) FROM cri WHERE id=? AND exported=0', $id))
  {
    my $stat = $self->SimpleSqlGet('SELECT status FROM cri WHERE id=?', $id);
    my %stats = (0 => 'rejected', 1 => 'submitted', 2 => 'UND');
    my $msg = 'unreviewed';
    $msg = $stats{$stat} if defined $stat;
    push @stati, "CRI-eligible ($msg)";
  }
  elsif ($self->SimpleSqlGet('SELECT COUNT(*) FROM candidates WHERE id=?', $id))
  {
    my $sql = 'SELECT p.name FROM candidates c'.
              ' INNER JOIN projects p ON c.newproject=p.id WHERE c.id=?';
    my $proj = $self->SimpleSqlGet($sql, $id);
    push @stati, "in Candidates ($proj project)";
  }
  my $src = $self->SimpleSqlGet('SELECT src FROM und WHERE id=?', $id);
  if (defined $src)
  {
    my %temps = ('no meta' => 1, 'duplicate' => 1, 'cross-record inheritance' => 1);
    push @stati, sprintf "%sfiltered ($src)", (defined $temps{$src})? 'temporarily ':'';
  }
  if ($self->SimpleSqlGet('SELECT COUNT(*) FROM exportdata WHERE id=?', $id))
  {
    my $sql = 'SELECT attr,reason,DATE(time),src,exported,status FROM exportdata WHERE id=? ORDER BY time DESC LIMIT 1';
    my $ref = $self->SelectAll($sql, $id);
    my $a = $ref->[0]->[0];
    my $r = $ref->[0]->[1];
    my $t = $ref->[0]->[2];
    my $src = $ref->[0]->[3];
    my $exp = $ref->[0]->[4];
    my $status = $ref->[0]->[5];
    $exp = ($exp)? '':' (unexported)';
    push @stati, "S$status$exp $a/$r $t from $src";
  }
  #else
  {
    my $n = $self->SimpleSqlGet('SELECT COUNT(*) FROM historicalreviews WHERE id=? AND legacy=1', $id);
    my $reviews = $self->Pluralize('review', $n);
    push @stati, "$n legacy $reviews" if $n;
  }
  if ($correction && $self->SimpleSqlGet('SELECT COUNT(*) FROM corrections WHERE id=?', $id))
  {
    my $sql = 'SELECT user,status,ticket,DATE(time) FROM corrections WHERE id=?';
    my $ref = $self->SelectAll($sql, $id);
    my $user = $ref->[0]->[0];
    my $status = $ref->[0]->[1];
    my $tx = $ref->[0]->[2];
    my $date = $ref->[0]->[3];
    my $s = (defined $user)? "correction by $user, status $status":'awaiting correction';
    $s .= " (Jira $tx)" if defined $tx;
    push @stati, $s
  }
  if ($inherit && $self->SimpleSqlGet('SELECT COUNT(*) FROM inherit WHERE id=? AND (status IS NULL OR status=1)', $id))
  {
    my $sql = 'SELECT e.id,e.attr,e.reason FROM exportdata e INNER JOIN inherit i ON e.gid=i.gid WHERE i.id=?';
    my $ref = $self->SelectAll($sql, $id);
    my $src = $ref->[0]->[0];
    my $a = $ref->[0]->[1];
    my $r = $ref->[0]->[2];
    push @stati, "inheriting $a/$r from $src";
  }
  if ($rights)
  {
    # See if it has a pre-CRMS determination.
    my $rq = $self->RightsQuery($id, 1);
    return 'Rights info unavailable' unless defined $rq;
    my ($attr,$reason,$src,$usr,$time,$note) = @{$rq->[0]};
    $time =~ s/(\d\d\d\d-\d\d-\d\d).*/$1/;
    push @stati, "Latest rights $attr/$reason ($usr $time)";
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
  my $r = $self->SelectAll($sql);
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
    # FiXME: is this redundant?
    if ($vals[2] ne '')
    {
      $vals[0] = $self->FormatTime($row->[0]) if $row->[0];
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
  my $sql = 'INSERT INTO systemstatus (status,message) VALUES (?,?)';
  $self->PrepareSubmitSql($sql, $status, $msg);
}

# Returns name of system, or undef for production
sub WhereAmI
{
  my $self = shift;

  my $where = undef;
  my $dev = $self->get('dev');
  if ($dev)
  {
    if ($dev eq '1') { $where = 'Dev'; }
    elsif ($dev eq 'crms-training') { $where = 'Training'; }
    else { $where = $dev. ' Dev'; }
  }
  return $where;
}

sub DevBanner
{
  my $self = shift;

  my $where = $self->WhereAmI();
  if (defined $where)
  {
    $where .= ' | Production DB' if $self->get('pdb');
    $where .= ' | Training DB' if $self->get('tdb');
  }
  return '[ '. $where. ' ]' if defined $where;
}

sub SelfURL
{
  my $self = shift;

  my $url = 'quod.lib.umich.edu';
  my $dev = $self->get('dev');
  if ($dev)
  {
    $url = $dev . '.' . $url if $dev eq 'crms-training' or $dev eq 'moseshll';
  }
  return 'https://' . $url;
}

sub IsTrainingArea
{
  my $self = shift;

  my $where = $self->WhereAmI();
  return (defined $where && $where =~ m/^training/i);
}

sub ResetButton
{
  my $self = shift;
  my $nuke = shift;

  return unless $self->IsTrainingArea();
  if ($nuke)
  {
    my $sql = 'SELECT id FROM queue WHERE status<4'.
              ' AND id IN (SELECT DISTINCT id FROM reviews)';
    my $ref = $self->SelectAll($sql);
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
  my $ref = $self->SelectAll($sql, $host);
  my @return = ($ref->[0]->[0],$self->FormatTime($ref->[0]->[1]));
  return @return;
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

sub InheritanceSearchMenu
{
  my $self = shift;
  my $searchName = shift;
  my $searchVal = shift;
  my $auto = shift;

  my @keys = ('date','idate','src','id','sysid','prior','prior5','title');
  my @labs = ('Export Date','Inherit Date','Source Volume','Inheriting Volume','System ID',
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
  $new_search = 'b.sysid' if $search eq 'sysid';
  $new_search = 'i.id' if $search eq 'id';
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
  my @rest = ();
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
  my $datesrc = ($dateType eq 'date')? 'DATE(e.time)':'DATE(i.time)';
  push @rest, "$datesrc >= '$startDate'" if $startDate;
  push @rest, "$datesrc <= '$endDate'" if $endDate;
  push @rest, "$search1 $tester1 '$search1Value'" if $search1Value or $search1Value eq '0';
  if ($auto)
  {
    push @rest, '(i.reason=1 OR (i.reason=12 AND (e.attr="pd" OR e.attr="pdus")))';
  }
  else
  {
    push @rest, '(i.reason!=1 AND !(i.reason=12 AND (e.attr="pd" OR e.attr="pdus")))';
  }
  my $restrict = 'WHERE '. join(' AND ', @rest);
  my $sql = 'SELECT COUNT(DISTINCT e.id),COUNT(DISTINCT i.id) FROM inherit i'.
            ' INNER JOIN exportdata e ON i.gid=e.gid'.
            ' LEFT JOIN bibdata b ON e.id=b.id '. $restrict;
  my $ref;
  #print "$sql<br/>\n";
  eval {
    $ref = $self->SelectAll($sql);
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
  $sql = 'SELECT i.id,i.attr,i.reason,i.gid,e.id,e.attr,e.reason,'.
         'b.title,DATE(e.time),i.src,DATE(i.time),b.sysid,i.status'.
         ' FROM inherit i INNER JOIN exportdata e ON i.gid=e.gid'.
         ' LEFT JOIN bibdata b ON e.id=b.id '. $restrict.
         " ORDER BY $order $dir, $order2 $dir2 LIMIT $offset, $pagesize";
  #print "$sql<br/>\n";
  $ref = undef;
  eval {
    $ref = $self->SelectAll($sql);
  };
  if ($@)
  {
    $self->SetError($@);
  }
  my $i = $offset;
  my @return = ();
  foreach my $row (@{$ref})
  {
    $i++;
    my $id = $row->[0];
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
    my $sysid = $row->[11];
    my $status = $row->[12];
    $title =~ s/&/&amp;/g;
    my $incrms = (($attr eq 'ic' && $reason eq 'bib') || $reason eq 'gfv')? undef:1;
    my $h5 = undef;
    if ($incrms)
    {
      my $sql = 'SELECT COUNT(*) FROM historicalreviews WHERE id=? AND status=5';
      $h5 = 1 if $self->SimpleSqlGet($sql, $id) > 0;
    }
    my $change = $self->AccessChange($attr, $attr2);
    my $summary = '';
    if ($self->IsVolumeInQueue($id))
    {
      $summary = sprintf "in queue (P%s)", $self->GetPriority($id);
      $sql = 'SELECT user FROM reviews WHERE id=?';
      my $ref2 = $self->SelectAll($sql, $id);
      my $users = join ', ', (map {$_->[0]} @{$ref2});
      $summary .= "; reviewed by $users" if $users;
      my $locked = $self->SimpleSqlGet('SELECT locked FROM queue WHERE id=?', $id);
      $summary .= "; locked for $locked" if $locked;
    }
    my %dic = ('i'=>$i, 'inheriting'=>$id, 'sysid'=>$sysid, 'rights'=>"$attr/$reason",
               'newrights'=>"$attr2/$reason2", 'incrms'=>$incrms, 'change'=>$change, 'from'=>$id2,
               'title'=>$title, 'gid'=>$gid, 'date'=>$date, 'summary'=>ucfirst $summary,
               'src'=>ucfirst $src, 'h5'=>$h5, 'idate'=>$idate, 'status'=>$status);
    push @return, \%dic;
  }
  return {'rows' => \@return,
          'source' => $totalVolumes,
          'inheriting' => $inheritingVolumes,
          'n' => $n,
          'of' => $of
         };
}

sub HasMissingOrWrongRecord
{
  my $self  = shift;
  my $id    = shift;
  my $sysid = shift;
  my $rows  = shift;

  $rows = $self->VolumeIDsQuery($sysid) unless $rows;
  foreach my $ref (@{$rows})
  {
    my $id2 = $ref->{'id'};
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

sub UpdateInheritanceRights
{
  my $self = shift;

  my $sql = 'SELECT id,attr,reason FROM inherit';
  my $ref = $self->SelectAll($sql);
  foreach my $row (@{$ref})
  {
    my $id = $row->[0];
    my $a = $row->[1];
    my $r = $row->[2];
    my $rq = $self->RightsQuery($id, 1);
    next unless defined $rq;
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

# NULL = no activity, 0 = deleted, 1 = approved
sub GetInheritanceStatus
{
  my $self = shift;
  my $id   = shift;

  return $self->SimpleSqlGet('SELECT status FROM inherit WHERE id=?', $id);
}

sub SetInheritanceStatus
{
  my $self   = shift;
  my $id     = shift;
  my $status = shift;

  $self->PrepareSubmitSql('UPDATE inherit SET status=? WHERE id=?', $status, $id);  
}

sub DeleteInheritances
{
  my $self  = shift;
  my $quiet = shift;

  my $sql = 'SELECT id FROM inherit WHERE status=0';
  my $ref = $self->SelectAll($sql);
  foreach my $row (@{$ref})
  {
    my $id = $row->[0];
    print "Deleting inheritance for $id\n" unless $quiet;
    $self->PrepareSubmitSql('DELETE FROM inherit WHERE id=?', $id);
    # Only unfilter if the und src is 'duplicate' because duplicate filtration
    # does not override other sources like gfv
    if ($self->IsFiltered($id, 'duplicate'))
    {
      print "Unfiltering $id\n" unless $quiet;
      $self->Unfilter($id);
    }
  }
}

sub SubmitInheritances
{
  my $self  = shift;
  my $quiet = shift;

  my $sql = 'SELECT id,gid,status FROM inherit WHERE (status IS NULL OR status=1)';
  my $ref = $self->SelectAll($sql);
  printf "Submitting %d inheritances\n", scalar @{$ref} unless $quiet;
  foreach my $row (@{$ref})
  {
    my $id = $row->[0];
    my $gid = $row->[1];
    my $status = $row->[2];
    if ((defined $status && $status == 1) || $self->CanAutoSubmitInheritance($id, $gid))
    {
      print "Submitting inheritance for $id\n" unless $quiet;
      $self->SubmitInheritance($id);
    }
  }
}

# Given inheriting id and source gid,
# can the inheritance take place automatically?
# It can only happen in the following circumstances:
# The current rights are available and are */bib or */gfv,
#    where in the case of gfv inherited rights are pd or pdus.
sub CanAutoSubmitInheritance
{
  my $self = shift;
  my $id   = shift;
  my $gid  = shift;

  my $rq = $self->RightsQuery($id, 1);
  return 0 unless defined $rq;
  my ($attr,$reason,$src,$usr,$time,$note) = @{$rq->[0]};
  return 1 if $reason eq 'bib';
  my $attr = $self->SimpleSqlGet('SELECT attr FROM exportdata WHERE gid=?', $gid);
  return 1 if $attr =~ m/^pd/ and $reason eq 'gfv';
  return 0;
}

# Returns whether attr/* changing to attr2/* will result
# in a change of access in U.S. or outside U.S.
sub AccessChange
{
  my $self  = shift;
  my $attr  = shift;
  my $attr2 = shift;

  my ($pd,$pdus,$icund,$icus) = (0,0,0,0);
  $pd = 1 if $attr eq 'pd' or $attr2 eq 'pd';
  $pdus = 1 if $attr eq 'pdus' or $attr2 eq 'pdus';
  $icund = 1 if $attr eq 'ic' or $attr2 eq 'ic' or $attr eq 'und' or $attr2 eq 'und';
  $icus = 1 if $attr eq 'icus' or $attr2 eq 'icus';
  return ($pd + $pdus + $icund + $icus > 1)? 1:0;
}

sub SubmitInheritance
{
  my $self = shift;
  my $id   = shift;

  my $sql = 'SELECT COUNT(*) FROM reviews r INNER JOIN queue q ON r.id=q.id WHERE r.id=? AND r.user="autocrms" AND q.status=9';
  return 'skip' if $self->SimpleSqlGet($sql, $id);
  $sql = 'SELECT a.id,rs.id,i.gid FROM inherit i'.
         ' INNER JOIN exportdata e ON i.gid=e.gid'.
         ' INNER JOIN attributes a ON e.attr=a.id'.
         ' INNER JOIN reasons rs ON e.reason=rs.id'.
         ' WHERE i.id=?';
  my $row = $self->SelectAll($sql, $id)->[0];
  return "$id is no longer available for inheritance (has it been processed?)" unless $row;
  my $attr = $row->[0];
  my $reason = $row->[1];
  my $gid = $row->[2];
  my $category = 'Rights Inherited';
  # Returns a status code (0=Add, 1=Error) followed by optional text.
  my $res = $self->AddInheritanceToQueue($id, $gid);
  my $code = substr $res, 0, 1;
  if ($code ne '0')
  {
    return $id . ': ' . substr $res, 1, length $res;
  }
  $self->PrepareSubmitSql('DELETE FROM reviews WHERE id=?', $id);
  # FIXME: can this note be generated on the fly in Historical Reviews?
  my $note = 'See all reviews for Sys #'. $self->BarcodeToId($id);
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
  my $gid  = shift;

  my $stat = 0;
  my @msgs = ();
  my $sql = 'SELECT newproject FROM exportdata WHERE gid=?';
  my $proj = $self->SimpleSqlGet($sql, $gid);
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
        $self->PrepareSubmitSql('UPDATE queue SET source="inherited",newproject=? WHERE id=?', $id, $proj);
      }
    }
    $self->UnlockItem($id, 'autocrms');
  }
  else
  {
    my $sql = 'INSERT INTO queue (id,priority,source,newproject) VALUES (?,0,"inherited",?)';
    $self->PrepareSubmitSql($sql, $id, $proj);
    $self->UpdateMetadata($id, 1);
    $self->UpdateQueueRecord(1, 'inheritance');
  }
  return $stat . join '; ', @msgs;
}

sub LinkToCatalog
{
  my $self  = shift;
  my $sysid = shift;

  return 'http://catalog.hathitrust.org/Record/'. $sysid;
}

sub LinkToHistorical
{
  my $self  = shift;
  my $sysid = shift;
  my $full  = shift;

  my $url = $self->Sysify('/cgi/c/crms/crms?p=adminHistoricalReviews;search1=SysID;search1value='. $sysid);
  $url = $self->SelfURL() . $url if $full;
  return $url;
}

sub LinkToDeterminations
{
  my $self = shift;
  my $gid  = shift;
  my $full = shift;

  my $url = $self->Sysify('/cgi/c/crms/crms?p=exportData;search1=GID;search1value='. $gid);
  $url = $self->SelfURL() . $url if $full;
  return $url;
}

sub LinkToRetrieve
{
  my $self  = shift;
  my $sysid = shift;
  my $full  = shift;

  my $url = $self->Sysify('/cgi/c/crms/crms?p=track;query='. $sysid);
  $url = $self->SelfURL() . $url if $full;
  return $url;
}

sub LinkToMirlynDetails
{
  my $self = shift;
  my $id   = shift;

  my $url = 'http://mirlyn.lib.umich.edu/Record/';
  $url .= 'HTID/' if $id =~ m/\./;
  $url .= $id;
  $url .= '/Details#tabs' unless $id =~ m/\./;
  return $url;
}

sub LinkToJira
{
  my $self = shift;
  my $tx   = shift;

  use Jira;
  return Jira::LinkToJira($tx);
}

# Populates $data (a hash ref) with information about the duplication status of an exported determination.
sub DuplicateVolumesFromExport
{
  my $self      = shift;
  my $id        = shift;
  my $gid       = shift;
  my $sysid     = shift;
  my $attr      = shift;
  my $reason    = shift;
  my $data      = shift;
  my $record    = shift;
  my $candidate = shift; # id of candidate to inherit onto

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
  $data->{'titles'}->{$id} = $record->title;
  # Get most recent CRMS determination for any volume on this record
  # and see if it's more recent that what we're exporting.
  my $latest = $id;
  my $latestTime = $self->SimpleSqlGet('SELECT time FROM exportdata WHERE gid=?', $gid);
  if (!defined $candidate)
  {
    foreach my $ref (@{$rows})
    {
      my $id2 = $ref->{'id'};
      my $time = $self->SimpleSqlGet('SELECT MAX(time) FROM exportdata WHERE id=? AND src!="inherited"', $id2);
      if ($time && $time gt $latestTime)
      {
        $latest = $id2;
        $latestTime = $time;
      }
    }
  }
  my $wrong = $self->HasMissingOrWrongRecord($id, $sysid, $rows);
  foreach my $ref (@{$rows})
  {
    my $id2 = $ref->{'id'};
    next if $id eq $id2;
    next if defined $candidate && $candidate ne $id2;
    my $rq = $self->RightsQuery($id2, 1);
    next unless defined $rq;
    my ($attr2,$reason2,$src2,$usr2,$time2,$note2) = @{$rq->[0]};
    # In case we have a more recent export that has not made it into the rights DB...
    if ($self->SimpleSqlGet('SELECT COUNT(*) FROM exportdata WHERE id=? AND exported=1 AND time>?', $id2, $time2))
    {
      my $sql = 'SELECT attr,reason FROM exportdata WHERE id=? AND exported=1 ORDER BY time DESC LIMIT 1';
      ($attr2,$reason2) = @{$self->SelectAll($sql, $id2)->[0]};
    }
    my $newrights = "$attr/$reason";
    my $oldrights = "$attr2/$reason2";
    if ($newrights eq 'pd/ncn')
    {
      $data->{'disallowed'}->{$id} .= "$id2\t$sysid\t$oldrights\t$newrights\t$id\tCan't inherit from pd/ncn\n";
    }
    elsif ($attr2 eq $attr && $reason2 ne 'bib' && $reason2 ne 'gfv')
    {
      $data->{'unneeded'}->{$id} .= "$id2\t$sysid\t$oldrights\t$newrights\t$id\n";
    }
    elsif ($newrights eq 'und/crms' && $usr2 =~ m/^crms/)
    {
      $data->{'disallowed'}->{$id} .= "$id2\t$sysid\t$oldrights\t$newrights\t$id\tCan't inherit from und/crms\n";
    }
    elsif ($okattr{$oldrights} ||
           ($oldrights eq 'pdus/gfv' && $attr =~ m/^pd/) ||
           $oldrights eq 'ic/bib' || $oldrights eq 'und/bib' ||
           ($self->Sys() eq 'crmsworld' && $oldrights =~ m/^pdus/))
    {
      if (!$record->doEnumchronMatch($id, $id2))
      {
        $data->{'chron'}->{$id} = sprintf "$id2\t$sysid\t%s\t%s\n", $record->enumchron($id), $record->enumchron($id2);
      }
      elsif ($wrong)
      {
        $data->{'disallowed'}->{$id} .= "$id2\t$sysid\t$oldrights\t$newrights\t$id\tMissing/Wrong Record on $wrong\n";
        delete $data->{'unneeded'}->{$id};
        delete $data->{'inherit'}->{$id};
      }
      elsif ($self->SimpleSqlGet('SELECT COUNT(*) FROM exportdata WHERE id=? AND src LIKE "HTS%"', $id)>0)
      {
        $data->{'disallowed'}->{$id} .= "$id2\t$sysid\t$oldrights\t$newrights\t$id\tWas One-Off Review\n";
        delete $data->{'unneeded'}->{$id};
        delete $data->{'inherit'}->{$id};
      }
      elsif ($latest ne $id)
      {
        $data->{'disallowed'}->{$id} = "$id2\t$sysid\t$oldrights\t$newrights\t$id\t$latest has newer determination ($latestTime)\n";
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
        $data->{'inherit'}->{$id} .= sprintf "$id2\t$sysid\t$attr2\t$reason2\t$attr\t$reason\t$gid\t%s\t%s\n",
                                             $record->enumchron($id), $record->enumchron($id2);
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

  my $sql = 'SELECT CONCAT(a.name,"/",rs.name) FROM rights r'.
            ' INNER JOIN attributes a ON r.attr=a.id'.
            ' INNER JOIN reasons rs ON r.reason=rs.id';
  my $ref = $self->SelectAll($sql);
  my %okattr;
  $okattr{$_->[0]} = 1 for @{$ref};
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
  $data->{'titles'}->{$id} = $record->title;
  my $n = 0;
  foreach my $ref (@{$rows})
  {
    my $id2 = $ref->{'id'};
    next if $id eq $id2;
    my $sql = 'SELECT attr,reason,gid FROM exportdata WHERE id=? AND src!="inherited"'.
              ' AND time>="2010-06-02 00:00:00"'.
              ' ORDER BY IF(status=5,1,0) DESC,time DESC LIMIT 1';
    my $ref = $self->SelectAll($sql, $id2);
    next unless scalar @{$ref};
    $n++;
    my $attr = $ref->[0]->[0];
    my $reason = $ref->[0]->[1];
    my $gid2 = $ref->[0]->[2];
    $self->DuplicateVolumesFromExport($id2, $gid2, $sysid, $attr, $reason, $data, $record, $id);
  }
  $data->{'noexport'}->{$id} .= "$sysid\n" unless $n > 0;
}

sub ExportSrcToEnglish
{
  my $self = shift;
  my $src  = shift;

  my %srces = ('adminui'  => 'Added to Queue',
               'rereport' => 'Rereports',
               'newyear'  => 'Expired ADD',
               'cri'      => 'Cross-record Inheritance');
  my $eng = $srces{$src};
  $eng = ucfirst $src unless defined $eng;
  return $eng;
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
  my $user = shift || $self->get('user');

  my $q = $self->GetUserQualifications($user);
  my $sql = 'SELECT id,name,class,restricted FROM menus ORDER BY n';
  my $ref = $self->SelectAll($sql);
  my @all = ();
  foreach my $row (@{$ref})
  {
    my $r = $row->[3];
    if ($self->DoQualificationsAndRestrictionsOverlap($q, $r))
    {
      push @all, $row;
    }
  }
  return \@all;
}

# Returns aref of arefs to name, url, and target
sub MenuItems
{
  my $self = shift;
  my $menu = shift;
  my $user = shift || $self->get('user');

  $menu = $self->SimpleSqlGet('SELECT id FROM menus WHERE docs=1 LIMIT 1') if $menu eq 'docs';
  my $q = $self->GetUserQualifications($user);
  my $inst = $self->GetUserProperty($user, 'institution');
  my $iname = $self->GetInstitutionName($inst, 1);
  my $sql = 'SELECT name,href,restricted,target FROM menuitems WHERE menu=? ORDER BY n ASC';
  my $ref = $self->SelectAll($sql, $menu);
  my @all = ();
  foreach my $row (@{$ref})
  {
    my $r = $row->[2];
    if ($self->DoQualificationsAndRestrictionsOverlap($q, $r))
    {
      my $name = $row->[0];
      $name =~ s/__INST__/$iname/;
      push @all, [$name, $row->[1], $row->[3]];
    }
  }
  return \@all;
}

sub GetUserQualifications
{
  my $self = shift;
  my $user = shift || $self->get('user');

  my $sql = 'SELECT CONCAT('.
            ' IF(reviewer=1 OR advanced=1,"r",""),'.
            ' IF(expert=1,"e",""),'.
            ' IF(admin=1,"a",""),'.
            ' IF(superadmin=1,"xas",""))'.
            ' FROM users where id=?';
  my $q = $self->SimpleSqlGet($sql, $user);
  $q .= 'i' if $self->IsUserIncarnationExpertOrHigher($user);
  return $q;
}

# Called by the top-level script to make sure the user is allowed.
# Returns undef if user qualifies, error otherwise.
sub AccessCheck
{
  my $self = shift;
  my $page = shift;
  my $user = shift || $self->get('user');

  my $sql = 'SELECT COUNT(*) FROM users WHERE id=?';
  my $cnt = $self->SimpleSqlGet($sql, $user);
  if ($cnt == 0)
  {
    return "DBC failed for $page.tt: user '$user' not in system";
  }
  $sql = 'SELECT restricted FROM menuitems WHERE page=?';
  my $r = $self->SimpleSqlGet($sql, $page) || '';
  my $q = $self->GetUserQualifications($user) || '';
  if (!$self->DoQualificationsAndRestrictionsOverlap($q, $r))
  {
    return "DBC failed for $page.tt: r='$r', q='$q'";
  }
  return undef;
}

# Returns Boolean: do qualifications and restriction overlap?
sub DoQualificationsAndRestrictionsOverlap
{
  my $self = shift;
  my $q    = shift;
  my $r    = shift;

  return 1 unless defined $r and length $r;
  return (($q =~ m/c/ && $r =~ m/c/) ||
          ($q =~ m/e/ && $r =~ m/e/) ||
          ($q =~ m/i/ && $r =~ m/i/) ||
          ($q =~ m/r/ && $r =~ m/r/) ||
          ($q =~ m/x/ && $r =~ m/x/) ||
          ($q =~ m/a/ && $r =~ m/a/) ||
          ($q =~ m/s/ && $r =~ m/s/));
}

sub Categories
{
  my $self = shift;
  my $id   = shift;

  my $proj = $self->SimpleSqlGet('SELECT newproject FROM queue WHERE id=?', $id);
  my $q = $self->GetUserQualifications();
  my $sql = 'SELECT c.name,c.restricted FROM categories c'.
            ' INNER JOIN projectcategories p ON c.id=p.category'.
            ' WHERE p.project=? ORDER BY c.name ASC';
  my $ref = $self->SelectAll($sql, $proj);
  my @all = ();
  foreach my $row (@{$ref})
  {
    my $r = $row->[1];
    if ($self->DoQualificationsAndRestrictionsOverlap($q, $r))
    {
      push @all, $row->[0];
    }
  }
  return \@all;
}

# Get the rights combinations appropriate to the project
# in an order appropriate for a two-column layout.
sub Rights
{
  my $self = shift;
  my $id   = shift;

  my $proj = $self->SimpleSqlGet('SELECT newproject FROM queue WHERE id=?', $id);
  my @all = ();
  my $sql = 'SELECT r.id,CONCAT(a.name,"/",rs.name),r.description FROM rights r'.
            ' INNER JOIN attributes a ON r.attr=a.id'.
            ' INNER JOIN reasons rs ON r.reason=rs.id'.
            ' INNER JOIN projectrights pr ON r.id=pr.rights'.
            ' WHERE (r.restricted IS NULL OR r.restricted NOT LIKE "%i%")'.
            ' AND pr.newproject=?'.
            ' ORDER BY IF(a.name="pd"||a.name="pdus",1,0) DESC, a.name ASC, rs.name ASC';
  #print "$sql<br/>\n";
  my $ref = $self->SelectAll($sql, $proj);
  my %seen = ();
  my $n = 1;
  foreach my $row (@{$ref})
  {
    push @all, [$row->[0], $row->[1], $row->[2], $n];
    $n++;
  }
  my @inorder;
  my $of = scalar @all;
  my $middle = int($of / 2);
  $middle += 1 if $of % 2 == 1;
  foreach $n (0 .. $middle - 1)
  {
    push @inorder, $all[$n];
    push @inorder, $all[$n + $middle] if $n + $middle < $of;
  }
  return \@inorder;
}

# Information sources for the various review pages.
# Returns a ref to in-display-order list of dictionaries with the following keys:
# name, url, accesskey, initial
sub Authorities
{
  my $self = shift;
  my $id   = shift;
  my $mag  = shift;
  my $view = shift;
  my $page = shift;
  my $gid  = shift;

  use URI::Escape;
  $mag = '100' unless $mag;
  $view = 'image' unless $view;
  $page = 'review' unless defined $page;
  my $proj = $self->SimpleSqlGet('SELECT newproject FROM queue WHERE id=?', $id);
  my $sql = 'SELECT a.name,a.url,p.accesskey,p.initial FROM pageauthorities p'.
            ' INNER JOIN authorities a ON p.id=a.id'.
            ' INNER JOIN projectauthorities pa ON pa.authority=a.id'.
            ' WHERE p.page=? AND pa.project=?'.
            ' ORDER BY p.n ASC';
  
  #print "$sql\n<br/>";
  my $ref = $self->SelectAll($sql, $page, $proj);
  my @all = ();
  my $a = $self->GetAuthor($id);
  foreach my $row (@{$ref})
  {
    my $name = $row->[0];
    my $url = $row->[1];
    $url =~ s/__HTID__/$id/g;
    $url =~ s/__GID__/$gid/g;
    $url =~ s/__MAG__/$mag/g;
    $url =~ s/__VIEW__/$view/g;
    if ($url =~ m/crms\?/)
    {
      $url = $self->Sysify($url);
    }
    if ($url =~ m/__AUTHOR__/)
    {
      my $a2 = uri_escape_utf8($a);
      $url =~ s/__AUTHOR__/$a2/g;
    }
    if ($url =~ m/__AUTHOR_(\d+)__/)
    {
      my $a2 = $a;
      if ($name eq 'NGCOBA' && $a =~ m/^ma?c(.)/i)
      {
        $a2 = 'm1';
        my $x = lc $1;
        $a2 = 'm14' if $x le 'z';
        $a2 = 'm13' if $x le 'r';
        $a2 = 'm12' if $x le 'n';
        $a2 = 'm11' if $x le 'e';
      }
      else
      {
        $a2 = lc substr($a, 0, $1);
      }
      $a2 = uri_escape_utf8($a2);
      $url =~ s/__AUTHOR_\d+__/$a2/g;
    }
    if ($url =~ m/__AUTHOR_F__/)
    {
      my $a2 = $1 if $a =~ m/^.*?([A-Za-z]+)/;
      $url =~ s/__AUTHOR_F__/$a2/g;
    }
    if ($url =~ m/__TITLE__/)
    {
      my $t = $self->GetTitle($id);
      $t = uri_escape_utf8($t);
      $url =~ s/__TITLE__/$t/g;
    }
    if ($url =~ m/__TICKET__/)
    {
      my $t = $self->SimpleSqlGet('SELECT ticket FROM queue WHERE id=?', $id);
      $url =~ s/__TICKET__/$t/g;
    }
    if ($url =~ m/__SYSID__/)
    {
      my $sysid = $self->BarcodeToId($id);
      $url =~ s/__SYSID__/$sysid/g;
    }
    push @all, {'name' => $name, 'url' => $url,
                'accesskey' => $row->[2], 'initial' => $row->[3]};
  }
  return \@all;
}

# Makes sure a URL has the correct sys and pdb params if needed.
sub Sysify
{
  my $self = shift;
  my $url  = shift;

  my $sys = $self->Sys();
  $url = Utilities::AppendParam($url, 'sys', $sys) if $sys ne 'crms';
  my $pdb = $self->get('pdb');
  $url = Utilities::AppendParam($url, 'pdb', $pdb) if $pdb;
  my $tdb = $self->get('tdb');
  $url = Utilities::AppendParam($url, 'tdb', $tdb) if $tdb;
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

# If necessary, emits a hidden input with the sys name and pdb
sub HiddenSys
{
  my $self = shift;

  my $html = '';
  my $sys = $self->Sys();
  $html = "<input type='hidden' name='sys' value='$sys'/>" if $sys && $sys ne 'crms';
  my $pdb = $self->get('pdb');
  $html .= "<input type='hidden' name='pdb' value='$pdb'/>" if $pdb;
  my $tdb = $self->get('tdb');
  $html .= "<input type='hidden' name='tdb' value='$tdb'/>" if $tdb;
  return $html;
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

# CRMS World specific. Returns the last year the work was/will be in copyright,
# or undef on error or not enough info.
sub PredictLastCopyrightYear
{
  my $self   = shift;
  my $id     = shift; # Volume id
  my $year   = shift; # ADD or Pub entered by user
  my $ispub  = shift; # Pub date checkbox
  my $crown  = shift; # Crown copyright note category
  my $record = shift; # Metadata (optional) so we don't spam bibdata table for volumes not in queue.
  my $pubref = shift; # Pub date, by reference

  # Punt if the year is not exclusively 1 or more decimal digits with optional minus.
  return undef if $year !~ m/^-?\d+$/;
  my $pub = (defined $pubref)? $$pubref:undef;
  $pub = $year if $ispub;
  $pub = $self->FormatPubDate($id, $record) unless defined $pub;
  return undef unless defined $pub;
  if ($pub =~ m/-/)
  {
    my ($d1, $d2) = split '-', $pub;
    # Use the maximum iff the date range does not span 1923 boundary.
    if ($d1 =~ m/^\d+$/ && $d2 =~ m/^\d+$/ && $d1 < $d2 &&
        (($d1 < 1923 && $d2 < 1923) || ($d1 >= 1923 && $d2 >= 1923)))
    {
      $pub = $d2;
    }
    else
    {
      return undef;
    }
  }
  $$pubref = $pub if defined $pubref;
  my $where = undef;
  $where = $record->country if defined $record;
  $where = $self->GetPubCountry($id) unless $where;
  return undef unless defined $where;
  my $now = $self->GetTheYear();
  # $when is the last year the work was in copyright
  my $when;
  if ($where eq 'United Kingdom')
  {
    $when = $year + (($crown)? 50:70);
  }
  elsif ($where eq 'Canada')
  {
    $when = $year + 50;
  }
  elsif ($where eq 'Australia')
  {
    $when = $year + (($year >= 1955)? 70:50);
  }
  elsif ($where eq 'Spain')
  {
    $when = $year + 80;
  }
  return $when;
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
  my $pub    = shift; # Actual pub date when date range.

  my ($attr, $reason) = (0,0);
  my $now = $self->GetTheYear();
  my $when = $self->PredictLastCopyrightYear($id, $year, $ispub, $crown, $record, \$pub);
  return unless defined $when;
  return undef if $pub =~ m/^\d+-\d+$/;
  if ($when < $now)
  {
    if ($when >= 1996 && $pub >= 1923 &&
        $pub + 95 >= $now)
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
    $attr = ($pub < 1923)? 'pdus':'ic';
    $reason = 'add';
  }
  my $sql = 'SELECT r.id FROM rights r INNER JOIN attributes a ON r.attr=a.id'.
            ' INNER JOIN reasons rs ON r.reason=rs.id'.
            ' WHERE a.name=? AND rs.name=?';
  return $self->SimpleSqlGet($sql, $attr, $reason);
}

sub Unescape
{
  my $self = shift;

  use URI::Escape;
  return uri_unescape(shift);
}

#046	##$f1899$g1961
#100	1#$aHemingway, Ernest,$d1899-1961
#Dates are in ISO 8601 format unless specified in a $2, thus
#Died January 10 1963=$g 19630110
#Died January 1963= $g 1963-01
#Died January 10 or 11, 1963=$g [19630110,19630111] $2 edtf <-- we don't handle this
#Died Between 1930 and 1933=$g 1930...1933 $2 edtf <-- we can't handle this
#Died 65 AD=$g 0065
#Died 361 BC= $g -0360
sub GetADDFromAuthor
{
  my $self   = shift;
  my $id     = shift;
  my $a      = shift; # For testing
  my $record = shift || $self->GetMetadata($id);

  my $add = undef;
  return unless defined $record;
  $a = $record->author(1) unless defined $a;
  my $regex = '(\d?\d\d\d\??)?\s*-\s*(\d?\d\d\d)[.,;) ]*$';
  if (defined $a && $a =~ m/$regex/)
  {
    $add = $2;
    $add = undef if $a =~ m/(fl\.*|active)\s*$regex/i;
  }
  if (!defined $add)
  {
    my $data = $record->GetDatafield('046', 'g', 1);
    if ($data && $data =~ m/^\s*(-?\d\d\d\d)/)
    {
      $add = $1;
    }
  }
  return $add;
}

sub VIAFWarning
{
  my $self   = shift;
  my $id     = shift;
  my $record = shift;

  use VIAF;
  my %warnings;
  $record = $self->GetMetadata($id) unless defined $record;
  return 'unable to fetch MARC metadata for volume' unless defined $record;
  my @authors = $record->GetAllAuthors();
  foreach my $author (@authors)
  {
    my $data = VIAF::GetVIAFData($self, $author);
    if (defined $data and scalar keys %{$data} > 0)
    {
      my $country = $data->{'country'};
      if (defined $country && $country ne 'US')
      {
        my $abd = $data->{'abd'};
        my $add = $data->{'add'};
        next if defined $abd and $abd <= 1815;
        next if defined $add and $add <= 1925;
        my $dates = '';
        $dates = sprintf ' %s-%s', (defined $abd)? $abd:'', (defined $add)? $add:'' if $abd or $add;
        my $last = $author;
        $last = $1 if $last =~ m/^(.+?),.*/;
        $last =~ s/[.,;) ]*$//;
        $warnings{"$last ($country$dates)"} = 1;
      }
    }
  }
  return (scalar keys %warnings)? join '; ', keys %warnings:undef;
}

# Return dollarized barcode if suffix is the right length,
# and metadata is available, or undef.
# Returns the metadata by reference.
sub Dollarize
{
  my $self = shift;
  my $id   = shift;
  my $meta = shift;

  if ($id =~ m/uc1\.b\d{1,6}$/)
  {
    my $id2 = $id;
    $id2 =~ s/b/\$b/;
    my $record = $self->GetMetadata($id2);
    if (!defined $record)
    {
      $self->ClearErrors();
    }
    else
    {
      $$meta = $record if defined $meta;
      return $id2;
    }
  }
  return undef;
}

# Return undollarized barcode if suffix is the right length,
# or undef.
sub Undollarize
{
  my $self = shift;
  my $id   = shift;

  if ($id =~ m/uc1\.\$b\d{1,6}$/)
  {
    my $id2 = $id;
    $id2 =~ s/\$b/b/;
    my $record = $self->GetMetadata($id2);
    if (!defined $record)
    {
      $self->ClearErrors();
    }
    else
    {
      return $id2;
    }
  }
  return undef;
}

# FIXME: projectcategories may make this obsolete.
sub CanVolumeBeCrownCopyright
{
  my $self = shift;
  my $id   = shift;

  my $c = $self->GetPubCountry($id);
  return 1 if defined $c && ($c eq 'United Kingdom' || $c eq 'Canada' || $c eq 'Australia');
}

sub GetAddToQueueRef
{
  my $self = shift;
  my $user = shift || $self->get('user');

  my $sql = 'SELECT q.id,b.title,b.author,YEAR(b.pub_date),DATE(q.time),q.added_by,' .
            ' q.status,q.priority,q.source,q.issues,q.ticket,p.name FROM queue q'.
            ' INNER JOIN bibdata b ON q.id=b.id'.
            ' INNER JOIN projects p ON q.newproject=p.id'.
            ' WHERE q.added_by=? AND p.name="Special"'.
            ' ORDER BY q.added_by,q.source,q.status ASC,q.priority DESC,q.id ASC';
  #print "$sql\n";
  my $ref = $self->SelectAll($sql, $user);
  my @result;
  foreach my $row (@{$ref})
  {
    push @result, {'id' => $row->[0], 'title' => $row->[1], 'author' => $row->[2],
                   'pub_date' => $row->[3], 'date' => $row->[4], 'added_by' => $row->[5],
                   'status' => $row->[6], 'priority' => $row->[7], 'source' => $row->[8],
                   'issues' => $row->[9], 'ticket' => $row->[10], 'project' => $row->[11]};
  }
  return \@result;
}

sub GetBothSystems
{
  my $self = shift;

  my ($crmsUS, $crmsWorld);
  if ($self->Sys() eq 'crmsworld')
  {
    $crmsUS = CRMS->new(
      logFile      => $self->get('logfile'),
      sys          => 'crms',
      verbose      => 0,
      root         => $self->get('root'),
      dev          => $self->get('dev'));
    $crmsWorld = $self;
  }
  else
  {
    $crmsUS = $self;
    $crmsWorld = CRMS->new(
      logFile      => $self->get('logfile'),
      sys          => 'crmsworld',
      verbose      => 0,
      root         => $self->get('root'),
      dev          => $self->get('dev'));
  }
  return [$crmsUS,$crmsWorld];
}

# The standard XHTML declarations up to an including <body>
sub StartHTML
{
  my $self  = shift;
  my $title = shift;
  my $head  = shift;

  $title = '' unless defined $title;
  $head  = '' unless defined $head;
  my $html = <<END;
<!DOCTYPE html>
<html lang="en">
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8"/>
    <title>$title</title>
    $head
  </head>
  <body>
END
  return $html;
}

sub SubjectLine
{
  my $self = shift;
  my $rest = shift || '<No Subject>';

  return sprintf "%s %s: $rest", $self->System(), $self->WhereAmI() || 'Prod';
}

sub GetClosedTickets
{
  my $self = shift;
  my $ua   = shift;

  my $sql = 'SELECT DISTINCT source FROM queue WHERE source LIKE "HTS%"';
  my @txs;
  my %stats2;
  push @txs, $_->[0] for @{$self->SelectAll($sql)};
  if (scalar @txs > 0)
  {
    use Jira;
    $ua = Jira::Login($self) unless defined $ua;
    my $stats = Jira::GetIssuesStatus($self, $ua, \@txs);
    foreach my $tx (keys %{$stats})
    {
      my $stat = $stats->{$tx};
      $stats2{$tx} = $stat if $stat eq 'Closed' or $stat eq 'Resolved' or $stat eq 'Status unknown';
    }
  }
  return \%stats2;
}

sub Note
{
  my $self = shift;
  my $note = shift;

  $self->PrepareSubmitSql('INSERT INTO note (note) VALUES (?)', $note);
}

sub GetUserProjects
{
  my $self = shift;
  my $user = shift || $self->get('user');

  my $sql = 'SELECT pu.project,p.name,'.
            '(SELECT COUNT(*) FROM queue q WHERE q.newproject=pu.project)'.
            ' FROM projectusers pu INNER JOIN projects p ON pu.project=p.id WHERE pu.user=?'.
            ' ORDER BY p.name';
  #print "$sql\n";
  my $ref = $self->SelectAll($sql, $user);
  my @ps = map {{'id' => $_->[0], 'name' => $_->[1], 'count' => $_->[2]};} @{$ref};
  @ps = () if scalar @ps == 1 and !defined $ref->[0]->[0];
  return \@ps;
}

sub SetUserCurrentProject
{
  my $self = shift;
  my $user = shift || $self->get('user');
  my $proj = shift || '1';

  my $sql = 'UPDATE users SET newproject=? WHERE id=?';
  $self->PrepareSubmitSql($sql, $proj, $user);
}

# Get the name for either a project or volume ID in the queue.
sub GetProjectName
{
  my $self = shift;
  my $id   = shift;

  my $sql = 'SELECT name FROM projects WHERE id=?';
  $sql = 'SELECT p.name FROM projects p INNER JOIN queue q ON q.newproject=p.id WHERE q.id=?' if $id !~ m/^\d+$/;
  $self->SimpleSqlGet($sql, $id);
}

# Returns an arrayref of hashrefs with id, name, color, userCount (active assignees),
# queueCount, rights (arrayref), categories (arrayref), authorities (arrayref).
sub GetProjectsRef
{
  my $self = shift;

  my @projects;
  my $sql = 'SELECT p.id,p.name,p.restricted,p.color,'.
            '(SELECT COUNT(*) FROM projectusers pu INNER JOIN users u ON pu.user=u.id'.
            ' WHERE pu.project=p.id AND u.reviewer+u.advanced+u.expert+u.admin+u.superadmin>0),'.
            '(SELECT COUNT(*) FROM queue q WHERE q.newproject=p.id),'.
            '(SELECT COUNT(*) FROM candidates c WHERE c.newproject=p.id),'.
            '(SELECT COUNT(*) FROM exportdata e WHERE e.newproject=p.id)'.
            ' FROM projects p ORDER BY p.id ASC';
  my $ref = $self->SelectAll($sql);
  foreach my $row (@{$ref})
  {
    push @projects, {'id' => $row->[0], 'name' => $row->[1], 'restricted' => $row->[2],
                     'color' => $row->[3], 'userCount' => $row->[4], 'queueCount' => $row->[5],
                     'candidatesCount' => $row->[6], 'determinationsCount' => $row->[7]};
    my $ref2 = $self->SelectAll('SELECT rights FROM projectrights WHERE newproject=?', $row->[0]);
    $projects[-1]->{'rights'} = [map {$_->[0]} @{$ref2}];
    $ref2 = $self->SelectAll('SELECT category FROM projectcategories WHERE project=?', $row->[0]);
    $projects[-1]->{'categories'} = [map {$_->[0]} @{$ref2}];
    $ref2 = $self->SelectAll('SELECT authority FROM projectauthorities WHERE project=?', $row->[0]);
    $projects[-1]->{'authorities'} = [map {$_->[0]} @{$ref2}];
    $ref2 = $self->SelectAll('SELECT user FROM projectusers WHERE project=?', $row->[0]);
    $projects[-1]->{'users'} = [map {$_->[0]} @{$ref2}];
  }
  return \@projects;
}

# Returns the id of the added project, or under on error.
sub AddProject
{
  my $self     = shift;
  my $name     = shift;
  my $restrict = shift;

  my $sql = 'INSERT INTO projects (name,restricted) VALUES (?,?)';
  $self->PrepareSubmitSql($sql, $name, $restrict);
  return $self->SimpleSqlGet('SELECT id FROM projects WHERE name=?', $name);
}

sub AllAssignableRights
{
  my $self = shift;

  my $sql = 'SELECT r.id,CONCAT(a.name,"/",rs.name),CONCAT(a.dscr,"/",rs.dscr) FROM rights r'.
            ' INNER JOIN attributes a ON r.attr=a.id'.
            ' INNER JOIN reasons rs ON r.reason=rs.id'.
            ' WHERE rs.name!="crms"'.
            ' ORDER BY IF (a.name LIKE "pd%",1,0) DESC,a.name,rs.name';
  #print "$sql\n";
  my $ref = $self->SelectAll($sql);
  my @rights;
  push @rights, {'id' => $_->[0], 'rights' => $_->[1], 'description' => $_->[2]} for @{$ref};
  return \@rights;
}

sub AllAssignableCategories
{
  my $self = shift;

  my $sql = 'SELECT c.id,c.name FROM categories c WHERE interface=1 ORDER BY c.name ASC';
  my $ref = $self->SelectAll($sql);
  my @categories;
  push @categories, {'id' => $_->[0], 'name' => $_->[1]} for @{$ref};
  return \@categories;
}

sub AllAssignableAuthorities
{
  my $self = shift;

  my $sql = 'SELECT a.id,a.name,a.url FROM authorities a ORDER BY a.name ASC';
  my $ref = $self->SelectAll($sql);
  my @authorities;
  push @authorities, {'id' => $_->[0], 'name' => $_->[1], 'url' => $_->[2]} for @{$ref};
  return \@authorities;
}

sub AllAssignableUsers
{
  my $self = shift;

  my $sql = 'SELECT u.id,u.name FROM users u WHERE u.reviewer+u.advanced+u.expert+u.admin+u.superadmin>0 ORDER BY u.name ASC';
  my $ref = $self->SelectAll($sql);
  my @authorities;
  push @authorities, {'id' => $_->[0], 'name' => $_->[1]} for @{$ref};
  return \@authorities;
}

sub SetProjectUsers
{
  my $self = shift;
  my $proj = shift;

  my $sql = 'DELETE FROM projectusers WHERE project=?';
  $self->PrepareSubmitSql($sql, $proj);
  $sql = 'INSERT INTO projectusers (user,project) VALUES (?,?)';
  foreach my $user (@_)
  {
    $self->PrepareSubmitSql($sql, $user, $proj);
  }
}

1;
