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
#use Encode;
#use FindBin;
use JSON::XS;
use Plack::App::File;
use Plack::Builder;
#use POSIX;
#use Template;
#use URI::Escape;

use App::Root;
#use CRMS;
#use CRMS::Session;
#use User;
#use Utilities;

$CGI::LIST_CONTEXT_WARN = 0;

my $app = builder {
  enable "TrailingSlashKiller", redirect => 1;
  mount "/crms" => \&App::Root::run;
  mount "/api/v1" => \&serve_api;
  mount "/crms/web" => Plack::App::File->new(root => '/htapps/babel/crms/web')->to_app;
};

sub serve_api {
  my $env = shift;

  my $req = CGI::PSGI->new($env);
  my $data = Dumper $req->path_info;
  my $json = JSON::XS->new->encode($data);

  return [
      '200',
      [ 'Content-Type' => 'application/json;charset=UTF-8' ],
      [ $json ],
  ];
}



