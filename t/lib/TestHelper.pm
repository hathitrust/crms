package TestHelper;

use strict;
use warnings;
use utf8;
use 5.010;

use lib "$ENV{SDRROOT}/crms/cgi";
use lib "$ENV{SDRROOT}/crms/lib";

use CRMS;

my $SHARED_CRMS;

sub fixtures_directory {
  state $fixtures_dir = $ENV{'SDRROOT'} . '/crms/t/fixtures/';

  return $fixtures_dir;
}

sub CRMS {
  return $SHARED_CRMS if defined $SHARED_CRMS;

  my $cgi = CGI->new();
  $SHARED_CRMS = CRMS->new('cgi' => $cgi, 'verbose' => 0);
  return $SHARED_CRMS;
}

1;
