package Candidates_crms;

use strict;
use warnings;

sub new
{
  my $class = shift;
  my $self = { crms => shift };
  return bless $self, $class;
}

sub Countries
{
  my $self = shift;

  return {'USA'=>1};
}

# If new_attr and new_reason are supplied, they are the final determination
# and this checks whether that determination should be exported (is the
# volume in scope?).
# There are no additional rules governing this in CRMS US, so we let the
# core logic handle it.
sub HasCorrectRights
{
  my $self       = shift;
  my $attr       = shift;
  my $reason     = shift;
  #my $new_attr   = shift;
  #my $new_reason = shift;

  my $correct = 0;
  $correct = 1 if ($attr eq 'ic' && $reason eq 'bib') || $attr eq 'op';
  return $correct;
}

sub HasCorrectYear
{
  my $self    = shift;
  my $country = shift;
  my $year    = shift;

  my $min = $self->GetCutoffYear($country, 'minYear');
  my $max = $self->GetCutoffYear($country, 'maxYear');
  return ($min <= $year && $year <= $max);
}

sub GetCutoffYear
{
  my $self    = shift;
  my $country = shift;
  my $name    = shift;

  return 1923 if $name eq 'minYear';
  return 1963 if $name eq 'maxYear';
  return 1977 if $name eq 'maxYearOverride';
}

sub GetViolations
{
  my $self = shift;
  my ($id, $record, $priority, $override) = @_;

  my @errs = ();
  my $pub = $record->copyrightDate;
  if (defined $pub && $pub =~ m/\d\d\d\d/)
  {
    my $min = $self->GetCutoffYear(undef, 'minYear');
    my $max = $self->GetCutoffYear(undef, 'maxYear');
    if (($override && $priority == 3) or $priority == 4)
    {
      $max = $self->GetCutoffYear(undef, 'maxYearOverride');
    }
    push @errs, "$pub not in range $min-$max" if ($pub < $min || $pub > $max);
  }
  else
  {
    my $leader = $record->GetControlfield('008');
    my $type = substr($leader, 6, 1);
    my $date1 = substr($leader, 7, 4);
    my $date2 = substr($leader, 11, 4);
    push @errs, "pub date not completely specified ($date1,$date2,'$type')";
  }
  push @errs, 'gov doc' if $self->IsGovDoc($record);
  my $where = $record->country;
  push @errs, "foreign pub ($where)" if $where ne 'USA';
  push @errs, 'non-BK format' unless $record->isFormatBK($id, $record);
  return @errs;
}

sub ShouldVolumeBeFiltered
{
  my $self   = shift;
  my $id     = shift;
  my $record = shift;

  return 'gov' if $self->IsProbableGovDoc($record);
  return 'language' if 'eng' ne $record->language;
  return 'dissertation' if $record->isThesis;
  return 'translation' if $record->isTranslation;
  return 'foreign' if $self->IsReallyForeignPub($record);
  return undef;
}

# 008:28 is 'f' byte.
sub IsGovDoc
{
  my $self   = shift;
  my $record = shift;

  my $is = undef;
  eval {
    my $leader = $record->GetControlfield('008');
    $is = (length $leader > 28 && substr($leader, 28, 1) eq 'f');
  };
  $self->{crms}->SetError($record->id . " failed in IsGovDoc(): $@") if $@;
  return $is;
}

# An item is a probable gov doc if one of the following is true. All are case insensitive.
# Author begins with "United States" and 260 is blank
# Author begins with "United States" and 260a begins with "([)Washington"
# Author begins with "United States" and 260b begins with "U.S. G.P.O." or "U.S. Govt. Print. Off."
# Author begins with "Library of Congress" and 260a begins with "Washington"
# Title begins with "Code of Federal Regulations" and 260a begins with "Washington"
# Author is blank and 260(a) begins with "([)Washington" and 260(b) begins with "U.S."
# Author is blank and 260(a) begins with "([)Washington" and 260(b) begins with "G.P.O."
# Author is blank and 260(b) includes "National Aeronautics and Space"
# Author begins with "Federal Reserve Bank"
# Author includes "Bureau of Mines"
sub IsProbableGovDoc
{
  my $self   = shift;
  my $record = shift;

  my $author = $record->author;
  my $title = $record->title;
  my $xpath  = '//*[local-name()="datafield" and @tag="260"]/*[local-name()="subfield" and @code="a"]';
  my $field260a = $record->xml->findvalue($xpath);
  $xpath  = '//*[local-name()="datafield" and @tag="260"]/*[local-name()="subfield" and @code="b"]';
  my $field260b = $record->xml->findvalue($xpath);
  $field260a =~ s/^\s*(.*?)\s*$/$1/;
  $field260b =~ s/^\s*(.*?)\s*$/$1/;
  # If there is an alphabetic character in 008:28 other than 'f',
  # we accept it and say it is NOT probable
  $xpath  = q{//*[local-name()='controlfield' and @tag='008']};
  my $leader = lc $record->xml->findvalue($xpath);
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

# Rejects anything with 008 15-17 that is not '**u' or 'us*'.
# As a convenience (and for testing) returns undef for US titles and a string with the country code that failed.
sub IsForeignPub
{
  my $self   = shift;
  my $record = shift;

  my $is = undef;
  eval {
    my $code = substr($record->GetControlfield('008'), 15, 3);
    $is = $code if substr($code,2,1) ne 'u';
  };
  $self->{crms}->SetError("failed in IsForeignPub: $@") if $@;
  return $is;
}

# second/foreign place of pub. From Tim's documentation:
# Check of 260 field for multiple subfield a:
# If PubPlace 17 eq 'u', and the 260 field contains multiple subfield
# a's, then the data in each subfield a is normalized and matched
# against a list of known US cities.  If any of the subfield a?s are not
# in the list, then the mult_260a_non_us flag is set.
# As a convenience (and for testing) returns undef for US titles and a string with the city that failed.
sub IsReallyForeignPub
{
  my $self   = shift;
  my $record = shift;

  my $is = $self->IsForeignPub($record);
  return $is if $is;
  eval {
    my $path = '//*[local-name()="datafield" and @tag="260"]/*[local-name()="subfield" and @code="a"]';
    my @nodes = $record->xml->findnodes($path)->get_nodelist();
    return if scalar @nodes == 1;
    foreach my $node (@nodes)
    {
      my $where = Normalize($node->textContent);
      my $cities = $self->{crms}->get('cities');
      $cities = $self->ReadCities() unless $cities;
      if ($cities !~ m/==$where==/i)
      {
        $is = $where;
        return;
      }
    }
  };
  $self->{crms}->SetError("failed in IsReallyForeignPub: $@") if $@;
  return $is;
}

sub ReadCities
{
  my $self = shift;
  
  my $in = $self->{crms}->get('root') . '/bin/c/crms/us_cities.txt';
  open (FH, '<', $in) || $self->{crms}->SetError("Could not open $in");
  my $cities = '';
  while (<FH>) { chomp; $cities .= "==$_=="; }
  close FH;
  $self->{crms}->set('cities',$cities);
  return $cities;
}

# This is code from Tim for normalizing the 260 subfield for U.S. cities.
sub Normalize
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

1;
