package Stanford;
use JSON::XS;
use Unicode::Normalize;
use URI::Escape;

sub GetStanfordData
{
  my $self  = shift;
  my $q     = shift;
  my $field = shift || 'search';
  my $page  = shift;

  my $ret;
  return unless defined $q and length $q;
  my $url = GetStanfordURL($self, $q, $field, $page);
  my $ua = LWP::UserAgent->new;
  $ua->timeout(1000);
  my $req = HTTP::Request->new(GET => $url);
  my $res = $ua->request($req);
  if (!$res->is_success)
  {
    $self->SetError("Got ". $res->code(). " getting $url\n");
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
    $self->SetError('Stanford parse error for '. $url);
    return;
  }
  return $json->{'response'};
}

sub GetStanfordURL
{
  my $self  = shift;
  my $q     = shift;
  my $field = shift;
  my $page  = shift;

  $q = Unicode::Normalize::decompose($q);
  $q = uri_escape_utf8($q);
  my $url = $url = 'https://exhibits.stanford.edu/copyrightrenewals/catalog.json?'.
                   '&q='. $q. '&search_field='. $field;
  $url .= '&page='. $page if $page;
  return $url;
}

return 1;
