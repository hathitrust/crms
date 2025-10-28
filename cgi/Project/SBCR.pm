package SBCR;
use parent 'Project';

use strict;
use warnings;

sub new {
  my $class = shift;
  return $class->SUPER::new(@_);
}

# ========== REVIEW ========== #
sub ValidateSubmission {
  my $self = shift;
  my $cgi  = shift;

  my @errs;
  my $params = $self->extract_parameters($cgi);
  return 'You must select a rights/reason combination' unless $params->{rights};
  my $rights_data = CRMS::Entitlements->new(crms => $self->{crms})->rights_by_id($params->{rights});
  my $attr = $rights_data->{attribute_name};
  my $reason = $rights_data->{reason_name};
  # Renewal information
  my $renNum = $params->{renNum};
  my $renDate = $params->{renDate};
  # ADD and pub date
  my $date = $params->{date};
  my $actual = $params->{actual};
  # Note and note category
  my $note = $params->{note};
  my $category = $params->{category};
  if ($date && $date !~ m/^-?\d{1,4}$/) {
    push @errs, 'year must be only decimal digits';
  }
  elsif (($reason eq 'add' || $reason eq 'exp') && !$date) {
    push @errs, "*/$reason must include a numeric year";
  }
  ## ic/ren requires a nonexpired renewal if 1963 or earlier
  if ($attr eq 'ic' && $reason eq 'ren') {
    if ($renNum && $renDate) {
      my $year = $self->renewal_date_to_year($renDate);
      if ($year && $year < 1950) {
        push @errs, "renewal ($renDate) has expired: volume is pd";
      }
    }
    else {
      push @errs, 'ic/ren must include renewal id and renewal date';
    }
  }
  ## pd/ren should not have a ren number or date, and is not allowed for post-1963 works.
  if ($attr eq 'pd' && $reason eq 'ren') {
    if ($renNum && $renDate) {
      push @errs, 'pd/ren should not include renewal info';
    }
  }
  if ($actual && $actual !~ m/^\d{4}(-\d{4})?$/) {
    push @errs, 'Actual Publication Date must be a date or a date range (YYYY or YYYY-YYYY)';
  }
  ## pd*/cdpp must not have renewal data
  if (($attr eq 'pd' || $attr eq 'pdus') && $reason eq 'cdpp' && ($renNum || $renDate)) {
    push @errs, "$attr/$reason must not include renewal info";
  }
  if ($attr eq 'pd' && $reason eq 'cdpp' && (!$note || !$category)) {
    push @errs, 'pd/cdpp must include note category and note text';
  }
  ## ic/cdpp must not have renewal data
  # NOTE: this could be merged with the pd/cdpp and pdus/cdpp logic above
  if ($attr eq 'ic' && $reason eq 'cdpp' && ($renNum || $renDate)) {
    push @errs, 'ic/cdpp must not include renewal info';
  }
  # NOTE: this could be merged with the pd/cdpp and pdus/cdpp logic above
  if ($attr eq 'ic' && $reason eq 'cdpp' && (!$note || !$category)) {
    push @errs, 'ic/cdpp must include note category and note text';
  }
  if ($attr eq 'und' && $reason eq 'nfi' && !$category) {
    push @errs, 'und/nfi must include note category';
  }
  
  ### FIXME: STILL NEED TESTS FOR MOST OF THESE
  
  ## und/ren must have Note Category Inserts/No Renewal
  if ($attr eq 'und' && $reason eq 'ren') {
    if (!defined $category || $category ne 'Inserts/No Renewal') {
      push @errs, 'und/ren must have note category Inserts/No Renewal';
    }
  }
  ## and vice versa
  if ($category && $category eq 'Inserts/No Renewal') {
    if ($attr ne 'und' || $reason ne 'ren') {
      push @errs, 'Inserts/No Renewal must have rights code und/ren. ';
    }
  }
  # Category/Note
  if ($category && !$note) {
    if ($self->{'crms'}->SimpleSqlGet('SELECT need_note FROM categories WHERE name=?', $category)) {
      push @errs, qq{category "$category" requires a note};
    }
  }
  elsif ($note && !$category) {
    push @errs, 'must include a category if there is a note';
  }
  if ($category && $category eq 'Not Government' && $attr ne 'und') {
    push @errs, 'Not Government category requires und/NFI';
  }
  return join ', ', @errs;
}

# Extract Project-specific data from the CGI into a struct
# that will be encoded as JSON string in the reviewdata table.
sub ExtractReviewData {
  my $self = shift;
  my $cgi  = shift;

  my $renNum = $cgi->param('renNum') || '';
  my $renDate = $cgi->param('renDate') || '';
  my $date = $cgi->param('date') || '';
  my $pub = $cgi->param('pub') || '';
  my $crown = $cgi->param('crown') || '';
  my $actual = $cgi->param('actual') || '';
  my $approximate = $cgi->param('approximate') || '';
  my $data = {};
  $data->{'renNum'} = $renNum if $renNum;
  $data->{'renDate'} = $renDate if $renDate;
  $data->{'date'} = $date if $cgi->param('date');
  $data->{'pub'} = 1 if $cgi->param('pub');
  $data->{'crown'} = 1 if $cgi->param('crown');
  $data->{'actual'} = $actual if $actual;
  $data->{'approximate'} = 1 if $approximate;
  return $data;
}

sub FormatReviewData {
  my $self = shift;
  my $id   = shift;
  my $json = shift;

  # FIXME pretty() isn't needed here?
  my $jsonxs = JSON::XS->new->utf8->canonical(1)->pretty(0);
  my $data = $jsonxs->decode($json);
  my @lines;
  if (scalar keys %$data) {
    if ($data->{renNum} || $data->{renDate}) {
      push @lines, sprintf '<strong>Renewal</strong> %s / %s', $data->{'renNum'}, $data->{'renDate'};
    }
    if ($data->{date}) {
      my $date_type = ($data->{pub})? 'Pub' : 'ADD';
      push @lines, "<strong>$date_type</strong> $data->{date}";
    }
    if ($data->{crown}) {
      push @lines, "<strong>Crown</strong> \x{1F451}";
    }
    if ($data->{actual}) {
      push @lines, "<strong>Actual Pub Date</strong> $data->{actual}";
    }
    if ($data->{approximate}) {
      push @lines, "<strong>Approximate Pub Date</strong>";
    }
  }
  return {
    'id' => $id,
    'format' => join('<br/>', @lines),
    'format_long' => ''
  };
}

sub ReviewPartials {
  return [
    'top',
    'bibdata_sbcr',
    'expertDetails',
    'authorities',
    'sbcr_form'
  ];
}

# extract CGI parameters into a hashref
# values are stripped
# Note: this might be useful to apply much earlier in the call chain, would
# decouple project modules from CGI
sub extract_parameters {
  my $self = shift;
  my $cgi  = shift;

  my $params = {};
  foreach my $name ($cgi->param) {
    my $value = $cgi->param($name);
    $value =~ s/\A\s+|\s+\z//ug;
    $params->{$name} = $value;
  }
  return $params;
}

# Turn a Stanford renewal date, e.g., 21Oct52, into a year, e.g., 1952
sub renewal_date_to_year {
  my $self    = shift;
  my $renDate = shift;

  # If the last two digits are not numeric for some reason then there is no reasonable answer.
  return '' unless $renDate =~ m/\d\d$/;
  return '19' . substr($renDate, -2, 2);
}

1;
