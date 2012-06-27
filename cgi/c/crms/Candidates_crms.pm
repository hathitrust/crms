package Candidates;

use strict;
use warnings;
use vars qw( @ISA @EXPORT @EXPORT_OK );
our @EXPORT = qw(RightsClause GetViolations ShouldVolumeGoInUndTable);

sub RightsClause
{
  return 'attr=2 AND reason=1';
}

sub GetViolations
{
  my $self = shift;
  my ($id, $record, $priority, $override) = @_;
  my @errs = ();

  my $pub = $self->GetPublDate($id, $record);
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
  my ($attr,$reason,$src,$usr,$time,$note) = @{$self->RightsQuery($id,1)->[0]};
  push @errs, "current rights are $attr/$reason" unless ($attr eq 'ic' && $reason eq 'bib') or
                                                        ($override and $priority == 3) or $priority == 4;
  return @errs;
}

sub ShouldVolumeGoInUndTable
{
  my $self   = shift;
  my $id     = shift;
  my $record = shift;

  my $src = undef;
  $record = $self->GetMetadata($id) unless $record;
  return $src unless $record;
  my $lang = $self->GetPubLanguage($id, $record);
  if ($self->IsProbableGovDoc($id, $record)) { $src = 'gov'; }
  elsif ('eng' ne $lang) { $src = 'language'; }
  elsif ($self->IsThesis($id, $record)) { $src = 'dissertation'; }
  elsif ($self->IsTranslation($id, $record)) { $src = 'translation'; }
  # FIXME: Move IsReallyForeignPub over here?
  elsif ($self->IsReallyForeignPub($id, $record)) { $src = 'foreign'; }
  return $src;
}

1;
