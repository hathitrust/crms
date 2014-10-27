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
  my $self = shift;

  my $root = $self->get('root');
  my $sys = $self->get('sys');
  my $cfg = $root . '/bin/c/crms/' . $sys . 'pw.cfg';
  my %d = $self->ReadConfigFile($cfg);
  my $username   = $d{'jiraUser'};
  my $password = $d{'jiraPasswd'};
  my $ua = new LWP::UserAgent;
  $ua->cookie_jar({});
  my $url = 'https://wush.net/jira/hathitrust/rest/auth/1/session';
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

# Returns undef on success, error otherwise.
# tx:     Jira ticket
# msg:    Text of Jira comment
# [ua]:   LWP user agent to (re-)use from Jira::Login
# [noop]: Do not submit
sub AddComment
{
  my $self = shift;
  my $tx   = shift;
  my $msg  = shift;
  my $ua   = shift;
  my $noop = shift;

  my $json = <<END;
{
  "update":
  {
    "comment":
    [
      {
        "add":
        {
          "body":"$msg"
        }
      }
    ]
  }
}
END
  return PostToJira($self, $tx, $json, $ua, $noop);
}

# Returns undef on success, error otherwise.
# tx:     Jira ticket
# msg:    Text of Jira comment
# [ua]:   LWP user agent to (re-)use from Jira::Login
# [noop]: Do not submit
sub CloseIssue
{
  my $self = shift;
  my $tx   = shift;
  my $msg  = shift;
  my $ua   = shift;
  my $noop = shift;

  my $json = <<END;
{
  "update":
  {
    "comment":
    [
      {
        "add":
        {
          "body":"$msg"
        }
      }
    ]
  },
  "fields":
  {
    "resolution":
    {
      "name":"Fixed"
    }
  },
  "transition":
  {
    "id":"141"
  }
}
END
  return PostToJira($self, $tx, $json, $ua, $noop);
}

# Returns undef on success, error otherwise.
# tx:     Jira ticket
# json:   JSON to post
# [ua]:   LWP user agent to (re-)use from Jira::Login
# [noop]: Do not submit
sub PostToJira
{
  my $self = shift;
  my $tx   = shift;
  my $json = shift;
  my $ua   = shift;
  my $noop = shift;

  $ua = Jira::Login($self) unless defined $ua;
  return 'No connection to Jira' unless defined $ua;
  return 'No ticket specified' unless defined $tx;
  my $err;
  my $url = 'https://wush.net/jira/hathitrust/rest/api/2/issue/' . $tx . '/transitions';
  my $code;
  if (!$noop)
  {
    my $req = HTTP::Request->new(POST => $url);
    $req->content_type('application/json');
    $req->content($json);
    my $res = $ua->request($req);
    if (!$res->is_success())
    {
      my $code = $res->code();
      $err = 'Got ' . $code . ' posting ' . $url;
    }
  }
  return $err;
}

# 1-6 currently, 1-3 are considered major
sub GetIssuePriority
{
  my $self = shift;
  my $ua   = shift;
  my $tx   = shift;

  my $url = 'https://wush.net/jira/hathitrust/rest/api/2/issue/' . $tx;
  my $stat = 'Unknown';
  my $req = HTTP::Request->new(GET => $url);
  my $res = $ua->request($req);
  if ($res->is_success())
  {
    my $json = JSON::XS->new;
    my $content = $res->content;
    eval {
      my $data = $json->decode($content);
      $stat = $data->{'fields'}->{'priority'}->{'id'};
    }
  }
  else
  {
    warn("Got " . $res->code() . " getting $url\n");
    #printf "%s\n", $res->content();
  }
  return $stat;
}

sub GetIssueStatus
{
  my $self = shift;
  my $ua   = shift;
  my $tx   = shift;

  my $url = 'https://wush.net/jira/hathitrust/rest/api/2/issue/' . $tx;
  my $stat = 'Unknown';
  my $req = HTTP::Request->new(GET => $url);
  my $res = $ua->request($req);
  if ($res->is_success())
  {
    my $json = JSON::XS->new;
    my $content = $res->content;
    eval {
      my $data = $json->decode($content);
      $stat = $data->{'fields'}->{'status'}->{'name'};
    }
  }
  else
  {
    warn("Got " . $res->code() . " getting $url\n");
    #printf "%s\n", $res->content();
  }
  return $stat;
}

sub GetIssuesStatus
{
  my $self = shift;
  my $ua   = shift;
  my $txs  = shift;

  my %stats;
  my $url = sprintf 'https://wush.net/jira/hathitrust/rest/api/2/search?'.
                    'fields=status&jql=issueKey in (%s)', join ',', @{$txs};
  $stats{$_} = 'Status unknown' for @{$txs};
  my $req = HTTP::Request->new(GET => $url);
  my $res = $ua->request($req);
  if ($res->is_success())
  {
    my $json = JSON::XS->new;
    my $content = $res->content;
    eval {
      my $data = $json->decode($content);
      foreach my $iss (@{$data->{'issues'}})
      {
        my $tx = $iss->{'key'};
        my $stat = $iss->{'fields'}->{'status'}->{'name'};
        $stats{$tx} = $stat;
      }
    };
    $self->SetError("GetIssuesStatus error: " . $@) if $@;
  }
  else
  {
    $self->SetError("GetIssuesStatus got " . $res->code() . " getting $url\n");
    #printf "%s\n", $res->content();
  }
  return \%stats;
}

sub GetComments
{
  my $self = shift;
  my $ua   = shift;
  my $tx   = shift;
  
  my $url = 'https://wush.net/jira/hathitrust/rest/api/2/issue/' . $tx;
  my @comments;
  my $req = HTTP::Request->new(GET => $url);
  my $res = $ua->request($req);
  if ($res->is_success())
  {
    my $json = JSON::XS->new;
    my $content = $res->content;
    eval {
      my $data = $json->decode($content);
      push @comments, $_->{'body'} for @{$data->{'fields'}->{'comment'}->{'comments'}};
    }
  }
  else
  {
    warn("Got " . $res->code() . " getting $url\n");
    #printf "%s\n", $res->content();
  }
  return \@comments;
}

sub LinkToJira
{
  my $tx = shift;

  return '<a href="https://wush.net/jira/hathitrust/browse/'.
         $tx. '" target="_blank">'. $tx. '</a>';
}

1;
