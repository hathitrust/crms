package FakeMetadata;

# For testing with minimal records where we're mainly interested in the 008
# and using a fixture would be overkill.

use strict;
use warnings;
use v5.10;

use Clone;

use lib $ENV{'SDRROOT'} . '/crms/cgi';
use Metadata;

sub fake_record {
  my $xml  = shift;
  my $cid  = shift || '000000000';
  my $htid = shift || 'test.000';

  state $JSON_TEMPLATE = {
    'records' => {
      '000000000' => {
        'recordURL' => '',
        'titles' => [],
        'isbns' => [],
        'issns' => [],
        'oclcs' => [],
        'lccns' => [],
        'publishDates' => [],
        'marc-xml' => ''
      }
    },
    'items' => [
      {
        'orig' => '',
        'fromRecord' => $cid,
        'htid' => '',
        'itemURL' => '',
        'rightsCode' => 'ic',
        'lastUpdate' => '20230101',
        'enumcron' => undef,
        'usRightsString' => 'Limited (search-only)'
      }
    ]
  };
  my $json = Clone::clone($JSON_TEMPLATE);
  my @keys = keys %{$json->{records}};
  $json->{'records'}->{$cid} = delete $json->{records}->{'000000000'};
  $json->{'records'}->{$cid}->{'marc-xml'} = $xml;
  my $record = Metadata->new(id => $htid, json => $json);
  return $record;
}

sub fake_record_with_008_and_leader {
  my $f008   = shift || '850423s1951    at a          000 0 eng d';
  my $leader = shift || '00437cam a22001571  4500';

  my $xml = <<END_XML;
<?xml version="1.0" encoding="UTF-8"?>
  <collection xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns="http://www.loc.gov/MARC21/slim" xsi:schemaLocation="http://www.loc.gov/MARC21/slim http://www.loc.gov/standards/marcxml/schema/MARC21slim.xsd">
    <record>
      <leader>$leader</leader>
      <controlfield tag="008">$f008</controlfield>
    </record>
  </collection>
END_XML
  return fake_record($xml);
}

1;
