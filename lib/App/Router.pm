package App::Router;

use strict;
use warnings;
use utf8;

#BEGIN {
#  unshift(@INC, $ENV{'SDRROOT'}. '/crms/cgi');
#  unshift(@INC, $ENV{'SDRROOT'}. '/crms/lib');
#}


use Router::Simple;

use App::I18n;

# Path, controller, action, method, model
# FIXME: stick this in a config file
my $ROUTE_DATA = [
  ['/', 'AppController', 'index', 'GET'],
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
  $self->__setup;
  $ROUTER_SINGLETON = $self;
  return $self;
}

sub __setup {
  my $self = shift;

  $self->{router_simple} = Router::Simple->new();
  foreach my $data (@$ROUTE_DATA) {
    $self->{router_simple}->connect($data->[0], {controller => $data->[1], action => $data->[2]}, {method => $data->[3]});
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
  my $model  = shift;
  my $id     = shift;

  my $path;
  foreach my $data (@$ROUTE_DATA) {
    if ($action eq $data->[2] && $model eq $data->[4]) {
      $path = $data->[0];
      if (defined $id) {
        $path =~ s/:id/$id/g;
      }
    }
  }
  $path = $self->{prefix} . $path;
  $path .= '?';
  $path .= 'locale=' . App::I18n::CurrentLocale();
  return $path;
}

1;
