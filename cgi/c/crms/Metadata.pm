package Metadata;
use vars qw(@ISA @EXPORT @EXPORT_OK);
our @EXPORT = qw(GetErrors id sysid mirlyn);

use LWP::UserAgent;
use XML::LibXML;
use JSON::XS;
use Data::Dumper;

sub new
{
  my ($class, %args) = @_;
  my $self = bless {}, $class;
  my $errors = [];
  $self->set('errors', $errors);
  my $id = $args{'id'};
  if ($id !~ m/\./)
  {
    if ($id =~ m/^0/)
    {
      $self->set($id,'mirlyn');
      $id = $self->MirlynToSystem($id);
      $self->set('id', $id);
    }
    else
    {
      $self->set('sysid', $id);
    }
  }
  $self->set('id', $id);
  $self->json;
  $self->xml;
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

  my $crms = $self->get('crms');
  $error .= "\n" . $self->StackTrace() if defined $crms;
  my $errors = $self->get('errors');
  push @{$errors}, $error;
}

sub GetErrors
{
  my $self = shift;
  return $self->get('errors');
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
    my $content = $res->content;
    eval {
      $json = $jsonxs->decode($res->content);
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
    $xml = $records->{$keys[0]}->{'marc-xml'};
    my $parser = XML::LibXML->new();
    my $source;
    eval {
      $source = $parser->parse_string($xml);
    };
    if ($@)
    {
      $self->SetError("failed to parse ($xml) for $id: $@");
      return;
    }
    my $root = $source->getDocumentElement();
    my @records = $root->findnodes('//*[local-name()="record"]');
    $xml = $records[0];
    $self->set('xml', $xml) if defined $xml;
  }
  return $xml;
}

sub mirlyn
{
  my $self = shift;
  my $mirlyn = $self->get('mirlyn');
  if (!defined $mirlyn)
  {
    $mirlyn = $self->HTIDToMirlyn($self->id);
    $self->set('mirlyn', $mirlyn) if defined $mirlyn;
  }
  return $mirlyn;
}

# This is the correct way to do it.
# Look at leader[6] and leader[7]
# If leader[6] is in {a t} and leader[7] is in {a c d m} then BK
sub isFormatBK
{
  my $self   = shift;

  my $ldr  = $self->xml->findvalue('//*[local-name()="leader"]');
  my $type = substr $ldr, 6, 1;
  my $lev  = substr $ldr, 7, 1;
  my %types = ('a'=>1, 't'=>1);
  my %levs = ('a'=>1, 'c'=>1, 'd'=>1, 'm'=>1);
  return 1 if $types{$type}==1 && $levs{$lev}==1;
  return 0;
}

sub isThesis
{
  my $self   = shift;

  my $is = 0;
  if (!$record) { $self->SetError("no record in IsThesis($id)"); return 0; }
  eval {
    my $xpath = "//*[local-name()='datafield' and \@tag='502']/*[local-name()='subfield' and \@code='a']";
    my $doc  = $self->xml->findvalue($xpath);
    $is = 1 if $doc =~ m/thes(e|i)s/i or $doc =~ m/diss/i;
    my $nodes = $record->findnodes("//*[local-name()='datafield' and \@tag='500']");
    foreach my $node ($nodes->get_nodelist())
    {
      $doc = $node->findvalue("./*[local-name()='subfield' and \@code='a']");
      $is = 1 if $doc =~ m/thes(e|i)s/i or $doc =~ m/diss/i;
    }
  };
  $self->SetError("failed in IsThesis($id): $@") if $@;
  return $is;
}

# Translations: 041, first indicator=1, $a=eng, $h= (original
# language code); Translation (or variations thereof) in 500(a) note field.
sub isTranslation
{
  my $self   = shift;

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
  $self->SetError("failed in IsTranslation($id): $@") if $@;
  return $is;
}

sub HTIDToMirlyn
{
  my $self   = shift;
  my $id     = shift;

  my $url = 'http://mirlyn.lib.umich.edu/cgi-bin/bc2meta?id=' .$id. '&schema=marcxml';
  my $ua  = LWP::UserAgent->new;
  $ua->timeout(1000);
  my $req = HTTP::Request->new(GET => $url);
  my $res = $ua->request($req);
  if (! $res->is_success)
  {
    $self->SetError("Failed $url: " . $res->message());
    return;
  }
  my $source;
  eval
  {
    my $parser = XML::LibXML->new();
    $source = $parser->parse_string($res->content());
  };
  if ($@)
  {
    $self->SetError("failed to parse response: $@");
    return;
  }
  my $root = $source->getDocumentElement();
  return $self->GetControlfield('001', $root);
}

sub MirlynToSystem
{
  my $self   = shift;
  my $id     = shift;

  return $id if $id=~ m/^1\d*/;
  my $sysid;
  my $url = 'http://mirlyn.lib.umich.edu/Record/' .$id. '.json';
  my $ua  = LWP::UserAgent->new;
  $ua->timeout(1000);
  my $req = HTTP::Request->new(GET => $url);
  my $res = $ua->request($req);
  if (! $res->is_success)
  {
    $self->SetError("Failed $url: " . $res->message());
    return;
  }
  my $source;
  eval
  {
    my $json = JSON::XS->new;
    my $fields = $json->decode($res->content())->{fields};
    # Array ref of hash ref
    foreach my $field (@$fields)
    {
      foreach my $fieldname (keys %$field)
      {
        if ($fieldname eq '035')
        {
          my $fieldcontent = $field->{$fieldname};
          my $sub = $fieldcontent->{subfields}->[0]->{a};
          if ($sub =~ m/^sdr-zephir(\d+)$/)
          {
            $sysid = $1;
            last;
          }
        }
      }
      last if defined $sysid;
    }
  };
  if ($@)
  {
    $self->SetError("failed to parse response: $@");
    return;
  }
  $sysid = $id unless defined $sysid;
  return $sysid;
}

# The long param includes the author dates in the 100d field if present.
sub author
{
  my $self = shift;
  my $long = shift;

  my $record = $self->xml;
  my $data = $self->GetSubfields('100', $record, 1, 'a', 'b', 'c', ($long)? 'd':undef);
  $data = $self->GetSubfields('110', $record, 1, 'a', 'b') unless defined $data;
  $data = $self->GetSubfields('111', $record, 1, 'a', 'c') unless defined $data;
  $data = $self->GetSubfields('700', $record, 1, 'a', 'b', 'c', ($long)? 'd':undef) unless defined $data;
  $data = $self->GetSubfields('710', $record, 1, 'a') unless defined $data;
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
  # Get rid of trailing punctuation
  $title =~ s/\s*([:\/,;]*\s*)+$// if $title;
  return $title;
}

sub pubdate
{
  my $self   = shift;
  my $date2  = shift;
  my $leader  = $self->GetControlfield('008');
  return substr($leader, ($date2)? 11:7, 4);
}

sub language
{
  my $self   = shift;
  my $leader  = $self->GetControlfield('008');
  return substr($leader, 35, 3);
}

sub country
{
  my $self   = shift;
  my $long   = shift;
  my $code  = substr($self->GetControlfield('008'), 15, 3);
  use Countries;
  return Countries::TranslateCountry($code, $long);
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
      my $chron = $item->{'enumcron'};
      $chron = '' unless $chron;
      my $rights = $item->{'usRightsString'};
      push @ids, $id . '__' . $chron . '__' . $rights;
    }
  };
  $self->SetError('Holdings query for ' . $self->id . " failed: $@") if $@;
  return \@ids;
}

# sub GetMarcFixfield
# {
#   my $self  = shift;
#   my $field = shift;
#   my $record = shift;
# 
#   $record = $self->xml unless defined $record;
#   my $xpath = qq{//*[local-name()='oai_marc']/*[local-name()='fixfield' and \@id='$field']};
#   eval { $data = $self->xml->findvalue($xpath); };
#   if ($@) { $self->SetError("failed to parse metadata: $@"); }
#   return $data;
# }

# sub GetMarcVarfield
# {
#   my $self  = shift;
#   my $field = shift;
#   my $label = shift;
#   my $record = shift;
# 
#   $record = $self->xml unless defined $record;
#   my $xpath = qq{//*[local-name()='oai_marc']/*[local-name()='varfield' and \@id='$field']} .
#               qq{/*[local-name()='subfield' and \@label='$label']};
#   eval { $data = $self->xml->findvalue($xpath); };
#   if ($@) { $self->SetError("failed to parse metadata: $@"); }
#   return $data;
# }

sub GetControlfield
{
  my $self   = shift;
  my $field  = shift;

  my $xpath = "//*[local-name()='controlfield' and \@tag='$field']";
  eval { $data = $self->xml->findvalue($xpath); };
  if ($@) { $self->SetError($self->id . " GetControlfield failed: $@"); }
  return $data;
}

sub GetDatafield
{
  my $self   = shift;
  my $field  = shift;
  my $code   = shift;
  my $index  = shift;

  $index = 1 unless defined $index;
  my $xpath = "//*[local-name()='datafield' and \@tag='$field'][$index]" .
              "/*[local-name()='subfield'  and \@code='$code']";
  my $data;
  eval { $data = $self->xml->findvalue($xpath); };
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

  $record = $self->xml;
  my $n = 0;
  eval {
    my $nodes = $record->findnodes("//*[local-name()='datafield' and \@tag='$field']");
    $n = scalar $nodes->get_nodelist();
  };
  $self->SetError('CountDatafields: ' . $@) if $@;
  return $n;
}

sub GetAdditionalAuthors
{
  my $self   = shift;

  my @aus = ();
  my $n = $self->CountDatafields('700');
  foreach my $i (1 .. $n)
  {
    my $data = $self->GetSubfields('700', $i, 'a', 'b', 'c', 'd');
    push @aus, $data if defined $data;
  }
  $n = $self->CountDatafields('710');
  foreach my $i (1 .. $n)
  {
    my $data = $self->GetSubfields('710', $i, 'a', 'b');
    push @aus, $data if defined $data;
  }
  return @aus;
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

