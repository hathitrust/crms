package CRMS::PublicationDate;

# An object that encapsulates the date-related parts of the 008 field,
# in particular 06 dateType, 07-10 date1, and 11-14 date2,
# as well as any year string that can be extracted from enumcron.

use strict;
use warnings;
use utf8;

use Data::Dumper;

my $MULTIPLE_DATE_TYPES = {
  'c' => 1,
  'd' => 1,
  'i' => 1,
  'k' => 1,
  'm' => 1,
  'q' => 1,
  'u' => 1
};

# This is currently not used but is staying because it's a useful reference.
my $DATE_TYPE_TO_DESCRIPTION = {
  'b' => 'No dates given; B.C. date involved',
  'c' => 'Continuing resource currently published',
  'd' => 'Continuing resource ceased publication',
  'e' => 'Detailed date',
  'i' => 'Inclusive dates of collection',
  'k' => 'Range of years of bulk of collection',
  'm' => 'Multiple dates',
  'n' => 'Dates unknown',
  'p' => 'Date of distribution/release/issue and production/recording session when different',
  'q' => 'Questionable date',
  'r' => 'Reprint/reissue date and original date',
  's' => 'Single known date/probable date',
  't' => 'Publication date and copyright date',
  'u' => 'Continuing resource status unknown',
  '|' => 'No attempt to code'
};

# Examples:
# CRMS::PublicationDate->new(date_type => 'm', date_1 => '1923', date_2 => '1963',
# enumcron_date => '1933');
# or
# CRMS::PublicationDate->new(field_008 => '850423s1940       a          000 0 eng d',
# enumcron_date => '1940');
#
# Field 008 takes precedence over individual in that it will overwrite values specified
# individually.
#
# enumcron_date (if provided) should be the output of Metadata::get_volume_date,
# not the whole enumcron. At some point the enumcron date extraction may move into this
# module, but not while there is not-yet-deprecated code in Metadata.pm using it.
sub new {
  my ($class, %args) = @_;
  my $self = bless {}, $class;
  $self->{date_type} = $args{date_type};
  $self->{orig_date_1} = $args{date_1};
  $self->{orig_date_2} = $args{date_2};
  $self->{enumcron_date} = $args{enumcron_date} || '';
  if ($args{field_008}) {
    $self->{date_type} = substr($args{field_008}, 6, 1);
    $self->{orig_date_1} = substr($args{field_008}, 7, 4);
    $self->{orig_date_2} = substr($args{field_008}, 11, 4);
  }
  $self->{date_1} = clean_date($self->{orig_date_1});
  $self->{date_2} = clean_date($self->{orig_date_2});
  return $self;
}

# Filter a 008 date1 or date2 according to a strict standard:
# it must consist only of digits and 'u'.
# We make no attempt to "fix" characters outside this set.
# '0000' is also considered an invalid date.
# Returns undef given an underspecified date.
sub clean_date {
  my $date = shift;

  return if $date !~ m/^[0-9u]+$/;
  return if $date eq '0000';
  return $date;
}

# Round a date with 'u' placeholders up to 9.
# If $range interprets 'uuuu' as '9999' (for date ranges)
# Otherwise interprets as undef.
sub round_up {
  my $date  = shift;
  my $range = shift;

  return unless defined $date;
  return if $date eq 'uuuu' && !$range;
  $date =~ s/u/9/g;
  return $date;
}

# Round a date with 'u' placeholders down to 0.
sub round_down {
  my $date = shift;

  return $date unless defined $date;
  $date =~ s/u/0/g;
  return $date;
}

# ============== PUBLIC INSTANCE METHODS ==============

# Human-readable summary of the inputs.
# This is close to the bare metal, in that we are displaying the non-sanitized
# orig_date_1 and orig_date_2,
sub to_s {
  my $self = shift;

  return "[$self->{date_type} $self->{orig_date_1} $self->{orig_date_2}]{$self->{enumcron_date}}";
}

# Another human-readable version.
# Returns '' for no date, a single YYYY string for single date,
# and YYYY-YYYY for date range.
sub format {
  my $self = shift;

  my $dates = $self->extract_dates;
  return join "-", @$dates;
}

# For debugging purposes.
sub inspect {
  my $self = shift;

  return Dumper $self;
}

# Returns an arrayref:
#   Empty if no dates can be extracted.
#   One entry for single date.
#   [minimum possible date, maximum possible date] for multiple date types.
# Date extracted from enumcron takes precedence over 008.
# Multiple dates are guaranteed to be in sorted order.
sub extract_dates {
  my $self = shift;

  my @dates = ();
  return [$self->{enumcron_date}] if $self->{enumcron_date};
  if ($self->_is_multiple_date_type) {
    my $min = round_down($self->{date_1});
    my $max = round_up($self->{date_2}, 1);
    if (defined $min && defined $max) {
      push @dates, $min;
      push @dates, $max if $max ne $min;
    }
  } else {
    # Type b and n have no usable date info in the 008
    if ($self->{date_type} eq 'b' || $self->{date_type} eq 'n') {
      # do not add any dates
    }
    # Type p has earlier date (production) in date2, date1 is distribution date.
    # Type t has earlier date (copyright notice) in date2, date1 is publication date.
    elsif ($self->{date_type} eq 'p' || $self->{date_type} eq 't') {
      my $max = round_up($self->{date_2});
      push @dates, $max if defined $max;
    }
    # Reprints can have added copyrighted material so we use the most conservative estimate.
    elsif ($self->{date_type} eq 'r') {
      my $max = round_up($self->{date_2});
      push @dates, $max if defined $max;
    }
    # Everything else uses date1 or the range extractable from it.
    else {
      my @date_array = _to_a($self->{date_1});
      push @dates, @date_array;
    }
  }
  @dates = sort @dates;
  return \@dates;
}

# Distill the pub date info down to a single exact copyright date.
# Returns a single YYYY string if single date or there is extractable enumcron.
# Returns undef if no extractable date, or if date range with no enumcron.
sub exact_copyright_date {
  my $self = shift;

  my $dates = $self->extract_dates;
  return if scalar @$dates > 1;
  return $dates->[0];
}

# Distill the pub date info down to a single maximum copyright date
# that may not be guaranteed to be the exact date but may still be useful for
# calculating the safest copyright term.
#
# This is similar in spirit to what the bib rights algorithm does, erring
# on the side of caution.
#
# Returns a single YYYY string or undef.
sub maximum_copyright_date {
  my $self = shift;

  return $self->extract_dates->[-1];
}

# Does the publication date for the HTID (or the catalog record)
sub is_single_date {
  my $self = shift;

  return @{$self->extract_dates} == 1 ? 1 : 0;
}

# Returns 0 or 1
sub do_dates_overlap {
  my $self  = shift;
  my $start = shift;
  my $end   = shift;

  die "undefined start date passed to do_dates_overlap" unless defined $start;
  die "undefined end date passed to do_dates_overlap" unless defined $end;
  my $dates = $self->extract_dates;
  return 0 if scalar @$dates == 0;
  my $min = $dates->[0];
  $min = $dates->[1] if scalar @$dates > 1 and $dates->[1] < $dates->[0];
  my $max = $dates->[0];
  $max = $dates->[1] if scalar @$dates > 1 and $dates->[1] > $dates->[0];
  # The two cases where there is no overlap:
  #            start_____end
  # min___max
  # (max < start)
  #            start_____end
  #                           min___max
  # (min > end)
  return ($max < $start || $min > $end) ? 0 : 1;
}

# ============== PRIVATE INSTANCE METHOD ==============
sub _is_multiple_date_type {
  my $self = shift;

  return (defined $MULTIPLE_DATE_TYPES->{$self->{date_type}}) ? 1 : 0;
}

# ============== PRIVATE FUNCTION ==============
# Turn a single date into an array splitting it into min and max if necessary
sub _to_a {
  my $date = shift;

  return () unless defined $date;
  my $min = round_down($date);
  my $max = round_up($date);
  return unless defined $max;
  return ($date) if $min eq $max;
  return ($min, $max);
}

1;
