package Jira;

use LWP::UserAgent;
use strict;
use warnings;
use vars qw(@ISA @EXPORT @EXPORT_OK);
our @EXPORT = qw(Login);

# Returns a user agent or undef.
sub Login
{
  my $self    = shift;

  my $root = $self->get('root');
  my $sys = $self->get('sys');
  my $cfg = $root . '/bin/c/crms/' . $sys . 'pw.cfg';
  my %d = $self->ReadConfigFile($cfg);
  my $username   = $d{'jiraUser'};
  my $password = $d{'jiraPasswd'};
  my $ua = new LWP::UserAgent;
  $ua->cookie_jar( {} );
  my $url = 'http://wush.net/jira/hathitrust/rest/auth/1/session';
  my $req = HTTP::Request->new(POST => $url);
  $req->content_type('application/json');
  $req->content(<<END);
    {
        "username": "$username",
        "password": "$password"
    }
END
  my $res = $ua->request($req);
  if (!$res->is_success)
  {
    $self->SetError("Got " . $res->code() . " getting $url\n");
    return undef;
  }
  return $ua;
}

1;
