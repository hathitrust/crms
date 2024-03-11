package CRMS::RightsPredictor;

# Predict copyright term for Commonwealth countries based on
# author death date or publication date.
# Used in Commonwealth project UI for populating and updating UI with
# rights based on metadata and researcher-provided data.
# Also used for New Year rights rollover.

# This could be extended to non-Commonwealth countries.

# TODO: this code relies heavily on publication/copyright date,
# and as a result makes Bib API calls multiple times in the course
# of a single review. Extending the Metadata module to use a local
# database cache for volumes in queue would enhance responsiveness
# an eliminate some unnecessary "paranoia" code.

use strict;
use warnings;
use utf8;

use Carp;
use POSIX;

use constant {
  AUSTRALIA => 'Australia',
  CANADA => 'Canada',
  UNITED_KINGDOM => 'United Kingdom'
};

use constant {
  # 95 years from date of publication; if published in 1900 the last US copyright year is 1995.
  US_COPYRIGHT_TERM => 95,
  # GATT bestowed full US copyright term to foreign works that were in copyright
  # in the non-US country of publication on Jan 1 1996.
  # Thus, if last source copyright year >= 1996 then the work is GATT-eligible.
  GATT_RESTORATION_START => 1996,
  COMMONWEALTH_CROWN_COPYRIGHT_TERM => 50,
  COMMONWEALTH_STANDARD_TERM => 70,
  CANADA_CORPORATE_TERM => 75
};

# Sanity check on reviewer-supplied date
my $VALID_DEATH_OR_PUB_DATE = qr/^-?\d{1,4}$/;
# Sanity check on 008 pub date mainly to cull partial dates and date ranges
my $VALID_PUB_DATE = qr/^\d{1,4}$/;

my $TERM_PREDICTORS = {
  &AUSTRALIA => \&australia_term,
  &CANADA => \&canada_term,
  &UNITED_KINGDOM => \&united_kingdom_term
};

# use CRMS::RightsPredictor;
# use Metadata;
#
# my $record = Metadata->new('id' => 'mdp.001');
# my $predictor = CRMS::RightsPredictor->new(record => $record);
#
# See cgi/predictRights for end-to-end example.
sub new {
  my ($class, %args) = @_;
  my $self = bless {}, $class;
  Carp::confess "record => Metadata object is a required parameter" unless $args{record};
  $self->{record} = $args{record};
  return $self;
}

# Simple API mainly for testing and reports. Currently not used in the GUI or scripts.
# Returns the same fields as #rights minus the US-specific and overall rights.
sub last_source_copyright {
  my $self              = shift;
  my $death_or_pub_date = shift || ''; # Reviewer-supplied
  my $is_pub            = shift; # Treat $death_or_pub_date as pub date for corporate authors
  my $is_crown          = shift; # Crown copyright
  my $reference_year    = shift || POSIX::strftime("%Y", localtime); # The "current" year

  # Initialize return struct
  my $prediction = { death_or_pub_date => $death_or_pub_date,
    is_pub => $is_pub,
    is_crown => $is_crown,
    reference_year => $reference_year,
    desc => [],
    error => 0 };
  $self->predict_last_source_copyright($prediction);
  return $prediction;
}

# Only used in Commonwealth project UI and New Year public domain rollover with
# dates collected in the course of reviewer research.
# Returns data structure with the following fields:
# (Note: don't expect the date math to work out in this made-up example.)
#   my $prediction = {
#     === Function parameters ===
#     death_or_pub_date => '1933',
#     is_pub => 1,
#     is_crown => 0,
#     reference_year => '2023',
#     === An array of logic and/or error descriptions intended to be concatenated ===
#     === Guaranteed to be populated with at least an error message ===
#     desc => ['this is how we calculated everything'],
#     === Error flag for unusable input or metadata ===
#     error => 0,
#     === calculated cutoff years, may be undefined in case of error ===
#     pub_year => 1933,
#     last_source_copyright_year => 2001,
#     last_us_copyright_year => 2022,
#     === calculated rights, may also be undefined in case of error ===
#     attr => 'pd',
#     reason => 'exp',
#     rights => 'pd/exp',
#   };
#
sub rights {
  my $self              = shift;
  my $death_or_pub_date = shift || ''; # Reviewer-supplied
  my $is_pub            = shift; # Treat $death_or_pub_date as pub date for corporate authors
  my $is_crown          = shift; # Crown copyright
  my $reference_year    = shift || POSIX::strftime("%Y", localtime); # The "current" year

  # Initialize return struct
  my $prediction = { death_or_pub_date => $death_or_pub_date,
    is_pub => $is_pub,
    is_crown => $is_crown,
    reference_year => $reference_year,
    desc => [],
    error => 0 };
  $prediction->{pub_year} = ($is_pub) ? $death_or_pub_date : $self->{record}->formatPubDate;
  $self->predict_last_source_copyright($prediction);
  return $prediction if $prediction->{error};

  $self->validate_for_rights($prediction);
  return $prediction if $prediction->{error};
  $prediction->{last_us_copyright_year} = $prediction->{pub_year} + US_COPYRIGHT_TERM;
  if ($prediction->{last_source_copyright_year} < $reference_year) {
    push @{$prediction->{desc}},
      "source © expired ($prediction->{last_source_copyright_year} < $reference_year)";
    $self->predict_rights_with_source_copyright_expired($prediction);
  }
  else {
    push @{$prediction->{desc}},
      "source © in force ($prediction->{last_source_copyright_year} >= $reference_year)";
    $self->predict_rights_with_source_copyright_in_force($prediction);
  }
  $prediction->{rights} = "$prediction->{attr}/$prediction->{reason}";
  return $prediction;
}

# Determine overall rights given copyright in (non-US) country of publication has expired.
sub predict_rights_with_source_copyright_expired {
  my $self       = shift;
  my $prediction = shift;

  if ($self->is_subject_to_gatt_restoration($prediction)) {
    $prediction->{attr} = 'icus';
    $prediction->{reason} = 'gatt';
    push @{$prediction->{desc}},
      "$prediction->{last_source_copyright_year} >= @{[ GATT_RESTORATION_START ]}" .
      " and US © in force ($prediction->{last_us_copyright_year} >= $prediction->{reference_year}) [GATT]";
  }
  else {
    $prediction->{attr} = 'pd';
    $prediction->{reason} = ($prediction->{is_pub})? 'exp' : 'add';
    push @{$prediction->{desc}},
      "$prediction->{last_source_copyright_year} < @{[ GATT_RESTORATION_START ]}" .
      " or US © expired ($prediction->{last_us_copyright_year} < $prediction->{reference_year}) [no GATT]";
  }
}

sub predict_rights_with_source_copyright_in_force {
  my $self       = shift;
  my $prediction = shift;

  if ($prediction->{last_us_copyright_year} >= $prediction->{reference_year}) {
    $prediction->{attr} = 'ic';
    $prediction->{reason} = ($prediction->{is_pub})? 'cdpp' : 'add';
    push @{$prediction->{desc}},
      "US © in force ($prediction->{last_us_copyright_year} >= $prediction->{reference_year})";
  }
  else {
    $prediction->{attr} = 'pdus';
    # pdus/exp is unattested and appears to be impossible given that US
    # copyright term will always extend longer than the foreign term
    # when both are based on publication date.
    # uncoverable branch true
    $prediction->{reason} = ($prediction->{is_pub})? 'exp' : 'add';
    push @{$prediction->{desc}},
      "US © expired ($prediction->{last_us_copyright_year} < $prediction->{reference_year})";
  }
}

sub is_subject_to_gatt_restoration {
  my $self       = shift;
  my $prediction = shift;

  ($prediction->{last_source_copyright_year} >= GATT_RESTORATION_START
    && $prediction->{last_us_copyright_year} >= $prediction->{reference_year})
}

# Last year the work was/will be in copyright in country of publication.
# This is intended to be called only after #validate has weeded out bad inputs.
sub predict_last_source_copyright {
  my $self       = shift;
  my $prediction = shift;

  # Validate inputs and metadata for source copyright term prediction
  $self->validate_for_source($prediction);
  return if $prediction->{error};
  my $country = $self->{record}->country;
  my $predictor = $TERM_PREDICTORS->{$country};
  my $term = $predictor->(
    $prediction->{death_or_pub_date},
    $prediction->{is_pub},
    $prediction->{is_crown}
  );
  $prediction->{last_source_copyright_year} = $prediction->{death_or_pub_date} + $term;
  push @{$prediction->{desc}},
    "Last $country © $prediction->{last_source_copyright_year} ($prediction->{death_or_pub_date} + $term-year term)";
}

sub australia_term {
  my ($death_or_pub_date, undef, $is_crown) = @_;

  return COMMONWEALTH_CROWN_COPYRIGHT_TERM if $is_crown;
  return 50 if $death_or_pub_date < 1955;
  return COMMONWEALTH_STANDARD_TERM;
}

sub canada_term {
  my ($death_or_pub_date, $is_pub, $is_crown) = @_;

  return COMMONWEALTH_CROWN_COPYRIGHT_TERM if $is_crown;
  return 50 if $death_or_pub_date < 1972;
  return $is_pub ? CANADA_CORPORATE_TERM : COMMONWEALTH_STANDARD_TERM;
}

sub united_kingdom_term {
  my ($death_or_pub_date, undef, $is_crown) = @_;

  return ($is_crown) ? COMMONWEALTH_CROWN_COPYRIGHT_TERM : COMMONWEALTH_STANDARD_TERM;
}

# Validate user input and country of publication for #predict_last_source_copyright
# Sets $prediction->{error} and adds to $prediction->{desc} in case of error.
sub validate_for_source {
  my $self       = shift;
  my $prediction = shift;

  # Validate info entered by reviewer.
  if ($prediction->{death_or_pub_date} !~ m/$VALID_DEATH_OR_PUB_DATE/) {
    push @{$prediction->{desc}},
      "unsupported date format '$prediction->{death_or_pub_date}'";
    $prediction->{error} = 1;
  }
  # Sanity-check the country, in case we get a volume that has drifted out of scope 
  my $country = $self->{record}->country;
  my $predictor = $TERM_PREDICTORS->{$country};
  unless (defined $predictor) {
    push @{$prediction->{desc}},
      "unknown copyright term for source country $country";
    $prediction->{error} = 1;
  }
}

# Verify that we can reason about the year of publication.
# We currently don't support date ranges at all.
# If we collect actual pub dates, we can sanity check that
# and then use it in place of the info in the catalog record 008.
sub validate_for_rights {
  my $self       = shift;
  my $prediction = shift;

  if (!defined $prediction->{pub_year}) {
    push @{$prediction->{desc}}, "undefined pub year";
    $prediction->{error} = 1;
    return;
  }
  if ($prediction->{pub_year} !~ m/$VALID_PUB_DATE/) {
    push @{$prediction->{desc}},
      "unsupported pub date format '$prediction->{pub_year}'";
    $prediction->{error} = 1;
  }
}

1;
