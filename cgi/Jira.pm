package Jira;

use LWP::UserAgent;
use HTTP::Cookies;
use strict;
use warnings;
use vars qw(@ISA @EXPORT @EXPORT_OK);
our @EXPORT = qw(Login);

# Returns a user agent or undef.
sub Login
{
  my $crms = shift;

  my %d = $crms->ReadConfigFile('crmspw.cfg');
  my $username   = $d{'jiraUser'};
  my $password = $d{'jiraPasswd'};
  my $ua = new LWP::UserAgent;
  $ua->cookie_jar({});
  
  my $url = $crms->get('jira_prefix') . '/rest/auth/1/session';
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
    $crms->SetError(sprintf "Got %s (%s) posting $url: %s",
                            $res->code(), $res->message(), $res->content());
    return;
  }
  return $ua;
}

# Returns undef on success, error otherwise.
# tx:     Jira ticket
# msg:    Text of Jira comment
# [ua]:   LWP user agent to (re-)use from Jira::Login
# [noop]: Do not submit
sub AddComment
{
  my $crms = shift;
  my $tx   = shift;
  my $msg  = shift;
  my $ua   = shift;
  my $noop = shift;

  $msg =~ s/"/\\"/g;
  $msg =~ s/\n/\\n/gm;
  my $json = qq({ "body": "$msg", "properties":[{"key":"sd.public.comment","value":{"internal":true}}] });
  my $url = $crms->get('jira_prefix') . '/rest/api/2/issue/$tx/comment';
  return PostToJira($crms, $tx, $json, $url, $ua, $noop);
}


# Returns undef on success, error otherwise.
# tx:     Jira ticket
# json:   JSON data for URL
# url:    URL to post
# [ua]:   LWP user agent to (re-)use from Jira::Login
# [noop]: Do not submit
sub PostToJira
{
  my $crms = shift;
  my $tx   = shift;
  my $json = shift;
  my $url  = shift;
  my $ua   = shift;
  my $noop = shift;

  return 'No ticket specified' unless $tx;
  return 'No JSON specified' unless $json;
  return 'No URL specified' unless $url;
  $ua = Jira::Login($crms) unless defined $ua;
  return 'No connection to Jira' unless defined $ua;
  my $err;
  my $code;
  if (!$noop)
  {
    my $req = HTTP::Request->new(POST => $url);
    $req->content_type('application/json');
    $req->content($json);
    my $res = $ua->request($req);
    if (!$res->is_success())
    {
      $err = sprintf "Got %s (%s) posting $url: %s",
                     $res->code(), $res->message(), $res->content();
    }
  }
  return $err;
}

sub GetComments
{
  my $crms = shift;
  my $tx   = shift;
  my $ua   = shift;

  $ua = Jira::Login($crms) unless defined $ua;
  return 'No connection to Jira' unless defined $ua;
  my $url = $crms->get('jira_prefix') . '/rest/api/2/issue/' . $tx;
  my @comments;
  my $req = HTTP::Request->new(GET => $url);
  my $res = $ua->request($req);
  if ($res->is_success())
  {
    my $jsonxs = JSON::XS->new;
    my $content = $res->content;
    eval {
      my $data = $jsonxs->decode($content);
      push @comments, $_->{'body'} for @{$data->{'fields'}->{'comment'}->{'comments'}};
    }
  }
  else
  {
    warn("Got " . $res->code() . " getting $url\n");
    printf "%s\n", $res->content();
  }
  return \@comments;
}

sub LinkToJira
{
  my $crms = shift;
  my $tx   = shift;

  my $url = $crms->get('jira_prefix') . '/browse/' . $tx;
  return "<a href=\"$url\" target=\"_blank\">$tx</a>";
}

1;
