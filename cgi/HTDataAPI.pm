package HTDataAPI;

use strict;
use warnings;
use OAuth::Lite::Consumer;
use OAuth::Lite::AuthMethod;

use Utilities;

# Returns div if METS copyright is found, undef otherwise.
# This works but is currently unused.
# sub HasCopyright {
#   my $self = shift;
#   my $id   = shift;
# 
#   my $config = CRMS::Config::SecretConfig();
#   my $access_key = $config->{'dataAPIAccessKey'};
#   my $secret_key = $config->{'dataAPISecretKey'};
#   my $request_url = 'https://babel.hathitrust.org/cgi/htd/structure/'. $id;
#   my $consumer = OAuth::Lite::Consumer->new(
#     consumer_key    => $access_key,
#     consumer_secret => $secret_key,
#     auth_method     => OAuth::Lite::AuthMethod::URL_QUERY,
#   );
#   my $res = $consumer->request(
#     method  => 'GET',
#     url     => $request_url,
#     params  => {'v' => 2, 'format' => 'json'}
#   );
#   if ($res->is_success) {
#     my $jsonxs = JSON::XS->new;
#     my $json = $jsonxs->decode($res->content);
#     my $map = $json->{'METS:structMap'}->{'METS:div'}->{'METS:div'};
#     # Array of dicts
#     foreach my $div (@{$map}) {
#       my $lab = $div->{'LABEL'};
#       return $div->{'ORDER'} if defined $lab && $lab =~ m/copyright/i;
#     }
#   } else {
#     printf "$id oops: %s\n", $res->content;
#   }
#   return;
# }

# Returns hashref with 'data' field of Base64 image data and 'success' field 1
sub GetPageImage {
  my $self = shift;
  my $id   = shift;
  my $seq  = shift;

  my %data;
  my $config = CRMS::Config::SecretConfig();
  my $access_key = $config->{'dataAPIAccessKey'};
  my $secret_key = $config->{'dataAPISecretKey'};
  my $url = 'https://babel.hathitrust.org/cgi/htd/volume/pageimage/'. $id. '/'. $seq;
  my $consumer = OAuth::Lite::Consumer->new(
    consumer_key    => $access_key,
    consumer_secret => $secret_key,
    auth_method     => OAuth::Lite::AuthMethod::URL_QUERY,
  );
  my $res = $consumer->request(
     method  => 'GET',
     url     => $url,
     params  => {'v' => 2, 'format' => 'png', 'watermark' => 1}
  );
  $data{'url'} = $url;
  #$data{'access_key'} = $access_key;
  #$data{'secret_key'} = $secret_key;
  if ($res->is_success) {
    use MIME::Base64;
    my $encoded = MIME::Base64::encode_base64($res->content);
    $data{'data'} = $encoded;
    $data{'success'} = 1;
  } else {
    $data{'data'} = sprintf "$id oops: %s\n", $res->content;
  }
  return \%data;
}

1;
