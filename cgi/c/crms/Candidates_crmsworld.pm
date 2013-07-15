package Candidates;

use strict;
use warnings;
use vars qw( @ISA @EXPORT @EXPORT_OK );
our @EXPORT = qw(HasCorrectRights HasCorrectYear GetCutoffYear GetViolations ShouldVolumeGoInUndTable);

# If new_attr and new_reason are supplied, they are the final determination
# and this checks whether that determination should be exported (is the
# volume in scope?).
# In CRMS World, we can't export anything if the volume is out of scope, or
# if current rights are pdus and new rights are und.
sub HasCorrectRights
{
  my $self       = shift;
  my $attr       = shift;
  my $reason     = shift;
  my $new_attr   = shift;
  my $new_reason = shift;

  my $correct = 0;
  $correct = 1 if ($attr eq 'ic' && $reason eq 'bib') ||
                  ($attr eq 'pdus' && $reason eq 'bib') ||
                  $attr eq 'op';
  $correct = 0 if defined $new_attr && $new_attr eq 'und' &&
                  ($attr eq 'pd' || $attr eq 'pdus');
  # Clobber pdus/gfv if exporting any rights; per rrotter Core Services
  # never put pdus/gfv over pdus/bib.
  $correct = 1 if defined $new_attr && defined $new_reason &&
                  $attr eq = 'pdus' && $reason eq 'gfv';
  return $correct;
}

sub HasCorrectYear
{
  my $self    = shift;
  my $country = shift;
  my $year    = shift;

  my $min = GetCutoffYear($self, $country, 'minYear');
  my $max = GetCutoffYear($self, $country, 'maxYear');
  return ($min <= $year && $year <= $max);
}

sub GetCutoffYear
{
  my $self    = shift;
  my $country = shift;
  my $name    = shift;

  my $year = $self->GetTheYear();
  # Generic cutoff for add to queue page.
  if (! defined $country)
  {
    return $year-140 if $name eq 'minYear';
    return $year-51;
  }
  if ($country eq 'United Kingdom')
  {
    return $year-140 if $name eq 'minYear';
    return $year-71;
  }
  return $year-120 if $name eq 'minYear';
  return $year-51;
}

sub GetViolations
{
  my $self = shift;
  my ($id, $record, $priority, $override) = @_;
  my @errs = ();
  my $pub = $self->GetRecordPubDate($id, $record);
  my $where = $self->GetRecordPubCountry($id, $record);
  $where =~ s/\s*\(.*//;
  if ($pub =~ m/\d\d\d\d/)
  {
    my $min = GetCutoffYear($self, $where, 'minYear');
    my $max = GetCutoffYear($self, $where, 'maxYear');
    #$max = GetCutoffYear('maxYearOverride') if ($override and $priority == 3) or $priority == 4;
    push @errs, "$pub not in range $min-$max" if ($pub < $min || $pub > $max);
  }
  else
  {
    push @errs, "pub date not completely specified ($pub)";
  }
  push @errs, "foreign pub ($where)" if $where ne 'United Kingdom' and
                                        $where ne 'Australia' and
                                        $where ne 'Canada';
  push @errs, 'non-BK format' unless $self->IsFormatBK($id, $record);
  my $ref = $self->RightsQuery($id,1);
  $ref = $ref->[0] if $ref;
  if ($ref)
  {
    my ($attr,$reason,$src,$usr,$time,$note) = @{$ref};
    my $rights = "$attr/$reason";
    push @errs, "current rights are $rights" unless $attr eq 'pdus' or
                                                    $rights eq 'ic/bib' or
                                                    $attr eq 'op';
  }
  else
  {
    push @errs, "rights query for $id failed";
  }
  #printf "$id: %s\n", join '; ', @errs if scalar @errs;
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
  if ('eng' ne $lang) { $src = 'language'; }
  elsif ($self->IsTranslation($id, $record)) { $src = 'translation'; }
  return $src;
}

1;
