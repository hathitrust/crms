package Candidates;

use strict;
use warnings;
use vars qw( @ISA @EXPORT @EXPORT_OK );
our @EXPORT = qw(RightsClause GetViolations ShouldVolumeGoInUndTable);

# pd/bib or op
sub RightsClause
{
  return '(attr=2 AND reason=1) OR attr=3';
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
  push @errs, 'gov doc' if $self->IsGovDoc($id, $record );
  push @errs, 'foreign pub' if $self->IsForeignPub($id, $record);
  push @errs, 'non-BK format' unless $self->IsFormatBK($id, $record);
  my $ref = $self->RightsQuery($id,1);
  $ref = $ref->[0] if $ref;
  if ($ref)
  {
    my ($attr,$reason,$src,$usr,$time,$note) = @{$ref};
    push @errs, "current rights are $attr/$reason" unless ($attr eq 'ic' && $reason eq 'bib') or
                                                          ($override and $priority == 3) or $priority == 4;
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
  $record = $self->GetMetadata($id) unless $record;
  return 'no meta' unless $record;
  my $lang = $self->GetRecordPubLanguage($id, $record);
  if (IsProbableGovDoc($self, $id, $record)) { $src = 'gov'; }
  elsif ('eng' ne $lang) { $src = 'language'; }
  elsif ($self->IsThesis($id, $record)) { $src = 'dissertation'; }
  elsif ($self->IsTranslation($id, $record)) { $src = 'translation'; }
  # FIXME: Move IsReallyForeignPub over here?
  elsif ($self->IsReallyForeignPub($id, $record)) { $src = 'foreign'; }
  return $src;
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

  $record = $self->GetMetadata($id) unless $record;
  if (!$record) { $self->SetError("no record in IsProbableGovDoc: $id"); return 0; }
  my $author = $self->GetRecordAuthor($id, $record);
  my $title = $self->GetRecordTitle($id, $record);
  my $xpath  = q{//*[local-name()='datafield' and @tag='260']/*[local-name()='subfield' and @code='a']};
  my $field260a = $record->findvalue($xpath);
  $xpath  = q{//*[local-name()='datafield' and @tag='260']/*[local-name()='subfield' and @code='b']};
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

1;
