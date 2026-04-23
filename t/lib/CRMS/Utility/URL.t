use strict;
use warnings;
use utf8;

use Test::Exception;
use Test::More;

use lib "$ENV{SDRROOT}/crms/lib";

use CRMS::Utility::URL;

subtest '#new' => sub {
  ok(defined CRMS::Utility::URL->new);
};

#subtest '#css_url' => sub {
#  my $file = 'review.css';
#  my $url = CRMS::Utility::URL->new->css_url($file);
#  ok(length $url > 0, 'produces a URL string');
#  ok($url =~ m/\?v=\d+$/, 'URL has a cache buster param');
#};

subtest '#js_url' => sub {
  my $file = 'main.js';
  my $url = CRMS::Utility::URL->new->js_url($file);
  ok(length $url > 0, 'produces a URL string');
  ok($url =~ m/\?v=\d+$/, 'URL has a cache buster param');
};

done_testing();
