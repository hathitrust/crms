package Candidates;

use strict;
use warnings;
use vars qw( @ISA @EXPORT @EXPORT_OK );
our @EXPORT = qw(HasCorrectRights GetViolations ShouldVolumeGoInUndTable);

sub HasCorrectRights
{
  my $self   = shift;
  my $attr   = shift;
  my $reason = shift;
  
  return (($attr eq 'ic' && $reason eq 'bib') ||
           $attr eq 'op');
}

sub GetViolations
{
  my $self = shift;
  my ($id, $record, $priority, $override) = @_;

  my @errs = ();
  my $pub = $self->GetRecordPubDate($id, $record);
  my $min = $self->GetCutoffYear('minYear');
  my $max = $self->GetCutoffYear('maxYear');
  $max = $self->GetCutoffYear('maxYearOverride') if ($override and $priority == 3) or $priority == 4;
  if ($pub =~ m/\d\d\d\d/)
  {
    my $min = $self->GetCutoffYear('minYear');
    my $max = $self->GetCutoffYear('maxYear');
    $max = $self->GetCutoffYear('maxYearOverride') if ($override and $priority == 3) or $priority == 4;
    push @errs, "$pub not in range $min-$max" if ($pub < $min || $pub > $max);
  }
  else
  {
    push @errs, "pub date not in range or not completely specified ($pub)";
  }
  push @errs, 'gov doc' if IsGovDoc($self, $id, $record );
  push @errs, 'foreign pub' if IsForeignPub($self, $id, $record);
  push @errs, 'non-BK format' unless $self->IsFormatBK($id, $record);
  my $ref = $self->RightsQuery($id,1);
  $ref = $ref->[0] if $ref;
  if ($ref)
  {
    my ($attr,$reason,$src,$usr,$time,$note) = @{$ref};
    my $rights = "$attr/$reason";
    push @errs, "current rights are $rights" unless $rights eq 'ic/bib' or
                                                    $attr eq 'op' or
                                                    ($override and $priority == 3) or
                                                    $priority == 4;
  }
  else
  {
    push @errs, "rights query for $id failed";
  }
  return @errs;
}

sub ShouldVolumeGoInUndTable
{
  my $self   = shift;
  my $id     = shift;
  my $record = shift;

  my $src = undef;
  my $lang = $self->GetRecordPubLanguage($id, $record);
  if (IsProbableGovDoc($self, $id, $record)) { $src = 'gov'; }
  elsif ('eng' ne $lang) { $src = 'language'; }
  elsif ($self->IsThesis($id, $record)) { $src = 'dissertation'; }
  elsif ($self->IsTranslation($id, $record)) { $src = 'translation'; }
  elsif (IsReallyForeignPub($self, $id, $record)) { $src = 'foreign'; }
  return $src;
}

# 008:28 is 'f' byte.
sub IsGovDoc
{
  my $self   = shift;
  my $id     = shift;
  my $record = shift;

  my $is = undef;
  eval {
    my $path  = '//*[local-name()="controlfield" and @tag="008"]';
    my $leader = $record->findvalue($path);
    $is = (substr($leader, 28, 1) eq 'f');
  };
  $self->SetError("failed in IsGovDoc($id): $@") if $@;
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
  my $id     = shift;
  my $record = shift;

  my $author = $self->GetRecordAuthor($id, $record);
  my $title = $self->GetRecordTitle($id, $record);
  my $xpath  = '//*[local-name()="datafield" and @tag="260"]/*[local-name()="subfield" and @code="a"]';
  my $field260a = $record->findvalue($xpath);
  $xpath  = '//*[local-name()="datafield" and @tag="260"]/*[local-name()="subfield" and @code="b"]';
  my $field260b = $record->findvalue($xpath);
  $field260a =~ s/^\s*(.*?)\s*$/$1/;
  $field260b =~ s/^\s*(.*?)\s*$/$1/;
  # If there is an alphabetic character in 008:28 other than 'f',
  # we accept it and say it is NOT probable
  $xpath  = q{//*[local-name()='controlfield' and @tag='008']};
  my $leader = lc $record->findvalue($xpath);
  my $code = substr($leader, 28, 1);
  return 0 if ($code ne 'f' && $code =~ m/[a-z]/);
  if ($author =~ m/^united\s+states/i)
  {
    return 1 unless $field260a or $field260b;
    return 1 if $field260a =~ m/^\[?washington/i;
    return 1 if $field260b and $field260b =~ m/^u\.s\.\s+g\.p\.o\./i;
    return 1 if $field260b and $field260b =~ m/^u\.s\.\s+govt\.\s+print\.\s+off\./i;
  }
  return 1 if $author =~ m/^library\s+of\s+congress/i and $field260a =~ m/^washington/i;
  return 1 if $title =~ m/^code\s+of\s+federal\s+regulations/i and $field260a =~ m/^washington/i;
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
  my $id     = shift;
  my $record = shift;

  my $is = undef;
  eval {
    my $path = '//*[local-name()="controlfield" and @tag="008"]';
    my $code  = substr($record->findvalue($path), 15, 3);
    $is = $code if substr($code,2,1) ne 'u';
  };
  $self->SetError("failed in IsForeignPub($id): $@") if $@;
  return $is;
}

# second/foreign place of pub. From Tim's documentation:
# Check of 260 field for multiple subfield a:
# If PubPlace 17 eq 'u', and the 260 field contains multiple subfield
# a?s, then the data in each subfield a is normalized and matched
# against a list of known US cities.  If any of the subfield a?s are not
# in the list, then the mult_260a_non_us flag is set.
# As a convenience (and for testing) returns undef for US titles and a string with the city that failed.
sub IsReallyForeignPub
{
  my $self   = shift;
  my $id     = shift;
  my $record = shift;

  my $is = IsForeignPub($self, $id, $record);
  return $is if $is;
  eval {
    my $path = '//*[local-name()="datafield" and @tag="260"]/*[local-name()="subfield" and @code="a"]';
    my @nodes = $record->findnodes($path)->get_nodelist();
    return if scalar @nodes == 1;
    foreach my $node (@nodes)
    {
      my $where = Normalize($node->textContent);
      my $cities = $self->get('cities');
      $cities = ReadCities($self) unless $cities;
      if ($cities !~ m/==$where==/i)
      {
        $is = $where;
        return;
      }
    }
  };
  $self->SetError("failed in IsReallyForeignPub($id): $@") if $@;
  return $is;
}

sub ReadCities
{
  my $self = shift;
  
  my $in = $self->get('root') . '/bin/c/crms/us_cities.txt';
  open (FH, '<', $in) || $self->SetError("Could not open $in");
  my $cities = '';
  while (<FH>) { chomp; $cities .= "==$_=="; }
  close FH;
  $self->set('cities',$cities);
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
