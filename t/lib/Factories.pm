package Factories;

use strict;
use warnings;
use Data::Dumper;
use Data::Faker;
use Data::Faker::Internet;
use FindBin;

use lib $FindBin::Bin;
use TestHelper;

use User;

sub User {
  my $user = User->new(email => Data::Faker::Internet->email,
    name => Data::Faker->name, @_);
  $user->save;
  return $user;
}

1;
