use strict;
use warnings;
use utf8;

use FindBin;
use Test::More;

use lib "$FindBin::Bin/lib";
use TestHelper;
use Metadata;

test_xml_input();
test_us_cities();

sub test_xml_input {
  my $file = TestHelper::fixtures_directory() . '/metadata/000317872.xml';
  open my $fh, '<:utf8', $file or die "error opening $file: $!";
  read $fh, my $xml, -s $file;
  close $fh;
  my $record = Metadata->new('id' => 'mdp.39015078588566', 'xml' => $xml);
  ok(ref $record eq 'Metadata');
}

sub test_us_cities {
  my $cities = Metadata::US_Cities;
  ok(ref $cities eq 'HASH', 'Metadata::US_Cities return value is a hashref');
  ok(scalar keys %$cities > 0, 'Metadata::US_Cities hash has multiple keys');

  my $record = Metadata->new('id' => 'coo.31924000029250');
  $cities = $record->cities;
  ok(ref $cities eq 'HASH', 'cities return value is a hashref');
  ok(ref $cities->{'us'} eq 'ARRAY', 'cities us value is an arrayref');
  ok(ref $cities->{'non-us'} eq 'ARRAY', 'cities non-us value is an arrayref');
}

done_testing();
