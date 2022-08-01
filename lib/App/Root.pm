package App::Root;

BEGIN {
  unshift(@INC, $ENV{'SDRROOT'}. '/crms/cgi');
  unshift(@INC, $ENV{'SDRROOT'}. '/crms/lib');
}

use strict;
use warnings;
use utf8;

use Carp;
#use CGI;
use CGI::Cookie;
use CGI::PSGI;
use Data::Dumper;
use Encode;
use FindBin;
use Plack::Builder;
use Plack::Request;
use POSIX;
use Router::Simple;
use Template;
use URI::Escape;

use App::Flash;

use CRMS;
use CRMS::Session;
use User;
use Utilities;

my $router;

sub setup_router {
  return if defined $router;
  $router = Router::Simple->new();
  $router->connect('/', {controller => 'AppController', action => 'index'}, {method => 'GET'});
  $router->connect('/users', {controller => 'UsersController', action => 'index'}, {method => 'GET'});
  $router->connect('/users/:id', {controller => 'UsersController', action => 'show'}, {method => 'GET'});
  $router->connect('/users/:id/edit', {controller => 'UsersController', action => 'edit'}, {method => 'GET'});
  $router->connect('/users/:id', {controller => 'UsersController', action => 'update'}, {method => 'POST'});
  $router->connect('/users/new', {controller => 'UsersController', action => 'new'}, {method => 'GET'});
  $router->connect('/users/new', {controller => 'UsersController', action => 'create'}, {method => 'POST'});
}

$CGI::LIST_CONTEXT_WARN = 0;

sub run {
  my $env = shift;

  setup_router();
  my $cookie;
  my $req = Plack::Request->new($env);
  ## the template page (tt) is called based on the CGI 'p' param (ex editReviews -> editReviews.tt)
  ## the default is home.tt in case a tt is not found
  my $page = $req->param('p') || 'home';
  my $debug = $req->param('debug');
  my $crms = CRMS->new;
  my $session = CRMS::Session->new;
  # Set up default admin user if running in dev
  if ($crms->Instance eq 'dev') {
    my $default_user = User::Where(name => 'Default Admin')->[0];
    $session->{remote_user} = $default_user->{id};
    $session->{user} = $default_user;
  } else {
    if (defined $session->{stepup_redirect}) {
      my $url = $session->{stepup_redirect};
      $url .= "&target=" . URI::Escape::uri_escape($req->uri);
      return Plack::Response->new->redirect($url)->finalize;
    }
  }
  # Alias stuff is for dev only.
  if ($crms->Instance() eq 'dev') {
    my $alias_user_id;
    # Set alias if changing to user.
    if (defined $req->param('changeuser') && $req->param('changeuser') == 1) {
      $alias_user_id = $req->param('newuser');
    }
    # Set alias if alias is cookified
    if (!defined $alias_user_id) {
      $alias_user_id = $req->cookies->{alias_user_id};
    }
    # Set cookie
    if (defined $alias_user_id) {
      $session->SetAlias($alias_user_id);
      if (defined $session->{'alias_user_id'}) {
        # Can't use secure cookie if we want this to run on localhost
        $cookie = CGI::Cookie->new(-name     => 'alias_user_id',
                                   -value    => $alias_user_id,
                                   -expires  => '+3M',
                                   -samesite => 'Strict');
      }
    }
  }

  if ($page eq 'Logout') {
    # Remove all locks for this user.
    # If we're aliased, we don't log out, we just drop the alias.
    $crms->UnlockAllItemsForUser($session->{'user'});
    if ($session->{'alias_user_id'}) {
      $session->SetAlias();
      $cookie = CGI::Cookie->new(-name     => 'alias_user_id',
                                 -value    => '',
                                 -expires  => '-3M',
                                 -samesite => 'Strict');
      #$req->delete_all();
      $page = 'home';
    }
  }
  my $response = eval {
    my $match = $router->match($env);
    if (!defined $match) {
      return [404, [], ['not found']];
    }
    my $tt_vars = {
      crms         => $crms,
      cgi          => $req,
      current_user => $session->{user},
      utils        => Utilities->new(),
      flash        => App::Flash->new()
    };
    my $controller = GetControllerFromClassName($match->{controller}, $tt_vars, $req, $match);
    my $response = undef;
    if (defined $controller) {
      $tt_vars->{controller} = $controller;
      $response = $controller->process($match->{action});
    }
    return $response if defined $response;
    my $body = $controller->{body};
    #$body .= sprintf("<br/><br/><h4>ROUTES</h4><br/><pre>%s</pre><br/>\n", $router->as_string);
    #$body .= sprintf("<br/><br/><h4>ROUTER MATCH</h4><br/><pre>%s</pre><br/>\n", Dumper $match);
    #$body .= sprintf "<br/><br/><h4>Controller</h4><br/><pre>%s</pre><br/>\n", Dumper $controller;
    #$body .= sprintf "<br/><br/><h4>TT VARS</h4><br/><pre>%s</pre><br/>\n", Dumper $tt_vars;
    #$body .= sprintf "<br/>COOKIE: <pre>%s</pre><br/>\n", ($cookie || '<blank>');
    #$body .= sprintf "<br/>PSGI URI: <pre>%s</pre><br/>\n", $req->uri;
    #$body .= sprintf "<br/><br/><h4>USER</h4><br/><pre>%s</pre><br/>\n", Dumper $session->{user};
    #$body .= sprintf "<br/><br/><h4>ENV</h4><br/><pre>%s</pre><br/>\n", Dumper $env;
    $body = Encode::encode_utf8($body);
    return [
        '200',
        [ 'Content-Type' => 'text/html;charset=UTF-8',
          'Set-Cookie' => $cookie ],
        [ $body ],
    ]; 
  };
  if ($@) {
    my $body = $@;
    $body =~ s/\n+/<br\/>\n/gm;
    $response = [
      '200',
      [ 'Content-Type' => 'text/html;charset=UTF-8' ],
      [ $body ],
    ];
  }
  return $response;
}

sub GetControllerFromClassName {
  my $name = shift;
  my $tt_vars = shift;
  my $req = shift;
  my $match = shift;

  my $file = 'App/Controllers/'. $name. '.pm';
  #my $full_path = $ENV{'SDRROOT'} . '/crms/lib/' . $file;
  #return unless -f $full_path;
  require $file;
  my $class = 'App::Controllers::'. $name;
  my $controller = $class->new(req => $req, vars => $tt_vars, params => $match);
  # if ($@) {
#     $tt_vars->{flash}->add('alert', "Controller error $@");
#     $controller = undef;
#   }
  return $controller;
}

return 1;
