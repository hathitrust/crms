use strict;
use warnings;

use FindBin;
use HTTP::Request::Common qw(GET);
use Plack::Test;
use Plack::Util;
use Test::More;

use lib "$FindBin::Bin/lib";

use TestHelper;

#my $app = do 'cgi/crms.psgi';
my $app = Plack::Util::load_psgi "$FindBin::Bin/../cgi/crms.psgi";
 
my $test = Plack::Test->create($app);
 
#my $main = path('www/index.html')->slurp_utf8;
subtest "/crms" => sub {
  my $res = $test->request(GET "/crms"); # HTTP::Response
  is $res->code, 200;
  is $res->message, 'OK';
  #diag $res->headers; #HTTP::Headers
  #diag explain [ $res->headers->header_field_names ];
  #is $res->header('Content-Length'), length $main;
  is $res->header('Content-Type'), 'text/html; charset=utf-8';
  #diag $res->header('Last-Modified');
  #is $res->content, $main;
};

# FIXME: move this to t/app/users.t
subtest "/crms/users" => sub {
  my $res = $test->request(GET "/crms/users");
  is $res->code, 200;
  is $res->message, 'OK';
  is $res->header('Content-Type'), 'text/html; charset=utf-8';
};

subtest "/crms/users/:id" => sub {
  my $sql = 'SELECT id,name FROM users LIMIT 1';
  my $ref = TestHelper->new->db->selectall_arrayref($sql);
  my ($uid, $name) = @{$ref->[0]};
  my $res = $test->request(GET "/crms/users/$uid");
  is $res->code, 200;
  is $res->message, 'OK';
  is $res->header('Content-Type'), 'text/html; charset=utf-8';
  $name = Utilities->new->EscapeHTML($name);
  ok(index($res->content, $name) >= 0);
};

subtest "/crms/queue" => sub {
  my $res = $test->request(GET "/crms/queue");
  is $res->code, 200;
  is $res->message, 'OK';
  is $res->header('Content-Type'), 'text/html; charset=utf-8';
};

done_testing();
