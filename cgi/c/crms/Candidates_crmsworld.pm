package Candidates;

use strict;
use warnings;
use vars qw( @ISA @EXPORT @EXPORT_OK );
our @EXPORT = qw(RightsClause GetViolations ShouldVolumeGoInUndTable);

# pd/bib or pdus/bib or op
sub RightsClause
{
  return '(attr=2 AND reason=1) OR (attr=3 AND reason=1) OR attr=9';
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
    my $min = $self->GetCutoffYear('minYear');
    my $max = $self->GetCutoffYear('maxYear');
    $max = $self->GetCutoffYear('maxYearOverride') if ($override and $priority == 3) or $priority == 4;
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
    push @errs, "current rights are $attr/$reason" unless ($attr eq 'pdus' || ($attr eq 'ic' && $reason eq 'bib'));
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
