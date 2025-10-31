package SBCR;
use parent 'Project';

use strict;
use warnings;

use lib $ENV{'SDRROOT'} . '/crms/lib';
use CRMS::Entitlements;

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
  ## ic/ren requires a renewal number and date
  if ($rights eq 'ic/ren') {
    if (!$renNum || !$renDate) {
      push @errs, 'ic/ren must include renewal id and renewal date';
    }
  }
  if ($actual && $actual !~ m/^\d{4}(-\d{4})?$/) {
    push @errs, 'Actual Publication Date must be a date or a date range (YYYY or YYYY-YYYY)';
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

sub format_renewal_data {
  my $self    = shift;
  my $renNum  = shift || '';
  my $renDate = shift || '';

  return '' unless $renNum || $renDate;
  return "<strong>Renewal</strong> $renNum / $renDate";
}

1;
