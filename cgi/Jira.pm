package Jira;

use LWP::UserAgent;
use strict;
use warnings;
use vars qw(@ISA @EXPORT @EXPORT_OK);
our @EXPORT = qw(Login);

sub GetComments {
  my $crms = shift;
  my $tx   = shift;

  my $path = '/rest/api/2/issue/' . $tx;
  my @comments;
  my $req = Request($crms, 'GET', $path);
  my $res = LWP::UserAgent->new->request($req);
  if ($res->is_success()) {
    my $jsonxs = JSON::XS->new;
    my $content = $res->content;
    eval {
      my $data = $jsonxs->decode($content);
      push @comments, $_->{'body'} for @{$data->{'fields'}->{'comment'}->{'comments'}};
    }
  }
  else {
     warn("While adding comment: got a " . $res->code() . " with content \n" . $res->content);
     return [];
  }
  return \@comments;
}

# Returns error string or undef for success.
sub AddComment {
  my $crms    = shift;
  my $tx      = shift;
  my $comment = shift;

  my $err;
  $comment =~ s/"/\\"/g;
  $comment =~ s/\n/\\n/gm;
  my $data = qq({ "body": "$comment", "properties":[{"key":"sd.public.comment","value":{"internal":true}}] });
  my $path = "/rest/api/2/issue/$tx/comment";
  my $req = Request($crms, 'POST', $path);
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
  my $crms = shift;
  my $tx   = shift;

  my $url = $crms->get('jira_prefix') . '/browse/' . $tx;
  return "<a href=\"$url\" target=\"_blank\">$tx</a>";
}

sub Request {
  my $crms   = shift;
  my $method = shift;
  my $path   = shift;

  my %d = $crms->ReadConfigFile('crmspw.cfg');
  my $username = $d{'jiraUser'};
  my $password = $d{'jiraPasswd'};
  my $prefix = $crms->get('jira_prefix');
  my $req = HTTP::Request->new($method => $prefix . $path);
  $req->authorization_basic($username, $password);
  return $req;
}

1;
