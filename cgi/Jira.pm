package Jira;

BEGIN {
  use lib $ENV{'SDRROOT'} . '/crms/lib';
}

use strict;
use warnings;

use LWP::UserAgent;

use CRMS::Config;

# Returns error string or undef for success.
sub AddComment {
  my $tx      = shift;
  my $comment = shift;

  my $err;
  $comment =~ s/"/\\"/g;
  $comment =~ s/\n/\\n/gm;
  my $data = qq({ "body": "$comment", "properties":[{"key":"sd.public.comment","value":{"internal":true}}] });
  my $path = "/rest/api/2/issue/$tx/comment";
  my $req = Request('POST', $path);
  $req->content_type('application/json');
  $req->content($data);
  my $res = LWP::UserAgent->new->request($req);
  if (!$res->is_success()) {
    $err = sprintf "Got %s (%s) posting $path: %s",
      $res->code(), $res->message(), $res->content();
  }
  return $err;
}

sub LinkToJira {
  my $tx = shift;

  my $config = CRMS::Config->new;
  my $prefix = $config->config->{'jira_prefix'};
  my $url = $prefix . '/browse/' . $tx;
  return "<a href=\"$url\" target=\"_blank\">$tx</a>";
}

sub Request {
  my $method = shift;
  my $path   = shift;

  my $config = CRMS::Config->new;
  my $username = $config->credentials->{'jira_user'};
  my $password = $config->credentials->{'jira_password'};
  my $prefix = $config->config->{'jira_prefix'};
  my $req = HTTP::Request->new($method => $prefix . $path);
  $req->authorization_basic($username, $password);
  return $req;
}

1;
