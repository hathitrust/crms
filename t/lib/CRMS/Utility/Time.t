use strict;
use warnings;
use utf8;

use Test::Exception;
use Test::More;

use lib "$ENV{SDRROOT}/crms/lib";

use CRMS::Database;
use CRMS::Utility::Time;

subtest '#new' => sub {
  ok(defined CRMS::Utility::Time->new);
};

subtest '#year' => sub {
  my $year = CRMS::Utility::Time->new->year;
  ok(
    $year eq CRMS::Database->new->one('SELECT YEAR(NOW())'), 'year matches DB year'
  );
};

done_testing();
