package StateGovDocs;
use parent 'Project';

use strict;
use warnings;

sub new
{
  my $class = shift;
  return $class->SUPER::new(@_);
}

my %TEST_HTIDS = (
    'yale.39002030686159' => 'Example'
);

sub tests
{
  my $self = shift;

  my @tests = keys %TEST_HTIDS;
  return \@tests;
}

# ========== CANDIDACY ========== #
# Returns undef for failure, or hashref with two fields:
# status in {'yes', 'no', 'filter'}
# msg potentially empty explanation.
sub EvaluateCandidacy
{
  my $self   = shift;
  my $id     = shift;
  my $record = shift;
  my $attr   = shift;
  my $reason = shift;

  my @errs;
  # Check current rights
  push @errs, "current rights $attr/$reason" if $attr ne 'ic' or $reason ne 'bib';
  # Check well-defined record dates
  my $publication_date = $record->publication_date;
  my $copyright_date = $publication_date->exact_copyright_date;
  if (!defined $copyright_date)
  {
    my $publication_date_string = $publication_date->to_s;
    push @errs, "pub date not completely specified ($publication_date_string)";
  }
  else
  {
    # Check year range
    my $now = $self->{'crms'}->GetTheYear();
    my $min = $now - 95 + 1;
    my $max = 1977;
    if ($copyright_date < $min or $copyright_date > $max)
    {
      push @errs, "pub date $copyright_date not in range $min-$max";
    }
  }
  # Out of scope if published in a non-US country, or if Undetermined country
  # and foreign city or no US city.
  # I.e., explicitly undetermined place requires 1+ US and 0 foreign cities.
  my $where = $record->country;
  my $cities = $record->cities;
  if ($where =~ m/^Undetermined/i)
  {
    if (!scalar @{$cities->{'us'}} || scalar @{$cities->{'non-us'}})
    {
      push @errs, 'undetermined pub place';
    }
  }
  elsif ($where ne 'USA')
  {
    push @errs, "foreign pub ($where)";
  }
  push @errs, 'non-BK format' unless $record->isFormatBK($id, $record);
  push @errs, 'not a state government document' unless $self->IsStateGovDoc($id, $record);
  if (scalar @errs)
  {
    return {'status' => 'no', 'msg' => join '; ', @errs};
  }
  my $src;
  $src = 'gov' if $record->IsProbableGovDoc();
  my %langs = ('   ' => 1, '|||' => 1, 'emg' => 1,
               'eng' => 1, 'enm' => 1, 'mul' => 1,
               'new' => 1, 'und' => 1);
  $src = 'language' if !$langs{$record->language};
  $src = 'dissertation' if $record->isThesis;
  $src = 'translation' if $record->isTranslation;
  #$src = 'foreign' if $self->IsReallyForeignPub($record);
  return {'status' => 'filter', 'msg' => $src} if defined $src;
  return {'status' => 'yes', 'msg' => ''};
}

# Returns a code {clmos} if state or local document, undef otherwise.
sub IsStateGovDoc
{
  my $self   = shift;
  my $id     = shift;
  my $record = shift;

  my %codes = ('c' => 1, 'l' => 1, 'm' => 1, 'o' => 1, 's' => 1);
  my $author = $record->author || '';
  my $title = $record->title || '';
  my $leader = $record->GetControlfield('008');
  my $code = (length $leader > 28)? substr($leader, 28, 1):'';
  my $field260b = $record->GetDatafield('260', 'b') || '';
  my $field110ab = $record->GetSubfields('110', 1, 'a', 'b') || '';
  return $code if (defined $codes{$code} &&
                   $author !~ m/university/i && $author !~ m/college/i &&
                   $title !~ m/university/i && $title !~ m/college/i &&
                   $field260b !~ m/((university)|(univ\.)|(college)).*?press/i) ||
                   $field110ab =~ m/\(state\)/i;
}

# ========== REVIEW ========== #
sub ReviewPartials
{
  return ['top', 'bibdata', 'authorities',
          'copyrightForm', 'expertDetails'];
}

1;
