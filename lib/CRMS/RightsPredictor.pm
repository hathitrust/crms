package CRMS::RightsPredictor;

# Predict copyright term for Commonwealth countries based on
# author death date or publication date.
# Used in Commonwealth project UI for populating and updating UI with
# rights based on metadata and researcher-provided data.
# Also used for New Year rights rollover.

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
# Sanity check on reviewer-supplied date as well as 008 pub date
my $VALID_PUB_DATE = qr/^\d{1,4}$/;

my $TERM_PREDICTORS = {
  &AUSTRALIA => \&_australia_term,
  &CANADA => \&_canada_term,
  &UNITED_KINGDOM => \&_united_kingdom_term
};

# use CRMS::RightsPredictor;
# use Metadata;
#
# my $record = Metadata->new('id' => 'mdp.001');
# # Initialize for prediction based on anonymous author or corporate work,
# # not crown copyright, with an actual pub date of 1920 (where the catalog record
# # might have, for example, 1918-1930 on a multipart work)
# my $predictor = CRMS::RightsPredictor->new(record => $record, effective_date => '1933',
# is_corporate => 1, is_crown => 0, pub_date => '1920');
#
# See cgi/predictRights for end-to-end example.
#
# Can be called with:
#  Author death date (effective_date)
#  Author death date and actual pub date (effective_date and pub_date)
#  OR
#  Pub date alone (effective_date and is_corporate=1)

# This is not a particularly good initializer (the semantics of effective_date vs
# pub_date could be de-obfuscated into -- for example -- author_death_date and
# pub_date, and the is_corporate flag could perhaps be eliminated. However,
# for historical reasons going back to the CRMS-World project, the author/publication
# dates used to calculated copyright term have been collected in the same HTML form field
# and stored under the same crms.reviewdata JSON key.
# To avoid writing glue in multiple places we leave the initializer here messy and
# try to solve any inconsistencies internally.

# Constructor parameters:
# effective_date  Reviewer-supplied author death date or pub date from Commonwealth UI,
#                 and for PDD rollover the corresponding data from the reviewdata table.
# is_corporate    (0/1) effective_date is publication by non-human or anonymous author.
# is_crown        (0/1) Crown copyright applies (implies is_corporate).
# pub_date        Actual publication/copyright date from UI if date range, otherwise
#                 the value is supplied by the effective_date (if is_corporate) or catalog record.
# reference_year  The "current" year, only used for testing.
#
# In addition to the constructor parameters, the following attributes may be consulted:
# description        Arrayref of human-readable logic
# error_description  Arrayref of human-readable errors
# NOTE: use the description() API for convenience
# error              (0/1) Has an error point been reached?
# attr               "pd" or "ic" type rights attribute
# reason             "add" or "exp" type rights reason
# rights             "pd/add" or "ic/exp" type rights string
#
# One new instance should be used per prediction. This object is not intended for reuse.
sub new {
  my $class = shift;

  my $self = bless {}, $class;
  my %defaults = ( reference_year => POSIX::strftime("%Y", localtime) );
  my %args = (%defaults, @_);
  # Assigns arguments and default values to %args, actual named
  # args will override keys in defaults where they match
  while (my ($attr, $value) = each %args ) {
    $self->{$attr} = $value;
  }
  Carp::confess "record => Metadata object is a required parameter" unless $self->{record};
  if (!$self->{effective_date}) {
    $self->{effective_date} = '';
  }
  # If not supplied, populate pub_date from corporate date or catalog
  if (!$self->{pub_date}) {
    if ($self->{is_corporate}) {
      $self->{pub_date} = $self->{effective_date};
    } else {
      $self->{pub_date} = $self->{record}->publication_date->exact_copyright_date;
    }
  }
  $self->{error_description} = [];
  $self->{description} = [];
  $self->{error} = 0;
  return $self;
}

# Return the human-readable description or the error description in case of error.
sub description {
  my $self = shift;

  my $description = ($self->{error} == 0) ? $self->{description} : $self->{error_description};
  return ucfirst join(', ', @$description);
}

# Simple API mainly for testing and reports. Currently not used in the GUI or scripts.
# Returns the last year the volume was or will be in copyright in its country of publication.
# Returns undef in case of error and sets $self->{error} = 1
sub last_source_copyright {
  my $self = shift;

  $self->_predict_last_source_copyright;
  return $self->{last_source_copyright_year}
}

# The main entrypoint for Commonwealth UI predictions as well as the PDD rollover script for
# Commonwealth and Crown Copyright projects.
# Returns a human readable (e.g., "pd/add") rights string.
# Returns undef in case of error and sets $self->{error} = 1
sub rights {
  my $self = shift;

  $self->_predict_last_source_copyright;
  return if $self->{error};

  $self->_validate_for_rights;
  return if $self->{error};

  $self->{last_us_copyright_year} = $self->{pub_date} + US_COPYRIGHT_TERM;
  if ($self->{last_source_copyright_year} < $self->{reference_year}) {
    push @{$self->{description}},
      "source © expired ($self->{last_source_copyright_year} < $self->{reference_year})";
    $self->_predict_rights_with_source_copyright_expired;
  }
  else {
    push @{$self->{description}},
      "source © in force ($self->{last_source_copyright_year} >= $self->{reference_year})";
    $self->_predict_rights_with_source_copyright_in_force;
  }
  $self->{rights} = "$self->{attr}/$self->{reason}";
  return $self->{rights};
}

# ============== PRIVATE INSTANCE METHODS ==============

# Determine overall rights given copyright in (non-US) country of publication has expired.
sub _predict_rights_with_source_copyright_expired {
  my $self = shift;

  if ($self->_is_subject_to_gatt_restoration) {
    $self->{attr} = 'icus';
    $self->{reason} = 'gatt';
    push @{$self->{description}},
      "$self->{last_source_copyright_year} >= @{[ GATT_RESTORATION_START ]}" .
      " and US © in force ($self->{last_us_copyright_year} >= $self->{reference_year}) [GATT]";
  }
  else {
    $self->{attr} = 'pd';
    $self->{reason} = ($self->{is_corporate})? 'exp' : 'add';
    push @{$self->{description}},
      "$self->{last_source_copyright_year} < @{[ GATT_RESTORATION_START ]}" .
      " or US © expired ($self->{last_us_copyright_year} < $self->{reference_year}) [no GATT]";
  }
}

sub _predict_rights_with_source_copyright_in_force {
  my $self = shift;

  if ($self->{last_us_copyright_year} >= $self->{reference_year}) {
    $self->{attr} = 'ic';
    $self->{reason} = ($self->{is_corporate})? 'cdpp' : 'add';
    push @{$self->{description}},
      "US © in force ($self->{last_us_copyright_year} >= $self->{reference_year})";
  }
  else {
    $self->{attr} = 'pdus';
    # pdus/exp is unattested and appears to be impossible given that US
    # copyright term will always extend longer than the foreign term
    # when both are based on publication date.
    # uncoverable branch true
    $self->{reason} = ($self->{is_corporate})? 'exp' : 'add';
    push @{$self->{description}},
      "US © expired ($self->{last_us_copyright_year} < $self->{reference_year})";
  }
}

sub _is_subject_to_gatt_restoration {
  my $self = shift;

  ($self->{last_source_copyright_year} >= GATT_RESTORATION_START
    && $self->{last_us_copyright_year} >= $self->{reference_year})
}

# Last year the work was/will be in copyright in country of publication.
# This is intended to be called only after #validate has weeded out bad inputs.
sub _predict_last_source_copyright {
  my $self = shift;

  # Validate inputs and metadata for source copyright term prediction
  $self->_validate_for_source;
  return if $self->{error};
  my $country = $self->{record}->country;
  my $predictor = $TERM_PREDICTORS->{$country};
  my $effective_date = $self->{effective_date};
  my $term = $predictor->($effective_date, $self->{is_corporate}, $self->{is_crown});
  $self->{last_source_copyright_year} = $effective_date + $term;
  push @{$self->{description}},
    "last $country © $self->{last_source_copyright_year} ($effective_date + $term-year term)";
}

sub _australia_term {
  my ($effective_date, undef, $is_crown) = @_;

  return COMMONWEALTH_CROWN_COPYRIGHT_TERM if $is_crown;
  return 50 if $effective_date < 1955;
  return COMMONWEALTH_STANDARD_TERM;
}

sub _canada_term {
  my ($effective_date, $is_corporate, $is_crown) = @_;

  return COMMONWEALTH_CROWN_COPYRIGHT_TERM if $is_crown;
  return 50 if $effective_date < 1972;
  return $is_corporate ? CANADA_CORPORATE_TERM : COMMONWEALTH_STANDARD_TERM;
}

sub _united_kingdom_term {
  my ($effective_date, undef, $is_crown) = @_;

  return $is_crown ? COMMONWEALTH_CROWN_COPYRIGHT_TERM : COMMONWEALTH_STANDARD_TERM;
}

# Validate user input and country of publication for #predict_last_source_copyright
# Sets $self->{error} and adds to $self->{description} in case of error.
sub _validate_for_source {
  my $self = shift;

  # Validate info entered by reviewer.
  if ($self->{effective_date} !~ m/$VALID_DEATH_OR_PUB_DATE/) {
    $self->_add_error("unsupported date format '$self->{effective_date}'");
  }
  # Sanity-check the country, in case we get a volume that has drifted out of scope 
  my $country = $self->{record}->country;
  my $predictor = $TERM_PREDICTORS->{$country};
  unless (defined $predictor) {
    $self->_add_error("unknown copyright term for source country $country");
  }
}

# Verify that we can reason about the year of publication.
sub _validate_for_rights {
  my $self = shift;

  if (!defined $self->{pub_date}) {
    $self->_add_error("no pub date provided");
    return;
  }
  if ($self->{pub_date} !~ m/$VALID_PUB_DATE/) {
    $self->_add_error("unsupported pub date format '$self->{pub_date}'");
  }
}

sub _add_error {
  my $self = shift;
  my $err  = shift;

  push @{$self->{error_description}}, $err;
  $self->{error} = 1;
}

1;
