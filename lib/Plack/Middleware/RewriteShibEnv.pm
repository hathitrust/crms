use strict;
use warnings;

package Plack::Middleware::RewriteShibEnv;
use parent 'Plack::Middleware';

my $SHIB_ENV_VARS = {
  'HTTP_X_SHIB_AUTHENTICATION_METHOD' => 'X-Shib-Authentication-Method',
  'HTTP_X_SHIB_AUTHNCONTEXT_CLASS' => 'X-Shib-AuthnContext-Class',
  'HTTP_X_SHIB_DISPLAYNAME' => 'X-Shib-displayName',
  'HTTP_X_SHIB_EDUPERSONPRINCIPALNAME' => 'X-Shib-eduPersonPrincipalName',
  'HTTP_X_SHIB_EDUPERSONSCOPEDAFFILIATION' => 'X-Shib-eduPersonScopedAffiliation',
  'HTTP_X_SHIB_IDENTITY_PROVIDER' => 'X-Shib-Identity-Provider',
  'HTTP_X_SHIB_MAIL' => 'X-Shib-mail',
  'HTTP_X_SHIB_PERSISTENT_ID' => 'X-Shib-Persistent-ID',
  'REMOTE_USER' => 'X-Remote-User',
  'HTTP_X_FORWARDED_PROTO' => 'X-Forwarded-Proto'
};
  

sub call {
  my ($self, $env) = @_;

  foreach my $key (keys %$SHIB_ENV_VARS) {
    $env->{$SHIB_ENV_VARS->{$key}} = $ENV{$key};
    delete $ENV{$key};
  }
  return $self->app->($env);
}

1;

