package Commonwealth;
use parent 'Project';

use strict;
use warnings;

sub new {
  my $class = shift;
  return $class->SUPER::new(@_);
}

my $CANDIDATE_COUNTRIES = {
  'Australia' => 1,
  'Canada' => 1,
  'United Kingdom' => 1
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
  # Country of publication
  my $where = $record->country;
  # Check well-defined record dates
  my $publication_date = $record->publication_date;
  my $publication_date_string = $publication_date->to_s;
  my $extracted_dates = $publication_date->extract_dates;
  my ($min, $max) = @{$self->year_range($where)};
  if (!scalar @$extracted_dates) {
    push @errs, "pub date not completely specified ($publication_date_string)";
  } else {
    if (!$publication_date->do_dates_overlap($min, $max)) {
      push @errs, "$publication_date_string not in range $min-$max for $where"
    }
  }
  unless ($CANDIDATE_COUNTRIES->{$where}) {
    push @errs, "foreign pub ($where)";
  }
  push @errs, 'non-BK format' unless $record->isFormatBK($id);
  return {'status' => 'no', 'msg' => join '; ', @errs} if scalar @errs;
  my $src;
  $src = 'translation' if $record->isTranslation;
  return {'status' => 'filter', 'msg' => $src} if defined $src;
  return {'status' => 'yes', 'msg' => ''};
}

sub year_range {
  my $self    = shift;
  my $country = shift;
  my $year    = shift || $self->{crms}->GetTheYear();

  if ($country eq 'United Kingdom' || $country eq 'Australia') {
    return [$year - 124, $year - 83]
  }
  # Magic hardcoded 1971 based on regime changes, not rolling wall.
  return [$year - 125, 1971] if $country eq 'Canada';
  return [0, 0];
}

# ========== REVIEW ========== #
sub PresentationOrder {
  return 'q.priority DESC,b.author ASC';
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
sub ExtractReviewData {
  my $self = shift;
  my $cgi  = shift;

  my $date = $cgi->param('date');
  my $data;
  if ($date) {
    $data = {'date' => $date};
    $data->{'pub'} = 1 if $cgi->param('pub');
    $data->{'crown'} = 1 if $cgi->param('crown');
    $data->{'src'} = $cgi->param('src') if $cgi->param('src');
    # There may be a stale Actual Pub Date hidden in the UI when
    # the Publication Date checkbox is checked, only record it if
    # the effective date is not a pub date.
    if (!$cgi->param('pub') && $cgi->param('actual')) {
      $data->{'actual'} = $cgi->param('actual');
    }
  }
  return $data;
}

# Return a dictionary ref with the following keys:
# id: the reviewdata id
# format: HTML-formatted data for inline display. May be blank.
# format_long: HTML-formatted data for tooltip display. May be blank.
# e.g., {"date":"1881","pub":1,"src":"VIAF"}
sub FormatReviewData {
  my $self = shift;
  my $id   = shift;
  my $json = shift;

  my $jsonxs = JSON::XS->new->utf8->canonical(1)->pretty(0);
  my $data = $jsonxs->decode($json);
  my $fmt = '';
  if (scalar keys %$data) {
    my $date_type = ($data->{pub})? 'Pub' : 'ADD';
    $fmt = "$date_type <strong>$data->{date}</strong>";
    if ($data->{crown}) {
      $fmt .= " Crown <strong>\x{1F451}</strong>";
    }
    if ($data->{actual}) {
      $fmt .= "<br/>Actual Pub Date <strong>$data->{actual}</strong>";
    }
  }
  return {'id' => $id, 'format' => $fmt, 'format_long' => ''};
}

1;
