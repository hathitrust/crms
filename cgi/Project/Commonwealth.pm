package Commonwealth;
use parent 'Project';

use strict;
use warnings;

sub new
{
  my $class = shift;
  return $class->SUPER::new(@_);
}

# 2023 Commonwealth reactivation only for Canada
my $CANDIDATE_COUNTRIES = {
  # 'Australia' => 1,
  'Canada' => 1,
  # 'United Kingdom' => 1
};

# ========== CANDIDACY ========== #
# Returns undef for failure, or hashref with two fields:
# status in {'yes', 'no', 'filter'}
# msg potentially empty explanation.
sub EvaluateCandidacy {
  my $self   = shift;
  my $id     = shift;
  my $record = shift;
  my $attr   = shift;
  my $reason = shift;

  my @errs = ();
  # Check current rights
  push @errs, "current rights $attr/$reason" if ($attr ne 'ic' and $attr ne 'pdus') or $reason ne 'bib';
  # Check well-defined record dates
  my $pub = $record->copyrightDate;
  if (!defined $pub || $pub !~ m/\d\d\d\d/) {
    my $leader = $record->GetControlfield('008');
    my $type = substr($leader, 6, 1);
    my $date1 = substr($leader, 7, 4);
    my $date2 = substr($leader, 11, 4);
    push @errs, "pub date not completely specified ($date1,$date2,'$type')";
  }
  # Check country of publication
  my $where = $record->country;
  unless ($CANDIDATE_COUNTRIES->{$where}) {
    push @errs, "foreign pub ($where)";
  }
  if (defined $pub && $pub =~ m/\d\d\d\d/) {
    my ($min, $max) = @{$self->year_range($where)};
    push @errs, "$pub not in range $min-$max for $where" if ($pub < $min || $pub > $max);
  }
  push @errs, 'non-BK format' unless $record->isFormatBK($id);
  return {'status' => 'no', 'msg' => join '; ', @errs} if scalar @errs;
  my $src;
  my $lang = $record->language;
  $src = 'language' if 'eng' ne $lang;
  $src = 'translation' if $record->isTranslation;
  my $date = $self->{crms}->FormatPubDate($id, $record);
  $src = 'date range' if $date =~ m/^\d+-(\d+)?$/;
  return {'status' => 'filter', 'msg' => $src} if defined $src;
  return {'status' => 'yes', 'msg' => ''};
}

sub year_range {
  my $self    = shift;
  my $country = shift;
  my $year    = shift || $self->{crms}->GetTheYear();

  if ($country eq 'United Kingdom' || $country eq 'Australia') {
    return [$year - 125, $year - 71]
  }
  # Magic hardcoded 1971 based on regime changes, not rolling wall.
  return [$year - 125, 1971] if $country eq 'Canada';
  return [0, 0];
}

# ========== REVIEW ========== #
sub PresentationOrder {
  return 'b.author ASC';
}

sub ReviewPartials {
  return ['top', 'bibdata_commonwealth', 'authorities',
          'ADDForm', 'expertDetails'];
}

sub ValidateSubmission {
  my $self = shift;
  my $cgi  = shift;

  my @errs;
  my $rights = $cgi->param('rights');
  return 'You must select a rights/reason combination' unless $rights;
  my ($attr, $reason) = $self->{'crms'}->TranslateAttrReasonFromCode($rights);
  my $date = $cgi->param('date');
  my $pub = $cgi->param('pub');
  my $note = $cgi->param('note');
  my $category = $cgi->param('category');
  $date =~ s/\s+//g if $date;
  if ($attr eq 'und' && $reason eq 'nfi' &&
      (!$category ||
       (!$note && 1 == $self->{'crms'}->SimpleSqlGet('SELECT need_note FROM categories WHERE name=?', $category)))) {
    push @errs, 'und/nfi must include note category and note text';
  }
  if ($date && $date !~ m/^-?\d{1,4}$/) {
    push @errs, 'year must be only decimal digits';
  }
  elsif (($reason eq 'add' || $reason eq 'exp') && !$date) {
    push @errs, "*/$reason must include a numeric year";
  }
  if ($category && !$note) {
    if ($self->{'crms'}->SimpleSqlGet('SELECT need_note FROM categories WHERE name=?', $category)) {
      push @errs, qq{category "$category" requires a note};
    }
  }
  elsif ($note && !$category) {
    push @errs, 'must include a category if there is a note';
  }
  return join ', ', @errs;
}

# Extract Project-specific data from the CGI into a struct
# that will be encoded as JSON string in the reviewdata table.
sub ExtractReviewData
{
  my $self = shift;
  my $cgi  = shift;

  my $date = $cgi->param('date');
  my $data;
  if ($date)
  {
    $data = {'date' => $date};
    $data->{'pub'} = 1 if $cgi->param('pub');
    $data->{'crown'} = 1 if $cgi->param('crown');
    $data->{'src'} = $cgi->param('src') if $cgi->param('src');
    $data->{'actual'} = $cgi->param('actual') if $cgi->param('actual');
  }
  return $data;
}

# Return a dictionary ref with the following keys:
# id: the reviewdata id
# format: HTML-formatted data for inline display. May be blank.
# format_long: HTML-formatted data for tooltip display. May be blank.
# e.g., {"date":"1881","pub":1,"src":"VIAF"}
sub FormatReviewData
{
  my $self = shift;
  my $id   = shift;
  my $json = shift;

  my $jsonxs = JSON::XS->new->utf8->canonical(1)->pretty(0);
  my $data = $jsonxs->decode($json);
  my $fmt = sprintf '%s <strong>%s</strong> %s%s',
    ($data->{'pub'})? 'Pub' : 'ADD',
    $data->{'date'},
    ($data->{'crown'})? " Crown <strong>\x{1F451}</strong>" : '';
  return {'id' => $id, 'format' => $fmt, 'format_long' => ''};
}

1;
