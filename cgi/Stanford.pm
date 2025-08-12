package Stanford;

use strict;
use warnings;
use JSON::XS;
use Unicode::Normalize;
use URI::Escape;

use lib "$ENV{SDRROOT}/crms/lib";
use CRMS::Config;

sub GetStanfordData
{
  my $self  = shift;
  my $q     = shift;
  my $field = shift || 'search';
  my $page  = shift;

  return unless defined $q and length $q;
  my $url = GetStanfordURL($self, $q, $field, $page);
  my $crms_user_agent = CRMS::Config->new->config->{'crms_user_agent'};
  my $ua = LWP::UserAgent->new(
    agent => $crms_user_agent,
    timeout => 1000
  );
  my $req = HTTP::Request->new(GET => $url);
  my $res = $ua->request($req);
  if (!$res->is_success)
  {
    $self->SetError("Got ". $res->code(). " getting $url: $res->content\n");
    return;
  }
  my $jsonxs = JSON::XS->new->utf8;
  my $json;
  eval {
    no warnings 'all';
    $json = $jsonxs->decode($res->content);
  };
  if ($@)
  {
    $self->SetError("Stanford parse error for $url: " . $res->content);
    return;
  }
  $json->{'response'}->{'json'} = $res->content;
  $json->{'response'}->{'url'} = $url;
  return $json;
}

sub GetStanfordURL
{
  my $self  = shift;
  my $q     = shift;
  my $field = shift;
  my $page  = shift;

  $q = Unicode::Normalize::decompose($q);
  $q = uri_escape_utf8($q);
  my $url = 'https://exhibits.stanford.edu/copyrightrenewals/catalog.json?q='.
            $q. '&search_field='. $field;
  $url .= '&page='. $page if $page;
  return $url;
}

return 1;
