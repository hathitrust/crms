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
  my $rights = $rights_data->{name};
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
    push @errs, 'date must be only decimal digits';
  }
  if (($reason eq 'add' || $reason eq 'exp') && !$date) {
    push @errs, "*/$reason must include a numeric year";
  }
  ## ic/ren requires a nonexpired renewal if 1963 or earlier
  if ($rights eq 'ic/ren') {
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
  if ($rights eq 'pd/ren') {
    if ($renNum || $renDate) {
      push @errs, 'pd/ren should not include renewal info';
    }
  }
  if ($actual && $actual !~ m/^\d{4}(-\d{4})?$/) {
    push @errs, 'Actual Publication Date must be a date or a date range (YYYY or YYYY-YYYY)';
  }
  ## pd*/cdpp must not have renewal data
  if (($rights eq 'pd/cdpp' || $rights eq 'pdus/cdpp') && ($renNum || $renDate)) {
    push @errs, "$attr/cdpp must not include renewal info";
  }
  if ($rights eq 'pd/cdpp' && (!$note || !$category)) {
    push @errs, 'pd/cdpp must include note category and note text';
  }
  ## ic/cdpp must not have renewal data
  # NOTE: this could be merged with the pd/cdpp and pdus/cdpp logic above
  if ($rights eq 'ic/cdpp' && ($renNum || $renDate)) {
    push @errs, 'ic/cdpp must not include renewal info';
  }
  # NOTE: this could be merged with the pd/cdpp and pdus/cdpp logic above
  if ($rights eq 'ic/cdpp' && (!$note || !$category)) {
    push @errs, 'ic/cdpp must include note category and note text';
  }
  if ($rights eq 'und/nfi' && !$category) {
    push @errs, 'und/nfi must include note category';
  }
  ## und/ren must have Note Category Inserts/No Renewal
  if ($rights eq 'und/ren') {
    if (!$category || $category ne 'Inserts/No Renewal') {
      push @errs, 'und/ren must have note category Inserts/No Renewal';
    }
  }
  ## and vice versa
  if ($category && $category eq 'Inserts/No Renewal') {
    if ($rights ne 'und/ren') {
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

  my $params = $self->extract_parameters($cgi);
  my $data = {};
  $data->{'renNum'} = $params->{renNum} if $params->{renNum};
  $data->{'renDate'} = $params->{renDate} if $params->{renDate};
  $data->{'date'} = $params->{date} if $params->{date};
  $data->{'pub'} = 1 if $params->{pub};
  $data->{'crown'} = 1 if $params->{crown};
  $data->{'actual'} = $params->{actual} if $params->{actual};
  $data->{'approximate'} = 1 if $params->{approximate};
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
  my $renewal_fmt = $self->format_renewal_data($data->{renNum}, $data->{renDate});
  if ($renewal_fmt) {
    push @lines, $renewal_fmt;
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
# Would have to think carefully about other possible side effect data transformations,
# don't know if it's appropriate to delve into the semantics of the review
# parameters too deeply.
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
# Note: this can also be used by the Core project logic in Project.pm
sub renewal_date_to_year {
  my $self    = shift;
  my $renDate = shift;

  # If the last two digits are not numeric for some reason then there is no reasonable answer.
  return '' unless $renDate =~ m/\d\d$/;
  return '19' . substr($renDate, -2, 2);
}

sub format_renewal_data {
  my $self    = shift;
  my $renNum  = shift || '';
  my $renDate = shift || '';

  return '' unless $renNum || $renDate;
  return "<strong>Renewal</strong> $renNum / $renDate";
}

1;
