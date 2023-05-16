package CRMS::Jira;

use strict;
use warnings;

use LWP::UserAgent;

use lib "$ENV{SDRROOT}/crms/lib";
use CRMS::Config;

sub new {
  my ($class, %args) = @_;
  my $self = bless {}, $class;
  $self->{config} = CRMS::Config->new;
  return $self;
}

# Returns error string or undef for success.
# Keyword parameters:
#   ticket (required)
#   comment (required)
#   user_agent (optional, used only for testing)
sub add_comment {
  my ($self, %args) = @_;

  my $err;
  # uncoverable condition right
  my $ua = $args{user_agent} || LWP::UserAgent->new;
  my $comment = $args{comment};
  $comment =~ s/"/\\"/g;
  $comment =~ s/\n/\\n/gm;
  my $data = qq({ "body": "$comment", "properties":[{"key":"sd.public.comment","value":{"internal":true}}] });
  my $path = "/rest/api/2/issue/$args{ticket}/comment";
  my $req = $self->request(method => 'POST', path => $path);
  $req->content_type('application/json');
  $req->content($data);
  my $res = $ua->request($req);
  if (!$res->is_success()) {
    $err = sprintf "Got %s (%s) posting $path: %s",
      $res->code(), $res->message(), $res->content();
  }
  return $err;
}

# Standard URL for ticket. Used in CRMS CGI to display Jira links.
sub browse_url {
  my ($self, $ticket) = @_;

  return $self->{config}->config->{jira_prefix} . '/browse/' . $ticket
}

# Returns HTTP::Request with basic authorization based on config.
# Keyword parameters:
#   method (required)
#   path (required)
# Example
#   $req = $jira->request(method => 'POST', path => '/rest/api/2/issue/HT-33/comment');
sub request {
  my ($self, %args) = @_;

  my $credentials = $self->{config}->credentials;
  my $prefix = $self->{config}->config->{'jira_prefix'};
  my $req = HTTP::Request->new($args{method} => $prefix . $args{path});
  $req->authorization_basic($credentials->{jira_user}, $credentials->{jira_password});
  return $req;
}

1;
