package CRMS;

## ----------------------------------------------------------
## Object of shared code for the CRMS DB CGI and BIN scripts.
## ----------------------------------------------------------

use strict;
use warnings;
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
use utf8;
use Unicode::Normalize;
binmode(STDOUT, ':encoding(UTF-8)');

## -------------------------------------------------
##  Top level CRMS object. This guy does everything.
## -------------------------------------------------
sub new
{
  my ($class, %args) = @_;
  my $self = bless {}, $class;
  if ($args{'root'})
  {
    print "<strong>Warning: root passed to <code>CRMS->new()</code>\n";
  }
  if ($args{'logFile'})
  {
    print "<strong>Warning: logFile passed to <code>CRMS->new()</code>\n";
  }
  my $root = $ENV{'DLXSROOT'};
  $root = $ENV{'SDRROOT'} unless $root and -d $root;
  die 'ERROR: cannot locate root directory with DLXSROOT or SDRROOT!' unless $root and -d $root;
  $root = '/' unless $root;
  $self->set('root', $root);
  my %d = $self->ReadConfigFile('crms.cfg');
  $self->set($_, $d{$_}) for keys %d;
  $self->SetupLogFile();
  # Initialize error reporting.
  $self->ClearErrors();
  $self->set('verbose',  $args{'verbose'});
  # If running under Apache.
  $self->set('instance', $ENV{'CRMS_INSTANCE'});
  # If running from command line.
  $self->set('instance', $args{'instance'}) if $args{'instance'};
  # Only need to authorize when running as CGI.
  if ($ENV{'GATEWAY_INTERFACE'})
  {
    $CGI::LIST_CONTEXT_WARN = 0;
    my $cgi = $args{'cgi'};
    print "<strong>Warning: no CGI passed to <code>CRMS->new()</code>\n" unless $cgi;
    $self->set('cgi',      $cgi);
    $self->set('pdb',      $cgi->param('pdb'));
    $self->set('tdb',      $cgi->param('tdb'));
    $self->set('debugSql', $args{'debugSql'});
    $self->set('debugVar', $args{'debugVar'});
    $self->SetupUser();
  }
  $self->DebugVar('self', $self);
  return $self;
}

sub Version
{
  return '8.2.15';
}

# First, try to establish the identity of the user as represented in the users table.
# 1. REMOTE_USER directly (uniqname/friend)
# 2. email directly
# 3. eppn (e.g., somebody+blah.com@umich.edu) directly
# 4. REMOTE_USER as ht_users userid
# Then, set login credentials as remote_user and user as alias if it is set.
sub SetupUser
{
  my $self = shift;

  my $note = '';
  my $sdr_dbh = $self->get('ht_repository');
  if (!defined $sdr_dbh)
  {
    $sdr_dbh = $self->ConnectToSdrDb('ht_repository');
    $self->set('ht_repository', $sdr_dbh) if defined $sdr_dbh;
  }
  return unless defined $sdr_dbh;
  my ($ht_user, $crms_user);
  my $usersql = 'SELECT COUNT(*) FROM users WHERE id=?';
  my $htsql = 'SELECT email FROM ht_users WHERE userid=?';
  my $candidate = $ENV{'REMOTE_USER'};
  $candidate = lc $candidate if defined $candidate;
  $note .= sprintf "ENV{REMOTE_USER}=%s\n", (defined $candidate)? $candidate:'<undef>';
  if ($candidate)
  {
    my $candidate2;
    my $ref = $sdr_dbh->selectall_arrayref($htsql, undef, $candidate);
    if ($ref && scalar @{$ref})
    {
      $ht_user = $candidate;
      $note .= "Set ht_user=$ht_user\n";
      $candidate2 = $ref->[0]->[0];
    }
    if ($self->SimpleSqlGet($usersql, $candidate))
    {
      $crms_user = $candidate;
      $note .= "Set crms_user=$crms_user from lc ENV{REMOTE_USER}\n";
    }
    if (!$crms_user && $self->SimpleSqlGet($usersql, $candidate2))
    {
      $crms_user = $candidate2;
      $note .= "Set crms_user=$crms_user from ht_users.email\n";
    }
  }
  if (!$crms_user || !$ht_user)
  {
    $candidate = $ENV{'email'};
    $candidate = lc $candidate if defined $candidate;
    $candidate =~ s/\@umich.edu// if defined $candidate;
    $note .= sprintf "ENV{email}=%s\n", (defined $candidate)? $candidate:'<undef>';
    if ($candidate)
    {
      my $candidate2;
      my $ref = $sdr_dbh->selectall_arrayref($htsql, undef, $candidate);
      if ($ref && scalar @{$ref} && !$ht_user)
      {
        $ht_user = $candidate;
        $note .= "Set ht_user=$ht_user\n";
        $candidate2 = $ref->[0]->[0];
      }
      if ($self->SimpleSqlGet($usersql, $candidate) && !$crms_user)
      {
        $crms_user = $candidate;
        $note .= "Set crms_user=$crms_user from lc ENV{email}\n";
      }
      if (!$crms_user && $self->SimpleSqlGet($usersql, $candidate2) && !$crms_user)
      {
        $crms_user = $candidate2;
        $note .= "Set crms_user=$crms_user from ht_users.email\n";
      }
    }
  }
  if ($ht_user)
  {
    if ($self->NeedStepUpAuth($ht_user))
    {
      $note .= "HT user $ht_user step-up auth required.\n";
      $self->set('stepup', 1);
    }
    $self->set('ht_user', $ht_user);
  }
  if ($crms_user)
  {
    $note .= "Setting CRMS user to $crms_user.\n";
    $self->set('remote_user', $crms_user);
    my $alias = $self->GetAlias($crms_user);
    $crms_user = $alias if defined $alias and length $alias and $alias ne $crms_user;
    $self->set('user', $crms_user);
  }
  $self->set('id_note', $note);
  return $crms_user;
}

# read the template from ht_institutions
# replace __HOST__ with $ENV{SERVER_NAME}
# replace __TARGET__ with something like CGI::self_url($cgi)
# append &authnContextClassRef=$shib_authncontext_class
sub NeedStepUpAuth
{
  my $self = shift;
  my $user = shift;

  #return 0 if $self->WhereAmI() =~ m/^dev/i;
  my $need = 0;
  my $idp = $ENV{'Shib_Identity_Provider'};
  my $class = $ENV{'Shib_AuthnContext_Class'};
  my $sdr_dbh = $self->get('ht_repository');
  if (!defined $sdr_dbh)
  {
    $sdr_dbh = $self->ConnectToSdrDb('ht_repository');
    $self->set('ht_repository', $sdr_dbh) if defined $sdr_dbh;
  }
  my $sql = 'SELECT COALESCE(mfa,0) FROM ht_users WHERE userid=? LIMIT 1';
  my $ref;
  my $mfa;
  eval {
    $ref = $sdr_dbh->selectall_arrayref($sql, undef, $user);
  };
  if ($ref && scalar @{$ref})
  {
    $mfa = $ref->[0]->[0];
  }
  if ($mfa)
  {
    my ($dbclass, $dbtemplate);
    $sql = 'SELECT shib_authncontext_class,template FROM ht_institutions'.
           ' WHERE entityID=? LIMIT 1';
    eval {
      $ref = $sdr_dbh->selectall_arrayref($sql, undef, $idp);
    };
    if ($ref && scalar @{$ref})
    {
      $dbclass    = $ref->[0]->[0]; # https://refeds.org/profile/mfa or NULL
      $dbtemplate = $ref->[0]->[1]; # https://___HOST___/Shibboleth.sso/Login?entityID=https://shibboleth.umich.edu/idp/shibboleth&target=___TARGET___
      #$dbtemplate = 'https://___HOST___/Shibboleth.sso/Login?entityID=___ENTITY_ID___&target=___TARGET___';
    }
    if (defined $class && defined $dbclass && $class ne $dbclass)
    {
      $need = 1;
      my $tpl = $dbtemplate;
      use URI::Escape;
      my $target = CGI::self_url($self->get('cgi'));
      if ($dbtemplate)
      {
        $tpl =~ s/___HOST___/$ENV{SERVER_NAME}/;
        $tpl =~ s/___TARGET___/$target/;
        $tpl =~ s/___ENTITY_ID___/$idp/; # FIXME: may be obsolete
        $tpl .= "&authnContextClassRef=$dbclass";
        $self->set('stepup_redirect', $tpl);
      }
      my $note = sprintf "ENV{Shib_Identity_Provider}='$idp'\n".
                         "ENV{Shib_AuthnContext_Class}='$class'\n".
                         "DB class=%s\n".
                         'TEMPLATE=%s FROM=%s (%s,%s)',
                         (defined $dbclass)? $dbclass:'<undef>',
                         (defined $tpl)? $tpl:'<undef>',
                         (defined $dbtemplate)? $dbtemplate:'<undef>',
                         $ENV{SERVER_NAME}, $target;
      $self->set('auth_note', $note);
    }
  }
  return $need;
}

# The href or URL to use.
# Path is e.g. 'logo.png', returns {'/c/crms/logo.png', '/crms/web/logo.png'}
sub WebPath
{
  my $self = shift;
  my $type = shift;
  my $path = shift;

  my %types = ('bin' => 1, 'cgi' => 1, 'prep' => 1, 'web' => 1);
  if (!$types{$type})
  {
    $self->SetError("Unknown path type '$type'");
    die "FSPath: unknown type $type";
  }
  my $fullpath = "/crms/$type/". $path;
  if ($self->get('root') !~ m/htapps/)
  {
    $fullpath = ($type eq 'web')? ("/c/crms/". $path): ("/$type/c/crms/". $path);
  }
  #print "$fullpath ($type, $path)\n";
  return $self->Sysify($fullpath);
}

# The href or URL to use.
# type+path is e.g. 'prep' + 'crms.rights'
# returns {'/l1/dev/moseshll/prep/c/crms/crms.rights', '/htapps/moseshll.babel/crms/prep/crms.rights'}
sub FSPath
{
  my $self = shift;
  my $type = shift;
  my $path = shift;

  my %types = ('bin' => 1, 'cgi' => 1, 'prep' => 1, 'web' => 1);
  if (!$types{$type})
  {
    $self->SetError("Unknown path type '$type'");
    die "FSPath: unknown type $type";
  }
  my $fullpath = $self->get('root');
  $fullpath .= '/' unless $fullpath =~ m/\/$/;
  $fullpath .= (($self->get('root') =~ m/htapps/)? "crms/$type/":"$type/c/crms/"). $path;
  return $fullpath;
}

# Temporary hack to translate menuitems urls into quod/HT urls
# /c/crms/blah -> $self->WebPath('web', 'blah')
# crms?blah=1 -> $self->WebPath('cgi', 'crms?blah=1')
sub MenuPath
{
  my $self = shift;
  my $path = shift;

  my $newpath = $path;
  if ($path =~ m/^\/c\/crms\/(.*)$/)
  {
    $newpath = $self->WebPath('web', $1);
  }
  elsif ($path =~ m/^crms/)
  {
    $newpath = $self->WebPath('cgi', $path);
  }
  return $newpath;
}

sub SetupLogFile
{
  my $self = shift;

  my $log = $0 || 'crms_cgi';
  $log = 'crms_cgi' if $log =~ m/\//;
  $log =~ s/[^A-Za-z0-9]/_/g;
  $self->set('logFile', $self->FSPath('prep', $log));
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

sub ReadConfigFile
{
  my $self = shift;
  my $path = shift;

  $path = $self->FSPath('bin', $path);
  my %dict = ();
  my $fh;
  unless (open $fh, '<:encoding(UTF-8)', $path)
  {
    $self->SetError("failed to read config file at $path: " . $!);
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
  my $instance  = $self->get('instance') || '';

  my %d = $self->ReadConfigFile('crmspw.cfg');
  my $db_user   = $d{'mysqlUser'};
  my $db_passwd = $d{'mysqlPasswd'};
  if ($instance eq 'production'
      || $self->get('pdb')
      || $instance eq 'crms-training'
      || $self->get('tdb')
      )
  {
    $db_server = $self->get('mysqlServer');
  }
  my $db = $self->DbName();
  my $dbh = DBI->connect("DBI:mysql:$db:$db_server", $db_user, $db_passwd,
            { PrintError => 0, RaiseError => 1, AutoCommit => 1 }) || die "Cannot connect: $DBI::errstr";
  $dbh->{mysql_enable_utf8} = 1;
  $dbh->{mysql_auto_reconnect} = 1;
  $dbh->do('SET NAMES "utf8";');
  return $dbh;
}

sub DbInfo
{
  my $self = shift;

  my $db_server = $self->get('mysqlServerDev');
  my $instance  = $self->get('instance') || '';

  my $msg = '';
  my %d = $self->ReadConfigFile('crmspw.cfg');
  my $db_user   = $d{'mysqlUser'};
  my $db_passwd = $d{'mysqlPasswd'};
  if ($instance eq 'production'
      || $self->get('pdb')
      || $instance eq 'crms-training'
      || $self->get('tdb'))
  {
    $db_server = $self->get('mysqlServer');
  }
  my $db = $self->DbName();
  my $where = $self->DevBanner() || 'PRODUCTION';
  $msg = "DB Info:\nInstance $instance\n$where\n$db on $db_server as $db_user";
  $msg .= "\n(PDB set)" if $self->get('pdb');
  $msg .= "\n(TDB set)" if $self->get('tdb');
  return $msg;
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
  my $instance  = $self->get('instance') || '';

  $db = $self->get('mysqlMdpDbName') unless defined $db;
  my %d = $self->ReadConfigFile('crmspw.cfg');
  my $db_user   = $d{'mysqlMdpUser'};
  my $db_passwd = $d{'mysqlMdpPasswd'};
  if ($instance eq 'production'
      || $instance eq 'crms-training'
      || $self->get('pdb')
      || $self->get('tdb'))
  {
    $db_server = $self->get('mysqlMdpServer');
  }
  my $sdr_dbh = DBI->connect("DBI:mysql:$db:$db_server", $db_user, $db_passwd,
                             {PrintError => 0, AutoCommit => 1});
  if ($sdr_dbh)
  {
    $sdr_dbh->{mysql_auto_reconnect} = 1;
    $sdr_dbh->{mysql_enable_utf8} = 1;
  }
  else
  {
    my $err = $DBI::errstr;
    $self->SetError($err);
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

  my $instance = $self->get('instance') || '';
  my $tdb = $self->get('tdb');
  my $db = $self->get('mysqlDbName');
  $db .= '_training' if $instance eq 'crms-training' or $tdb;
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

# Returns 1 on success.
sub PrepareSubmitSql
{
  my $self = shift;
  my $sql  = shift;

  return 1 if $self->get('noop');
  my $dbh = $self->GetDb();
  my $t1 = Time::HiRes::time();
  my $sth = $dbh->prepare($sql);
  eval { $sth->execute(@_); };
  my $t2 = Time::HiRes::time();
  $self->DebugSql($sql, 1000.0*($t2-$t1), 1, undef, @_);
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
  if ($@)
  {
    my $msg = sprintf 'SQL failed (%s): %s', Utilities::StringifySql($sql, @_), $@;
    $self->SetError($msg);
    $self->Logit($msg);
  }
  my $t2 = Time::HiRes::time();
  $self->DebugSql($sql, 1000.0*($t2-$t1), $ref, undef, @_);
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
  if ($@)
  {
    my $msg = sprintf 'SQL failed (%s): %s', Utilities::StringifySql($sql, @_), $@;
    $self->SetError($msg);
    $self->Logit($msg);
  }
  my $t2 = Time::HiRes::time();
  $self->DebugSql($sql, 1000.0*($t2-$t1), $ref, 'ht_rights', @_);
  return $ref;
}

# Returns a parenthesized comma separated list of n question marks.
sub WildcardList
{
  my $self = shift;
  my $n    = shift;

  return '()' if $n < 1;
  return '(' . ('?,' x ($n-1)) . '?)';
}

sub DebugSql
{
  my $self = shift;
  my $sql  = shift;
  my $time = shift;
  my $ref  = shift;
  my $db   = shift;

  my $debug = $self->get('debugSql');
  if ($debug)
  {
    my $ct = $self->get('debugCount') || 0;
    my @parts = split m/\s+/, $sql;
    my $type = uc $parts[0];
    $type .= ' '. $db if defined $db;
    my $trace = Utilities::LocalCallChain();
    $trace = join '<br>', @{$trace};
    my $stat = ($ref)? '':'<i>FAIL</i>';
	  my $html = <<END;
    <div class="debug">
      <div class="debugSql" onClick="ToggleDiv('details$ct', 'debugSqlDetails');">
        SQL QUERY [$type] ($ct) $stat
      </div>
      <div id="details$ct" class="divHide"
           style="background-color: #9c9;" onClick="ToggleDiv('details$ct', 'debugSqlDetails');">
        $sql <strong>{%s}</strong> <i>(%.3fms)</i><br/>
        <i>$trace</i>
      </div>
    </div>
END
    my $msg = sprintf $html, join(',', @_), $time;
    my $storedDebug = $self->get('storedDebug') || '';
    $self->set('storedDebug', $storedDebug. $msg);
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
  if ($debug)
  {
    my $ct = $self->get('debugCount') || 0;
	  my $html = <<END;
    <div class="debug">
      <div class="debugVar" onClick="ToggleDiv('details$ct', 'debugVarDetails');">
        VAR $var
      </div>
      <div id="details$ct" class="divHide"
           style="background-color: #fcc;" onClick="ToggleDiv('details$ct', 'debugVarDetails');">
        %s
      </div>
    </div>
END
    use Data::Dumper;
    my $msg = sprintf $html, Dumper($val);
    my $storedDebug = $self->get('storedDebug') || '';
    $self->set('storedDebug', $storedDebug. $msg);
    $ct++;
    $self->set('debugCount', $ct);
  }
}

sub DebugAuth
{
  my $self = shift;

  my $debug = $self->get('debugAuth');
  if ($debug)
  {
    my $ct = $self->get('debugCount') || 0;
	  my $html = <<END;
    <div class="debug">
      <div class="debugVar" onClick="ToggleDiv('details$ct', 'debugVarDetails');">
        AUTH
      </div>
      <div id="details$ct" class="divHide"
           style="background-color: #fcc;" onClick="ToggleDiv('details$ct', 'debugVarDetails');">
        %s
      </div>
    </div>
END
    my $storedDebug = $self->get('storedDebug') || '';
    $self->set('storedDebug', $storedDebug. $self->AuthDebugHTML());
    $ct++;
    $self->set('debugCount', $ct);
  }
}

sub AuthDebugData
{
  my $self = shift;
  my $html = shift;

  my $note1 = $self->get('id_note') || '';
  my $note2 = $self->get('auth_note') || '';
  my $msg = $note1. "\n". $note2;
  if ($html)
  {
    $msg = CGI::escapeHTML($msg);
    $msg =~ s/\n+/<br\/>/gs;
  }
  return $msg;
}

# Called to return and flush any accumulated debugging display.
sub Debug
{
  my $self = shift;

  my $d = $self->get('storedDebug') || '';
  $self->set('storedDebug', '');
  $d;
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
  my $time  = shift || $self->SimpleSqlGet('SELECT NOW()');

  # Get the underlying system status, ignoring replication delays.
  my $stat = $self->GetSystemStatus(1);
  $self->ReportMsg(sprintf("ProcessReviews: system status is '%s'", (defined $stat)? $stat->[1] : 'normal')) unless $quiet;
  # Clear the deleted inheritances, regardless of system status
  my $sql = 'SELECT COUNT(*) FROM inherit WHERE status=0';
  my $dels = $self->SimpleSqlGet($sql);
  if ($dels)
  {
    $self->ReportMsg('Deleted inheritances to be removed: '. $dels) unless $quiet;
    $self->DeleteInheritances($quiet);
  }
  else
  {
    $self->ReportMsg('No deleted inheritances to remove.') unless $quiet;
  }
  my $reason = '';
  # Don't do this if the system is down or if it is Sunday.
  if ($stat->[1] ne 'normal')
  {
    $reason = 'system status is '. $stat->[1];
  }
  elsif ($self->GetSystemVar('autoinherit', '') eq 'disabled')
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
    $self->ReportMsg('Not auto-submitting inheritances because '. $reason) unless $quiet;
  }
  my $tmpstat = ['', 'partial',
                 'CRMS is processing reviews. The Review page is temporarily unavailable. '.
                 'Try back in about a minute.'];
  $self->SetSystemStatus($tmpstat);
  my %stati = (2=>0, 3=>0, 4=>0, 8=>0);
  $sql = 'SELECT id FROM reviews WHERE id IN (SELECT id FROM queue WHERE status=0) GROUP BY id HAVING COUNT(*)=2';
  my $ref = $self->SelectAll($sql);
  #print Dumper $self->ReviewData('uiug.30112124385599');
  foreach my $row (@{$ref})
  {
    my $id = $row->[0];
    # Don't process anything that las a review less than 8 hours old.
    my $sql = 'SELECT COUNT(*) FROM reviews WHERE id=? AND time>DATE_SUB(?, INTERVAL 8 HOUR)';
    if (0 < $self->SimpleSqlGet($sql, $id, $time))
    {
      $self->ReportMsg("Not processing $id: it has one or more reviews less than 8 hours old") unless $quiet;
      next;
    }
    my $data = $self->CalcStatus($id);
    my $status = $data->{'status'};
    next unless defined $status and $status > 0;
    my $hold = $data->{'hold'};
    if ($hold)
    {
      $self->ReportMsg("Not processing $id for $hold: it is held") unless $quiet;
      next;
    }
    if ($status == 8)
    {
      $self->SubmitReview($id, 'autocrms', $data);
    }
    $self->RegisterStatus($id, $status);
    $sql = 'UPDATE reviews SET hold=0,time=time WHERE id=?';
    $self->PrepareSubmitSql($sql, $id);
    $stati{$status}++;
  }
  $self->ReportMsg(sprintf "Setting system status back to '%s'", $stat->[1]) unless $quiet;
  $self->SetSystemStatus($stat);
  $sql = 'INSERT INTO processstatus VALUES ()';
  $self->PrepareSubmitSql($sql);
  $self->PrepareSubmitSql('DELETE FROM predeterminationsbreakdown WHERE date=DATE(NOW())');
  $sql = 'INSERT INTO predeterminationsbreakdown (date,s2,s3,s4,s8) VALUES (DATE(NOW()),?,?,?,?)';
  $self->PrepareSubmitSql($sql, $stati{2}, $stati{3}, $stati{4}, $stati{8});
}

# Returns a data structure with the following fields:
# status: the status to set to queue item to
# hold: id of a user with a review on hold
# attr: the final rights attribute (status 8)
# reason: the final rights reason (status 8)
# category: the final determination category (status 8)
sub CalcStatus
{
  my $self = shift;
  my $id   = shift;

  my $return = {'status' => 0};
  my $sql = 'SELECT r.user,a.name,rs.name,r.hold,d.data'.
            ' FROM reviews r INNER JOIN attributes a ON r.attr=a.id'.
            ' INNER JOIN reasons rs ON r.reason=rs.id'.
            ' LEFT JOIN reviewdata d ON r.data=d.id'.
            ' WHERE r.id=? ORDER BY r.time ASC';
  my $ref = $self->SelectAll($sql, $id);
  my ($user, $attr, $reason, $hold, $data) = @{$ref->[0]};
  $sql = 'SELECT r.user,a.name,rs.name,r.hold,d.data'.
         ' FROM reviews r INNER JOIN attributes a ON r.attr=a.id'.
         ' INNER JOIN reasons rs ON r.reason=rs.id'.
         ' LEFT JOIN reviewdata d ON r.data=d.id'.
         ' WHERE r.id=? AND r.user!=? ORDER BY r.time ASC';
  $ref = $self->SelectAll($sql, $id, $user);
  return $return if 0 == scalar @{$ref};
  my ($user2, $attr2, $reason2, $hold2, $data2) = @{$ref->[0]};
  if ($hold)
  {
    $return->{'hold'} = $user;
  }
  if ($hold2)
  {
    $return->{'hold'} = $user2;
  }
  if (DoRightsMatch($self, $attr, $reason, $attr2, $reason2))
  {
    # If both reviewers are non-advanced mark as provisional match
    if ((!$self->IsUserAdvanced($user)) && (!$self->IsUserAdvanced($user2)))
    {
      $return->{'status'} = 3;
    }
    else # Mark as 4 or 8 - two that agree
    {
      $return->{'status'} = 4;
      if ($reason ne $reason2)
      {
        # Nonmatching reasons are resolved as an attr match status 8
        $return->{'status'} = 8;
        $return->{'attr'} = $self->TranslateAttr($attr);
        $return->{'reason'} = $self->TranslateReason('crms');
        $return->{'category'} = 'Attr Match';
      }
      elsif ($attr eq 'ic' && $reason eq 'ren' && $reason2 eq 'ren' &&
             !$self->TolerantCompare($data, $data2))
      {
        $return->{'status'} = 8;
        $return->{'attr'} = $self->TranslateAttr($attr);
        $return->{'reason'} = $self->TranslateReason($reason);
        $return->{'category'} = 'Attr Match';
        $return->{'note'} = 'Nonmatching renewals';
      }
    }
  }
  else
  {
    $return->{'status'} = 2;
    # Do auto for ic vs und
    # FIXME: for Commonwealth (non-renewal) projects this may need to be
    # resurrected, but for US Monographs and such we want to catch missing
    # renewal information.
    #if (($attr eq 'ic' && $attr2 eq 'und') ||
    #    ($attr eq 'und' && $attr2 eq 'ic'))
    #{
    #  # If both reviewers are non-advanced mark as provisional match
    #  if ((!$self->IsUserAdvanced($user)) && (!$self->IsUserAdvanced($user2)))
    #  {
    #     $return->{'status'} = 3;
    #  }
    #  else
    #  {
    #    $return->{'status'} = 8;
    #    $return->{'attr'} = $self->TranslateAttr('und');
    #    $return->{'reason'} = $self->TranslateReason('crms');
    #    $return->{'category'} = 'Attr Default';
    #  }
    #}
  }
  return $return;
}

sub CalcPendingStatus
{
  my $self = shift;
  my $id   = shift;

  my $n = $self->SimpleSqlGet('SELECT COUNT(*) FROM reviews WHERE id=?', $id);
  if ($n > 1)
  {
    my $data = CalcStatus($self, $id);
    return (defined $data)? $data->{'status'}:0;
  }
  return $n;
}

sub DoRightsMatch
{
  my $self    = shift;
  my $attr1   = shift;
  my $reason1 = shift;
  my $attr2   = shift;
  my $reason2 = shift;

  return 0 if $attr1 ne $attr2;
  return 0 if $attr1 eq 'pdus' && (($reason1 eq 'ncn' && $reason2 eq 'ren') || ($reason1 eq 'ren' && $reason2 eq 'ncn'));
  return 0 if $attr1 eq 'und' && (($reason1 eq 'nfi' && $reason2 eq 'ren') || ($reason1 eq 'ren' && $reason2 eq 'nfi'));
  return 1;
}

# If quiet is set, don't try to create the export file, print stuff, or send mail.
sub ClearQueueAndExport
{
  my $self  = shift;
  my $quiet = shift;

  my @export;
  my $expert = $self->GetExpertRevItems();
  push @export, $_->[0] for @{$expert};
  my $auto = $self->GetAutoResolvedItems();
  push @export, $_->[0] for @{$auto};
  my $inh = $self->GetInheritedItems();
  push @export, $_->[0] for @{$inh};
  my $double = $self->GetDoubleRevItemsInAgreement();
  push @export, $_->[0] for @{$double};
  $self->ExportReviews(\@export, $quiet);
  $self->UpdateExportStats();
  $self->UpdateDeterminationsBreakdown();
  my $msg = sprintf 'Removed from queue: %d matching, %d expert-reviewed, %d auto-resolved, %d inherited',
                    scalar @{$double}, scalar @{$expert}, scalar @{$auto}, scalar @{$inh};
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
  my $sql  = 'SELECT id FROM queue WHERE status>=5 AND status<8 AND id NOT IN'.
             ' (SELECT id FROM reviews WHERE hold=1)';
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
    $self->ReportMsg('>>> noExport system variable is set; will only export high-priority volumes.');
  }
  my $training = $self->IsTrainingArea();
  if ($training && !$quiet)
  {
    $self->ReportMsg('>>> <b>Training site detected. Will not write .rights file.</b>');
  }
  my $count = 0;
  my $user = 'crms';
  my ($fh, $temp, $perm, $filename);
  ($fh, $temp, $perm, $filename) = $self->GetExportFh() unless $training or $quiet;
  $self->ReportMsg("<i>Exporting to <code>$temp</code>.</i>") unless $training or $quiet;
  my $start_size = $self->GetCandidatesSize();
  foreach my $id (@{$list})
  {
    my ($attr, $reason) = $self->GetFinalAttrReason($id);
    my $export = $self->CanExportVolume($id, $attr, $reason, $quiet);
    if ($export && !$training && !$quiet)
    {
      print $fh "$id\t$attr\t$reason\t$user\tnull\n";
    }
    my $sql = 'SELECT status,priority,source,added_by,project,ticket FROM queue WHERE id=?';
    my $ref = $self->SelectAll($sql, $id);
    my $status = $ref->[0]->[0];
    my $pri = $ref->[0]->[1];
    my $src = $ref->[0]->[2];
    my $added_by = $ref->[0]->[3];
    my $proj = $ref->[0]->[4];
    my $tx = $ref->[0]->[5];
    $sql = 'INSERT INTO exportdata (id,attr,reason,status,priority,src,added_by,project,ticket,exported)'.
           ' VALUES (?,?,?,?,?,?,?,?,?,?)';
    $self->PrepareSubmitSql($sql, $id, $attr, $reason, $status, $pri, $src, $added_by, $proj, $tx, $export);
    my $gid = $self->SimpleSqlGet('SELECT MAX(gid) FROM exportdata WHERE id=?', $id);
    $self->MoveFromReviewsToHistoricalReviews($id, $gid);
    $self->RemoveFromQueue($id);
    $self->RemoveFromCandidates($id);
    $count++;
  }
  if (!$training && !$quiet)
  {
    close $fh;
    $self->ReportMsg("<i>Moving to <code>$perm</code>.</i>");
    rename $temp, $perm;
  }
  # Update correctness now that everything is in historical
  $self->UpdateValidation($_) for @{$list};
  if (!$training && !$quiet)
  {
    my $dels = $start_size-$self->GetCandidatesSize();
    $self->ReportMsg("After export, removed $dels volumes from candidates.");
    $self->set('export_path', $perm);
    $self->set('export_file', $filename);
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

  # Do not export anything without an attr/reason (like Frontmatter/Corrections).
  if (!defined $attr || !defined $reason ||
      $self->TranslateAttr($attr) eq $attr ||
      $self->TranslateReason($reason) eq $reason)
  {
    my $msg = sprintf "Not exporting $id because of rights %s/%s",
                      (defined $attr)? $attr:'<undef>',
                      (defined $reason)? $reason:'<undef>';
    $self->ReportMsg($msg) unless $quiet;
    return 0;
  }
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
    $self->ReportMsg("Not exporting $id; it is status 6") unless $quiet;
    return 0;
  }
  my $sql = 'SELECT p.name FROM queue q INNER JOIN projects p'.
            ' ON q.project=p.id WHERE q.id=?';
  my $project = $self->SimpleSqlGet($sql, $id);
  if (defined $gid && !defined $project)
  {
    $sql = 'SELECT p.name FROM exportdata e INNER JOIN projects p'.
           ' ON e.project=p.id WHERE e.gid=?';
    $project = $self->SimpleSqlGet($sql, $gid);
  }
  if ($self->GetSystemVar('noExport'))
  {
    if ($project eq 'Special')
    {
      $self->ReportMsg("Exporting $id; noExport is on but it is Special") unless $quiet;
      return 1;
    }
    else
    {
      $self->ReportMsg("Not exporting $id; noExport is on and it is project $project") unless $quiet;
      return 0;
    }
  }
  my $rq = $self->RightsQuery($id, 1);
  return 0 unless defined $rq;
  my ($attr2, $reason2, $src2, $usr2, $time2, $note2) = @{$rq->[0]};
  # Do not export determination if the volume has gone out of scope,
  # or if exporting und would clobber pdus in World.
  if ($reason2 ne 'bib' ||
      ($attr eq 'und' && ($attr2 eq 'pd' || $attr2 eq 'pdus')))
  {
    # But, we clobber OOS if any of the following conditions hold:
    # 1. Current rights are pdus/gfv (which per rrotter in Core Services never overrides pd/bib)
    #    and determination is not und.
    # 2. Current rights are */bib (unless a und would clobber pdus/bib).
    # 3. Project 'Special' FIXME: add "always export" flag to projects table.
    # 4. Previous rights were by user crms*.
    # 5. The determination is pd* (unless a pdus would clobber pd/bib).
    if (($reason2 eq 'gfv' && $attr ne 'und')
        || ($reason2 eq 'bib' && !($attr eq 'und' && $attr2 =~ m/^pd/))
        || $project eq 'Special'
        || $usr2 =~ m/^crms/i
        || ($attr =~ m/^pd/ && !($attr eq 'pdus' && $attr2 eq 'pd')))
    {
      # This is used for cleanup purposes
      if (defined $time)
      {
        if ($usr2 =~ m/^crms/ && $time lt $time2)
        {
          $self->ReportMsg("Not exporting $id as $attr/$reason; there is a newer CRMS export ($attr2/$reason2 by $usr2 [$time2])") unless $quiet;
          $export = 0;
        }
      }
      $self->ReportMsg("Exporting $id ($project) as $attr/$reason even though it is out of scope ($attr2/$reason2 by $usr2 [$time2])")
            unless $quiet or $export == 0;
    }
    else
    {
      $self->ReportMsg("Not exporting $id as $attr/$reason; it is out of scope ($attr2/$reason2)") unless $quiet;
      $export = 0;
    }
  }
  return $export;
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
  my $filename = 'crms_'. $date. '.rights';
  my $perm = $self->FSPath('prep', $filename);
  if ($self->WhereAmI() eq 'Production')
  {
    $perm = $self->GetSystemVar('productionRightsDirectory');
    $perm .= '/' unless substr($perm, -1) eq '/';
    $perm .= $filename;
  }
  my $temp = $perm . '.tmp';
  if (-f $temp) { die "file already exists: $temp\n"; }
  open (my $fh, '>', $temp) || die "failed to open exported file ($temp): $!\n";
  return ($fh, $temp, $perm, $filename);
}

# Remove from the queue only if the volume is untouched.
# Returns 1 if successful, undef otherwise.
sub SafeRemoveFromQueue
{
  my $self = shift;
  my $id   = shift;

  my $sql = 'SELECT COUNT(*) FROM reviews WHERE id=?';
  return undef if $self->SimpleSqlGet($sql, $id) > 0;
  $sql = 'UPDATE queue SET priority=-2 WHERE id=?'.
         ' AND project NOT IN (SELECT id FROM projects WHERE name="Special")'.
         ' AND locked IS NULL AND status=0 AND pending_status=0';
  my $return1 = $self->PrepareSubmitSql($sql, $id);
  $sql = 'DELETE FROM queue WHERE id=? AND priority=-2'.
         ' AND locked IS NULL AND status=0 AND pending_status=0';
  my $return2 = $self->PrepareSubmitSql($sql, $id);
  return ($return1 && $return2)? 1:undef;
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

  if ($self->SafeRemoveFromQueue($id))
  {
    $self->PrepareSubmitSql('DELETE FROM candidates WHERE id=?', $id);
    $self->PrepareSubmitSql('DELETE FROM und WHERE id=?', $id);
    return 1;
  }
}

# Returns number of candidates added.
sub LoadNewItemsInCandidates
{
  my $self   = shift;
  my $start  = shift;
  my $end    = shift;

  my $now = (defined $end)? $end : $self->GetTodaysDate();
  $start = $self->SimpleSqlGet('SELECT max(time) FROM candidatesrecord') unless $start;
  my $start_size = $self->GetCandidatesSize();
  $self->ReportMsg("Candidates size is $start_size, last load time was $start");
  my $sql = 'SELECT id FROM und WHERE src="no meta"';
  my $ref = $self->SelectAll($sql);
  my $n = scalar @{$ref};
  if ($n)
  {
    $self->ReportMsg("Checking $n possible no-meta additions to candidates");
    $self->CheckAndLoadItemIntoCandidates($_->[0]) for @{$ref};
    $n = $self->SimpleSqlGet('SELECT COUNT(*) FROM und WHERE src="no meta"');
    $self->ReportMsg("Number of no-meta volumes now $n.");
  }
  my $endclause = ($end)? " AND time<='$end' ":' ';
  $sql = 'SELECT namespace,id,time FROM rights_current WHERE time>?' . $endclause . 'ORDER BY time ASC';
  $ref = $self->SelectAllSDR($sql, $start);
  $n = scalar @{$ref};
  $self->ReportMsg("Checking $n possible additions to candidates from rights DB");
  foreach my $row (@{$ref})
  {
    my $id = $row->[0] . '.' . $row->[1];
    my $time = $row->[2];
    $self->CheckAndLoadItemIntoCandidates($id, $time);
  }
  my $end_size = $self->GetCandidatesSize();
  my $diff = $end_size - $start_size;
  $self->ReportMsg("After load, candidates has $end_size volumes. Added $diff.");
  # Record the update
  $sql = 'INSERT INTO candidatesrecord (time,addedamount) VALUES (?,?)';
  $self->PrepareSubmitSql($sql, $now, $diff);
  return $diff;
}

# Does all checks to see if a volume should be in the candidates or und tables, removing
# it from either table if it is already in one and no longer qualifies.
# If necessary, updates the system table with a new sysid.
sub CheckAndLoadItemIntoCandidates
{
  my $self   = shift;
  my $id     = shift;
  my $time   = shift;
  my $record = shift || $self->GetMetadata($id);

  if (!defined $record)
  {
    $self->ReportMsg("Skip $id -- no metadata to be had");
    $self->Filter($id, 'no meta');
    $self->ClearErrors();
    return;
  }
  # FIXME: in some circumstances, can project modules override the historical
  # and inheritance restrictions?
  if ($self->SimpleSqlGet('SELECT COUNT(*) FROM historicalreviews WHERE id=?', $id) > 0)
  {
    $self->ReportMsg("Skip $id -- already in historical reviews");
    return;
  }
  if ($self->SimpleSqlGet('SELECT COUNT(*) FROM inherit WHERE (status IS NULL OR status=1) AND id=?', $id) > 0)
  {
    $self->ReportMsg("Skip $id -- already inheriting");
    return;
  }
  my $incand = $self->SimpleSqlGet('SELECT id FROM candidates WHERE id=?', $id);
  my $inund  = $self->SimpleSqlGet('SELECT src FROM und WHERE id=?', $id);
  my $inq    = $self->IsVolumeInQueue($id);
  my $rq = $self->RightsQuery($id, 1);
  if (!defined $rq)
  {
    $self->ReportMsg("Can't get rights for $id, filtering.");
    $self->Filter($id, 'no meta');
    return;
  }
  my $oldSysid = $self->SimpleSqlGet('SELECT sysid FROM bibdata WHERE id=?', $id);
  if (defined $oldSysid)
  {
    $record = $self->GetMetadata($id);
    if (defined $record)
    {
      my $sysid = $record->sysid;
      if (defined $sysid && defined $oldSysid && $sysid ne $oldSysid)
      {
        $self->ReportMsg("Update system IDs from $oldSysid to $sysid");
        $self->UpdateSysids($record);
      }
    }
  }
  my $eval = $self->EvaluateCandidacy($id, $record);
  if ($eval->{'project'})
  {
    $self->AddItemToCandidates($id, $eval->{'project'}, $time, $record);
  }
  else
  {
    my $src;
    $src = $eval->{'msg'} if $eval->{'status'} eq 'filter';
    if (defined $src)
    {
      if (!defined $inund || $inund ne $src)
      {
        $self->ReportMsg(sprintf("Skip $id ($src) -- %s in filtered volumes",
                                 (defined $inund)? "updating $inund->$src":"inserting as $src"));
        $self->Filter($id, $src);
      }
      else
      {
        $self->ReportMsg("Skip $id already filtered as $src");
      }
    }
    elsif (defined $inund || defined $incand || $inq)
    {
      my @from;
      push @from, "und [$inund]" if defined $inund;
      push @from, 'candidates' if defined $incand;
      push @from, 'queue' if $inq;
      $self->ReportMsg(sprintf "Remove $id from %s\n", join ', ', @from);
      $self->RemoveFromCandidates($id);
    }
  }
}

sub AddItemToCandidates
{
  my $self   = shift;
  my $id     = shift;
  my $proj   = shift;
  my $time   = shift;
  my $record = shift || $self->GetMetadata($id);

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
      $self->ReportMsg(sprintf("Filter $id2%s as duplicate of $id%s",
                       (length $chron)? " ($chron)":'', (length $chron2)? " ($chron2)":''));
      $self->Filter($id2, 'duplicate');
    }
  }
  my $project = $self->GetProjectRef($proj)->name;
  if (!$self->IsVolumeInCandidates($id))
  {
    $self->ReportMsg(sprintf("Add $id to candidates for project '$project' ($proj)"));
    my $sql = 'INSERT INTO candidates (id,time,project) VALUES (?,?,?)';
    $self->PrepareSubmitSql($sql, $id, $time, $proj);
    $self->PrepareSubmitSql('DELETE FROM und WHERE id=?', $id);
  }
  else
  {
    my $sql = 'SELECT project FROM candidates WHERE id=?';
    my $proj2 = $self->SimpleSqlGet($sql, $id);
    if ($proj != $proj2)
    {
      $self->ReportMsg("Update $id project from $proj2 to $proj");
      my $sql = 'UPDATE candidates SET project=? WHERE id=?';
      $self->PrepareSubmitSql($sql, $proj, $id);
    }
    $sql = 'SELECT project FROM queue WHERE id=? AND source="candidates"';
    $proj2 = $self->SimpleSqlGet($sql, $id);
    if (defined $proj2 && $proj != $proj2)
    {
      $self->ReportMsg("Update $id queue project from $proj2 to $proj");
      my $sql = 'UPDATE queue SET project=? WHERE id=?';
      $self->PrepareSubmitSql($sql, $proj, $id);
    }
  }
  #if ($self->GetSystemVar('cri') && defined $self->CheckForCRI($id, $quiet))
  #{
  #  $self->ReportMsg("Filter $id as CRI") unless $quiet;
  #  $self->Filter($id, 'cross-record inheritance');
  #}
  #else
  #{
    $self->PrepareSubmitSql('DELETE FROM und WHERE id=?', $id);
  #}
  $self->UpdateMetadata($id, 1, $record);
}

# Returns the gid of the determination inheriting from, or undef if no inheritance.
# sub CheckForCRI
# {
#   my $self  = shift;
#   my $id    = shift;
#   my $quiet = shift;
#
#   my $cri = $self->get('criModule');
#   if (!defined $cri)
#   {
#     use CRI;
#     $cri = CRI->new('crms' => $self);
#     $self->set('criModule', $cri);
#   }
#   my $gid = $cri->CheckVolume($id);
#   if (defined $gid)
#   {
#     $self->ReportMsg("Adding CRI for $id ($gid)") unless $quiet;
#     my $sql = 'INSERT INTO cri (id,gid) VALUES (?,?)';
#     $self->PrepareSubmitSql($sql, $id, $gid);
#     return $gid;
#   }
#   return undef;
# }

sub Filter
{
  my $self = shift;
  my $id   = shift;
  my $src  = shift;

  return if $src eq 'duplicate' && $self->SimpleSqlGet('SELECT COUNT(*) FROM und WHERE id=?', $id);
  $self->PrepareSubmitSql('REPLACE INTO und (id,src) VALUES (?,?)', $id, $src);
  $self->PrepareSubmitSql('DELETE FROM candidates WHERE id=?', $id);
  $self->SafeRemoveFromQueue($id);
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

# Returns hashref with project EvaluateCandidacy fields, plus optional
# project id of the project that it qualified for, if any.
# Used by Add to Queue page for filtering non-overrides.
# Iterate through projects and add to candidates if the status is 'yes'.
# The last project that says "yes" gets the volume.
# If one or more projects sees fit to filter, last source is used for filter.
sub EvaluateCandidacy
{
  my $self   = shift;
  my $id     = shift;
  my $record = shift || $self->GetMetadata($id);
  my $proj   = shift; # For add to queue when specified by admin

  my $rq = $self->RightsQuery($id, 1);
  unless (defined $record && defined $rq)
  {
    $self->ClearErrors();
    return {'status' => 'filter', 'msg' => 'no meta'};
  }
  my ($attr, $reason, $src, $usr, $time, $note) = @{$rq->[0]};
  my $projects = $self->Projects();
  # Pare down projects hash to one member if it is specified.
  $projects = {$proj => $projects->{$proj}} if $proj;
  my $eval = {'status' => 'no', 'msg' => 'default CRMS::EvaluateCandidacy message'};
  my ($yesEval, $filterEval);
  foreach my $pid (sort {$a <=> $b;} keys %{$projects})
  {
    my $obj = $projects->{$pid};
    next unless $obj;
    $eval = $obj->EvaluateCandidacy($id, $record, $attr, $reason);
    if ($eval->{'status'} eq 'yes')
    {
      $yesEval = $eval;
      $yesEval->{'project'} = $pid;
    }
    elsif ($eval->{'status'} eq 'filter')
    {
      $filterEval = $eval;
      $filterEval->{'project'} = $pid;
    }
  }
  return $yesEval if defined $yesEval;
  return $filterEval if defined $filterEval;
  return $eval;
}

sub GetQueueSize
{
  my $self = shift;

  return $self->SimpleSqlGet('SELECT COUNT(*) FROM queue');
}

# Calls LoadQueueForProject() for each project in candidates.
# Does not bother to do anything for other projects.
# Updates queuerecord with the delta.
sub LoadQueue
{
  my $self = shift;

  my $before = $self->GetQueueSize();
  my $sql = 'SELECT DISTINCT project FROM candidates ORDER BY project ASC';
  $self->LoadQueueForProject($_->[0]) for @{$self->SelectAll($sql)};
  my $after = $self->SimpleSqlGet('SELECT COUNT(*) FROM queue');
  $self->UpdateQueueRecord($after - $before, 'candidates');
}

# Load candidates into queue for a given project ID.
sub LoadQueueForProject
{
  my $self    = shift;
  my $project = shift;

  my $project_name = $self->GetProjectRef($project)->name;
  my $sql = 'SELECT COUNT(*) FROM queue WHERE project=?';
  my $queueSize = $self->SimpleSqlGet($sql, $project);
  my $targetQueueSize = $self->GetProjectRef($project)->queue_size();
  my $needed = $targetQueueSize - $queueSize;
  $self->ReportMsg("Project $project_name: $queueSize volumes -- need $needed");
  return if $needed <= 0;
  my $count = 0;
  my %dels = ();
  my %seen; # Catalog IDs that have been considered
  $sql = 'SELECT id FROM candidates'.
         ' WHERE id NOT IN (SELECT DISTINCT id FROM inherit)'.
         ' AND id NOT IN (SELECT DISTINCT id FROM queue)'.
         ' AND id NOT IN (SELECT DISTINCT id FROM reviews)'.
         ' AND id NOT IN (SELECT DISTINCT id FROM historicalreviews)'.
         ' AND time<=DATE_SUB(NOW(), INTERVAL 1 WEEK) AND project=?'.
         ' ORDER BY time DESC';
  #print "$sql\n";
  my $ref = $self->SelectAll($sql, $project);
  my $potential = scalar @$ref;
  $self->ReportMsg("$potential qualifying volumes for project $project queue");
  foreach my $row (@{$ref})
  {
    my $id = $row->[0];
    next if $dels{$id};
    my $record = $self->GetMetadata($id);
    if (!defined $record)
    {
      $self->ReportMsg("Filtering $id: can't get metadata for queue");
      $self->Filter($id, 'no meta');
      next;
    }
    my $sysid = $record->sysid;
    next if $seen{$sysid};
    $seen{$sysid} = 1;
    my $ids = $record->allHTIDs;
    $self->ReportMsg(sprintf "Checking %d %s on catalog $sysid (candidate $id)",
                             scalar @$ids, $self->Pluralize('volume', scalar @$ids));
    foreach my $id2 (@$ids)
    {
      my $dup = $self->IsSameVolumeInQueue($id2, $record);
      if ($dup)
      {
        my $chron = $record->enumchron($id2) || 'no enumchron';
        my $chron2 = $record->enumchron($dup) || 'no enumchron';
        $self->ReportMsg("Filtering $id ($chron): queue has $dup ($chron2)");
        $self->Filter($id2, 'duplicate');
        next;
      }
      my $eval = $self->EvaluateCandidacy($id2, $record, $project);
      if ($eval->{'status'} eq 'filter')
      {
        my $src = $eval->{'msg'} || '<unknown src>';
        $self->ReportMsg("Filtering $id2 as $src ($sysid)");
        $self->Filter($id2, $src);
      }
      elsif ($eval->{'status'} eq 'no')
      {
        if ($self->IsVolumeInCandidates($id2))
        {
          $self->ReportMsg(sprintf("Will delete $id2: %s ($sysid)", $eval->{'msg'}));
          $dels{$id2} = 1;
        }
      }
      else
      {
        if ($self->AddItemToQueue($id2, $record, $project))
        {
          $self->ReportMsg("Added to queue: $id2 ($sysid)");
          $count++;
        }
      }
    }
    last if $count >= $needed;
  }
  # FIXME: we should give the volumes a chance to be assigned to another project instead of deleting outright.
  $self->RemoveFromCandidates($_) for keys %dels;
}

sub UpdateQueueRecord
{
  my $self  = shift;
  my $count = shift;
  my $src   = shift;

  my $sql = 'SELECT MAX(time) FROM queuerecord WHERE source=?'.
            ' AND time>=DATE_SUB(NOW(),INTERVAL 1 MINUTE)';
  my $then = $self->SimpleSqlGet($sql, $src);
  if ($then)
  {
    $sql = 'UPDATE queuerecord SET itemcount=itemcount+?,time=NOW()'.
           ' WHERE source=? AND time=? LIMIT 1';
    $self->PrepareSubmitSql($sql, $count, $src, $then);
  }
  else
  {
    $sql = 'INSERT INTO queuerecord (itemcount,source) VALUES (?,?)';
    $self->PrepareSubmitSql($sql, $count, $src);
  }
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

# Return HTID from queue if it has matching enumchron.
sub IsSameVolumeInQueue
{
  my $self = shift;
  my $id   = shift;
  my $record = shift || $self->GetMetadata($id);

  my $sql = 'SELECT q.id FROM queue q INNER JOIN bibdata b ON q.id=b.id'.
            ' WHERE q.id!=? AND b.sysid=?';
  my $ref = $self->SelectAll($sql, $id, $record->sysid);
  foreach my $row (@$ref)
  {
    my $id2 = $row->[0];
    return $id2 if $record->doEnumchronMatch($id, $id2);
  }
  return;
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
  $self->PrepareSubmitSql('INSERT INTO queue (id,project) VALUES (?,?)', $id, $project);
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
  my $record   = shift || undef;
  my $project  = shift || 1;
  my $ticket   = shift || undef;

  my $stat = 0;
  my @msgs = ();
  if ($project !~ m/^\d+$/)
  {
    my $sql = 'SELECT id FROM projects WHERE name=?';
    $project = $self->SimpleSqlGet($sql, $project) || 1;
  }
  my $oldproj = $self->SimpleSqlGet('SELECT project FROM queue WHERE id=?', $id);
  # Modify data for existing item.
  if (defined $oldproj)
  {
    my $sql = 'SELECT COUNT(*) FROM reviews WHERE id=?';
    my $n = $self->SimpleSqlGet($sql, $id);
    my $rlink = "already has $n ".
                "<a href='?p=adminReviews;search1=Identifier;search1value=$id' target='_blank'>".
                $self->Pluralize('review', $n). '</a>';
    # Not allowed to change project if there are already reviews.
    if ($oldproj != $project && $n > 0)
    {
      my $pname = $self->SimpleSqlGet('SELECT name FROM projects WHERE id=?', $oldproj);
      push @msgs, $rlink. " on project $pname";
      $stat = 1;
    }
    else
    {
      $sql = 'UPDATE queue SET priority=?,time=NOW(),source=?,'.
             'project=?,added_by=?,ticket=? WHERE id=?';
      $self->PrepareSubmitSql($sql, $priority, $src,
                              $project, $user, $ticket, $id);
      push @msgs, 'queue item updated';
      $stat = 2;
      push @msgs, $rlink if $n;
    }
  }
  else
  {
    $record = $self->GetMetadata($id) unless defined $record;
    if (!defined $record)
    {
      $self->ClearErrors();
      return {'status' => 1, 'msg' => 'HathiTrust search failed'};
    }
    my $eval = $self->EvaluateCandidacy($id, $record, $project);
    push @msgs, $eval->{'msg'} if $eval->{'msg'};
    # If there are error messages and user is not overriding it is an error.
    if ($eval->{'status'} ne 'yes' && !$override)
    {
      $stat = 1;
    }
    else
    {
      my $sql = 'INSERT INTO queue (id,priority,source,'.
                'project,added_by,ticket) VALUES (?,?,?,?,?,?)';
      $self->PrepareSubmitSql($sql, $id, $priority, $src,
                              $project, $user, $ticket);
      $self->UpdateMetadata($id, 1, $record);
      $self->UpdateQueueRecord(1, $src);
    }
  }
  my $msg = ucfirst join '; ', @msgs;
  return {'status' => $stat, 'msg' => $msg};
}

# Used by experts to approve a review made by a reviewer.
# Returns an error message.
sub CloneReview
{
  my $self = shift;
  my $id   = shift;
  my $user = shift;

  my $err = $self->LockItem($id, $user, 1);
  if ($err)
  {
    $err = "Could not approve review for $id -- lock failed ($err)";
    $self->UnlockItem($id, $user);
  }
  elsif ($self->HasItemBeenReviewedByAnotherExpert($id, $user))
  {
    $err = "Could not approve review for $id because it has already been reviewed by an expert.";
  }
  else
  {
    my $sql = 'SELECT attr,reason FROM reviews WHERE id=?';
    my $rows = $self->SelectAll($sql, $id);
    my $attr = $rows->[0]->[0];
    my $reason = $rows->[0]->[1];
    # If reasons mismatch, reason is 'crms'.
    $reason = 13 if $rows->[0]->[1] ne $rows->[1]->[1];
    my $params = {'attr' => $attr, 'reason' => $reason, 'note' => undef,
                  'category' => 'Expert Accepted', 'status' => 7};
    #$self->Note(Dumper $params);
    return $self->SubmitReview($id, $user, $params);
  }
  $self->Note("CloneReview\t$id\t$user\t". ((defined $err)? $err : ''));
  return $err;
}

sub SubmitReviewCGI
{
  my $self = shift;
  my $id   = shift;
  my $user = shift;
  my $cgi  = shift;

  my $projid = $self->GetProject($id);
  my $proj = $self->Projects()->{$projid};
  my $err = $self->ValidateSubmission($id, $user, $cgi);
  return $err if $err;
  my $json = $proj->ExtractReviewData($cgi);
  my %params = map {$_ => Encode::decode('UTF-8', $cgi->param($_));} $cgi->param;
  # Log CGI inputs for replay in case of error.
  my $jsonxs = JSON::XS->new->utf8->canonical(1)->pretty(0);
  my $encdata = $jsonxs->encode(\%params);
  $self->Note("SubmitReviewCGI\t$id\t$user\t$encdata");
  $params{'data'} = $json if defined $json;
  delete $params{'status'}; # Sanitize CGI input
  delete $params{'expert'}; # Sanitize CGI input
  $params{'data'} = $json if $json;
  return $self->SubmitReview($id, $user, \%params, $proj);
}

sub CheckReviewer
{
  my $self = shift;
  my $user = shift;

  return 1 if $user eq 'autocrms';
  my $isReviewer = $self->IsUserReviewer($user);
  my $isAdvanced = $self->IsUserAdvanced($user);
  my $isExpert = $self->IsUserExpert($user);
  return ($isReviewer || $isAdvanced || $isExpert);
}

sub ValidateSubmission
{
  my $self = shift;
  my $id   = shift;
  my $user = shift;
  my $cgi  = shift;

  ## Someone else has the item locked?
  my $lock = $self->IsLockedForOtherUser($id, $user);
  if ($lock)
  {
    my $note = sprintf "Collision for $user on %s: $id locked for $lock", $self->Hostname();
    $self->Note($note);
    return 'This item has been locked by another reviewer. Please cancel.';
  }
  if (!$self->IsVolumeInQueue($id))
  {
    return 'This volume is not in the queue. Please cancel.';
  }
  ## check user (should never happen)
  if (!$self->CheckReviewer($user))
  {
    return "$user is not a reviewer. Please cancel.";
  }
  my $incarn = $self->HasItemBeenReviewedByAnotherIncarnation($id, $user);
  if ($incarn)
  {
    return "Another expert must do this review because of a review by $incarn. Please cancel.";
  }
  my $err = $self->HasItemBeenReviewedByTwoReviewers($id, $user);
  return $err if $err;
  my $projid = $self->GetProject($id);
  my $proj = $self->Projects()->{$projid};
  return $proj->ValidateSubmission($cgi);
}

# Non-project-specific guts of review submission.
# Passes CGI params to Project to construct JSON reviewdata entry.
# Handles duration calculation and anything else that may require looking at
# existing values in the database.
# Returns an error message or undef.
sub SubmitReview
{
  my $self   = shift;
  my $id     = shift;
  my $user   = shift;
  my $params = shift;
  my $proj   = shift || $self->Projects()->{$self->GetProject($id)};

  eval {
  return 'CRMS::SubmitReview: no HTID' unless $id;
  return 'CRMS::SubmitReview: no reviewer' unless $user;
  return 'CRMS::SubmitReview: expert parameter no longer allowed' if defined $params->{'expert'};
  };
  $self->SetError("SubmitReview($id) failed: $@") if $@;
  return $@ if $@;
  my $status = $params->{'status'};
  my %dbfields = ('attr' => 1, 'reason' => 1, 'note' => 1, 'category' => 1,
                  'time' => 1, 'duration' => 1, 'swiss' => 1, 'hold' => 1, 'data' => 1);
  my @fields = ('id', 'user');
  my @values = ($id, $user);
  my ($attr, $reason, $did);
  if ($params->{'rights'})
  {
    ($attr, $reason) = $self->GetAttrReasonFromCode($params->{'rights'});
    push @fields, ('attr', 'reason');
    push @values, ($attr, $reason);
  }
  foreach my $field (keys %{$params})
  {
    my $value = $params->{$field};
    # Convert Boolean fields.
    if ($field eq 'hold' || $field eq 'swiss')
    {
      $value = ($value)? 1:0;
    }
    if ($field eq 'start')
    {
      $value = $self->SimpleSqlGet('SELECT TIMEDIFF(NOW(),?)', $value);
      my $note = "$id/$user time diff $value";
      my $sql = 'SELECT duration FROM reviews WHERE id=? AND user=?';
      my $dur2 = $self->SimpleSqlGet($sql, $id, $user);
      if (defined $dur2)
      {
        $value = $self->SimpleSqlGet('SELECT ADDTIME(?,?)', $value, $dur2);
        $note .= " with new time val $value from $dur2";
        $self->Note($note);
      }
      $field = 'duration';
    }
    if ($field eq 'data')
    {
      my $jsonxs = JSON::XS->new->utf8->canonical(1)->pretty(0);
      my $json = $jsonxs->encode($value);
      if ($json)
      {
        $did = $self->SimpleSqlGet('SELECT id FROM reviewdata WHERE data=?', $json);
        if (!$did)
        {
          $self->PrepareSubmitSql('INSERT INTO reviewdata (data) VALUES (?)', $json);
          $did = $self->SimpleSqlGet('SELECT MAX(id) FROM reviewdata WHERE data=?', $json);
        }
        $value = $did;
      }
    }
    if ($dbfields{$field} && $value)
    {
      push @fields, $field;
      push @values, $value;
    }
  }
  if ($user eq 'autocrms' || $self->IsUserExpert($user))
  {
    push @fields, 'expert';
    push @values, 1;
    if (!defined $status)
    {
      $status = $self->GetStatusForExpertReview($id, $user, $attr, $reason,
                                                $params->{'category'}, $did);
    }
  }
  #$self->Note(sprintf 'fields {%s} values {%s}', join(',', @fields), join(',', @values));
  my $wcs = $self->WildcardList(scalar @values);
  my $sql = 'REPLACE INTO reviews (' . join(',', @fields) . ') VALUES ' . $wcs;
  #printf "$sql, %s <-- %s\n", join(',', @fields), join(',', @values);
  my $result = $self->PrepareSubmitSql($sql, @values);
  return join '; ', @{$self->GetErrors()} unless $result;
  if (!defined $status || $status == 0)
  {
    $status = ($proj->single_review)? 5:0;
  }
  #$self->Note("Registering status $status");
  $self->RegisterStatus($id, $status);
  my $pstatus = $self->CalcPendingStatus($id);
  $self->RegisterPendingStatus($id, $pstatus);
  $self->UnlockItem($id, $user);
  return join '; ', @{$self->GetErrors()} if scalar @{$self->GetErrors()};
  return undef;
}

sub GetStatusForExpertReview
{
  my $self     = shift;
  my $id       = shift;
  my $user     = shift;
  my $attr     = shift;
  my $reason   = shift;
  my $category = shift;
  my $did     = shift;

  #return 6 if $category eq 'Missing' or $category eq 'Wrong Record';
  return 7 if $category eq 'Expert Accepted';
  return 9 if $category eq 'Rights Inherited';
  my $status = 5;
  # See if it's a provisional match and expert agreed with both of existing non-advanced reviews. If so, status 7.
  my $sql = 'SELECT status FROM queue WHERE id=?';
  my $s = $self->SimpleSqlGet($sql, $id);
  #printf "Status is %d\n", $s;
  if ($s && $s == 3)
  {
    $sql = 'SELECT attr,reason,data FROM reviews WHERE id=?';
    my $ref = $self->SelectAll($sql, $id);
    if (scalar @{$ref} >= 2)
    {
      my $attr1   = $ref->[0]->[0];
      my $reason1 = $ref->[0]->[1];
      my $data1   = $ref->[0]->[2];
      my $attr2   = $ref->[1]->[0];
      my $reason2 = $ref->[1]->[1];
      my $data2   = $ref->[1]->[2];
      if ($attr1 == $attr2 && $reason1 == $reason2 && $attr == $attr1 && $reason == $reason1 &&
          $self->TolerantCompare($did, $data1) && $self->TolerantCompare($data1, $data2))
      {
        $status = 7;
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

# Get project id/name from queue or exportdata.
sub GetProject
{
  my $self = shift;
  my $id   = shift;
  my $name = shift;

  my $sql = 'SELECT '. (($name)? 'p.name':'p.id').
            ' FROM queue q INNER JOIN projects p ON q.project=p.id WHERE q.id=?';
  my $proj = $self->SimpleSqlGet($sql, $id);
  unless (defined $proj)
  {
    $sql = 'SELECT '. (($name)? 'p.name':'p.id').
            ' FROM exportdata e INNER JOIN projects p ON e.project=p.id WHERE e.id=?';
    $proj = $self->SimpleSqlGet($sql, $id);
  }
  return $proj;
}

sub MoveFromReviewsToHistoricalReviews
{
  my $self = shift;
  my $id   = shift;
  my $gid  = shift;

  my $sql = 'INSERT INTO historicalreviews'.
            ' (id,time,user,attr,reason,note,data,expert,duration,legacy,'.
            '  category,swiss,gid)'.
            ' SELECT'.
            '  id,time,user,attr,reason,note,data,expert,duration,legacy,'.
            '  category,swiss,? FROM reviews WHERE id=?';
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
  #if (!$ref->[0]->[0])
  #{
  #  $self->SetError("$id not found in review table");
  #}
  my $attr   = $ref->[0]->[0];
  my $reason = $ref->[0]->[1];
  # If this is a project like frontmatter or corrections that does not generate
  # attr/reason values, then use project_name/crms as a placeholder.
  if (!defined $attr || !defined $reason)
  {
    my $proj = $self->Projects()->{$self->GetProject($id)};
    $attr = lc $proj->name;
    $reason = 'crms';
  }
  return ($attr, $reason);
}

sub RegisterStatus
{
  my $self   = shift;
  my $id     = shift;
  my $status = shift;

  my $sql = 'UPDATE queue SET status=? WHERE id=?';
  $self->PrepareSubmitSql($sql, $status, $id);
  if ($status > 0)
  {
    $sql = 'UPDATE reviews SET hold=0,time=time WHERE id=?'.
           ' AND user NOT IN (SELECT id FROM users WHERE expert=1)';
    $self->PrepareSubmitSql($sql, $id);
  }
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
  my $search = shift || '';
  my $page   = shift;
  my $order  = shift;

  my $prefix = ($page eq 'queue' || $page eq 'exportData')? 'q.':'r.';
  $prefix = 'c.' if $page eq 'candidates';
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
  elsif ($search eq 'Country') { $new_search = 'b.country'; }
  elsif ($search eq 'Priority') { $new_search = 'q.priority'; }
  elsif ($search eq 'Validated') { $new_search = 'r.validated'; }
  elsif ($search eq 'PubDate') { $new_search = 'YEAR(b.pub_date)'; }
  elsif ($search eq 'Locked') { $new_search = 'q.locked'; }
  elsif ($search eq 'ExpertCount')
  {
    $new_search = '(SELECT COUNT(*) FROM reviews r INNER JOIN users u'.
                  ' ON r.user=u.id WHERE r.id=q.id AND u.expert=1)';
  }
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
  my $offset       = shift || 0;
  my $pagesize     = shift || 0;
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
            'r.data,r.expert,r.category,r.legacy,q.priority,r.swiss,'.
            'q.status,q.project,b.title,b.author,b.country,r.hold FROM reviews r'.
            ' INNER JOIN queue q ON r.id=q.id'.
            ' INNER JOIN bibdata b ON r.id=b.id'.
            ' LEFT JOIN projects p ON q.project=p.id WHERE ';
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
  elsif ($page eq 'conflicts')
  {
    my $proj = $self->GetUserProperty($user, 'project');
    $sql .= 'q.status=2 AND q.project'. ((defined $proj)? "=$proj":' IS NULL');
  }
  elsif ($page eq 'adminHistoricalReviews')
  {
    $sql = 'SELECT r.id,DATE(r.time),r.duration,r.user,r.attr,r.reason,r.note,'.
           'r.data,r.expert,r.category,r.legacy,q.priority,r.swiss,'.
           'q.status,q.project,b.title,b.author,b.country,r.validated,q.src,q.gid'.
           ' FROM historicalreviews r'.
           ' LEFT JOIN exportdata q ON r.gid=q.gid'.
           ' LEFT JOIN bibdata b ON r.id=b.id'.
           ' LEFT JOIN projects p ON q.project=p.id WHERE r.id IS NOT NULL';
  }
  elsif ($page eq 'provisionals')
  {
    my $proj = $self->GetUserProperty($user, 'project');
    $sql .= 'q.status=3 AND q.project'. ((defined $proj)? "=$proj":' IS NULL');
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
  my $offset       = shift || 0;
  my $pagesize     = shift || 0;
  my $download     = shift;

  $dir = 'DESC' unless $dir;
  $pagesize = 20 unless $pagesize > 0;
  $offset = 0 unless $offset > 0;
  if (!$order)
  {
    $order = 'id';
    $order = 'time' if $page eq 'userReviews' or $page eq 'editReviews';
  }
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
    $doQ = 'LEFT JOIN exportdata q ON r.gid=q.gid LEFT JOIN projects p ON q.project=p.id';
  }
  else
  {
    $doQ = 'INNER JOIN queue q ON r.id=q.id';
  }
  if ($page eq 'provisionals')
  {
    push @rest, 'q.status=3';
  }
  elsif ($page eq 'conflicts')
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
  if ($page eq 'conflicts' || $page eq 'provisionals')
  {
    my $proj = $self->GetUserProperty(undef, 'project') || 1;
    push @rest, "q.project=$proj";
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
  my $offset       = shift || 0;
  my $pagesize     = shift || 0;
  my $download     = shift;

  $dir = 'DESC' unless $dir;
  $pagesize = 20 unless $pagesize > 0;
  $offset = 0 unless $offset > 0;
  if (!$order)
  {
    $order = 'id';
    $order = 'time' if $page eq 'userReviews' or $page eq 'editReviews';
  }
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
    $joins = 'exportdata q ON r.gid=q.gid LEFT JOIN bibdata b ON q.id=b.id'.
             ' LEFT JOIN projects p ON q.project=p.id';
  }
  else
  {
    $joins = 'queue q ON r.id=q.id LEFT JOIN bibdata b ON q.id=b.id';
  }
  if ($page eq 'provisionals')
  {
    push @rest, 'q.status=3';
  }
  elsif ($page eq 'conflicts')
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
  if ($page eq 'conflicts' || $page eq 'provisionals')
  {
    my $proj = $self->GetUserProperty(undef, 'project') || 1;
    push @rest, "q.project=$proj";
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
  my ($search1, $search1value, $op1, $search2, $search2value, $op2, $search3, $search3value) = map { (defined $_)? $_:'' } @_;
  my ($search1term, $search2term, $search3term) = ('', '', '');
  $op1 = 'AND' unless $op1;
  $op2 = 'AND' unless $op2;
  # Pull down search 2 if no search 1
  if (!length $search1value)
  {
    $search1 = $search2;
    $search2 = $search3;
    $search1value = $search2value;
    $search2value = $search3value;
    $search3value = $search3 = '';
  }
  # Pull down search 3 if no search 2
  if (!length $search2value)
  {
    $search2 = $search3;
    $search2value = $search3value;
    $search3value = $search3 = '';
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
  my %pref2table = ('b'=>'bibdata','r'=>$table,'q'=>'queue','p'=>'projects');
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
  my $offset       = shift || 0;
  my $pagesize     = shift || 0;

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
      my $data = $self->FormatReviewData($row->[7], $row->[14]);
      my $item = {id         => $id,
                  date       => $row->[1],
                  duration   => $row->[2],
                  user       => $row->[3],
                  attr       => $self->TranslateAttr($row->[4]),
                  reason     => $self->TranslateReason($row->[5]),
                  note       => $row->[6],
                  data       => $data,
                  expert     => $row->[8],
                  category   => $row->[9],
                  legacy     => $row->[10],
                  priority   => $self->StripDecimal($row->[11]),
                  swiss      => $row->[12],
                  status     => $row->[13],
                  project    => $row->[14],
                  title      => $row->[15],
                  author     => $row->[16],
                  country    => $row->[17],
                  hold       => $row->[18]
                 };
      if ($page eq 'adminHistoricalReviews')
      {
        my $pubdate = $self->SimpleSqlGet('SELECT YEAR(pub_date) FROM bibdata WHERE id=?', $id);
        ${$item}{'pubdate'} = $pubdate;
        ${$item}{'sysid'} = $self->SimpleSqlGet('SELECT sysid FROM bibdata WHERE id=?', $id);
        ${$item}{'validated'} = $row->[18];
        ${$item}{'src'} = $row->[19];
        ${$item}{'gid'} = $row->[20];
      }
      $sql = 'SELECT name FROM projects WHERE id=?';
      ${$item}{'project'} = $self->SimpleSqlGet($sql, $row->[14]);
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
    $sql = 'SELECT r.id,DATE(r.time),r.duration,r.user,r.attr,r.reason,r.note,r.data,'.
           'r.expert,r.category,r.legacy,q.priority,q.project,r.swiss,q.status,b.title,'.
           'b.author,YEAR(b.pub_date),b.country,b.sysid,'.
           (($page eq 'adminHistoricalReviews')? 'q.src,r.validated,q.gid':'r.hold').
           " FROM $table r $doQ LEFT JOIN bibdata b ON r.id=b.id".
           " WHERE r.id='$id' ORDER BY $order $dir";
    $sql .= ',r.time ASC' unless $order eq 'r.time';
    #print "$sql<br/>\n";
    my $ref2 = $self->SelectAll($sql);
    foreach my $row (@{$ref2})
    {
      my $data = $self->FormatReviewData($row->[7], $row->[12]);
      my $item = {id         => $row->[0],
                  date       => $row->[1],
                  duration   => $row->[2],
                  user       => $row->[3],
                  attr       => $self->TranslateAttr($row->[4]),
                  reason     => $self->TranslateReason($row->[5]),
                  note       => $row->[6],
                  data       => $data,
                  expert     => $row->[8],
                  category   => $row->[9],
                  legacy     => $row->[10],
                  priority   => $self->StripDecimal($row->[11]),
                  project    => $row->[12],
                  swiss      => $row->[13],
                  status     => $row->[14],
                  title      => $row->[15],
                  author     => $row->[16],
                  pubdate    => $row->[17],
                  country    => $row->[18],
                  sysid      => $row->[19],
                  hold       => $row->[20]
                 };
      if ($page eq 'adminHistoricalReviews')
      {
        ${$item}{'src'} = $row->[20],
        ${$item}{'validated'} = $row->[21];
        ${$item}{'gid'} = $row->[22];
      }
      $sql = 'SELECT name FROM projects WHERE id=?';
      ${$item}{'project'} = $self->SimpleSqlGet($sql, $row->[12]);
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
    $sql = 'SELECT r.id,DATE(r.time),r.duration,r.user,r.attr,r.reason,r.note,r.data,'.
           'r.expert,r.category,r.legacy,q.priority,q.project,r.swiss,q.status,b.title,'.
           'b.author,YEAR(b.pub_date),b.country,b.sysid,'.
           (($page eq 'adminHistoricalReviews')? 'q.src,r.validated,q.gid':'r.hold').
           " FROM $table r $doQ LEFT JOIN bibdata b ON r.id=b.id".
           " WHERE r.id='$id' ORDER BY $order $dir";
    $sql .= ',r.time ASC' unless $order eq 'r.time';
    #print "$sql<br/>\n";
    my $ref2 = $self->SelectAll($sql);
    foreach my $row (@{$ref2})
    {
      my $data = $self->FormatReviewData($row->[7], $row->[12]);
      my $item = {id         => $row->[0],
                  date       => $row->[1],
                  duration   => $row->[2],
                  user       => $row->[3],
                  attr       => $self->TranslateAttr($row->[4]),
                  reason     => $self->TranslateReason($row->[5]),
                  note       => $row->[6],
                  data       => $data,
                  expert     => $row->[8],
                  category   => $row->[9],
                  legacy     => $row->[10],
                  priority   => $self->StripDecimal($row->[11]),
                  project    => $row->[12],
                  swiss      => $row->[13],
                  status     => $row->[14],
                  title      => $row->[15],
                  author     => $row->[16],
                  pubdate    => $row->[17],
                  country    => $row->[18],
                  sysid      => $row->[19],
                  hold       => $row->[20]
                 };
      if ($page eq 'adminHistoricalReviews')
      {
        ${$item}{'src'} = $row->[20];
        ${$item}{'validated'} = $row->[21];
        ${$item}{'gid'} = $row->[22];
      }
      $sql = 'SELECT name FROM projects WHERE id=?';
      ${$item}{'project'} = $self->SimpleSqlGet($sql, $row->[12]);
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

sub FormatReviewData
{
  my $self = shift;
  my $did  = shift;
  my $proj = shift;

  return unless defined $did;
  my $data = $self->SimpleSqlGet('SELECT data FROM reviewdata WHERE id=?', $did);
  return unless defined $data;
  return $self->ProjectDispatch($proj, 'FormatReviewData', 0, $did, $data);
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
  my $offset       = shift || 0;
  my $pagesize     = shift || 0;
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
            ' INNER JOIN projects p ON q.project=p.id '. $restrict;
  #print "$sql<br/>\n";
  my $totalVolumes = $self->SimpleSqlGet($sql);
  $offset = $totalVolumes-($totalVolumes % $pagesize) if $offset >= $totalVolumes;
  my @return = ();
  $sql = 'SELECT q.id,DATE(q.time),q.status,q.locked,YEAR(b.pub_date),q.priority,'.
         'b.title,b.author,b.country,p.name,q.source,q.ticket,q.added_by'.
         ' FROM queue q LEFT JOIN bibdata b ON q.id=b.id'.
         ' INNER JOIN projects p ON q.project=p.id '. $restrict.
         ' ORDER BY '. "$order $dir LIMIT $offset, $pagesize";
  #print "$sql<br/>\n";
  my $ref = undef;
  eval {
    $ref = $self->SelectAll($sql);
  };
  if ($@)
  {
    $self->SetError($@);
  }
  my @columns = ('ID', 'Title', 'Author', 'Pub Date', 'Date Added', 'Status',
                 'Locked', 'Priority', 'Reviews', 'Expert Reviews',' Holds',
                 'Source', 'Added By', 'Project', 'Ticket');
  my @colnames = ('id', 'title', 'author', 'pubdate', 'date', 'status',
                  'locked', 'priority', 'reviews', 'expcnt', 'holds',
                  'source', 'added_by', 'project', 'ticket');
  my $data = join "\t", @columns;
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
    $sql = 'SELECT COUNT(*) FROM reviews r INNER JOIN users u ON r.user=u.id'.
           ' WHERE r.id=? AND u.expert=1';
    my $expcnt = $self->SimpleSqlGet($sql, $id);
    my $item = {id       => $id,
                date     => $row->[1],
                status   => $row->[2],
                locked   => $row->[3],
                pubdate  => $pubdate,
                priority => $self->StripDecimal($row->[5]),
                expcnt   => $expcnt,
                title    => $row->[6],
                author   => $row->[7],
                country  => $row->[8],
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
      $data .= "\n". join "\t", map {$item->{$_};} @colnames;
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

sub GetCandidatesRef
{
  my $self         = shift;
  my $order        = shift;
  my $dir          = shift;
  my $search1      = shift;
  my $search1Value = shift || '';
  my $op1          = shift;
  my $search2      = shift;
  my $search2Value = shift || '';
  my $startDate    = shift;
  my $endDate      = shift;
  my $offset       = shift || 0;
  my $pagesize     = shift || 0;
  my $download     = shift;

  $pagesize = 20 unless $pagesize > 0;
  $offset = 0 unless $offset > 0;
  $order = 'id' unless $order;
  $offset = 0 unless $offset;
  $search1 = $self->ConvertToSearchTerm($search1, 'candidates');
  $search2 = $self->ConvertToSearchTerm($search2, 'candidates');
  $order = $self->ConvertToSearchTerm($order, 'candidates');
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
  my $sql = 'SELECT COUNT(c.id) FROM candidates c LEFT JOIN bibdata b ON c.id=b.id'.
            ' INNER JOIN projects p ON c.project=p.id '. $restrict;
  #print "$sql<br/>\n";
  my $totalVolumes = $self->SimpleSqlGet($sql);
  $offset = $totalVolumes-($totalVolumes % $pagesize) if $offset >= $totalVolumes;
  my @return = ();
  $sql = 'SELECT c.id,DATE(c.time),b.sysid,YEAR(b.pub_date),b.title,b.author,'.
         ' b.country,p.name'.
         ' FROM candidates c LEFT JOIN bibdata b ON c.id=b.id'.
         ' INNER JOIN projects p ON c.project=p.id '. $restrict.
         ' ORDER BY '. "$order $dir LIMIT $offset, $pagesize";
  #print "$sql<br/>\n";
  my $ref = undef;
  eval {
    $ref = $self->SelectAll($sql);
  };
  if ($@)
  {
    $self->SetError($@);
  }
  my @columns = ('ID', 'Catalog ID', 'Title', 'Author', 'Pub Date', 'Country', 'Date Added', 'Project');
  my @colnames = ('id', 'sysid', 'title', 'author', 'pubdate', 'country', 'date', 'project');
  my $data = join "\t", @columns;
  foreach my $row (@{$ref})
  {
    my $id = $row->[0];
    my $item = {id       => $id,
                date     => $row->[1],
                sysid    => $row->[2],
                pubdate  => $row->[3],
                title    => $row->[4],
                author   => $row->[5],
                country  => $row->[6],
                project  => $row->[7]
               };
    push @return, $item;
    if ($download)
    {
      $data .= "\n". join "\t", map {$item->{$_};} @colnames;
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

# FIXME: could this share code with GetQueueRef()?
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
  my $offset       = shift || 0;
  my $pagesize     = shift || 0;
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
            ' INNER JOIN projects p ON q.project=p.id '. $restrict;
  #print "$sql<br/>\n";
  my $totalVolumes = $self->SimpleSqlGet($sql);
  $offset = $totalVolumes-($totalVolumes % $pagesize) if $offset >= $totalVolumes;
  my @return = ();
  $sql = 'SELECT q.id,DATE(q.time),q.attr,q.reason,q.status,q.priority,q.src,b.title,b.author,'.
         'YEAR(b.pub_date),b.country,q.exported,p.name,q.gid,q.added_by,q.ticket'.
         ' FROM exportdata q LEFT JOIN bibdata b ON q.id=b.id'.
         ' INNER JOIN projects p ON q.project=p.id'.
         " $restrict ORDER BY $order $dir LIMIT $offset, $pagesize";
  #print "$sql<br/>\n";
  my $ref = undef;
  eval { $ref = $self->SelectAll($sql); };
  if ($@)
  {
    $self->SetError($@);
  }
  my @columns = ('ID', 'Title', 'Author', 'Pub Date', 'Country', 'Date Exported', 'Rights',
                 'Status', 'Priority', 'Source', 'Added By', 'Project',
                 'Ticket', 'GID', 'Exported');
  my @colnames = ('id', 'title', 'author', 'pubdate', 'country', 'date', 'rights',
                  'status', 'priority', 'src', 'added_by', 'project',
                  'ticket', 'gid', 'exported');
  my $data = join "\t", @columns;
  foreach my $row (@{$ref})
  {
    my $id = $row->[0];
    my $pubdate = $row->[9];
    $pubdate = '?' unless $pubdate;
    my $item = {id         => $id,
                date       => $row->[1],
                attr       => $row->[2],
                reason     => $row->[3],
                rights     => $row->[2]. '/'. $row->[3],
                status     => $row->[4],
                priority   => $self->StripDecimal($row->[5]),
                src        => $row->[6],
                title      => $row->[7],
                author     => $row->[8],
                pubdate    => $pubdate,
                country    => $row->[10],
                exported   => $row->[11],
                project    => $row->[12],
                gid        => $row->[13],
                added_by   => $row->[14],
                ticket     => $row->[15],
               };
    push @return, $item;
    if ($download)
    {
      $data .= "\n". join "\t", map {$item->{$_};} @colnames;
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
  #my $syspt = $self->SimpleSqlGet('SELECT value FROM systemvars WHERE name="pt"');
  #$pt = $syspt if $syspt;
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
  my $url = $self->Sysify($self->WebPath('cgi', "crms?p=review;htid=$id;editing=1"));
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

  my $sql = 'SELECT id FROM rights WHERE attr=? AND reason=? LIMIT 1';
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
  my $note       = shift;
  my $projects   = shift;
  my $commitment = shift;
  my $disable    = shift;

  my @fields = (\$reviewer,\$advanced,\$expert,\$admin);
  ${$fields[$_]} = (length ${$fields[$_]} && !$disable)? 1:0 for (0 .. scalar @fields - 1);
  # Preserve existing privileges unless there are some checkboxes checked
  my $checked = 0;
  $checked += ${$fields[$_]} for (0 .. scalar @fields - 1);
  if ($checked == 0 && !$disable)
  {
    my $sql = 'SELECT reviewer,advanced,expert,admin FROM users WHERE id=?';
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
  if (!$self->SimpleSqlGet('SELECT COUNT(*) FROM users WHERE id=?', $id))
  {
    my $sql = 'INSERT INTO users (id,institution) VALUES (?,?)';
    $self->PrepareSubmitSql($sql, $id, $inst);
  }
  my $sql = 'UPDATE users SET name=?,kerberos=?,reviewer=?,advanced=?,'.
            'expert=?,admin=?,note=?,institution=?,commitment=? WHERE id=?';
  $self->PrepareSubmitSql($sql, $name, $kerberos, $reviewer, $advanced, $expert,
                          $admin, $note, $inst, $commitment, $id);
  $self->Note($_) for @{$self->GetErrors()};
  if (defined $projects && scalar @{$projects})
  {
    $self->PrepareSubmitSql('DELETE FROM projectusers WHERE user=?', $id);
    $sql = 'INSERT INTO projectusers (user,project) VALUES (?,?)';
    foreach my $proj (@{$projects})
    {
      $proj = undef unless int $proj;
      next unless defined $proj;
      $self->PrepareSubmitSql($sql, $id, $proj);
    }
  }
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
  my $instance = $self->get('instance') || '';
  if ($instance ne 'production' && $instance ne 'crms-training')
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

  my $sql = 'SELECT (expert OR admin) FROM users WHERE id=?';
  return $self->SimpleSqlGet($sql, $user);
}

sub IsUserAdmin
{
  my $self = shift;
  my $user = shift || $self->get('user');

  my $sql = 'SELECT admin FROM users WHERE id=?';
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
  my $ord  = shift || 0;

  my @users;
  my $order = '(u.reviewer+u.advanced+u.admin > 0) DESC';
  $order .= ',u.expert ASC' if $ord == 1;
  $order .= ',i.shortname ASC' if $ord == 2;
  $order .= ',(u.reviewer+(2*u.advanced)+(4*u.expert)'.
            '+(8*u.admin)) DESC' if $ord == 3;
  $order .= ',u.commitment DESC' if $ord == 4;
  $order .= ',u.name ASC';
  my $sql = 'SELECT u.id,u.name,u.reviewer,u.advanced,u.expert,u.admin,u.kerberos,'.
            'u.note,i.shortname,u.commitment'.
            ' FROM users u INNER JOIN institutions i'.
            ' ON u.institution=i.id ORDER BY ' . $order;
  my $ref = $self->SelectAll($sql);
  foreach my $row (@{$ref})
  {
    my $id = $row->[0];
    my $commitment = $row->[9];
    my $expiration = $self->IsUserExpired($id);
    my $progress = 0.0;
    my $commitmentFmt = '';
    if ($commitment)
    {
      $sql = 'SELECT s.total_time/60.0 FROM userstats s'.
             ' WHERE s.monthyear=DATE_FORMAT(NOW(),"%Y-%m") AND s.user=?';
      my $hours = $self->SimpleSqlGet($sql, $id);
      $sql = 'SELECT COALESCE(SUM(TIME_TO_SEC(duration)),0)/3600.0 from reviews'.
             ' WHERE user=?';
      $hours += $self->SimpleSqlGet($sql, $id);
      $progress = $hours/(160.0*$commitment) ;
      $progress = 0.0 if $progress < 0.0;
      $progress = 1.0 if $progress > 1.0;
      $commitmentFmt = (100.0 *$row->[9]). '%';
    }
    $sql = 'SELECT COUNT(*) FROM users WHERE ? REGEXP CONCAT(id,".+")';
    my $secondary = $self->SimpleSqlGet($sql, $id);
    push @users, {'id' => $id, 'name' => $row->[1], 'reviewer' => $row->[2],
                  'advanced' => $row->[3], 'expert' => $row->[4], 'admin' => $row->[5],
                  'kerberos' => $row->[6], 'note' => $row->[7],
                  'institution' => $row->[8], 'commitment' => $commitment,
                  'commitmentFmt' => $commitmentFmt, 'progress' => $progress,
                  'expiration' => $expiration, 'ips' => $self->GetUserIPs($id),
                  'role' => $self->GetUserRole($id), 'secondary' => $secondary};
  }
  return \@users;
}

sub IsUserIncarnationExpertOrHigher
{
  my $self = shift;
  my $user = shift || $self->get('user');

  my $sql = 'SELECT COALESCE(MAX(expert+admin),0) FROM users WHERE kerberos!=""' .
            ' AND kerberos IN (SELECT DISTINCT kerberos FROM users WHERE id=?)';
  return 0 < $self->SimpleSqlGet($sql, $user);
}

sub GetInstitutions
{
  my $self  = shift;
  my $order = shift || 'id';

  my @insts = ();
  my %ords = ('id' => 1, 'name' => 1, 'shortname' => 1);
  $order = 'id' unless defined $ords{$order};
  my $sql = 'SELECT i.id,i.name,i.shortname,i.suffix,'.
            '(SELECT COUNT(*) FROM users WHERE institution=i.id),'.
            '(SELECT COUNT(*) FROM users WHERE institution=i.id AND reviewer+advanced+expert+admin>0)'.
            ' FROM institutions i ORDER BY '. $order;
  my $ref = $self->SelectAll($sql);
  foreach my $row (@{$ref})
  {
    push @insts, {'id' => $row->[0], 'name' => $row->[1],
                  'shortname' => $row->[2], 'suffix' => $row->[3],
                  'users' => $row->[4], 'active' => $row->[5]};
  }
  return \@insts;
}

# If $id is blank then add a new institution.
# Otherwise update an existing one.
# Returns hashref with error field set if problem.
# If added, id field is set to the new id.
sub AddInstitution
{
  my $self       = shift;
  my $id         = shift;
  my $name       = shift;
  my $shortname  = shift;
  my $suffix     = shift;

  my %res;
  # Remove surrounding whitespace on submitted fields.
  $id =~ s/^\s*(.+?)\s*$/$1/;
  $name =~ s/^\s*(.+?)\s*$/$1/;
  $shortname =~ s/^\s*(.+?)\s*$/$1/;
  $suffix =~ s/^\s*(.+?)\s*$/$1/;
  $res{'id'} = $id;
  if ($id)
  {
    my $sql = 'SELECT COUNT(*) FROM institutions WHERE id=?';
    if ($self->SimpleSqlGet($sql, $id))
    {
      $name = $self->SimpleSqlGet('SELECT name FROM institutions WHERE id=?', $id) unless $name;
      $shortname = $self->SimpleSqlGet('SELECT shortname FROM institutions WHERE id=?', $id) unless $shortname;
      $suffix = $self->SimpleSqlGet('SELECT suffix FROM institutions WHERE id=?', $id) unless $suffix;
      $sql = 'UPDATE institutions SET name=?,shortname=?,suffix=? WHERE id=?';
      $self->PrepareSubmitSql($sql, $name, $shortname, $suffix, $id);
    }
    else
    {
      $res{'error'} = "unknown Institution ID '$id'";
    }
  }
  else
  {
    $res{'error'} = 'Institution e-mail suffix required' unless $suffix;
    $res{'error'} = 'Institution short name required' unless $shortname;
    $res{'error'} = 'Institution name required' unless $name;
    if (!$res{'error'})
    {
      my $sql = 'INSERT INTO institutions (name,shortname,suffix) VALUES (?,?,?)';
      $self->PrepareSubmitSql($sql, $name, $shortname, $suffix);
      $sql = 'SELECT id FROM institutions WHERE name=?'.
             ' AND shortname=? AND suffix=? ORDER BY id DESC LIMIT 1';
      $res{'id'} = $self->SimpleSqlGet($sql, $name, $shortname, $suffix);
    }
  }
  return \%res;
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
    $user = $user->{'id'};
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
  $report .= ('<tr>' . join('', map {my $tmp = $_; $tmp =~ s/\s/&nbsp;/g; "<th>$tmp</th>";} split("\t", $titles)) . '</tr>');
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

sub GetUserStatsYears
{
  my $self = shift;
  my $user = shift;

  use UserStats;
  return UserStats::GetUserStatsYears($self, $user);
}

sub GetUserStatsQueryParams
{
  my $self    = shift;
  my $user    = shift;
  my $year    = shift;
  my $project = shift;

  use UserStats;
  return UserStats::GetUserStatsQueryParams($self, $user, $year, $project);
}

sub CreateUserStatsReport
{
  my $self    = shift;
  my $user    = shift;
  my $year    = shift;
  my $project = shift;
  my $active  = shift;

  use UserStats;
  return UserStats::CreateUserStatsReport($self, $user, $year, $project, $active);
}

# Returns an array ref of hash refs
# Each hash has keys 'id', 'name', 'active'
# Array is sorted alphabetically with inactive reviewers last.
sub GetInstitutionReviewers
{
  my $self = shift;
  my $inst = shift;

  my @revs;
  my $sql = 'SELECT id,name,reviewer+advanced+expert+admin as active,COALESCE(commitment,0)'.
            ' FROM users WHERE institution=?'.
            #' AND (reviewer+advanced+expert>0 OR reviewer+advanced+expert+admin=0)'.
            ' ORDER BY active DESC,name';
  my $ref = $self->SelectAll($sql, $inst);
  foreach my $row (@{$ref})
  {
    my $id = $row->[0];
    my $name = $row->[1];
    my $active = ($row->[2] > 0)? 1:0;
    #next if $name =~ m/\(|\)/;
    push @revs, {'id'=>$id, 'name'=>$name, 'active'=>$active, 'commitment'=>$row->[3]};
  }
  @revs = sort {$b->{'active'} <=> $a->{'active'}
                || $b->{'commitment'} <=> $a->{'commitment'}
                || $a->{'name'} cmp $b->{'name'};} @revs;
  return \@revs;
}

sub UpdateUserStats
{
  my $self  = shift;
  my $quiet = shift;

  # Get the underlying system status, ignoring replication delays.
  my $stat = $self->GetSystemStatus(1);
  my $tmpstat = ['', $stat->[1],
                 'CRMS is updating user stats, so they may not display correctly. '.
                 'This usually takes five minutes or so to complete.'];
  $self->SetSystemStatus($tmpstat);
  my $sql = 'DELETE from userstats';
  $self->PrepareSubmitSql($sql);
  my $users = $self->GetUsers();
  foreach my $user (@{$users})
  {
    $user = $user->{'id'};
    $sql = 'SELECT DISTINCT DATE_FORMAT(r.time,"%Y-%m") AS ym,e.project'.
           ' FROM historicalreviews r INNER JOIN exportdata e ON r.gid=e.gid'.
           ' WHERE r.legacy!=1 AND r.user=? ORDER BY ym ASC';
    my $ref = $self->SelectAll($sql, $user);
    foreach my $row (@{$ref})
    {
      my ($y,$m) = split '-', $row->[0];
      my $proj = $row->[1];
      #$self->ReportMsg("Doing stats for $user $y-$m, project $proj") unless $quiet;
      $self->GetMonthStats($user, $y, $m, $proj);
    }
  }
  $self->ReportMsg(sprintf "Setting system status back to '%s'", $stat->[1]) unless $quiet;
  $self->SetSystemStatus($stat);
}

sub GetMonthStats
{
  my $self = shift;
  my $user = shift;
  my $y    = shift;
  my $m    = shift;
  my $proj = shift;

  my $lastDay = Days_in_Month($y, $m);
  my $start = "$y-$m-01 00:00:00";
  my $end = "$y-$m-$lastDay 23:59:59";
  my $sql = 'SELECT COUNT(*) FROM historicalreviews r INNER JOIN exportdata e'.
            ' ON r.gid=e.gid WHERE r.user=? AND r.legacy!=1'.
            ' AND r.time>=? AND r.time<=? AND e.project=?';
  my $total_reviews = $self->SimpleSqlGet($sql, $user, $start, $end, $proj);
  #pd/pdus
  $sql = 'SELECT COUNT(*) FROM historicalreviews r INNER JOIN exportdata e'.
         ' ON r.gid=e.gid WHERE r.user=? AND r.legacy!=1'.
         ' AND r.time>=? AND r.time<=? AND e.project=?'.
         ' AND (r.attr=1 OR r.attr=9)';
  my $total_pd = $self->SimpleSqlGet($sql, $user, $start, $end, $proj);
  #ic/icus
  $sql = 'SELECT COUNT(*) FROM historicalreviews r INNER JOIN exportdata e'.
         ' ON r.gid=e.gid WHERE r.user=? AND r.legacy!=1'.
         ' AND r.time>=? AND r.time<=? AND e.project=?'.
         ' AND (r.attr=2 || r.attr=19)';
  my $total_ic = $self->SimpleSqlGet($sql, $user, $start, $end, $proj);
  #und
  $sql = 'SELECT COUNT(*) FROM historicalreviews r INNER JOIN exportdata e'.
         ' ON r.gid=e.gid WHERE r.user=? AND r.legacy!=1'.
         ' AND r.time>=? AND r.time<=? AND e.project=?'.
         ' AND r.attr=5';
  my $total_und = $self->SimpleSqlGet($sql, $user, $start, $end, $proj);
  # time reviewing (in minutes) - not including outliers
  # default outlier seconds is 300 (5 min)
  my $outSec = $self->Projects()->{$proj}->OutlierSeconds();
  #my $outSec = $self->GetSystemVar('outlierSeconds', 300);
  $sql = 'SELECT COALESCE(SUM(TIME_TO_SEC(r.duration)),0)/60.0'.
         ' FROM historicalreviews r INNER JOIN exportdata e ON r.gid=e.gid'.
         ' WHERE r.user=? AND r.legacy!=1 AND r.time>=? AND r.time<=?'.
         ' AND e.project=? AND TIME(r.duration)<=SEC_TO_TIME(?)';

  my $total_time = $self->SimpleSqlGet($sql, $user, $start, $end, $proj, $outSec);
  # Total outliers
  $sql = 'SELECT COUNT(*) FROM historicalreviews r INNER JOIN exportdata e'.
         ' ON r.gid=e.gid WHERE r.user=? AND r.legacy!=1'.
         ' AND r.time>=? AND r.time<=? AND e.project=?'.
         ' AND TIME(r.duration)>SEC_TO_TIME(?)';
  my $total_outliers = $self->SimpleSqlGet($sql, $user, $start, $end, $proj, $outSec);
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
  my ($total_correct,$total_incorrect,$total_neutral,$total_flagged) = $self->CountCorrectReviews($user, $start, $end, $proj);
  $sql = 'INSERT INTO userstats (user,month,year,monthyear,project,'.
         'total_reviews,total_pd,total_ic,total_und,total_time,time_per_review,'.
         'reviews_per_hour,total_outliers,total_correct,total_incorrect,'.
         'total_neutral,total_flagged) VALUES ' . $self->WildcardList(17);
  $self->PrepareSubmitSql($sql, $user, $m, $y, $y. '-'. $m, $proj, $total_reviews,
                          $total_pd, $total_ic, $total_und, $total_time,
                          $time_per_review, $reviews_per_hour, $total_outliers,
                          $total_correct, $total_incorrect, $total_neutral,
                          $total_flagged);
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
    if ($self->HasItemBeenReviewedByAnotherExpert($id, $user))
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
      my $note = sprintf "Collision for $user on %s: $id has $count reviews", $self->Hostname();
      $self->Note($note);
    }
    $sql = 'SELECT COUNT(*) FROM queue WHERE id=? AND status!=0';
    $count = $self->SimpleSqlGet($sql, $id);
    if ($count >= 1) { $msg = 'This item has been processed already. Please Cancel.'; }
  }
  return $msg;
}

sub GetTitle
{
  my $self = shift;
  my $id   = shift;

  my $ti = $self->SimpleSqlGet('SELECT title FROM bibdata WHERE id=?', $id);
  if (!defined $ti)
  {
    $self->UpdateMetadata($id);
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
  if (!defined $date)
  {
    $record = $self->UpdateMetadata($id, undef, $record);
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
  return $record->formatPubDate() if defined $record;
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
    $self->UpdateMetadata($id);
    $where = $self->SimpleSqlGet($sql, $id);
  }
  return $where;
}

sub GetAuthor
{
  my $self = shift;
  my $id   = shift;

  my $au = $self->SimpleSqlGet('SELECT author FROM bibdata WHERE id=?', $id);
  if (!defined $au)
  {
    $self->UpdateMetadata($id);
    $au = $self->SimpleSqlGet('SELECT author FROM bibdata WHERE id=?', $id);
  }
  #$au =~ s,(.*[A-Za-z]).*,$1,;
  $au =~ s/^[([{]+(.*?)[)\]}]+\s*$/$1/ if $au;
  return $au;
}

sub GetMetadata
{
  my $self = shift;
  my $id   = shift;

  use Metadata;
  $self->get($id) || Metadata->new('id' => $id, 'crms' => $self);
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
  # Force parameter should only be used when something is to be further worked on,
  # like when adding to queue.
  return if $self->SimpleSqlGet('SELECT COUNT(*) FROM historicalreviews WHERE id=?', $id) and
            !$self->SimpleSqlGet('SELECT COUNT(*) FROM queue WHERE id=?', $id) and
            !$force;
  my $cnt = $self->SimpleSqlGet('SELECT COUNT(*) FROM bibdata WHERE id=?', $id);
  if ($cnt == 0 || $force)
  {
    $record = $self->GetMetadata($id) unless defined $record;
    if (defined $record)
    {
      my $date = $record->copyrightDate;
      $date .= '-01-01' if $date;
      my $sql = 'REPLACE INTO bibdata (id,author,title,pub_date,country,sysid)' .
                ' VALUES (?,?,?,?,?,?)';
      $self->PrepareSubmitSql($sql, $id, $record->author, $record->title,
                              $date, $record->country, $record->sysid);
    }
    else
    {
      $self->SetError('Could not get metadata for ' . $id);
    }
  }
  return $record;
}

# Returns a hashref with the following fields:
# queue -> hashref of all fields in queue entry
# reviews -> hashref of user -> hashref of review fields
# bibdata -> hashref of all fields in bibdata entry
#            with <field>_format the HTML-escaped version
# JSON -> stringified version of the return value without a self-reference
sub ReviewData
{
  my $self  = shift;
  my $id    = shift;

  require Languages;
  my $jsonxs = JSON::XS->new->canonical(1)->pretty(0);
  my $record = $self->GetMetadata($id);
  my $data = {};
  my $dbh = $self->GetDb();
  my $sql = 'SELECT * FROM queue WHERE id=?';
  my $ref = $dbh->selectall_hashref($sql, 'id', undef, $id);
  $data->{'queue'} = $ref->{$id};
  $data->{'queue'}->{'priority_format'} = $self->StripDecimal($data->{'queue'}->{'priority'});
  $sql = 'SELECT * FROM bibdata WHERE id=?';
  $ref = $dbh->selectall_hashref($sql, 'id', undef, $id);
  $data->{'bibdata'} = $ref->{$id};
  $data->{'bibdata'}->{$_. '_format'} = CGI::escapeHTML($data->{'bibdata'}->{$_}) for keys %{$data->{'bibdata'}};
  $data->{'bibdata'}->{'pub_date_format'} = $self->FormatPubDate($id, $record);
  $data->{'bibdata'}->{'language'} = Languages::TranslateLanguage($record->language);
  $sql = 'SELECT * FROM reviews WHERE id=?';
  $ref = $dbh->selectall_hashref($sql, 'user', undef, $id);
  foreach my $user (keys %{$ref})
  {
    $ref->{$user}->{'rights'} = $self->GetCodeFromAttrReason($ref->{$user}->{'attr'},
                                                             $ref->{$user}->{'reason'});
    $ref->{$user}->{'attr'} = $self->TranslateAttr($ref->{$user}->{'attr'});
    $ref->{$user}->{'reason'} = $self->TranslateReason($ref->{$user}->{'reason'});
    if ($ref->{$user}->{'data'})
    {
      $sql = 'SELECT data FROM reviewdata WHERE id=?';
      my $encdata = $self->SimpleSqlGet($sql, $ref->{$user}->{'data'});
      $ref->{$user}->{'data'} = $jsonxs->decode($encdata);
    }
  }
  $data->{'reviews'} = $ref;
  $data->{'json'} = $jsonxs->encode($data);
  $data->{'project'} = $self->Projects()->{$data->{'queue'}->{'project'}};
  return $data;
}

sub HasLockedItem
{
  my $self = shift;
  my $user = shift || $self->get('user');

  my $sql = 'SELECT COUNT(*) FROM queue WHERE locked=?';
  return $self->SimpleSqlGet($sql, $user);
}

sub GetLockedItem
{
  my $self = shift;
  my $user = shift || $self->get('user');

  my $sql = 'SELECT id FROM queue WHERE locked=?';
  $sql .= ' LIMIT 1';
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
  my $user = shift || $self->get('user');

  my $sql = 'SELECT COUNT(*) FROM queue WHERE id=? AND locked=?';
  return 1 == $self->SimpleSqlGet($sql, $id, $user);
}

sub IsLockedForOtherUser
{
  my $self = shift;
  my $id   = shift;
  my $user = shift || $self->get('user');

  my $sql = 'SELECT COUNT(*) FROM queue WHERE id=?'.
            ' AND locked IS NOT NULL AND locked!=?';
  return $self->SimpleSqlGet($sql, $id, $user);
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
    my $sql = 'SELECT id FROM queue WHERE id=? AND time<?';
    my $old = $self->SimpleSqlGet($sql, $id, $time);
    $self->UnlockItem($id, $user) if $old;
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

# Returns undef on success, error message on error.
sub LockItem
{
  my $self     = shift;
  my $id       = shift;
  my $user     = shift || $self->get('user');
  my $override = shift;

  ## if already locked for this user, that's OK
  return if $self->IsLockedForUser($id, $user);
  # Not locked for user, maybe someone else
  if ($self->IsLocked($id))
  {
    return 'Volume has been locked by another user';
  }
  ## can only have 1 item locked at a time (unless override)
  if (!$override)
  {
    my $locked = $self->GetLockedItem($user);
    if (defined $locked)
    {
      return if $locked eq $id;
      return "You already have a locked item ($locked).";
    }
  }
  my $sql = 'UPDATE queue SET locked=? WHERE id=?';
  return ($self->PrepareSubmitSql($sql, $user, $id))? undef:'SQL error submitting lock';
}

sub UnlockItem
{
  my $self = shift;
  my $id   = shift;
  my $user = shift || $self->get('user');

  my $sql = 'UPDATE queue SET locked=NULL WHERE id=? AND locked=?';
  $self->PrepareSubmitSql($sql, $id, $user);
}

sub UnlockAllItemsForUser
{
  my $self = shift;
  my $user = shift || $self->get('user');

  $self->PrepareSubmitSql('UPDATE queue SET locked=NULL WHERE locked=?', $user);
}

sub GetLockedItems
{
  my $self = shift;
  my $user = shift || $self->get('user');

  my $restrict = ($user)? "='$user'":'IS NOT NULL';
  my $sql = 'SELECT id, locked FROM queue WHERE locked ' . $restrict;
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

sub ReviewPartialsForProject
{
  my $self = shift;
  my $proj = shift;

  return $self->ProjectDispatch($proj, 'ReviewPartials');
}

sub ProjectDispatch
{
  my $self    = shift;
  my $proj    = shift;
  my $sub     = shift;
  my $default = shift;

  $self->SetError('ProjectDispatch() needs explicit project') unless $proj;
  $self->SetError('ProjectDispatch() should not take default') if $default;
  my $mod = $self->Projects()->{$proj};
  if (defined $mod && $mod->can($sub))
  {
    return $mod->$sub(@_);
  }
  elsif ($default)
  {
    return $self->$sub(@_);
  }
  else
  {
    $self->SetError("Unable to call sub $sub on module $mod");
    return undef;
  }
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
  my $sql = undef;
  eval {
    my $proj = $self->GetUserCurrentProject($user);
    my $project_ref = $self->GetProjectRef($proj);
    my @params = ($user, $proj);
    my @orders = ('q.priority DESC', 'cnt DESC', 'hash', 'q.time ASC');
    my $sysid;
    if ($project_ref->group_volumes && $self->IsUserAdvanced($user))
    {
      $sql = 'SELECT b.sysid FROM reviews r INNER JOIN bibdata b ON r.id=b.id'.
             ' WHERE r.user=? AND hold=0 ORDER BY r.time DESC LIMIT 1';
      $sysid = $self->SimpleSqlGet($sql, $user);
    }
    my $porder = $project_ref->PresentationOrder();
    my ($excludeh, $excludei) = ('', '');
    my $inc = $self->GetUserIncarnations($user);
    my $wc = $self->WildcardList(scalar @{$inc});
    $excludei = ' AND NOT EXISTS (SELECT * FROM reviews r2 WHERE r2.id=q.id AND r2.user IN '. $wc. ')';
    push @params, @{$inc};
    if (!$self->IsUserExpert($user))
    {
      $excludeh = ' AND NOT EXISTS (SELECT * FROM historicalreviews r3 WHERE r3.id=q.id AND r3.user IN '. $wc. ')';
      push @params, @{$inc};
    }
    if (defined $porder)
    {
      unshift @orders, $porder;
    }
    if (defined $sysid)
    {
      # First order, last param (assumes any order param will be last).
      # Adding any additional parameterized ordering will be trickier.
      unshift @orders, 'IF(b.sysid=?,1,0) DESC,q.id ASC';
      push @params, $sysid;
    }
    $sql = 'SELECT q.id,(SELECT COUNT(*) FROM reviews r WHERE r.id=q.id) AS cnt,'.
           'SHA2(CONCAT(?,q.id),0) AS hash,q.priority,q.project,b.sysid'.
           ' FROM queue q INNER JOIN bibdata b ON q.id=b.id'.
           ' WHERE q.project=? AND q.locked IS NULL AND q.status<2'.
           ' AND q.unavailable=0'.
           $excludei. $excludeh.
           ' HAVING cnt<2 ORDER BY '. join ',', @orders;
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
      $proj = $row->[4];
      my $sysid = $row->[5];
      if (defined $test)
      {
        printf "  $id2 ($sysid) [%s] %s ($cnt, %s...) (P %s Proj %s)\n",
               $self->GetAuthor($id2) || '', $self->GetTitle($id2) || '',
               uc substr($hash, 0, 8), $pri, $proj;
        $id = $id2 unless defined $id;
      }
      else
      {
        my $err;
        my $record = $self->GetMetadata($id2);
        $self->ClearErrors();
        if (!$record)
        {
          $err = 'No Record Found';
          $sql = 'UPDATE queue SET unavailable=1 WHERE id=?';
          $self->PrepareSubmitSql($sql, $id2);
          $self->Note("No record found for $id2, setting unavailable.");
        }
        else
        {
          $self->set($id2, $record);
          $err = $self->LockItem($id2, $user);
        }
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

# Called as part of overnight processing,
# Iterates through anything that was downgraded to unavailable by the
# queueing algorithm, restoring availability if metadata fetch succeeds.
sub UpdateQueueNoMeta
{
  my $self = shift;

  my $sql = 'SELECT id FROM queue WHERE unavailable=1';
  my $ref = $self->SelectAll($sql);
  foreach my $row (@{$ref})
  {
    my $id = $row->[0];
    my $record = $self->GetMetadata($id);
    if (defined $record)
    {
      $sql = 'UPDATE queue SET unavailable=0 WHERE id=?';
      $self->PrepareSubmitSql($sql, $id);
    }
    else
    {
      $self->ReportMsg("<b>$id</b>: still no meta, leaving unavailable");
    }
  }
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

  $id =~ s/ //gs;
  my $sql = 'SELECT DREG FROM stanford WHERE ID=?';
  my $date = $self->SimpleSqlGet($sql, $id);
  if (!$date)
  {
    $sql = 'SELECT DATE_FORMAT(renewal_date,"%e%b%y") FROM renewals WHERE renewal_id=?';
    $date = $self->SimpleSqlGet($sql, $id);
  }
  return $date;
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

sub ReportMsg
{
  my $self = shift;
  my $msg  = shift;
  my $ts   = shift;

  my $messages = $self->get('messages');
  if (defined $messages)
  {
    $msg = sprintf('<i>%s:</i> %s', scalar (localtime(time())), $msg) if $ts;
    $messages .= "$msg<br/>\n";
    $self->set('messages', $messages);
  }
  else
  {
    print $msg. "\n";
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
  if ($self->get('die'))
  {
    die $error;
  }
  my $errorh = $self->get('errorh');
  if (!$errorh->{$error})
  {
    my $errors = $self->get('errors');
    push @{$errors}, $error;
    $errorh->{$error} = 1;
  }
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

  $self->set('errors', []);
  $self->set('errorh', {});
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
  my $proj = shift;

  my $field = ($proj)? 'p.name':'q.priority';
  my $sql = 'SELECT DISTINCT '. $field. ' FROM queue q'.
            ' INNER JOIN projects p ON q.project=p.id'.
            ' ORDER BY '. $field. ' ASC';
  my @pris = map {$self->StripDecimal($_->[0])} @{$self->SelectAll($sql)};
  my @headers = map {"<th>Priority $_</th>";} @pris;
  @headers = map {"<th>$_</th>";} @pris if $proj;
  s/\s/&nbsp;/g for @headers;
  my $report = '<table class="exportStats">'.
               '<tr><th>Status</th><th>Total</th>'.
               (join '', @headers). "</tr>\n";
  foreach my $status (-1 .. 9)
  {
    my $statusClause = ($status == -1)? '':"WHERE STATUS=$status";
    $status = 'All' if $status == -1;
    my $class = ($status eq 'All')?' class="total"':'';
    $sql = 'SELECT '. $field. ',COUNT(*) FROM queue q'.
           ' INNER JOIN projects p ON q.project=p.id '. $statusClause.
           ' GROUP BY '. $field. ' ASC WITH ROLLUP';
    my $ref = $self->SelectAll($sql);
    my $count = (scalar @{$ref})? $ref->[-1]->[1]:0;
    $report .= sprintf("<tr><td%s>$status</td><td%s>$count</td>", $class, $class);
    $report .= $self->DoPriorityBreakdown($ref, $class, \@pris);
    $report .= "</tr>\n";
  }
  $sql = 'SELECT '. $field. ',COUNT(q.id) FROM queue q'.
         ' INNER JOIN projects p ON q.project=p.id'.
         ' WHERE q.status=0'.
         ' AND q.pending_status=0 GROUP BY '. $field. ' ASC WITH ROLLUP';
  my $ref = $self->SelectAll($sql);
  my $count = (scalar @{$ref})? $ref->[-1]->[1]:0;
  my $class = ' class="major"';
  $report .= sprintf("<tr><td%s>Not&nbsp;Yet&nbsp;Active</td><td%s>$count</td>", $class, $class);
  $report .= $self->DoPriorityBreakdown($ref, $class, \@pris);
  $report .= "</tr>\n";
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
  $count = $self->SimpleSqlGet($sql);
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
  my $proj = shift;

  my ($count,$time) = $self->GetLastExport();
  my %cts = ();
  my %pcts = ();
  my $field = ($proj)? 'p.name':'e.priority';
  my $sql = 'SELECT DISTINCT '. $field. ' FROM exportdata e'.
            ' INNER JOIN projects p ON e.project=p.id'.
            ' WHERE DATE(time)=DATE(?) ORDER BY '. $field. ' ASC';
  my @pris = map {$self->StripDecimal($_->[0])} @{$self->SelectAll($sql, $time)};
  my @headers = map {"<th>Priority $_</th>";} @pris;
  @headers = map {"<th>$_</th>";} @pris if $proj;
  s/\s/&nbsp;/g for @headers;
  $sql = 'SELECT COUNT(gid) FROM exportdata'.
         ' WHERE DATE(time)=DATE(?) ORDER BY priority ASC';
  my $total = $self->SimpleSqlGet($sql, $time);
  my $priheaders = join '', map {"<th>Priority&nbsp;$_</th>";} @pris;
  my $report = '<table class="exportStats">'.
               '<tr><th></th><th>Total</th>'.
               (join '', @headers).
               "</tr>\n";
  foreach my $status (4 .. 9)
  {
    $sql = 'SELECT COUNT(*) FROM exportdata e'.
           ' INNER JOIN projects p ON e.project=p.id'.
           ' WHERE e.status=? AND DATE(e.time)=DATE(?)';
    my $ct = $self->SimpleSqlGet($sql, $status, $time);
    my $pct = 0.0;
    eval {$pct = 100.0*$ct/$total;};
    $cts{$status} = $ct;
    $pcts{$status} = $pct;
  }
  my $colspan = 1 + scalar @pris;
  my ($count2,$time2) = $self->GetLastExport(1);
  $time2 =~ s/\s/&nbsp;/g;
  $count = 'None' unless $count;
  my $exported = $self->SimpleSqlGet('SELECT COUNT(gid) FROM exportdata');
  $report .= "<tr><th>Last&nbsp;CRMS&nbsp;Export</th><td colspan='$colspan'>$time2</td></tr>";
  foreach my $status (sort keys %cts)
  {
    $report .= sprintf("<tr><th>&nbsp;&nbsp;&nbsp;&nbsp;Status&nbsp;%d</th><td>%d&nbsp;(%.1f%%)</td>",
                       $status, $cts{$status}, $pcts{$status});
    $sql = 'SELECT '. $field. ',COUNT(*) FROM exportdata e'.
           ' INNER JOIN projects p ON e.project=p.id'.
           ' WHERE e.status=? AND DATE(time)=DATE(?) GROUP BY '. $field. ' ASC';
    my $ref = $self->SelectAll($sql, $status, $time);
    $report .= $self->DoPriorityBreakdown($ref, undef, \@pris, $cts{$status});
    $report .= '</tr>';
  }
  $report .= "<tr><th>&nbsp;&nbsp;&nbsp;&nbsp;Total</th><td>$count</td>";
  $sql = 'SELECT '. $field. ',COUNT(gid),CONCAT(FORMAT(IF(?=0,0,(COUNT(gid)*100.0)/?),1),"%")'.
         ' FROM exportdata e'.
         ' INNER JOIN projects p ON e.project=p.id'.
         ' WHERE DATE(time)=DATE(?) GROUP BY '. $field. ' ASC';
  my $ref = $self->SelectAll($sql, $total, $total, $time);
  $report .= sprintf('<td class="nowrap">%s (%s)</td>', $_->[1], $_->[2]) for @{$ref};
  $report .= '</tr>';
  $report .= "<tr><th class='nowrap'>Total CRMS Determinations</th><td colspan='$colspan'>$exported</td></tr>";
  $sql = 'SELECT src,COUNT(gid) FROM exportdata WHERE src IS NOT NULL'.
         ' GROUP BY src ORDER BY src ASC';
  $ref = $self->SelectAll($sql);
  foreach my $row (@{$ref})
  {
    my $n = $row->[1];
    $report .= sprintf("<tr><th>&nbsp;&nbsp;&nbsp;&nbsp;%s</th><td colspan='$colspan'>$n</td></tr>",
                       $self->ExportSrcToEnglish($row->[0]));
  }
  $report .= "</table>\n";
  return $report;
}

sub CreateReviewReport
{
  my $self = shift;
  my $proj = shift;

  my $field = ($proj)? 'p.name':'q.priority';
  my $sql = 'SELECT DISTINCT '. $field. ' FROM queue q'.
            ' INNER JOIN projects p ON q.project=p.id'.
            ' ORDER BY '. $field. ' ASC';
  my @pris = map {$self->StripDecimal($_->[0])} @{$self->SelectAll($sql)};
  my @headers = map {"<th>Priority $_</th>";} @pris;
  @headers = map {"<th>$_</th>";} @pris if $proj;
  s/\s/&nbsp;/g for @headers;
  my $report = '<table class="exportStats">'.
               '<tr><th>Status</th><th>Total</th>'.
               (join '', @headers).
               "</tr>\n";
  $sql = 'SELECT '. $field. ',COUNT(*) FROM queue q'.
         ' INNER JOIN projects p ON q.project=p.id'.
         ' WHERE q.status>0 OR q.pending_status>0'.
         ' GROUP BY '. $field. ' ASC WITH ROLLUP';
  my $ref = $self->SelectAll($sql);
  my $count = (scalar @{$ref})? $ref->[-1]->[1]:0;
  $report .= "<tr><td class='total'>Active</td><td class='total'>$count</td>";
  $report .= $self->DoPriorityBreakdown($ref, ' class="total"', \@pris) . "</tr>\n";
  # Unprocessed
  $sql = 'SELECT '. $field. ',COUNT(*) FROM queue q'.
         ' INNER JOIN projects p ON q.project=p.id'.
         ' WHERE q.status=0 AND q.pending_status>0 GROUP BY '. $field. ' WITH ROLLUP';
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
    $sql = 'SELECT '. $field. ',COUNT(*) from queue q'.
           ' INNER JOIN projects p ON q.project=p.id'.
           ' WHERE status=0 AND pending_status=? GROUP BY '. $field. ' WITH ROLLUP';
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
                   {'status'=>5,'name'=>'Expert-Reviewed'},
                   {'status'=>6,'name'=>'Reported to HathiTrust'},
                   {'status'=>7,'name'=>'Expert-Accepted'},
                   {'status'=>8,'name'=>'Auto-Resolved'},
                   {'status'=>9,'name'=>'Inheritance'});
  $sql = 'SELECT '. $field. ',COUNT(*) FROM queue q'.
         ' INNER JOIN projects p ON q.project=p.id'.
         ' WHERE status!=0 GROUP BY '. $field. ' WITH ROLLUP';
  $ref = $self->SelectAll($sql);
  $count = (scalar @{$ref})? $ref->[-1]->[1]:0;
  $report .= "<tr><td class='minor'>Processed</td><td class='minor'>$count</td>";
  $report .= $self->DoPriorityBreakdown($ref, ' class="minor"', \@pris) . "</tr>\n";
  foreach my $row (@processed)
  {
    $sql = 'SELECT '. $field. ',COUNT(*) from queue q'.
           ' INNER JOIN projects p ON q.project=p.id'.
           ' WHERE q.status=? GROUP BY '. $field. ' WITH ROLLUP';
    $ref = $self->SelectAll($sql, $row->{'status'});
    $count = (scalar @{$ref})? $ref->[-1]->[1]:0;
    if ($count)
    {
      $report .= sprintf "<tr><td class='nowrap'>&nbsp;&nbsp;&nbsp;%s</td><td>$count</td>", $row->{'name'};
      $report .= $self->DoPriorityBreakdown($ref, '', \@pris) . "</tr>\n";
    }
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
  foreach my $key (@{$pris})
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

sub GetLastExport
{
  my $self     = shift;
  my $readable = shift;

  my $sql = 'SELECT COUNT(*),MAX(time) FROM exportdata WHERE exported=1'.
            ' AND DATE(time)='.
            '  (SELECT DATE(MAX(time)) FROM exportdata WHERE exported=1)';
  my $ref = $self->SelectAll($sql);
  my $count = $ref->[0]->[0];
  my $time = $ref->[0]->[1];
  $time = $self->FormatTime($time) if $readable;
  return ($count,$time);
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

# Determines correctness of review passed in hash reference $user1
# containing keys 'user' and 'time'.
# Fills in additional details about the $user1 review, and the most
# recent expert review in $user2 hash reference.
# Returns 0 (incorrect), 1 (correct), or 2 (neutral)
# The algorithm:
# Reviews by autocrms are always correct.
# Reviews with note category Missing and Wrong Record are always correct if S6
# (these never occur in new reviews because the names have been superseded).
# Reviews for a determination of status 6, 7, or 8 are always correct.
# Reviews with a subsequent Newyear project determination are always correct.
# Otherwise, get the most recent subsequent expert review that is not
# by autocrms or done as a Newyear review.
#  If there is no such review, then return correct.
#  Otherwise, if the rights agree for the purposes of review matching, return 1.
#  Otherwise, return 2 if the expert review is swissed, 0 if not swissed.
sub ValidateReview
{
  my $self  = shift;
  my $id    = shift;
  my $user1 = shift;
  my $user2 = shift;

  # autocrms is always right
  return 1 if $user1->{'user'} eq 'autocrms';
  # Get the review
  my $sql = 'SELECT a.name,rs.name,r.expert,e.status,COALESCE(r.category,"")'.
            ' FROM historicalreviews r'.
            ' INNER JOIN exportdata e ON r.gid=e.gid'.
            ' INNER JOIN attributes a ON r.attr=a.id'.
            ' INNER JOIN reasons rs ON r.reason=rs.id'.
            ' WHERE r.id=? AND r.user=? AND r.time=?';
  my $r = $self->SelectAll($sql, $id, $user1->{'user'}, $user1->{'time'});
  my $row = $r->[0];
  $user1->{'attr'}     = $row->[0];
  $user1->{'reason'}   = $row->[1];
  $user1->{'expert'}   = $row->[2];
  $user1->{'status'}   = $row->[3];
  $user1->{'category'} = $row->[4];
  if (!defined $user1->{'status'} or !defined $user1->{'attr'})
  {
    use Data::Dumper;
    my $dump = Dumper $user1;
    $self->Note("Validation failure: $id ($dump)");
  }
  # Missing/Wrong record category is always right if status 6
  return 1 if ($user1->{'category'} eq 'Missing'
               or $user1->{'category'} eq 'Wrong Record')
               and $user1->{'status'} == 6;
  # A status 6/7/8 is always right.
  return 1 if ($user1->{'status'} >=6 && $user1->{'status'} <= 8);
  # If there is a newer newyear determination, that also offers blanket protection.
  $sql = 'SELECT COUNT(id) FROM exportdata WHERE id=? AND src="newyear" AND time>?';
  return 1 if $self->SimpleSqlGet($sql, $id, $user1->{'time'});
  # Get the most recent non-autocrms expert review that is not a subsequent
  # newyear review.
  $sql = 'SELECT r.user,r.time,a.name,rs.name,r.swiss'.
         ' FROM historicalreviews r'.
         ' INNER JOIN exportdata e ON r.gid=e.gid'.
         ' INNER JOIN attributes a ON r.attr=a.id'.
         ' INNER JOIN reasons rs ON r.reason=rs.id'.
         ' WHERE r.id=? AND r.expert>0 AND r.time>? AND r.user!="autocrms"'.
         ' AND (NOT (e.src="newyear" AND r.time>?))'.
         ' ORDER BY r.time DESC LIMIT 1';
  $r = $self->SelectAll($sql, $id, $user1->{'time'}, $user1->{'time'});
  return 1 unless scalar @{$r};
  $row = $r->[0];
  $user2->{'user'}   = $row->[0];
  $user2->{'time'}   = $row->[1];
  $user2->{'attr'}   = $row->[2];
  $user2->{'reason'} = $row->[3];
  $user2->{'swiss'}  = $row->[4];
  return 1 if DoRightsMatch($self, $user1->{'attr'}, $user1->{'reason'},
                            $user2->{'attr'}, $user2->{'reason'});
  return ($user2->{'swiss'} && !$user1->{'expert'})? 2:0;
}

sub UpdateValidation
{
  my $self = shift;
  my $id   = shift;

  my $sql = 'SELECT user,time,validated FROM historicalreviews WHERE id=?';
  my $r = $self->SelectAll($sql, $id);
  foreach my $row (@{$r})
  {
    my $val = $row->[2];
    my %user1 = ('user' => $row->[0], 'time' => $row->[1]);
    my %user2;
    my $val2 = $self->ValidateReview($id, \%user1, \%user2);
    if ($val != $val2)
    {
      $sql = 'UPDATE historicalreviews SET validated=? WHERE id=? AND user=? AND time=?';
      $self->PrepareSubmitSql($sql, $val2, $id, $row->[0], $row->[1]);
    }
  }
}

sub CountCorrectReviews
{
  my $self  = shift;
  my $user  = shift;
  my $start = shift;
  my $end   = shift;
  my $proj  = shift;

  my $correct = 0;
  my $incorrect = 0;
  my $neutral = 0;
  my $sql = 'SELECT r.validated,COUNT(r.id) FROM historicalreviews r'.
            ' INNER JOIN exportdata e ON r.gid=e.gid'.
            ' WHERE r.legacy!=1 AND r.user=? AND r.time>=? AND r.time<=?'.
            ' AND e.project=? GROUP BY r.validated';
  my $ref = $self->SelectAll($sql, $user, $start, $end, $proj);
  foreach my $row (@{$ref})
  {
    my $val = $row->[0];
    my $cnt = $row->[1];
    $incorrect = $cnt if $val == 0;
    $correct = $cnt if $val == 1;
    $neutral = $cnt if $val == 2;
  }
  $sql = 'SELECT COUNT(*) FROM historicalreviews r'.
         ' INNER JOIN exportdata e ON r.gid=e.gid'.
         ' WHERE r.legacy!=1 AND r.user=? AND r.time>=? AND r.time<=?'.
         ' AND e.project=? AND r.flagged IS NOT NULL AND r.flagged>0';
  my $flagged = $self->SimpleSqlGet($sql, $user, $start, $end, $proj);
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

  # FIXME: what purpose does GetType1Reviewers serve here?
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

  my @keys = ('Identifier', 'SysID', 'Title', 'Author', 'PubDate', 'Country', 'Date',
              'Status', 'Legacy', 'UserId', 'Attribute', 'Reason', 'NoteCategory', 'Note',
              'Priority', 'Validated', 'Swiss', 'Project');
  my @labs = ('Identifier', 'System ID', 'Title', 'Author', 'Pub Date', 'Country',
              'Review Date', 'Status', 'Legacy', 'Reviewer', 'Attribute', 'Reason',
              'Note Category', 'Note', 'Priority', 'Verdict', 'Swiss', 'Project');
  if (!$self->IsUserAtLeastExpert())
  {
    splice @keys, 16, 1; # Swiss
    splice @labs, 16, 1;
  }
  if ($page ne 'adminHistoricalReviews')
  {
    splice @keys, 15, 1; # Validated
    splice @labs, 15, 1;
  }
  if (!$self->IsUserAtLeastExpert())
  {
    splice @keys, 14, 1; # Priority
    splice @labs, 14, 1;
  }
  if ($page eq 'editReviews')
  {
    splice @keys, 9, 1; # UserId/Reviewer
    splice @labs, 9, 1;
  }
  if ($page ne 'adminHistoricalReviews' || $self->TolerantCompare(1,$self->GetSystemVar('noLegacy')))
  {
    splice @keys, 8, 1; # Legacy
    splice @labs, 8, 1;
  }
  if ($page ne 'adminHistoricalReviews')
  {
    splice @keys, 4, 2; #  Country and Pub Date
    splice @labs, 4, 2;
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

   my @keys = qw(Identifier SysID Title Author PubDate Country Date Status Locked
                Priority Reviews ExpertCount Holds Source AddedBy Project Ticket);
  my @labs = ('Identifier', 'System Identifier', 'Title', 'Author', 'Pub Date',
              'Country', 'Date Added', 'Status', 'Locked', 'Priority', 'Reviews',
              'Expert Reviews', 'Holds', 'Source', 'Added By', 'Project', 'Ticket');
  my $html = "<select title='Search Field' name='$searchName' id='$searchName'>\n";
  foreach my $i (0 .. scalar @keys - 1)
  {
    $html .= sprintf("  <option value='%s'%s>%s</option>\n",
                     $keys[$i],
                     ($searchVal eq $keys[$i])? ' selected="selected"':'',
                     $labs[$i]);
  }
  $html .= "</select>\n";
  return $html;
}

# Generates HTML to get the field type menu on the Volumes in Candidates page.
sub CandidatesSearchMenu
{
  my $self       = shift;
  my $searchName = shift;
  my $searchVal  = shift;

  my @keys = qw(Identifier SysID Title Author PubDate Country Date Project);
  my @labs = ('ID', 'Catalog ID', 'Title', 'Author', 'Pub Date', 'Country', 'Date Added',
              'Project');
  my $html = "<select title='Search Field' name='$searchName' id='$searchName'>\n";
  foreach my $i (0 .. scalar @keys - 1)
  {
    $html .= sprintf("  <option value='%s'%s>%s</option>\n",
                     $keys[$i],
                     ($searchVal eq $keys[$i])? ' selected="selected"':'',
                     $labs[$i]);
  }
  $html .= "</select>\n";
  return $html;
}

# Generates HTML to get the field type menu on the Final Determinations page.
sub ExportDataSearchMenu
{
  my $self       = shift;
  my $searchName = shift;
  my $searchVal  = shift;

  my @keys = qw(Identifier SysID Title Author PubDate Country Date Attribute Reason
                Status Priority Source AddedBy Project Ticket GID Exported);
  my @labs = ('Identifier', 'System Identifier', 'Title', 'Author', 'Pub Date', 'Country',
              'Date', 'Attribute', 'Reason', 'Status', 'Priority', 'Source',
              'Added By', 'Project', 'Ticket', 'GID', 'Exported');
  my $html = "<select title='Search Field' name='$searchName' id='$searchName'>\n";
  foreach my $i (0 .. scalar @keys - 1)
  {
    $html .= sprintf("  <option value='%s'%s>%s</option>\n",
                     $keys[$i],
                     ($searchVal eq $keys[$i])? ' selected="selected"':'',
                     $labs[$i]);
  }
  $html .= "</select>\n";
  return $html;
}

# This is used for the HTML page title.
sub PageToEnglish
{
  my $self = shift;
  my $page = shift;

  $self->SimpleSqlGet('SELECT name FROM menuitems WHERE page=?', $page) || 'Home';
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
  if ($self->SimpleSqlGet('SELECT COUNT(*) FROM reviews WHERE id=?', $id) > 0)
  {
    my ($a, $r) = $self->GetFinalAttrReason($id);
    if (defined $a && defined $r && ($a ne $ref->[0]->[0] || $r ne $ref->[0]->[1]))
    {
      $rights .= ' ' . "\N{U+2192}" . " $a/$r";
    }
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

  my $sql = 'SELECT iprestrict,mfa FROM ht_users WHERE userid=? OR email=?'.
            ' ORDER BY IF(role="crms",1,0) DESC';
  my $sdr_dbh = $self->get('ht_repository');
  if (!defined $sdr_dbh)
  {
    $sdr_dbh = $self->ConnectToSdrDb('ht_repository');
    $self->set('ht_repository', $sdr_dbh) if defined $sdr_dbh;
  }
  my ($ipr, $mfa);
  my $t1 = Time::HiRes::time();
  eval {
    my $ref = $sdr_dbh->selectall_arrayref($sql, undef, $user, $user);
    my $t2 = Time::HiRes::time();
    $self->DebugSql($sql, 1000.0*($t2-$t1), $ref, 'ht_repository', $user, $user);
    $ipr = $ref->[0]->[0];
    $mfa = $ref->[0]->[1];
  };
  if ($@)
  {
    my $msg = "SQL failed ($sql): ". $@;
    $self->SetError($msg);
  }
  my %ips;
  if ($mfa)
  {
    $ips{'mfa'} = 1;
  }
  elsif (defined $ipr)
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
  #$self->ClearErrors();
  return \%ips;
}

sub GetUserRole
{
  my $self = shift;
  my $user = shift || $self->get('user');

  my $sql = 'SELECT role FROM ht_users WHERE userid=? OR email=?'.
            ' ORDER BY IF(role="crms",1,0) DESC';
  my $sdr_dbh = $self->get('ht_repository');
  if (!defined $sdr_dbh)
  {
    $sdr_dbh = $self->ConnectToSdrDb('ht_repository');
    $self->set('ht_repository', $sdr_dbh) if defined $sdr_dbh;
  }
  my $role;
  eval {
    my $ref = $sdr_dbh->selectall_arrayref($sql, undef, $user, $user);
    $role = $ref->[0]->[0];
  };
  if ($@)
  {
    my $msg = "SQL failed ($sql): " . $@;
    $self->SetError($msg);
  }
  return $role;
}

# Returns a hash ref:
# expires => expiration date from database
# status => {0,1,2} where 0 is unexpired, 1 is expired, 2 is expiring soon
# days => number of days left before expiration
sub IsUserExpired
{
  my $self = shift;
  my $user = shift || $self->get('user');

  my %data;
  my $sql = 'SELECT DATE(expires),IF(expires<NOW(),1,'.
            'IF(DATE_SUB(expires,INTERVAL 10 DAY)<NOW(),2,0)),'.
            ' DATEDIFF(DATE(expires),DATE(NOW()))'.
            ' FROM ht_users WHERE userid=? OR email=?'.
            ' ORDER BY IF(role="crms",1,0) DESC';
  #print "$sql<br/>\n";
  my $sdr_dbh = $self->get('ht_repository');
  if (!defined $sdr_dbh)
  {
    $sdr_dbh = $self->ConnectToSdrDb('ht_repository');
    $self->set('ht_repository', $sdr_dbh) if defined $sdr_dbh;
  }
  eval {
    my $ref = $sdr_dbh->selectall_arrayref($sql, undef, $user, $user);
    $data{'expires'} = $ref->[0]->[0];
    $data{'status'} = $ref->[0]->[1];
    $data{'days'} = $ref->[0]->[2];
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

# All volumes in the query (q) are moved to the top of the results.
# The two groups are sorted by enumchron.
sub TrackingQuery
{
  my $self = shift;
  my $id   = shift;
  my $q    = shift;

  my %rest;
  $rest{$_} = 1 for @{$q};
  my $data = {};
  my @ids;
  my $rows;
  my $record = $self->GetMetadata($id);
  if (defined $record)
  {
    $data->{'title'} = $record->title;
    $data->{'sysid'} = $record->sysid;
    $rows = $self->VolumeIDsQuery($id, $record);
    foreach my $ref (sort
      {my $a1 = lc $a->{'chron'};
       my $b1 = lc $b->{'chron'};
       $a1 =~ s/[^a-z0-9]//g;
       $b1 =~ s/[^a-z0-9]//g;
       $a1 cmp $b1;} @{$rows})
    {
      my $id2 = $ref->{'id'};
      my @rightsInfo = ('' x 7);
      eval {
        @rightsInfo = @{$self->RightsQuery($id2, 1)->[0]};
      };
      my $data2 = [$id2, $ref->{'chron'},
                   $self->GetTrackingInfo($id2, 1, 1),
                   $ref->{'rights'}, @rightsInfo];
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
  $data->{'data'} = \@ids;
  return $data;
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
              ' ON q.project=p.id WHERE q.id=?';
    my $proj = $self->SimpleSqlGet($sql, $id);
    my $projinfo = (defined $proj)? ", $proj project":'';
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
              ' INNER JOIN projects p ON c.project=p.id WHERE c.id=?';
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

# Returns arrayref with [time, status, message]
# if $nodelay, ignore replication delay.
sub GetSystemStatus
{
  my $self    = shift;
  my $nodelay = shift;

  my ($delay, $since) = $self->ReplicationDelay();
  if (4 < $delay && !$nodelay)
  {
    return [$since, 'delayed',
            'The CRMS is currently experiencing delays. '.
            '"Review" and "Add to Queue" pages may not be available. '.
            'Please try again in a few minutes. '.
            'Locked volumes may need to have reviews re-submitted.'];
  }
  my $vals = ['forever', 'normal', ''];
  my $sql = 'SELECT time,COALESCE(status,"normal"),COALESCE(message,"")'.
            ' FROM systemstatus ORDER BY time DESC LIMIT 1';
  my $ref = $self->SelectAll($sql);
  if (scalar @{$ref})
  {
    $vals = $ref->[0];
    $vals->[0] = $self->FormatTime($vals->[0]);
    if (!$vals->[2])
    {
      if ($vals->[1] eq 'down')
      {
        $vals->[2] = 'The CRMS is currently unavailable until further notice.';
      }
      elsif ($vals->[1] eq 'partial')
      {
        $vals->[2] = 'The CRMS has limited functionality. "Review" and "Add to Queue" (administrators only) pages are currently disabled until further notice.';
      }
    }
  }
  return $vals;
}

# Takes undef/arrayref like return value from GetSystemStatus.
sub SetSystemStatus
{
  my $self = shift;
  my $stat = shift;

  $self->PrepareSubmitSql('DELETE FROM systemstatus');
  if (defined $stat)
  {
    my $sql = 'INSERT INTO systemstatus (status,message) VALUES (?,?)';
    $self->PrepareSubmitSql($sql, $stat->[1], $stat->[2]);
  }
}

# Returns capitalized name of system
sub WhereAmI
{
  my $self = shift;

  my %instances = ('production' => 1, 'crms-training' => 1, 'dev' => 1);
  my $instance = $self->get('instance') || $ENV{'HT_DEV'} || 'dev';
  $instance = "dev ($instance)" unless $instances{$instance};
  $instance = 'training' if $instance eq 'crms-training';
  return ucfirst $instance;
}

sub DevBanner
{
  my $self = shift;

  my $where = $self->WhereAmI();
  if ($where ne 'Production')
  {
    $where .= ' | Production DB' if $self->get('pdb');
    $where .= ' | Training DB' if $self->get('tdb');
    return '[ '. $where. ' ]';
  }
  return undef;
}

sub Host
{
  my $self = shift;

  my $host = $ENV{'HTTP_HOST'};
  if (!$host)
  {
    $host = $self->GetSystemVar('host');
    my $instance = $self->get('instance') || 'test';
    $host = $instance . '.' . $host if $instance ne 'production';
  }
  return 'https://' . $host;
}

sub IsDevArea
{
  my $self = shift;

  my $inst = $self->get('instance') || '';
  return ($inst eq 'production' || $inst eq 'crms-training')? 0:1;
}

sub IsTrainingArea
{
  my $self = shift;

  my $inst = $self->get('instance') || '';
  return $inst eq 'crms-training';
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
  my @return = (0, 'unknown');
  my $sql = 'SELECT seconds,DATE_SUB(time, INTERVAL seconds SECOND) FROM mysqlrep.delay WHERE client=?';
  my $ref = $self->SelectAll($sql, $host);
  if (scalar @$ref)
  {
    @return = ($ref->[0]->[0], $self->FormatTime($ref->[0]->[1]));
  }
  return @return;
}

sub LinkNoteText
{
  my $self = shift;
  my $note = shift;

  if ($note =~ m/See\sall\sreviews\sfor\sSys\s#(\d+)/)
  {
    my $url = $self->Sysify($self->WebPath('cgi', "crms?p=adminHistoricalReviews;stype=reviews;search1=SysID;search1value=$1"));
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
  $new_search = 'IF((SELECT COUNT(*) FROM historicalreviews h'.
                ' INNER JOIN exportdata e ON h.gid=e.gid'.
                ' WHERE h.id=i.id AND e.status=5)>0,1,0)' if $search eq 'prior5';
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
    push @rest, '(p.autoinherit=1 OR i.reason=1 OR (i.reason=12 AND (e.attr="pd" OR e.attr="pdus")))';
  }
  else
  {
    push @rest, '(p.autoinherit=0 AND i.reason!=1 AND !(i.reason=12 AND (e.attr="pd" OR e.attr="pdus")))';
  }
  my $restrict = 'WHERE '. join(' AND ', @rest);
  my $sql = 'SELECT COUNT(DISTINCT e.id),COUNT(DISTINCT i.id) FROM inherit i'.
            ' INNER JOIN exportdata e ON i.gid=e.gid'.
            ' INNER JOIN projects p ON e.project=p.id'.
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
         ' INNER JOIN projects p ON e.project=p.id'.
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
      my $sql = 'SELECT COUNT(*) FROM historicalreviews h'.
                ' INNER JOIN exportdata e ON h.gid=e.gid'.
                ' WHERE h.id=? AND e.status=5';
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
    $self->ReportMsg("Deleting inheritance for $id") unless $quiet;
    $self->PrepareSubmitSql('DELETE FROM inherit WHERE id=?', $id);
    # Only unfilter if the und src is 'duplicate' because duplicate filtration
    # does not override other sources like gfv
    if ($self->IsFiltered($id, 'duplicate'))
    {
      $self->ReportMsg("Unfiltering $id") unless $quiet;
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
  $self->ReportMsg(sprintf("Submitting %d inheritances", scalar @{$ref})) unless $quiet;
  foreach my $row (@{$ref})
  {
    my $id = $row->[0];
    my $gid = $row->[1];
    my $status = $row->[2];
    if ((defined $status && $status == 1) || $self->CanAutoSubmitInheritance($id, $gid))
    {
      $self->ReportMsg("Submitting inheritance for $id") unless $quiet;
      my $res = $self->SubmitInheritance($id);
      $self->ReportMsg("-- $res") if $res;
    }
  }
}

# Given inheriting id and source gid,
# can the inheritance take place automatically?
# It can only happen in the following circumstances:
# The current rights are available and are */bib or */gfv,
#    where in the case of gfv inherited rights are pd or pdus.
# OR
# the source volume's project has the autoinherit flag set.
sub CanAutoSubmitInheritance
{
  my $self = shift;
  my $id   = shift;
  my $gid  = shift;

  my $rq = $self->RightsQuery($id, 1);
  return 0 unless defined $rq;
  my ($attr, $reason, $src, $usr, $time, $note) = @{$rq->[0]};
  return 1 if $reason eq 'bib';
  $attr = $self->SimpleSqlGet('SELECT attr FROM exportdata WHERE gid=?', $gid);
  return 1 if $attr =~ m/^pd/ and $reason eq 'gfv';
  my $sql = 'SELECT p.autoinherit FROM exportdata e'.
            ' INNER JOIN projects p ON e.project=p.id WHERE e.gid=?';
  return $self->SimpleSqlGet($sql, $gid);
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
         ' INNER JOIN attributes a ON e.attr=a.name'.
         ' INNER JOIN reasons rs ON e.reason=rs.name'.
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
  my $params = {'attr' => $attr, 'reason' => $reason, 'expert' => 1,
                'category' => 'Rights Inherited', 'swiss' => $swiss,
                'status' => 9};
  $self->SubmitReview($id, 'autocrms', $params);
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
  my $sql = 'SELECT project FROM exportdata WHERE gid=?';
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
        $self->PrepareSubmitSql('UPDATE queue SET source="inherited",project=? WHERE id=?', $id, $proj);
      }
    }
    $self->UnlockItem($id, 'autocrms');
  }
  else
  {
    my $sql = 'INSERT INTO queue (id,priority,source,project) VALUES (?,0,"inherited",?)';
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

sub LinkToCatalogMARC
{
  my $self  = shift;
  my $sysid = shift;

  return 'http://catalog.hathitrust.org/Record/'. $sysid. '.marc';
}

sub LinkToHistorical
{
  my $self  = shift;
  my $sysid = shift;
  my $full  = shift;

  my $url = $self->WebPath('cgi','crms?p=adminHistoricalReviews;search1=SysID;search1value='. $sysid);
  $url = $self->Host() . $url if $full;
  return $url;
}

sub LinkToDeterminations
{
  my $self = shift;
  my $gid  = shift;
  my $full = shift;

  my $url = $self->WebPath('cgi','crms?p=exportData;search1=GID;search1value='. $gid);
  $url = $self->Host() . $url if $full;
  return $url;
}

sub LinkToRetrieve
{
  my $self  = shift;
  my $sysid = shift;
  my $full  = shift;

  my $url = $self->WebPath('cgi','crms?p=track;query='. $sysid);
  $url = $self->Host() . $url if $full;
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
  my $proj = $self->SimpleSqlGet('SELECT project FROM exportdata WHERE gid=?', $gid);
  my $project = $self->Projects()->{$proj};
  my $projname = $project->name;
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
    if (!$project->InheritanceAllowed())
    {
      $data->{'disallowed'}->{$id} .= "$id2\t$sysid\t$oldrights\t$newrights\t$id\tProject $projname does not allow inheritance\n";
    }
    elsif ($newrights eq 'pd/ncn')
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
           ($oldrights =~ '^pdus' && $attr =~ m/^pd/) ||
           $oldrights eq 'ic/bib' || $oldrights eq 'und/bib')
    {
      my $enumchron = $record->enumchron($id) || '';
      my $enumchron2 = $record->enumchron($id2) || '';
      if (!$record->doEnumchronMatch($id, $id2))
      {
        $data->{'chron'}->{$id} = "$id2\t$sysid\t$enumchron\t$enumchron2\n";
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
        $data->{'inherit'}->{$id} .= "$id2\t$sysid\t$attr2\t$reason2\t$attr\t$reason\t$gid\t$enumchron\t$enumchron2\n";
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
# If default is specified, returns it if otherwise the return value would be undefined.
sub GetSystemVar
{
  my $self    = shift;
  my $name    = shift;
  my $default = shift;
  my $ck      = shift;

  $self->SetError('WARNING: GetSystemVar() ck parameter is obsolete.') if $ck;
  my $sql = 'SELECT value FROM systemvars WHERE name=?';
  my $var = $self->SimpleSqlGet($sql, $name);
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

# Returns aref of arefs to name, url, target, and rel
sub MenuItems
{
  my $self = shift;
  my $menu = shift;
  my $user = shift || $self->get('user');

  $menu = $self->SimpleSqlGet('SELECT id FROM menus WHERE docs=1 LIMIT 1') if $menu eq 'docs';
  my $q = $self->GetUserQualifications($user);
  my ($inst, $iname);
  my $sql = 'SELECT name,href,restricted,target FROM menuitems WHERE menu=? ORDER BY n ASC';
  my $ref = $self->SelectAll($sql, $menu);
  my @all = ();
  foreach my $row (@{$ref})
  {
    my $r = $row->[2];
    if ($self->DoQualificationsAndRestrictionsOverlap($q, $r))
    {
      $inst = $self->GetUserProperty($user, 'institution') unless defined $inst;
      $iname = $self->GetInstitutionName($inst, 1) unless defined $iname;
      my $name = $row->[0];
      $name =~ s/__INST__/$iname/;
      my $rel = '';
      if ($row->[3] && $row->[3] eq '_blank' && $row->[1] =~ m/^http/i)
      {
        $rel = 'rel="noopener"';
      }
      push @all, [$name, $self->MenuPath($row->[1]), $row->[3], $rel];
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
            ' IF(admin=1,"xas",""))'.
            ' FROM users where id=?';
  my $q = $self->SimpleSqlGet($sql, $user);
  $q .= 'i' if $self->IsUserIncarnationExpertOrHigher($user);
  return $q;
}

# Called by the top-level script to make sure the user is allowed.
# Returns undef if user qualifies, hashref otherwise.
# hashref -> err string, hashref->page user was trying to access
sub AccessCheck
{
  my $self = shift;
  my $page = shift;
  my $user = shift || $self->get('user');

  my $err;
  my $sql = 'SELECT COUNT(*) FROM users WHERE id=?';
  my $cnt = $self->SimpleSqlGet($sql, $user);
  if ($cnt == 0)
  {
    $err = "DBC failed for $page.tt: user '$user' not in system";
  }
  $sql = 'SELECT restricted FROM menuitems WHERE page=?';
  my $r = $self->SimpleSqlGet($sql, $page) || '';
  my $q = $self->GetUserQualifications($user) || '';
  if (!$self->DoQualificationsAndRestrictionsOverlap($q, $r))
  {
    $err = "DBC failed for $page.tt: r='$r', q='$q'";
  }
  if ($err)
  {
    return {'err' => $err, 'page' => $page};
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

  my $proj = $self->SimpleSqlGet('SELECT project FROM queue WHERE id=?', $id);
  $proj = 1 unless defined $proj;
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
# in an order appropriate for a two-column layout unless $order.
sub Rights
{
  my $self  = shift;
  my $id    = shift;
  my $order = shift;

  my $proj = $self->SimpleSqlGet('SELECT project FROM queue WHERE id=?', $id);
  $proj = 1 unless defined $proj;
  my @all = ();
  my $sql = 'SELECT r.id,CONCAT(a.name,"/",rs.name),r.description,a.name,rs.name FROM rights r'.
            ' INNER JOIN attributes a ON r.attr=a.id'.
            ' INNER JOIN reasons rs ON r.reason=rs.id'.
            ' INNER JOIN projectrights pr ON r.id=pr.rights'.
            ' WHERE pr.project=?'.
            ' ORDER BY IF(a.name="pd"||a.name="pdus",1,0) DESC, a.name ASC, rs.name ASC';
  #print "$sql<br/>\n";
  my $ref = $self->SelectAll($sql, $proj);
  my %seen = ();
  my $n = 1;
  foreach my $row (@{$ref})
  {
    push @all, {'id' => $row->[0], 'rights' => $row->[1],
                'description' => $row->[2], 'n' => $n,
                'attr' => $row->[3], 'reason' => $row->[4]};
    $n++;
  }
  return \@all if $order;
  my @inorder;
  my $of = scalar @all;
  my $middle = int($of / 2);
  $middle += 1 if $of % 2 == 1;
  foreach my $n (0 .. $middle - 1)
  {
    push @inorder, $all[$n];
    push @inorder, $all[$n + $middle] if $n + $middle < $of;
  }
  return \@inorder;
}

# Information sources for the various review pages.
# Returns a ref to in-display-order list of dictionaries with the following keys:
# name, url, initial in menu
sub Authorities
{
  my $self = shift;
  my $id   = shift;
  my $mag  = shift || '100';
  my $view = shift || 'image';

  use URI::Escape;
  my $proj = $self->SimpleSqlGet('SELECT project FROM queue WHERE id=?', $id);
  $proj = 1 unless defined $proj;
  my $sql = 'SELECT primary_authority,secondary_authority FROM projects WHERE id=?';
  my ($pa, $sa) = @{$self->SelectAll($sql, $proj)->[0]};
  $sql = 'SELECT a.id,a.name,a.url,a.accesskey FROM authorities a'.
         ' INNER JOIN projectauthorities pa ON pa.authority=a.id'.
         ' WHERE pa.project=? ORDER BY a.name ASC';
  my $ref = $self->SelectAll($sql, $proj);
  my @all = ();
  my $a = $self->GetAuthor($id);
  foreach my $row (@{$ref})
  {
    my $aid = $row->[0];
    my $name = $row->[1];
    my $url = $row->[2];
    my $ak = $row->[3];
    $url =~ s/__HTID__/$id/g;
    #$url =~ s/__GID__/$gid/g;
    $url =~ s/__MAG__/$mag/g;
    $url =~ s/__VIEW__/$view/g;
    if ($url =~ m/crms\?/)
    {
      $url = $self->Sysify($url);
    }
    if ($url =~ m/__AUTHOR__/)
    {
      my $a2 = $a || '';
      $a2 =~ s/(.+?)\(.*\)/$1/;
      $a2 = uri_escape_utf8($a2);
      $url =~ s/__AUTHOR__/$a2/g;
    }
    if ($url =~ m/__AUTHOR_(\d+)__/)
    {
      my $a2 = $a || '';
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
        $a2 = lc substr($a2, 0, $1);
      }
      $a2 = uri_escape_utf8($a2);
      $url =~ s/__AUTHOR_\d+__/$a2/g;
    }
    if ($url =~ m/__AUTHOR_F__/)
    {
      my $a2 = '';
      if (defined $a && $a =~ m/^.*?([A-Za-z]+)/)
      {
        $a2 = $1;
      }
      $url =~ s/__AUTHOR_F__/$a2/g;
    }
    if ($url =~ m/__TITLE__/)
    {
      my $t = $self->GetTitle($id) || '';
      $t = uri_escape_utf8($t);
      $url =~ s/__TITLE__/$t/g;
    }
    if ($url =~ m/__TICKET__/)
    {
      my $t = $self->SimpleSqlGet('SELECT COALESCE(ticket,"") FROM queue WHERE id=?', $id);
      $url =~ s/__TICKET__/$t/g;
    }
    if ($url =~ m/__SYSID__/)
    {
      my $sysid = $self->BarcodeToId($id) || '';
      $url =~ s/__SYSID__/$sysid/g;
    }
    if ($url =~ m/__SHIB__/)
    {
      my $user = $self->get('remote_user') || '';
      $user .= '@umich.edu' unless $user =~ m/@/;
      my $idp = $self->GetIDP($user) || '';
      $url =~ s/__SHIB__/$idp/g;
    }
    if ($url =~ m/__HATHITRUST__/)
    {
      my $host = $self->IsDevArea()? $ENV{'HTTP_HOST'} : 'babel.hathitrust.org';
      $url =~ s/__HATHITRUST__/$host/;
    }
    my $initial;
    $initial = 1 if $self->TolerantCompare($aid, $pa);
    $initial = 2 if $self->TolerantCompare($aid, $sa);
    push @all, {'name' => $name, 'url' => $url, 'accesskey' => $ak,
                'initial' => $initial, 'id' => $aid};
  }
  return \@all;
}

sub GetIDP
{
  my $self = shift;
  my $user = shift;

  my $sql = 'SELECT identity_provider FROM ht_users WHERE email=? OR userid=?'.
            ' ORDER BY IF(role="crms",1,0) DESC';
  my $sdr_dbh = $self->get('ht_repository');
  if (!defined $sdr_dbh)
  {
    $sdr_dbh = $self->ConnectToSdrDb('ht_repository');
    $self->set('ht_repository', $sdr_dbh) if defined $sdr_dbh;
  }
  my $idp;
  eval {
    my $ref = $sdr_dbh->selectall_arrayref($sql, undef, $user, $user);
    $idp = $ref->[0]->[0];
  };
  if ($@)
  {
    my $err = "SQL failed ($sql): " . $@;
    $self->SetError($err);
  }
  return $idp;
}

# Makes sure a URL has the correct sys and pdb params if needed.
sub Sysify
{
  my $self = shift;
  my $url  = shift;

  return $url if $url =~ m/^https/ or $url =~ m/\.pdf(#.*)?$/;
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
  my $pdb = $self->get('pdb');
  $html .= "<input type='hidden' name='pdb' value='$pdb'/>" if $pdb;
  my $tdb = $self->get('tdb');
  $html .= "<input type='hidden' name='tdb' value='$tdb'/>" if $tdb;
  return $html;
}

# Compares 2 strings or undefs. Returns 1 or 0 for equality.
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
    $when = $year + 50 if $crown;
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
  my $now    = shift; # The current year, for predicting future public domain transitions.

  my ($attr, $reason) = (0,0);
  $now = $self->GetTheYear() unless defined $now;
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
    if ($pub < 1923)
    {
      $attr = 'pdus';
      $reason = ($ispub)? 'exp':'add';
    }
    else
    {
      $attr = 'ic';
      $reason = ($ispub)? 'cdpp':'add';
    }
  }
  my $sql = 'SELECT r.id FROM rights r INNER JOIN attributes a ON r.attr=a.id'.
            ' INNER JOIN reasons rs ON r.reason=rs.id'.
            ' WHERE a.name=? AND rs.name=?';
  #$self->Note(join ',', ($sql, $attr, $reason));
  return $self->SimpleSqlGet($sql, $attr, $reason);
}

sub Unescape
{
  my $self = shift;

  use URI::Escape;
  return uri_unescape(shift);
}

sub EscapeHTML
{
  my $self = shift;

  return CGI::escapeHTML(shift);
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
  my %excludes = ('us' => 1, 'usa' => 1, 'american' => 1, 'zz' => 1, 'xx' => 1,
                  Unicode::Normalize::NFC('미국') => 1,
                  Unicode::Normalize::NFC('spojené státy americké') => 1,
                  Unicode::Normalize::NFC('états-unis') => 1,
                  Unicode::Normalize::NFC('amerikas savienotās valstis') => 1,
                  'stany zjednoczone' => 1, 'forente stater' => 1);
  $record = $self->GetMetadata($id) unless defined $record;
  return 'unable to fetch MARC metadata for volume' unless defined $record;
  my @authors = $record->GetAllAuthors();
  my $errs = 0;
  foreach my $author (@authors)
  {
    my $data = VIAF::GetVIAFData($self, $author);
    if (defined $data->{'error'})
    {
      $errs++;
      next;
    }
    if (defined $data and scalar keys %{$data} > 0)
    {
      my $country = $data->{'country'};
      if (defined $country)
      {
        $country =~ s/[\.,;]+$//;
        $country =  Unicode::Normalize::NFC($country);
        if (!defined $excludes{lc $country} && lc $country !~ m/\(usa\)/)
				{
					my $abd = $data->{'birth_year'};
					my $add = $data->{'death_year'};
					next if defined $abd and $abd <= 1815;
					next if defined $add and $add <= 1925;
					my $dates = '';
					$dates = sprintf ' %s-%s', (defined $abd)? $abd:'', (defined $add)? $add:'' if $abd or $add;
					my $last = $author;
					$last = $1 if $last =~ m/^(.+?),.*/;
					$last =~ s/[.,;) ]*$//;
					my $url = VIAF::VIAFLink($self, $author);
					my $warning = "<a href='$url' target='_blank'>$last</a> ($country$dates)";
					$warnings{$warning} = 1;
				}
			}
    }
  }
  return 'error contacting VIAF' if $errs > 0 and scalar keys %warnings == 0;
  return (scalar keys %warnings)? join '; ', keys %warnings:undef;
}

sub VIAFLink
{
  my $self   = shift;
  my $author = shift;

  use VIAF;
  return VIAF::VIAFLink($self, $author);
}

sub VIAFCorporateLink
{
  my $self   = shift;
  my $author = shift;

  use VIAF;
  return VIAF::VIAFCorporateLink($self, $author);
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

# Return undollarized htid if suffix is the right length,
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

# FIXME: this should probably not include an explicit reference to "Special" project.
sub GetAddToQueueRef
{
  my $self = shift;
  my $user = shift || $self->get('user');

  my $sql = 'SELECT q.id,b.title,b.author,YEAR(b.pub_date),DATE(q.time),q.added_by,' .
            'q.status,q.priority,q.source,q.ticket,p.name FROM queue q'.
            ' INNER JOIN bibdata b ON q.id=b.id'.
            ' INNER JOIN projects p ON q.project=p.id'.
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
                   'ticket' => $row->[9], 'project' => $row->[10],
                   'tracking' => $self->GetTrackingInfo($row->[0], 1, 1)};
  }
  return \@result;
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

  return sprintf "CRMS %s: $rest", $self->WhereAmI();
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
            '(SELECT COUNT(*) FROM queue q WHERE q.project=pu.project AND status=0)'.
            ' FROM projectusers pu INNER JOIN projects p ON pu.project=p.id WHERE pu.user=?'.
            ' ORDER BY p.name';
  #print "$sql\n";
  my $ref = $self->SelectAll($sql, $user);
  my @ps = map {{'id' => $_->[0], 'name' => $_->[1], 'count' => $_->[2]};} @{$ref};
  @ps = () if scalar @ps == 1 and !defined $ref->[0]->[0];
  return \@ps;
}

# Get the user's current project, sanity-checking and updating it if necessary.
sub GetUserCurrentProject
{
  my $self = shift;
  my $user = shift || $self->get('user');

  my $sql = 'SELECT project FROM users WHERE id=?';
  my $proj = $self->SimpleSqlGet($sql, $user);
  $sql = 'SELECT COUNT(*) FROM projectusers WHERE project=? AND user=?';
  my $ct = $self->SimpleSqlGet($sql, $proj, $user);
  if (!$ct)
  {
    $sql = 'SELECT project FROM projectusers WHERE user=? ORDER BY project ASC LIMIT 1';
    $proj = $self->SimpleSqlGet($sql, $user);
    $self->SetUserCurrentProject($user, $proj);
  }
  return $proj;
}

sub SetUserCurrentProject
{
  my $self = shift;
  my $user = shift || $self->get('user');
  my $proj = shift || '1';

  my $sql = 'UPDATE users SET project=? WHERE id=?';
  $self->PrepareSubmitSql($sql, $proj, $user);
}

# Get a Project object for a single id.
sub GetProjectRef
{
  my $self = shift;
  my $id   = shift;

  $self->Projects()->{$id};
}

# Returns an arrayref of hashrefs with id, name, color, flags, userCount (active assignees),
# queueCount, rights (arrayref), categories (arrayref), authorities (arrayref), users (arrayref).
sub GetProjectsRef
{
  my $self = shift;

  my @projects;
  my $sql = 'SELECT p.id,p.name,COALESCE(p.color,"000000"),p.queue_size,p.autoinherit,'.
            'p.group_volumes,p.single_review,a1.name,a2.name,'.
            '(SELECT COUNT(*) FROM projectusers pu INNER JOIN users u ON pu.user=u.id'.
            ' WHERE pu.project=p.id AND u.reviewer+u.advanced+u.expert+u.admin>0),'.
            '(SELECT COUNT(*) FROM queue q WHERE q.project=p.id),'.
            '(SELECT COUNT(*) FROM candidates c WHERE c.project=p.id),'.
            '(SELECT COUNT(*) FROM exportdata e WHERE e.project=p.id)'.
            ' FROM projects p LEFT JOIN authorities a1 ON p.primary_authority=a1.id'.
            ' LEFT JOIN authorities a2 ON p.secondary_authority=a2.id'.
            ' ORDER BY p.id ASC';
  my $ref = $self->SelectAll($sql);
  foreach my $row (@{$ref})
  {
    push @projects, {'id' => $row->[0], 'name' => $row->[1], 'color' => $row->[2],
                     'queue_size' => $row->[3], 'autoinherit' => $row->[4],
                     'group_volumes' => $row->[5], 'single_review' => $row->[6],
                     'primary_authority' => $row->[7], 'secondary_authority' => $row->[8],
                     'userCount' => $row->[9], 'queueCount' => $row->[10],
                     'candidatesCount' => $row->[11], 'determinationsCount' => $row->[12]};
    my $ref2 = $self->SelectAll('SELECT rights FROM projectrights WHERE project=?', $row->[0]);
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

# Returns the id of the added project, or undef on error.
sub AddProject
{
  my $self     = shift;
  my $name     = shift;

  my $sql = 'INSERT INTO projects (name) VALUES (?,?)';
  $self->PrepareSubmitSql($sql, $name);
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

  my $sql = 'SELECT id,name,url FROM authorities ORDER BY name ASC';
  my $ref = $self->SelectAll($sql);
  my @authorities;
  push @authorities, {'id' => $_->[0], 'name' => $_->[1], 'url' => $_->[2]} for @{$ref};
  return \@authorities;
}

sub AllAssignableUsers
{
  my $self = shift;

  my $sql = 'SELECT u.id,u.name FROM users u'.
            ' WHERE u.reviewer+u.advanced+u.expert+u.admin>0'.
            ' ORDER BY u.name ASC';
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

# Returns a hashref of project id to project object.
sub Projects
{
  my $self = shift;

  my $objs = $self->get('Projects');
  if (!$objs)
  {
    my $sql = 'SELECT id,name FROM projects ORDER BY id ASC';
    my $ref = $self->SelectAll($sql);
    foreach my $row (@{$ref})
    {
      my $obj;
      my $id = $row->[0];
      my $class = $row->[1] || 'Core';
      $class =~ s/\s//g;
      my $file = 'Project/'. $class. '.pm';
      eval {
          require $file;
          $obj = $class->new('crms' => $self, 'id' => $id);
      };
      if ($@)
      {
        if (-f $file)
        {
          $self->SetError("Could not load module file $file '$class': $@");
        }
        else
        {
          $class = 'Project';
          require Project;
          $obj = $class->new('crms' => $self, 'id' => $id);
        }
      }
      $objs->{$id} = $obj;
    }
    $self->set('Projects', $objs);
  }
  return $objs;
}

sub GetStanfordData
{
  my $self  = shift;
  my $q     = shift;
  my $type  = shift;
  my $page  = shift;

  use Stanford;
  return Stanford::GetStanfordData($self, $q, $type, $page);
}

sub EchoInput
{
  my $self = shift;
  my $text = shift;

  use HTML::Entities;
  $text = decode_utf8($text);
  $text = encode_entities($text);
  return $text;
}

sub SubmitMail
{
  my $self = shift;
  my $id   = shift;
  my $user = shift;
  my $text = shift;
  my $uuid = shift;
  my $to   = shift; # default crms-experts
  my $wait = shift; # until volume is out of queue

  $id = undef if defined $id and $id eq '';
  $to = undef if defined $to and $to eq '';
  $wait = 1 if $wait;
  $wait = 0 unless $id;
  my $sql = 'SELECT COUNT(*) FROM mail WHERE uuid=?';
  return if $self->SimpleSqlGet($sql, $uuid);
  $sql = 'INSERT INTO mail (id,user,text,uuid,mailto,wait) VALUES (?,?,?,?,?,?)';
  $self->PrepareSubmitSql($sql, $id, $user, $text, $uuid, $to, $wait);
}

sub UUID
{
  my $self = shift;

  use UUID::Tiny;
  return UUID::Tiny::create_uuid_as_string(UUID::Tiny::UUID_V4);
}

sub GetPageImage
{
  my $self = shift;
  my $id   = shift;
  my $seq  = shift;

  use HTDataAPI;
  return HTDataAPI::GetPageImage($self, $id, $seq);
}

sub ExportReport
{
  my $self  = shift;
  my $start = shift || $self->GetTheYear(). '-01-01';
  my $report = [];
  my $sql = 'SELECT id,name FROM projects ORDER BY id';
  my $ref = $self->SelectAll($sql);
  foreach my $row (@{$ref})
  {
    my $proj = $row->[0];
    my $name = $row->[1];
    $sql = 'SELECT COUNT(*) FROM candidates WHERE project=?';
    my $cand = $self->SimpleSqlGet($sql, $proj);
    if ($cand == 0)
    {
      $sql = 'SELECT COUNT(*) FROM queue WHERE project=?';
      $cand = $self->SimpleSqlGet($sql, $proj);
    }
    $sql = 'SELECT COUNT(*) FROM exportdata WHERE project=?';
    my $det = $self->SimpleSqlGet($sql, $proj);
    $sql = 'SELECT COUNT(*) FROM exportdata WHERE project=? AND attr IN ("pd","pdus")';
    my $pddet = $self->SimpleSqlGet($sql, $proj);
    $sql = 'SELECT COUNT(*) FROM exportdata WHERE project=? AND DATE(time)>=?';
    my $ytddet = $self->SimpleSqlGet($sql, $proj, $start);
    $sql = 'SELECT COUNT(*) FROM exportdata WHERE project=? AND attr IN ("pd","pdus") AND DATE(time)>=?';
    my $ytdpddet = $self->SimpleSqlGet($sql, $proj, $start);
    my ($pdpct, $ytdpdpct) = ('0.0%', '0.0%');
    $pdpct = sprintf "%.1f%%", $pddet / $det * 100.0 if $det;
    $ytdpdpct = sprintf "%.1f%%", $ytdpddet / $ytddet * 100.0 if $ytddet;
    $sql = 'SELECT SUM(COALESCE(TIME_TO_SEC(r.duration),0)/3600.0)'.
           ' FROM historicalreviews r INNER JOIN exportdata e ON r.gid=e.gid'.
           ' WHERE TIME_TO_SEC(r.duration)<=3600 AND e.project=?';
    my $time = sprintf "%.1f", $self->SimpleSqlGet($sql, $proj);
    push @{$report}, {'id' => $proj, 'name' => $name, 'candidates' => $cand,
                      'determinations' => $det, 'pd_determinations' => $pddet,
                      'pd_pct' => $pdpct,
                      'ytd_determinations' => $ytddet,
                      'ytd_pd_determinations' => $ytdpddet,
                      'ytd_pd_pct' => $ytdpdpct,
                      'time' => $time};
  }
  return $report;
}


# Takes output of AllAssignableXXXs (list of hashes) and pulls the IDs into a list.
sub JSONifyIDs
{
  my $self = shift;
  my $data = shift;

  my @ret;
  push @ret, $_->{'id'} for @{$data};
  @ret = sort @ret;
  return JSON::XS->new->encode(\@ret);
}

sub Dump
{
  my $self = shift;
  my $data = shift;

  return Dumper $data;
}

sub Commify
{
  my $self = shift;
  my $n = shift;

  my $n2 = reverse $n;
  $n2 =~ s<(\d\d\d)(?=\d)(?!\d*\.)><$1,>g;
  # Don't just try to "return reverse $n2" as a shortcut. reverse() is weird.
  $n = reverse $n2;
  return $n;
}

sub KeioTables
{
  use Keio;
  Keio::Tables(@_);
}

sub KeioTranslation
{
  use Keio;
  Keio::Translation(@_);
}

sub KeioTableQuery
{
  use Keio;
  Keio::TableQuery(@_);
}

sub KeioQueries
{
  use Keio;
  Keio::Queries(@_);
}

sub KeioQuery
{
  use Keio;
  Keio::Query(@_);
}

1;
