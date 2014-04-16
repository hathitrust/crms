package Candidates_crmsworld;

use strict;
use warnings;

sub new
{
  my $class = shift;
  my $self = { crms => shift };
  return bless $self, $class;
}

# If oneoff is set, return undef to indicate this is the
# catch-all system.
sub Countries
{
  my $self   = shift;
  my $oneoff = shift;

  return undef if $oneoff;
  #return {'United Kingdom'=>1, 'Canada'=>1, 'Australia'=>1, 'Spain'=>1};
  return {'United Kingdom'=>1, 'Canada'=>1, 'Australia'=>1};
}

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

  my $year = $self->{crms}->GetTheYear();
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
  elsif ($country eq 'Australia')
  {
    return $year-120 if $name eq 'minYear';
    # FIXME: will this ever change?
    return 1954;
  }
  elsif ($country eq 'Spain')
  {
    return $year-140 if $name eq 'minYear';
    return 1935;
  }
  return $year-120 if $name eq 'minYear';
  return $year-51;
}

sub GetViolations
{
  my $self = shift;
  my ($id, $record, $priority, $override) = @_;

  my @errs = ();
  my $pub = $self->{crms}->GetRecordPubDate($id, $record);
  my $where = $self->{crms}->GetRecordPubCountry($id, $record);
  $where =~ s/\s*\(.*//;
  if ($pub =~ m/\d\d\d\d/)
  {
    my $min = $self->GetCutoffYear($where, 'minYear');
    my $max = $self->GetCutoffYear($where, 'maxYear');
    #$max = GetCutoffYear('maxYearOverride') if ($override and $priority == 3) or $priority == 4;
    push @errs, "$pub not in range $min-$max for $where" if ($pub < $min || $pub > $max);
  }
  else
  {
    push @errs, "pub date not completely specified ($pub)";
  }
  # FIXME: use Countries() method
  push @errs, "foreign pub ($where)" if $where ne 'United Kingdom' and
                                        $where ne 'Australia' and
                                        $where ne 'Canada';
  push @errs, 'non-BK format' unless $self->{crms}->IsFormatBK($id, $record);
  #printf "$id: %s\n", join '; ', @errs if scalar @errs;
  return @errs;
}

sub ShouldVolumeGoInUndTable
{
  my $self   = shift;
  my $id     = shift;
  my $record = shift;

  $record = $self->{crms}->GetMetadata($id) unless $record;
  return 'no meta' unless $record;
  my $lang = $self->{crms}->GetRecordPubLanguage($id, $record);
  my $where = $self->{crms}->GetRecordPubCountry($id, $record);
  if ($where eq 'Spain')
  {
    return 'language' if 'spa' ne $lang and 'eng' ne $lang;
  }
  else
  {
    return 'language' if 'eng' ne $lang;
  }
  return 'translation' if $self->{crms}->IsTranslation($id, $record);
  return undef;
}

1;
