package StateGovDocs;
use parent 'Project';

use strict;
use warnings;

use Utilities;

sub new
{
  my $class = shift;
  return $class->SUPER::new(@_);
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
  my $pub = $record->copyrightDate;
  if (!defined $pub || $pub !~ m/\d\d\d\d/)
  {
    my $leader = $record->GetControlfield('008');
    my $type = substr($leader, 6, 1);
    my $date1 = substr($leader, 7, 4);
    my $date2 = substr($leader, 11, 4);
    push @errs, "pub date not completely specified ($date1,$date2,'$type')";
  }
  else
  {
    # Check year range
    my $now = Utilities->new->Year();
    my $min = $now - 95 + 1;
    my $max = 1977;
    push @errs, "pub date $pub not in range $min-$max" if $pub < $min or $pub > $max;
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
          'HTView', 'copyrightForm', 'expertDetails'];
}

1;
