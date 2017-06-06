package Metadata;
use vars qw(@ISA @EXPORT @EXPORT_OK);

use strict;
use warnings;
use LWP::UserAgent;
use XML::LibXML;
use JSON::XS;
use Unicode::Normalize;

sub new
{
  my ($class, %args) = @_;
  my $self = bless {}, $class;
  my $errors = [];
  $self->set('errors', $errors);
  my $id = $args{'id'};
  $self->set('sysid', $id) if $id !~ m/\./;
  $self->set('id', $id);
  my $crms = $args{'crms'};
  die "Metadata module needs CRMS instance." unless defined $crms;
  $self->set('crms', $crms);
  $self->json;
  return undef unless defined $self->xml;
  return $self;
}

sub get
{
  my $self = shift;
  my $key  = shift;

  return $self->{$key};
}

sub set
{
  my $self = shift;
  my $key  = shift;
  my $val  = shift;

  delete $self->{$key} unless defined $val;
  $self->{$key} = $val if defined $key and defined $val;
}

sub SetError
{
  my $self   = shift;
  my $error  = shift;

  $self->get('crms')->SetError($error);
}

sub id
{
  my $self = shift;
  return $self->get('id');
}

sub sysid
{
  my $self = shift;
  my $sysid = $self->get('sysid');
  if (!defined $sysid)
  {
    my $json = $self->json;
    my $records = $json->{'records'};
    if ('HASH' eq ref $records)
    {
      my @keys = keys %$records;
      $sysid = $keys[0];
      $self->set('sysid', $sysid);
    }
  }
  return $sysid;
}

sub json
{
  my $self = shift;
  my $json = $self->get('json');
  if (!defined $json)
  {
    my $id = $self->get('id');
    $id = $self->get('sysid') unless defined $id;
    my $type = ($id =~ m/\./)? 'htid' : 'recordnumber';
    my $url = "http://catalog.hathitrust.org/api/volumes/full/$type/$id.json";
    my $ua = LWP::UserAgent->new;
    $ua->timeout(1000);
    my $req = HTTP::Request->new(GET => $url);
    my $res = $ua->request($req);
    if (!$res->is_success)
    {
      $self->SetError($url . ' failed: ' . $res->message());
      return;
    }
    my $xml = undef;
    my $jsonxs = JSON::XS->new;
    my $content = Unicode::Normalize::NFC($res->content);
    # Sometimes the API can return diagnostic information up top,
    # so we cut that out.
    $content =~ s/^(.*?)({"records":)/$2/s;
    eval {
      $json = $jsonxs->decode($content);
      if (!defined $self->get('id'))
      {
        my $id2 = $json->{items}->[0]->{htid};
        $self->set('id', $id2);
      }
      my $records = $json->{'records'};
      if ('HASH' eq ref $records)
      {
        my @keys = keys %$records;
        $self->set('sysid', $keys[0]);
      }
    };
    if ($@)
    {
      $self->SetError("failed to parse ($content) for $id:$@");
    }
    $self->set('json', $json) if defined $json;
  }
  return $json;
}

sub xml
{
  my $self = shift;
  my $xml = $self->get('xml');
  if (! defined $xml)
  {
    my $json = $self->json;
    my $records = $json->{'records'};
    my @keys = keys %$records;
    my $source;
    if (scalar @keys)
    {
      $xml = $records->{$keys[0]}->{'marc-xml'};
      my $parser = XML::LibXML->new();
      eval {
        $source = $parser->parse_string($xml);
      };
      if (!scalar @keys || $@)
      {
        $self->SetError($self->id . " failed to parse ($xml): $@");
        return;
      }
    }
    else
    {
      $self->SetError($self->id . " no records found");
      return;
    }
    my $root = $source->getDocumentElement();
    my @records = $root->findnodes('//*[local-name()="record"]');
    $xml = $records[0];
    $self->set('xml', $xml) if defined $xml;
  }
  return $xml;
}

sub fmt
{
  my $self = shift;

  my $ldr  = $self->xml->findvalue('//*[local-name()="leader"]');
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
  $self->SetError($self->id . ": failed in isThesis: $@") if $@;
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
  $self->SetError($self->id . ":failed in isTranslation: $@") if $@;
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
  my $field2;
  $field2 = $self->get_volume_date;
  $field = $field2 if $field2;
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

# Source code from Tim Prettyman
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
  #$item_desc =~ /\b(\d{4})\-(\d{2})\b/ and do {
  $item_desc =~ /\b(\d{4})[-\/](\d{2})\b/ and do {
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
  $self->SetError('enumchron query for ' . $self->id . " failed: $@") if $@;
  return $data;
}

sub countEnumchron
{
  my $self = shift;

  my $n = $self->get('enumchronCount');
  return $n if defined $n;
  $n = 0;
  eval {
    my $json = $self->json;
    foreach my $item (@{$json->{'items'}})
    {
      my $data = $item->{'enumcron'};
      $n++ if $data;
    }
  };
  $self->SetError('enumchron query for ' . $self->id . " failed: $@") if $@;
  $self->set('enumchronCount', $n);
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
  $self->SetError('enumchron query for ' . $self->id . " failed: $@") if $@;
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
  $self->SetError('volumeIDsQuery for ' . $self->id . " failed: $@") if $@;
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
  if ($@) { $self->SetError($self->id . " GetControlfield failed: $@"); }
  return $data;
}

sub GetDatafield
{
  my $self   = shift;
  my $field  = shift;
  my $code   = shift;
  my $index  = shift;
  my $xml    = shift;

  $self->SetError("no code: $field, $index") unless defined $code;
  $xml = $self->xml unless defined $xml;
  $index = 1 unless defined $index;
  my $xpath = "//*[local-name()='datafield' and \@tag='$field'][$index]" .
              "/*[local-name()='subfield' and \@code='$code']";
  my $data;
  eval { $data = $xml->findvalue($xpath); };
  if ($@) { $self->SetError($self->id . " GetDatafield failed: $@"); }
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
  $self->SetError('CountDatafields: ' . $@) if $@;
  return $n;
}

sub GetAllAuthors
{
  my $self   = shift;

  my %aus;
  my $au = $self->author(1);
  $aus{$au} = 1 if $au;
  my $n = $self->CountDatafields('700');
  foreach my $i (1 .. $n)
  {
    $au = $self->GetSubfields('700', $i, 'a', 'b', 'q', 'c', 'd');
    $aus{$au} = 1 if $au;
  }
  return sort keys %aus;
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

return 1;
