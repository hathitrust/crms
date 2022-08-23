package App::Controller;

use strict;
use warnings;

use Carp;
use Data::Dumper;
use Plack::Response;

use App::I18n;
use App::Presenter;
use App::Renderer;
use App::Router;

sub new {
  my ($class, %args) = @_;
  my $self = bless {}, $class;
  $self->{$_} = $args{$_} for keys %args;
  Carp::confess "No Params object passed to Controller" unless $args{params};
  Carp::confess "No Request object passed to Controller" unless $args{req};
  Carp::confess "No TT Vars object passed to Controller" unless $args{vars};
  #Carp::confess "No model name passed to Controller" unless $args{model};
  $self->{vars}->{presenter} = $self->__presenter;
  return $self;
}

# FIXME: should controller actions take the modified params hash directly?
# FIXME: what should the return value if process and controller actions be?
# May return a Plack response arrayref if a redirect is needed, default is undef
# in which case the rendered output is in controller->{body}.
sub process {
  my $self   = shift;
  my $action = shift;

  $self->__populate_params;
  # Because we need a "new" action but can't have another "new" method.
  my $method = '__' . $action;
  #$self->{vars}->{flash}->add('notice',
  #  sprintf("App::Controller->process trying $method with params %s", Dumper $self->{params}));
  if (my $ref = eval { $self->can($method); }) {
    $self->__before_action($action);
    return $self->$ref();
  }
  return [404, [], ['not found']];
}

# Called by action methods
sub render {
  my $self     = shift;
  my $template = shift;
  my $layout   = shift;

  my $renderer = App::Renderer->new(vars => $self->{vars});
  #$self->{vars}->{flash}->add('notice',
  #  sprintf("Controller->render with renderer %s", Dumper $renderer));
  eval {
    my $body = $renderer->render($template, $layout);
    $self->{body} = $body;
  };
  if ($@) {
     $self->{body} = $@;
  } else {
  #$self->{vars}->{flash}->add('notice',
  #  sprintf("Controller->render got body <pre>%s<pre>", Dumper $self->{body}));
  }
  return;
}

# Called by action methods
sub redirect {
  my $self = shift;
  my $url  = shift;

  #return [302, [ 'Location' => $url ], [] ];
  my $res = Plack::Response->new();
  $res->redirect($url);
  return $res->finalize;
}

# For use by view templates that don't have direct access to the Router
sub path_for {
  my $self   = shift;
  my $action = shift;
  my $id     = shift;

  return App::Router->new->path_for($action, $self->{model}, $id);
}
  

# Rails wannabe trigger warning.
# Massages $req->parameters of the form "user[name]" into self->{params}->{user}->{name}
# Other params become self->{params}->{whatever}
sub __populate_params {
  my $self = shift;

  my %params;
  # Merge the existing params (from the route match) first.
  foreach my $key (keys %{$self->{params}}) {
    $params{$key} = $self->{params}->{$key};
  }
  my $req_params = $self->{req}->parameters;
  foreach my $key (keys %$req_params) {
    my @values = $req_params->get_all($key);
    # Last param with this key in the form wins.
    # That's how we do the hidden checkbox trick Rails-style.
    my $value = $values[-1];
    if ($key =~ m/^(.+?)\[(.+?)\]\[(.+?)\]$/) {
      $params{$1}->{$2}->{$3} = $value;
    } elsif ($key =~ m/^(.+?)\[(.+?)\]$/) {
      $params{$1}->{$2} = $value;
    } else {
      $params{$key} = $value;
    }
  }
  $self->{params} = \%params;
}

sub __presenter {
  my $self = shift;

  my $class = 'App::Presenter';
  if (defined $self->{model}) {
    my $class_name = ucfirst($self->{model}) . 'Presenter';
    my $file = 'App/Presenters/'. $class_name . '.pm';
    my $full_path = $ENV{'SDRROOT'} . '/crms/lib/' . $file;
    if (-f $full_path) {
      require $file;
      $class .= "s::$class_name";
    }
  }
  return $class->new(controller => $self, model => $self->{model});
}

sub __before_action {
  my $self   = shift;
  my $action = shift;

  # May be implemented by subclasses
}

1;
