package CRMS::Session;

use CRMS::DB;
use User;

sub new {
  my $class = shift;

  my $self = { @_ };
  bless($self, $class);
  $self->SetupUser;
  return $self;
}

# Identify ht.ht_users.id and crms.users.email/id from environment.
# 1. Try REMOTE_USER as ht.ht_users.userid
# 1a. Try REMOTE_USER as crms.users.email
# 1b. Try ht.ht_users.userid as crms.users.email
# 2. Try ENV{email} (minus umich) as ht.ht_users.userid
# 2a. Try ENV{email} as crms.users.email
# 2b. Try ht.ht_users.userid as crms.users.email
# Then, set login credentials as remote_user and user as alias if it is set.
sub SetupUser {
  my $self = shift;

  my $note = '';
  my $crms_dbh = CRMS::DB->new->dbh;
  my $ht_dbh = CRMS::DB->new(name => 'ht')->dbh;
  return unless defined $crms_dbh and defined $ht_dbh;
  # ht.ht_users.email, crms.users.email, crms.users.id
  my ($ht_user, $crms_user, $crms_id);
  my $usersql = 'SELECT id FROM users WHERE email=?';
  my $htsql = 'SELECT email FROM ht_users WHERE userid=?';
  my $candidate = $ENV{'REMOTE_USER'};
  $candidate = lc $candidate if defined $candidate;
  $note .= sprintf "ENV{REMOTE_USER}=%s\n", (defined $candidate)? $candidate:'<undef>';
  if ($candidate) {
    my $candidate2;
    my $ref = $ht_dbh->selectall_arrayref($htsql, undef, $candidate);
    if (scalar @$ref) {
      $ht_user = $candidate;
      $note .= "ht_users.userid=$ht_user\n";
      $candidate2 = $ref->[0]->[0];
    }
    #$crms_id = $crms_dbh->selectall_arrayref($usersql, undef, $candidate)->[0]->[0];
    $ref = $crms_dbh->selectall_arrayref($usersql, undef, $candidate);
    $crms_id = $ref->[0]->[0] if scalar @$ref;
    if ($crms_id) {
      $crms_user = $candidate;
      $note .= "Set crms_user=$crms_user,crms_id=$crms_id from lc ENV{REMOTE_USER}\n";
    } else {
      $ref = $crms_dbh->selectall_arrayref($usersql, undef, $candidate2);
      $crms_id = $ref->[0]->[0] if scalar @$ref;
      if ($crms_id) {
        $crms_user = $candidate2;
        $note .= "Set crms_user=$crms_user,crms_id=$crms_id from ht_users.email\n";
      }
    }
  }
  if (!$crms_user || !$ht_user) {
    $candidate = $ENV{'email'};
    $candidate = lc $candidate if defined $candidate;
    $candidate =~ s/\@umich.edu// if defined $candidate;
    $note .= sprintf "ENV{email}=%s\n", (defined $candidate)? $candidate:'<undef>';
    if ($candidate) {
      # Candidate is e-mail address with umich stripped
      my $candidate2;
      my $ref = $ht_dbh->selectall_arrayref($htsql, undef, $candidate);
      if (scalar @$ref && !$ht_user) {
        $ht_user = $candidate;
        $note .= "Set ht_user=$ht_user\n";
        # Candidate2 is ht_users.email with ht_users.id as ENV{email}
        $candidate2 = $ref->[0]->[0];
      }
      #$crms_id = $crms_dbh->selectall_arrayref($usersql, undef, $candidate2)->[0]->[0];
      $ref = $crms_dbh->selectall_arrayref($usersql, undef, $candidate2);
      $crms_id = $ref->[0]->[0] if scalar @$ref;
      if ($crms_id) {
        $crms_user = $candidate;
        $note .= "Set crms_user=$crms_user,crms_id=$crms_id from lc ENV{email}\n";
      } else {
        $ref = $crms_dbh->selectall_arrayref($usersql, undef, $candidate2);
        $crms_id = $ref->[0]->[0] if scalar @$ref;
        if ($crms_id) {
          $crms_user = $candidate2;
          ### ========== POSSIBLY NOT USED ==========
          ### Makes sense since we don't use @umich.edu in users.email.
          $note .= "Set crms_user=$crms_user,crms_id=$crms_id from ht_users.email and ENV{email}\n";
        }
      }
    }
  }
  if ($ht_user) {
    if ($self->NeedStepUpAuth($ht_user)) {
      $note .= "HT user $ht_user step-up auth required.\n";
    }
    $self->{ht_user} = $ht_user;
  }
  if ($crms_user) {
    $note .= "Setting CRMS::Session remote_user to $crms_id from $crms_user.\n";
    # remote_user is the crms.users.id of the actual meatspace person using the system.
    $self->{remote_user} = $crms_id;
    my $user = User::Find($crms_id);
    $note .= sprintf("Set CRMS user object:\n%s\n", Dumper $user);
    $self->{user} = $user;
  }
  $self->{id_note} = $note;
}

# cgi/crms uses the value of $crms->{stepup_redirect} set by this routine.
# The return value is just used for debugging.
# If ht.ht_users entry is MFA-enabled and their institution's authn context class
# doesn't match the one in the environment, construct URL based on template.
# replace __HOST__ with $ENV{SERVER_NAME}
# replace __TARGET__ with something like CGI::self_url($cgi)
# append &authnContextClassRef=$shib_authncontext_class
#
# NOTE: the $session->{stepup_url} redirect needs a '&target=...' appended
# to it before use since we don't and maybe shouldn't have access to the
# CGI environment in this module.
sub NeedStepUpAuth {
  my $self = shift;
  my $user = shift;

  my $sql = 'SELECT COALESCE(mfa,0) FROM ht_users WHERE userid=?';
  my $ht_dbh = CRMS::DB->new(name => 'ht')->dbh;
  my $mfa = $ht_dbh->selectall_arrayref($sql, undef, $user)->[0]->[0];
  return 0 unless $mfa;

  my $idp = $ENV{'Shib_Identity_Provider'};
  my $class = $ENV{'Shib_AuthnContext_Class'};
  if (defined $class) {
    my $dbclass;
    $sql = 'SELECT shib_authncontext_class FROM ht_institutions WHERE entityID=?';
    my $ref = $ht_dbh->selectall_arrayref($sql, undef, $idp);
    $dbclass = $ref->[0]->[0] if scalar @$ref;
    if (defined $dbclass && $class ne $dbclass) {
      #use URI::Escape;
      #my $target = URI::Escape::uri_escape(CGI::url($self->get('cgi')));
      my $server = $ENV{SERVER_NAME} || '';
      my $template = "https://$server/Shibboleth.sso/Login?".
                     "entityID=$idp&&authnContextClassRef=$dbclass";
      $self->{stepup_redirect} = $template;
      my $note = sprintf "ENV{Shib_Identity_Provider}='$idp'\n".
                         "ENV{Shib_AuthnContext_Class}='$class'\n".
                         "DB class=%s\n".
                         'TEMPLATE=%s',
                         (defined $dbclass)? $dbclass:'<undef>',
                         $template;
      $self->{auth_note} = $note;
      return 1;
    }
  }
  return 0;
}

# If alias id is defined, switch to that alias.
# Otherwise, drop alias if there is one.
sub SetAlias {
  my $self     = shift;
  my $alias_id = shift;

  # Record debugging information.
  my $note = $self->{id_note} || '';
  my $alias_user = undef;
  my $real_user = User::Find($self->{remote_user});
  if (defined $alias_id) {
    $alias_user = User::Find($alias_id);
    if ($real_user->{id} == $alias_id) {
      $self->{user} = $real_user;
      delete $self->{alias_user_id};
      $alias_user = undef;
      $note .= "Ignoring alias $alias_id set to REMOTE_USER id\n";
    }
    if (defined $alias_user) {
      $self->{user} = $alias_user;
      $self->{alias_user_id} = $alias_id;
      $note .= "Set alias to $alias_user->{email} ($alias_id)\n";
    }
  } else {
    if ($self->{alias_user_id}) {
      $self->{user} = $real_user;
      delete $self->{alias_user_id};
      $note .= "Drop alias for $real_user->{email}\n";
    }
  }
  $self->{id_note} = $note;
}

return 1;
