use strict;
use warnings;

package Plack::Middleware::RewriteShibEnv;
use parent 'Plack::Middleware';

# If REMOTE_USER doesn't need the transformation to HTTP_X_REMOTE_USER then
# the keys can be used as an array with no name translation needed.
my $SHIB_ENV_VARS = {
  'HTTP_X_SHIB_AUTHENTICATION_METHOD' => 'HTTP_X_SHIB_AUTHENTICATION_METHOD',
  'HTTP_X_SHIB_AUTHNCONTEXT_CLASS' => 'HTTP_X_SHIB_AUTHNCONTEXT_CLASS',
  'HTTP_X_SHIB_DISPLAYNAME' => 'HTTP_X_SHIB_DISPLAYNAME',
  'HTTP_X_SHIB_EDUPERSONPRINCIPALNAME' => 'HTTP_X_SHIB_EDUPERSONPRINCIPALNAME',
  'HTTP_X_SHIB_EDUPERSONSCOPEDAFFILIATION' => 'HTTP_X_SHIB_EDUPERSONSCOPEDAFFILIATION',
  'HTTP_X_SHIB_IDENTITY_PROVIDER' => 'HTTP_X_SHIB_IDENTITY_PROVIDER',
  'HTTP_X_SHIB_MAIL' => 'HTTP_X_SHIB_MAIL',
  'HTTP_X_SHIB_PERSISTENT_ID' => 'HTTP_X_SHIB_PERSISTENT_ID',
  'REMOTE_USER' => 'HTTP_X_REMOTE_USER',
  'HTTP_X_FORWARDED_PROTO' => 'HTTP_X_FORWARDED_PROTO'
};

sub call {
  my ($self, $env) = @_;

  foreach my $key (keys %$SHIB_ENV_VARS) {
    if (defined $env->{$SHIB_ENV_VARS->{$key}}) {
      $env->{$SHIB_ENV_VARS->{$key}} = $ENV{$key};
    }
    # Not sure why this would be necessary.
    #delete $ENV{$key};
  }
  return $self->app->($env);
}

1;
