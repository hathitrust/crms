package App::Router;

use strict;
use warnings;
use utf8;

use Data::Dumper;
use Router::Simple;
use URI;

use App::I18n;

# Path, controller, action, method, model
# FIXME: stick this in a config file
my $ROUTE_DATA = [
  ['/', 'AppController', 'index', 'GET'],
  ['/queue', 'QueueController', 'index', 'GET', 'queue'],
  ['/queue/new', 'QueueController', 'new', 'GET', 'queue'],
  ['/queue/new', 'QueueController', 'create', 'POST', 'queue'],
  ['/users', 'UsersController', 'index', 'GET', 'user'],
  ['/users/:id', 'UsersController', 'show', 'GET', 'user'],
  ['/users/:id/edit', 'UsersController', 'edit', 'GET', 'user'],
  ['/users/:id', 'UsersController', 'update', 'POST', 'user'],
  ['/users/new', 'UsersController', 'new', 'GET', 'user'],
  ['/users/new', 'UsersController', 'create', 'POST', 'user']
];

my $ROUTER_SINGLETON;

sub new {
  return $ROUTER_SINGLETON if defined $ROUTER_SINGLETON;

  my ($class, %args) = @_;
  my $self = bless {}, $class;
  $self->{$_} = $args{$_} for keys %args;
  $self->{prefix} = '' unless defined $self->{prefix};
  Carp::confess "No Request object passed to Router" unless $args{req};
  $self->__setup;
  $ROUTER_SINGLETON = $self;
  return $self;
}

sub __setup {
  my $self = shift;

  $self->{router_simple} = Router::Simple->new();
  foreach my $data (@$ROUTE_DATA) {
    $self->{router_simple}->connect($data->[0],
      {controller => $data->[1], action => $data->[2], model => $data->[4]},
      {method => $data->[3]});
  }
}

sub match {
  my $self = shift;

  return $self->{router_simple}->match(@_);
}

sub as_string {
  my $self = shift;

  return $self->{router_simple}->as_string(@_);
}

sub path_for {
  my $self   = shift;
  my $action = shift;
  my $model  = shift || '';
  my $id     = shift;

  my $path;
  foreach my $data (@$ROUTE_DATA) {
    # print STDERR "App::Router::path_for uninitialized action\n" unless defined $action;
#     print STDERR "App::Router::path_for uninitialized data->[2] from $data\n" unless defined $data->[2];
#     print STDERR "App::Router::path_for uninitialized model\n" unless defined $model;
#     print STDERR sprintf("App::Router::path_for uninitialized data->[4] in %s\n", Dumper($data)) unless defined $data->[4];
    my $route_model = $data->[4] || '';
    if ($action eq $data->[2] && $model eq $route_model) {
      $path = $data->[0];
      if (defined $id) {
        $path =~ s/:id/$id/g;
      }
    }
  }
  $path = $self->{prefix} . $path;
  #$path .= '?';
  #$path .= 'locale=' . App::I18n::CurrentLocale();
  #$path = $self->put_locale('locale', App::I18n::CurrentLocale(), $path);
  return $self->put_locale($path);
}

# Add or replace a GET parameter in the passed or current URI
sub put_param {
  my $self  = shift;
  my $name  = shift;
  my $value = shift;
  my $uri   = shift || $self->{req}->uri;

  if (defined $uri) {
    # Assume string
    $uri = URI->new($uri);
  } else {
    $uri = $self->{req}->uri;
  }
  # FIXME:detect string form of URI and create whatever object Plack::Request is using.
  my $new_uri = $uri->clone;
  $new_uri->query_param($name => $value);
  return $new_uri->as_string;
}

sub put_locale {
  my $self = shift;
  my $path = shift;

  return $self->put_param('locale', App::I18n::CurrentLocale(), $path);
}


1;
