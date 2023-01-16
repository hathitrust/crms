package Metadata;

# An interface to the HathiTrust Bib API tailored to CRMS requirements.

# Some of the functionality here may be replaced via an intermediate layer
# using MARC::Record and MARC::File::XML, jettisoning some of the homebrew stuff.

# For testing with static fixtures, set CRMS_METADATA_FIXTURES_PATH
# and the module will fetch an id like '123456789' from
# CRMS_METADATA_FIXTURES_PATH + /123456789.json

use vars qw(@ISA @EXPORT @EXPORT_OK);

use strict;
use warnings;
use utf8;

use Carp;
use DB_File;
use File::Slurp;
use JSON::XS;
use LWP::UserAgent;
use Unicode::Normalize;
use XML::LibXML;

my $US_CITIES;

# TODO: this is duplicative of code in post_zephir_processing/bib_rights.pm
sub US_Cities {
  if (!defined $US_CITIES) {
    my %us_cities;
    my $us_cities_db = $ENV{'SDRROOT'} . '/crms/post_zephir_processing/data/us_cities.db';
    tie %us_cities, 'DB_File', $us_cities_db, O_RDONLY, 0644, $DB_BTREE or die "can't open db file $us_cities_db: $!";
    $US_CITIES = \%us_cities;
  }
  return $US_CITIES;
}

sub new
{
  my ($class, %args) = @_;
  my $self = bless {}, $class;
  $self->{$_} = $args{$_} for keys %args;
  my $id = $args{id};
  $self->{sysid} = $id if $id !~ m/\./;
  $self->{id} = $id;
  $self->json unless $self->is_error;
  $self->xml unless $self->is_error;
  return $self;
}

sub set_error
{
  my $self  = shift;
  my $error = shift;
  $self->{error} = "[$self->{id}] $error";
}

sub is_error {
  my $self = shift;
  return defined $self->{error};
}

sub error {
  my $self = shift;
  return $self->{error};
}

sub id
{
  my $self = shift;
  return $self->{id};
}

sub sysid
{
  my $self = shift;
  if (!defined $self->{sysid}) {
    my $records = $self->json->{'records'};
    if ('HASH' eq ref $records) {
      my @keys = keys %$records;
      $self->{sysid} = $keys[0];
    }
  }
  return $self->{sysid};
}

sub json
{
  my $self = shift;
  my $json = $self->{json};
  if (!defined $json)
  {
    my $content = $self->fetch_record($self->{sysid} || $self->{id});
    return unless defined $content;
    # Sometimes the API can return diagnostic information up top,
    # so we cut that out.
    $content =~ s/^(.*?)(\{"records":)/$2/s;
    eval {
      $json = JSON::XS->new->decode($content);
      my $records = $json->{'records'};
      if ('HASH' eq ref $records) {
        my @keys = keys %$records;
        $self->{sysid} = $keys[0];
      }
    };
    if ($@) {
      $self->set_error("$@ ($content)");
    }
    $self->{json} = $json;
  }
  return $json;
}

sub fetch_record {
  my $self = shift;
  my $id   = shift;

  if ($ENV{CRMS_METADATA_FIXTURES_PATH}) {
    return $self->fetch_fixture($id);
  }
  my $type = ($id =~ m/\./)? 'htid' : 'recordnumber';
  my $url = "https://catalog.hathitrust.org/api/volumes/full/$type/$id.json";
  my $attempt = 1;
  my $err = undef;
  while ($attempt <= 3) {
    my $ua = LWP::UserAgent->new;
    $ua->timeout(1000 * $attempt);
    my $req = HTTP::Request->new(GET => $url);
    my $res = $ua->request($req);
    if ($res->is_error) {
      $err = sprintf "%d %s from $url\n", $res->code, $res->message;
    }
    else {
      return Unicode::Normalize::NFC($res->content);
    }
    $attempt++;
  }
  $self->set_error($err);
  return;
}

sub fetch_fixture {
  my $self = shift;
  my $id   = shift;

  my $fixture = "$ENV{CRMS_METADATA_FIXTURES_PATH}/$id.json";
  unless (-r $fixture) {
    $self->set_error("cannot read fixture at $fixture");
    return;
  }
  return File::Slurp::read_file($fixture);
}

sub xml {
  my $self = shift;
  if (!defined $self->{xml})
  {
    my $json = $self->json;
    my $records = $json->{'records'};
    my @keys = keys %$records;
    my $source;
    if (scalar @keys) {
      my $xml = $records->{$keys[0]}->{'marc-xml'};
      my $parser = XML::LibXML->new();
      eval {
        $source = $parser->parse_string($xml);
      };
      if (!scalar @keys || $@) {
        $self->set_error("failed to parse ($xml): $@");
        return;
      }
    }
    else {
      $self->set_error('no records found');
      return;
    }
    my $root = $source->getDocumentElement();
    my @records = $root->findnodes('//*[local-name()="record"]');
    $self->{xml} = $records[0];
  }
  return $self->{xml};
}

sub leader
{
  my $self = shift;

  return $self->xml->findvalue('//*[local-name()="leader"]');
}

sub fmt
{
  my $self = shift;

  my $ldr  = $self->leader;
  my $type = substr $ldr, 6, 1;
  my $lev  = substr $ldr, 7, 1;
  my %bktypes = ('a'=>1, 't'=>1);
  my %bklevs = ('a'=>1, 'c'=>1, 'd'=>1, 'm'=>1);
  my %types = ('a' => 'Language material',
               'c' => 'Notated music',
               'd' => 'Manuscript notated music',
               'e' => 'Cartographic material',
               'f' => 'Manuscript cartographic material',
               'g' => 'Projected medium',
               'i' => 'Nonmusical sound recording',
               'j' => 'Musical sound recording',
               'k' => 'Two-dimensional nonprojectable graphic',
               'm' => 'Computer file',
               'o' => 'Kit',
               'p' => 'Mixed materials',
               'r' => 'Three-dimensional artifact or naturally occurring object',
               't' => 'Manuscript language material');

  my %levs = ('a' => 'Monographic component part',
              'b' => 'Serial component part',
              'c' => 'Collection',
              'd' => 'Subunit',
              'i' => 'Integrating resource',
              'm' => 'Monograph/Item',
              's' => 'Serial');
  my $fmt;
  if (defined $bktypes{$type} && defined $bklevs{$lev})
  {
    $fmt = 'Book';
  }
  elsif (defined $bktypes{$type} && !defined $bklevs{$lev})
  {
    $fmt = $levs{$lev};
  }
  else
  {
    $fmt = $types{$type};
  }
  return $fmt;
}

# This is the correct way to do it.
# Look at leader[6] and leader[7]
# If leader[6] is in {a t} and leader[7] is in {a c d m} then BK
sub isFormatBK
{
  my $self = shift;

  my $ldr  = $self->xml->findvalue('//*[local-name()="leader"]');
  my $type = substr $ldr, 6, 1;
  my $lev  = substr $ldr, 7, 1;
  my %types = ('a'=>1, 't'=>1);
  my %levs = ('a'=>1, 'c'=>1, 'd'=>1, 'm'=>1);
  return 1 if defined $types{$type} && defined $levs{$lev};
  return 0;
}

sub isThesis
{
  my $self = shift;

  my $is = 0;
  eval {
    my $record = $self->xml;
    my $xpath = "//*[local-name()='datafield' and \@tag='502']/*[local-name()='subfield' and \@code='a']";
    my $doc  = $record->findvalue($xpath);
    $is = 1 if $doc =~ m/thes(e|i)s/i or $doc =~ m/diss/i;
    my $nodes = $record->findnodes("//*[local-name()='datafield' and \@tag='500']");
    foreach my $node ($nodes->get_nodelist())
    {
      $doc = $node->findvalue("./*[local-name()='subfield' and \@code='a']");
      $is = 1 if $doc =~ m/thes(e|i)s/i or $doc =~ m/diss/i;
    }
  };
  $self->set_error($self->id . ": failed in isThesis: $@") if $@;
  return $is;
}

# Translations: 041, first indicator=1, $a=eng, $h= (original
# language code); Translation (or variations thereof) in 500(a) note field.
sub isTranslation
{
  my $self = shift;

  my $is = 0;
  eval {
    my $record = $self->xml;
    my $xpath = "//*[local-name()='datafield' and \@tag='041' and \@ind1='1']/*[local-name()='subfield' and \@code='a']";
    my $lang  = $record->findvalue($xpath);
    $xpath = "//*[local-name()='datafield' and \@tag='041' and \@ind1='1']/*[local-name()='subfield' and \@code='h']";
    my $orig  = $record->findvalue($xpath);
    if ($lang && $orig)
    {
      $is = 1 if $lang eq 'eng' and $orig ne 'eng';
    }
    if (!$is && $lang)
    {
      # some uc volumes have no 'h' but instead concatenate everything in 'a'
      $is = 1 if length($lang) > 3 and substr($lang,0,3) eq 'eng';
    }
    if (!$is)
    {
      my $nodes = $record->findnodes("//*[local-name()='datafield' and \@tag='500']");
      foreach my $node ($nodes->get_nodelist())
      {
        my $doc = $node->findvalue("./*[local-name()='subfield' and \@code='a']");
        $is = 1 if $doc =~ m/translat(ion|ed)/i;
      }
    }
    if (!$is)
    {
      $xpath = "//*[local-name()='datafield' and \@tag='245']/*[local-name()='subfield' and \@code='c']";
      my $doc  = $record->findvalue($xpath);
      if ($doc =~ m/translat(ion|ed)/i)
      {
        $is = 1;
        #$in245++;
        #print "245c: $id has '$doc'\n";
      }
    }
  };
  $self->set_error($self->id . ":failed in isTranslation: $@") if $@;
  return $is;
}

# The long param includes the author dates in the 100d field if present.
sub author
{
  my $self = shift;
  my $long = shift;

  my $data = $self->GetSubfields('100', 1, 'a', 'b', 'q', 'c', ($long)? 'd':undef);
  $data = $self->GetSubfields('110', 1, 'a', 'b') unless defined $data;
  $data = $self->GetSubfields('111', 1, 'a', 'c') unless defined $data;
  $data = $self->GetSubfields('700', 1, 'a', 'b', 'q', 'c', ($long)? 'd':undef, 'e') unless defined $data;
  $data = $self->GetSubfields('710', 1, 'a') unless defined $data;
  if (defined $data)
  {
    $data =~ s/\n+//gs;
    $data =~ s/\s*[,:;]*\s*$//;
    $data =~ s/^\s+//;
  }
  return $data;
}

sub title
{
  my $self = shift;
  my $title = $self->GetDatafield('245', 'a', 1);
  if (defined $title)
  {
    # Get rid of trailing punctuation
    $title =~ s/\s*([:\/,;]*\s*)+$//;
  }
  return $title;
}

sub copyrightDate
{
  my $self = shift;

  my $leader = $self->GetControlfield('008');
  my $type = substr($leader, 6, 1);
  my $date1 = substr($leader, 7, 4);
  my $date2 = substr($leader, 11, 4);
  $date1 =~ s/\s//g;
  $date2 =~ s/\s//g;
  $date1 = undef if $date1 =~ m/\D/ or $date1 eq '';
  $date2 = undef if $date2 =~ m/\D/ or $date2 eq '';
  my $field;
  if ($type eq 't' || $type eq 'c')
  {
    $field = $date1 if defined $date1;
    $field = $date2 if defined $date2 and $date2 ne '9999';
  }
  elsif ($type eq 'r' || $type eq 'e')
  {
    $field = $date1 if defined $date1;
  }
  else
  {
    $field = $date1 if defined $date1;
    $field = $date2 if defined $date2 and (defined $date1 and $date2 > $date1) and $date2 ne '9999';
  }
  $field = undef if defined $field and $field eq '';
  my $field2 = $self->get_volume_date;
  #printf "%s: field2 %s vs field %s\n", $self->id, (defined $field2)? $field2 : '<undef>', (defined $field)? $field : '<undef>';
  #$field = $field2 if $field2 && $field2 =~ m/^\d\d\d\d$/;
  $field = $field2 if $field2;
  #printf "%s: returning %s\n", $self->id, (defined $field)? $field : '<undef>';
  return $field;
}

sub dateType
{
  my $self  = shift;

  my $leader = $self->GetControlfield('008');
  return substr($leader, 6, 1);
}

sub pubDate
{
  my $self  = shift;
  my $date2 = shift;

  my $leader = $self->GetControlfield('008');
  my $type = substr($leader, 6, 1);
  my $field = substr($leader, ($date2)? 11:7, 4);
  $field =~ s/\s//g;
  $field = undef if $field =~ m/\D/ or $field eq '';
  return $field;
}

sub formatPubDate
{
  my $self = shift;

  my $date1 = $self->pubDate(0);
  my $date2 = $self->pubDate(1);
  my $type = $self->dateType();
  my $date = $self->copyrightDate();
  $date2 = undef if $type eq 'e';
  if (defined $date1)
  {
    if ($type eq 'd' || $type eq 'i' || $type eq 'k' ||
        $type eq 'm' || $type eq 'u' || $type eq ' ')
    {
      $date = "$date1-$date2" if defined $date2 and $date2 > $date1;
      $date = $date1. '-' if defined $date2 and $date2 eq '9999';
      $date = $date1. '-' if !defined $date2 and $type eq 'u';
    }
  }
  return $date;
}

# Adapted code from Tim Prettyman
sub get_volume_date
{
  my $self = shift;

  my $item_desc = $self->enumchron;
  $item_desc or return '';
  $item_desc = lc $item_desc;
  my @vol_date = ();
  my $orig_desc = $item_desc;
  my $low;
  my $high;
  my $date;

  # umdl item descriptions may contain NNNN.NNN--if so, return null
  $item_desc =~ /^\d{4}\.[a-z0-9]{3}$/i and return '';

  # check for tech report number formats
  $item_desc =~ /^\d{1,3}-\d{4}$/ and return '';

  # strip confusing page/part data:
  #39015022710779: Title 7 1965 pt.1090-end
  #39015022735396: v.23 no.5-8 1984 pp.939-1830
  #39015022735701: v.77 1983 no.7-12 p.673-1328
  #39015022735750: v.75 1981 no.7-12 p.673-1324
  #no. 3086/3115 1964
  #no.3043,3046
  #39015040299169      no.5001-5007,5009-5010
  #$item_desc =~ s/(v\.|no\.|p{1,2}\.|pt\.)[\d,-]+//g;
  $item_desc =~ s/\b(v\.\s*|no\.\s*|p{1,2}\.\s*|pt\.\s*)[\d,-\/]+//g;

  # strip months
  $item_desc =~ s/(january|february|march|april|may|june|july|august|september|october|november|december)\.{0,1}-{0,1}//gi;
  $item_desc =~ s/(jan|feb|mar|apr|may|jun|jul|aug|sept|sep|oct|nov|dec)\.{0,1}-{0,1}//gi;
  $item_desc =~ s/(winter|spring|summer|fall|autumn)-{0,1}//gi;
  $item_desc =~ s/(supplement|suppl|quarter|qtr|jahr)\.{0,1}-{0,1}//gi;

  # report numbers
  #no.CR-2291 1973
  $item_desc =~ s/\b[a-zA-Z.]+-\d+//;

  # check for date ranges: yyyy-yy
  #($low, $high) = ( $item_desc =~ /\b(\d{4})\-(\d{2})\b/ ) and do {
  #($low, $high) = ( $item_desc =~ /\s(\d{4})\-(\d{2})\s/ ) and do {
  # While loop to handle e.g., 1973/74-1977/78 will push {1974, 1978}
  while ($item_desc =~ /\b(\d{4})[-\/](\d{2})\b/g) {
    $low = $1;
    $high = $2;
    $high = substr($low,0,2) . $high;
    push(@vol_date, $high);
  };

  # check for date ranges: yyyy-y
  #($low, $high) = ( $item_desc =~ /\b(\d{4})\-(\d)\b/ ) and do {
  ($low, $high) = ( $item_desc =~ /\s(\d{4})\-(\d)\s/ ) and do {
    $high = substr($low,0,3) . $high;
    push(@vol_date, $high);
  };

  # look for 4-digit strings
#  $item_desc =~ tr/0-9u/ /cs;           # xlate non-digits to blank (keep "u")
  $item_desc =~ tr/u^|/9/;              # translate "u" to "9"
  push (@vol_date, $item_desc =~ /\b(\d{4})\b/g);

  # cull values before 1700 and after 5 years in future
  @vol_date = grep { $_ >= 1700 && $_ <= 1900 + (localtime)[5] + 5 } @vol_date;
  # return the maximum year
  @vol_date = sort(@vol_date);
  return if scalar @vol_date == 0;
  my $vol_date =  pop(@vol_date);
  # reality check--
  #$vol_date < 1700 and $vol_date = '';
  return $vol_date;
}

sub language
{
  my $self = shift;

  my $leader  = $self->GetControlfield('008');
  return (length $leader >=38)? substr($leader, 35, 3):'???';
}

sub country
{
  my $self = shift;
  my $long = shift;

  my $code = substr($self->GetControlfield('008'), 15, 3);
  use Countries;
  return Countries::TranslateCountry($code, $long);
}

# Returns hash of us-> and non-us-> arrays of normalized city names.
sub cities
{
  my $self  = shift;

  my $data = {'us' => [], 'non-us' => []};
  my $fields = $self->GetAllSubfields('260', 'a');
  foreach my $field (@$fields)
  {
    my $where = _NormalizeCity($field);
    my $cities = Metadata::US_Cities;
    if (defined $cities->{$where})
    {
      push @{$data->{'us'}}, $field;
    }
    else
    {
      push @{$data->{'non-us'}}, $field;
    }
  }
  return $data;
}

# This is code from Tim for normalizing the 260 subfield for U.S. cities.
sub _NormalizeCity
{
  my $suba = shift;

  $suba =~ tr/A-Za-z / /c;
  $suba = lc($suba);
  $suba =~ s/ and / /;
  $suba =~ s/ etc / /;
  $suba =~ s/ dc / /;
  $suba =~ s/\s+/ /g;
  $suba =~ s/^\s*(.*?)\s*$/$1/;
  return $suba;
}

# TODO: rename other "enumchron" references to use conventional spelling.
sub enumcron {
  my $self = shift;
  my $id   = shift;

  return $self->enumchron($id);
}

# This is the older, deprecated form
sub enumchron
{
  my $self = shift;
  my $id   = shift;

  $id = $self->id unless defined $id;
  my $data;
  eval {
    my $json = $self->json;
    foreach my $item (@{$json->{'items'}})
    {
      if ($id eq $item->{'htid'})
      {
        $data = $item->{'enumcron'};
        last;
      }
    }
  };
  $data = undef unless $data;
  $self->set_error('enumchron query for ' . $self->id . " failed: $@") if $@;
  return $data;
}

sub countEnumchron
{
  my $self = shift;

  return $self->{enumchronCount} if defined $self->{enumchronCount};
  my $n = 0;
  eval {
    my $json = $self->json;
    foreach my $item (@{$json->{'items'}})
    {
      my $data = $item->{'enumcron'};
      $n++ if $data;
    }
  };
  $self->set_error("enumchron query failed: $@") if $@;
  $self->{enumchronCount} = $n;
  return $n;
}

sub doEnumchronMatch
{
  my $self = shift;
  my $id   = shift;
  my $id2  = shift;

  my $chron = lc ($self->enumchron($id) || '');
  my $chron2 = lc ($self->enumchron($id2) || '');
  $chron =~ s/\s+//g;
  $chron2 =~ s/\s+//g;
  return ($chron eq $chron2);
}

sub allHTIDs
{
  my $self = shift;

  my @ids;
  eval {
    my $json = $self->json;
    push @ids, $_->{'htid'} for @{$json->{'items'}};
  };
  $self->set_error('enumchron query for ' . $self->id . " failed: $@") if $@;
  return \@ids;
}

sub volumeIDs
{
  my $self = shift;

  my @ids;
  eval {
    my $json = $self->json;
    foreach my $item (@{$json->{'items'}})
    {
      my $id = $item->{'htid'};
      my $chron = $item->{'enumcron'} || '';
      my $rights = $item->{'usRightsString'};
      my %data = ('id' => $id, 'chron' => $chron, 'rights' => $rights);
      push @ids, \%data;
    }
  };
  $self->set_error('volumeIDsQuery for ' . $self->id . " failed: $@") if $@;
  return \@ids;
}

sub GetControlfield
{
  my $self   = shift;
  my $field  = shift;
  my $xml    = shift;

  $xml = $self->xml unless defined $xml;
  my $xpath = "//*[local-name()='controlfield' and \@tag='$field']";
  my $data;
  eval { $data = $xml->findvalue($xpath); };
  if ($@) { $self->set_error($self->id . " GetControlfield failed: $@"); }
  return $data;
}

sub GetDatafield
{
  my $self   = shift;
  my $field  = shift;
  my $code   = shift;
  my $index  = shift;
  my $xml    = shift;

  $self->set_error("no code: $field, $index") unless defined $code;
  $xml = $self->xml unless defined $xml;
  $index = 1 unless defined $index;
  my $xpath = "//*[local-name()='datafield' and \@tag='$field'][$index]" .
              "/*[local-name()='subfield' and \@code='$code']";
  my $data;
  eval { $data = $xml->findvalue($xpath); };
  if ($@) { $self->set_error($self->id . " GetDatafield failed: $@"); }
  my $len = length $data;
  if ($len && $len % 3 == 0)
  {
    my $s = $len / 3;
    my $f1 = substr $data, 0, $s;
    my $f2 = substr $data, $s, $s;
    my $f3 = substr $data, 2*$s, $s;
    #print "Warning: possible triplet from '$data' ($id)\n" if $f1 eq $f2 and $f2 eq $f3;
    $data = $f1 if $f1 eq $f2 and $f2 eq $f3;
  }
  return $data;
}

sub CountDatafields
{
  my $self   = shift;
  my $field  = shift;
  my $xml    = shift;

  $xml = $self->xml unless defined $xml;
  my $n = 0;
  eval {
    my $nodes = $xml->findnodes("//*[local-name()='datafield' and \@tag='$field']");
    $n = scalar $nodes->get_nodelist();
  };
  $self->set_error('CountDatafields: ' . $@) if $@;
  return $n;
}

sub GetAllAuthors
{
  my $self = shift;

  my %aus;
  my $au = $self->author(1);
  $aus{$au} = 1 if $au;
  my $n = $self->CountDatafields('700');
  foreach my $i (1 .. $n)
  {
    $au = $self->GetSubfields('700', $i, 'a', 'b', 'q', 'c', 'd');
    $aus{$au} = 1 if $au;
  }
  my @authors = sort keys %aus;
  return @authors;
}

sub GetSubfields
{
  my $self   = shift;
  my $field  = shift;
  my $index  = shift;
  my @subfields = @_;

  my $data = undef;
  foreach my $subfield (@subfields)
  {
    next unless defined $subfield;
    my $data2 = $self->GetDatafield($field, $subfield, $index);
    $data2 =~ s/(^\s+)|(\s+$)//g if $data2;
    $data .= ' ' . $data2 if $data2;
  }
  if (defined $data)
  {
    $data =~ s/\n+//gs;
    $data =~ s/\s*[,:;]*\s*$//;
    $data =~ s/^\s+//;
  }
  return $data;
}

sub GetAllSubfields
{
  my $self   = shift;
  my $field  = shift;
  my $code   = shift;
  my $xml    = shift;

  $self->set_error("no code: $field") unless defined $code;
  $xml = $self->xml unless defined $xml;
  my $xpath = "//*[local-name()='datafield' and \@tag='$field']" .
              "/*[local-name()='subfield' and \@code='$code']";
  my @data;
  my $n = 0;
  eval {
    my $nodes = $xml->findnodes($xpath);
    foreach my $node ($nodes->get_nodelist())
    {
      push @data, $node->textContent;
    }
  };
  if ($@) { $self->set_error($self->id . " GetAllSubfields failed: $@"); }

  return \@data;
}

# An item is a probable gov doc if one of the following is true. All are case insensitive.
# Author begins with "United States" and 260 is blank
# Author begins with "United States" and 260a begins with "([)Washington"
# Author begins with "United States" and 260b begins with "U.S. G.P.O." or "U.S. Govt. Print. Off."
# Author begins with "Library of Congress" and 260a begins with "Washington"
# Title begins with "Code of Federal Regulations" and 260a begins with "Washington"
# Author is blank and 260(a) begins with "([)Washington" and 260(b) begins with "U.S." or "G.P.O."
# Author is blank and 260(b) includes "National Aeronautics and Space"
# Author begins with "Federal Reserve Bank"
# Author includes "Bureau of Mines"
sub IsProbableGovDoc
{
  my $self   = shift;

  my $author = $self->author;
  my $title = $self->title;
  my $xml = $self->xml;
  my $xpath  = '//*[local-name()="datafield" and @tag="260"]/*[local-name()="subfield" and @code="a"]';
  my $field260a = $xml->findvalue($xpath);
  $xpath  = '//*[local-name()="datafield" and @tag="260"]/*[local-name()="subfield" and @code="b"]';
  my $field260b = $xml->findvalue($xpath);
  $field260a =~ s/^\s*(.*?)\s*$/$1/;
  $field260b =~ s/^\s*(.*?)\s*$/$1/;
  # If there is an alphabetic character in 008:28 other than 'f',
  # we accept it and say it is NOT probable
  $xpath  = q{//*[local-name()='controlfield' and @tag='008']};
  my $leader = lc $xml->findvalue($xpath);
  if (length $leader >28)
  {
    my $code = substr($leader, 28, 1);
    return 0 if ($code ne 'f' && $code =~ m/[a-z]/);
  }
  if (defined $author && $author =~ m/^united\s+states/i)
  {
    return 1 unless $field260a or $field260b;
    return 1 if $field260a =~ m/^\[?washington/i;
    return 1 if $field260b and $field260b =~ m/^u\.s\.\s+g\.p\.o\./i;
    return 1 if $field260b and $field260b =~ m/^u\.s\.\s+govt\.\s+print\.\s+off\./i;
  }
  return 1 if defined $author and $author =~ m/^library\s+of\s+congress/i and $field260a =~ m/^washington/i;
  return 1 if defined $title and $title =~ m/^code\s+of\s+federal\s+regulations/i and $field260a =~ m/^washington/i;
  if (!$author)
  {
    return 1 if $field260a =~ m/^\[?washington/i and $field260b =~ m/^(u\.s\.|g\.p\.o\.)/i;
    return 1 if $field260b and $field260b =~ m/national\s+aeronautics\s+and\s+space/i;
  }
  else
  {
    return 1 if $author =~ m/^federal\s+reserve\s+bank/i;
    return 1 if $author =~ m/bureau\s+of\s+mines/i;
  }
  return 0;
}

return 1;
