BEGIN {
  unshift(@INC, $ENV{'SDRROOT'}. '/crms/cgi');
  unshift(@INC, $ENV{'SDRROOT'}. '/crms/lib');
}

use strict;
use warnings;
use utf8;

use Carp;
use CGI;
use CGI::Cookie;
use CGI::PSGI;
use Data::Dumper;
use Encode;
use FindBin;
use Plack::App::File;
use Plack::Builder;
use POSIX;
use Template;
use URI::Escape;

#use Unicode::UTF8;
#use warnings FATAL => 'utf8'; # fatalize encoding glitches


use CRMS;
use CRMS::Session;
use User;
use Utilities;

#binmode STDOUT, ':encoding(UTF-8)';
#binmode STDERR, ':encoding(UTF-8)';

$CGI::LIST_CONTEXT_WARN = 0;

my $app = builder {
    mount "/crms" => \&serve_root;
    mount "/crms/web" => Plack::App::File->new(root => '/htapps/babel/crms/web')->to_app;
};


sub serve_root {
  my $env = shift;

  my $cookie;
  my $output = '';
eval {
  my $req = CGI::PSGI->new($env);
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
  }
  my $user = $session->{'user'};
  my $alias_user_id = undef;

  my $debug_note = '';
  # Alias stuff is for dev only.
  if ($crms->Instance() eq 'dev' && defined $user) {
    #$debug_note .= "\$crms->Instance() eq 'dev' && defined \$user\n";
    # Set alias if changing to user.
    if (defined $req->param('changeuser') && $req->param('changeuser') == 1) {
      #$debug_note .= "defined \$req->param('changeuser') && \$req->param('changeuser') == 1\n";
      $alias_user_id = $req->param('newuser');
      #$req->delete_all();
    }
    # Set alias if alias is cookified
    if (!defined $alias_user_id) {
      #$debug_note .= "!defined \$alias_user_id\n";
      $alias_user_id = $req->cookie('alias_user_id');
      #$debug_note .= "alias_user_id FROM COOKIE $alias_user_id\n";
    }
    # Set cookie
    if (defined $alias_user_id) {
      #$debug_note .= "SET alias_user_id to $alias_user_id\n";
      $session->SetAlias($alias_user_id);
      if (defined $session->{'alias_user_id'}) {
        $user = User::Find($session->{'alias_user_id'});
        $debug_note .= "<strong>Running under alias $user->{name} ($user->{id})</strong>\n";
        # Can't use secure cookie if we want this to run on localhost
        $cookie = CGI::Cookie->new(-name     => 'alias_user_id',
                                   -value    => $alias_user_id,
                                   -expires  => '+3M',
                                   -samesite => 'Strict');
      }
    }
  }

  if ($page eq 'Logout')
  {
    # Remove all locks for this user.
    # If we're aliased, we don't log out, we just drop the alias.
    $crms->UnlockAllItemsForUser($session->{'user'});
    if ($session->{'alias_user_id'}) {
      $session->SetAlias();
      #$user = $crms->GetUser();
      $user = User::Find($session->{'remote_user'});
      $cookie = CGI::Cookie->new(-name     => 'alias_user_id',
                                 -value    => '',
                                 -expires  => '-3M',
                                 -samesite => 'Strict');
      $req->delete_all();
      $debug_note .= "COOKIE SET: $cookie\n";
    }
  }
  $crms->AddUserFields($user);
  my $template = $page . '.tt';
  my $full_path = $ENV{'SDRROOT'} . '/crms/cgi/' . $template;
  $template = 'home.tt' unless -f $full_path;

  ## config options for TT
  my $config = {
    INCLUDE_PATH => $ENV{'SDRROOT'}. '/crms/cgi',
    INTERPOLATE  => 1,     ## expand "$var" in plain text
    POST_CHOMP   => 1,     ## cleanup whitespace
    EVAL_PERL    => 1,     ## evaluate Perl code blocks
    ENCODING     => 'UTF-8'
  };

  my $tt = Template->new($config);
  my $vars = {
    crms         => $crms,
    cgi          => $req,
    current_user => $user,
    utils        => Utilities->new(),
    flash        => []
  };

  #print $req->header(-charset => 'utf-8',
  #                   -Cache_control => 'no-cache, no-store, must-revalidate',
  #                   -expires => '-1m',
  #                   -cookie => $cookie);
  if (!$tt->process($template, $vars, \$output)) {
    my $tt_err = $tt->error;
    $tt_err =~ s/\n+/<br\/>\n/gm;
    push @{$vars->{flash}}, $tt_err;
    $output .= sprintf "<h3>%s</h3>\n", $tt_err;
  }
  if (length $debug_note) {
    $debug_note =~ s/\n+/<br\/>\n/gm;
    push @{$vars->{flash}}, $debug_note;
  }
  my $layout = 'layout.tt';
  $vars->{content} = $output;
  $output = '';
  # PROCESS LAYOUT WITH CONTENT OF MAIN TEMPLATE
  if (!$tt->process($layout, $vars, \$output)) {
    $output .= sprintf "<h3><pre>%s</pre></h3>\n", $tt->error();
  }

  $output .= sprintf "<br/>COOKIE: <pre>%s</pre><br/>\n", ($cookie || '<blank>');
  $output .= sprintf "<br/>PSGI URL: <pre>%s</pre><br/>\n", $req->url;
  #$output .= sprintf "<br/>PSGI path: <pre>%s</pre><br/>\n", $req->path_info;
  #$output .= sprintf "<br/><br/><h4>INSTANCE</h4><br/><pre>%s</pre><br/>\n", Dumper $crms->Instance;
  $output .= sprintf "<br/><br/><h4>USER</h4><br/><pre>%s</pre><br/>\n", Dumper $user;
  #$output .= sprintf "<br/><br/><h4>CGI::PSGI REQUEST</h4><br/><pre>%s</pre><br/>\n", Dumper $req;
  $output .= sprintf "<br/><br/><h4>ENV</h4><br/><pre>%s</pre><br/>\n", Dumper $env;
  # Don't know why this is needed for adminUser.tt
  $output = Encode::encode_utf8($output);
};
if ($@) {
  $output = $@;
  $output =~ s/\n+/<br\/>\n/gm;
}
  return [
      '200',
      [ 'Content-Type' => 'text/html;charset=UTF-8',
        'Set-Cookie' => $cookie ],
      [ $output ],
  ];
}
