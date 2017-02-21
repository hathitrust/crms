package Candidates_crmsworld;

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
                  ($attr eq 'pdus' && $reason eq 'bib');
  $correct = 0 if defined $new_attr && $new_attr eq 'und' &&
                  ($attr eq 'pd' || $attr eq 'pdus');
  return $correct;
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
  my $pub = $record->copyrightDate;
  my $where = $record->country;
  $where =~ s/\s*\(.*//;
  if (defined $pub && $pub =~ m/\d\d\d\d/)
  {
    my $min = $self->GetCutoffYear($where, 'minYear');
    my $max = $self->GetCutoffYear($where, 'maxYear');
    #$max = GetCutoffYear('maxYearOverride') if ($override and $priority == 3) or $priority == 4;
    push @errs, "$pub not in range $min-$max for $where" if ($pub < $min || $pub > $max);
  }
  else
  {
    my $leader = $record->GetControlfield('008');
    my $type = substr($leader, 6, 1);
    my $date1 = substr($leader, 7, 4);
    my $date2 = substr($leader, 11, 4);
    push @errs, "pub date not completely specified ($type,$date1,$date2)";
  }
  # FIXME: use Countries() method
  push @errs, "foreign pub ($where)" if $where ne 'United Kingdom' and
                                        $where ne 'Australia' and
                                        $where ne 'Canada';
  push @errs, 'non-BK format' unless $record->isFormatBK($id);
  #printf "$id: %s\n", join '; ', @errs if scalar @errs;
  return @errs;
}

sub ShouldVolumeBeFiltered
{
  my $self   = shift;
  my $id     = shift;
  my $record = shift;

  my $lang = $record->language;
  my $where = $record->country;
  if ($where eq 'Spain')
  {
    return 'language' if 'spa' ne $lang and 'eng' ne $lang;
  }
  else
  {
    return 'language' if 'eng' ne $lang;
  }
  return 'translation' if $record->isTranslation;
  my $date = $self->{crms}->FormatPubDate($id, $record);
  return 'date range' if $date =~ m/^\d+-(\d+)?$/;
  return undef;
}

sub GetProject
{
  my $self   = shift;
  my $id     = shift;
  my $record = shift;

  return undef;
}

1;
