package Utilities;

use strict;
use warnings;

use Data::Dumper;
use Date::Calendar;
use DateTime;
use DateTime::Format::Strptime;
use DateTime::TimeZone;
use POSIX;
use Time::Piece;
use Time::Seconds;

use App::I18n;

my $DEFAULT_TIME_ZONE_NAME = 'America/Detroit';
my $DEFAULT_LOCALE = 'en';
my $UTILITIES_SINGLETON = undef;

sub new {
  return $UTILITIES_SINGLETON if defined $UTILITIES_SINGLETON;

  my ($class, %args) = @_;
  my $self = bless {}, $class;
  # Maybe time zone and default locale should go in a config
  $self->{tz} = DateTime::TimeZone->new(name => $DEFAULT_TIME_ZONE_NAME);
  $self->{locale} = $DEFAULT_LOCALE;
  $UTILITIES_SINGLETON = $self;
  return $self;
}

sub SetLocale {
  my $self = shift;
  my $locale = shift || $DEFAULT_LOCALE;

  $self->{locale} = $locale;
}

##### ===== DATABASE UTILITIES ===== #####
sub StringifySql {
  my $self = shift;
  my $sql  = shift;

  return $sql . ' (' . (join ',', map {(defined $_)? $_:'<undef>'} @_). ')';
}

# Returns a parenthesized comma separated list of n question marks.
sub WildcardList {
  my $self = shift;
  my $n    = shift;

  return '()' if $n < 1;
  return '(' . ('?,' x ($n-1)) . '?)';
}

##### ===== DATE AND TIME UTILITIES ===== #####
# Current year
sub Year {
  return POSIX::strftime "%Y", localtime;
}

# Current date in database format YYYY-MM-DD
sub Today {
  return POSIX::strftime "%F", localtime;
}

# Day before today or the supplied date in database format YYYY-MM-DD
sub Yesterday {
  my $self = shift;
  my $date = shift || $self->Today();

  my $t = Time::Piece->strptime($date, "%Y-%m-%d");
  $t -= Time::Seconds::ONE_DAY;
  return $t->strftime('%F');
}

# Current time in database format YYYY-MM-DD HH:MM:SS
sub Now {
  #return POSIX::strftime "%F %H:%M:%S", localtime;
  return POSIX::strftime "%F %T", localtime;
}

sub FormatDate {
  my $self   = shift;
  my $date   = shift || $self->Today();

  my $pattern = (length $date > 10) ? '%Y-%m-%d %T' : '%Y-%m-%d';
  my $locale = DateTime::Locale->load($self->{locale});
  my $dts = DateTime::Format::Strptime->new(pattern => $pattern, locale => $locale,
    time_zone => $self->{tz}, on_error => 'croak');
  my $dt = $dts->parse_datetime($date);
  return '' unless defined $dt;
  return $dt->format_cldr($locale->date_format_long);
}

sub FormatTime {
  my $self = shift;
  my $date = shift || $self->Now();

  my $pattern = '%Y-%m-%d %H:%M:%S';
  my $locale = DateTime::Locale->load($self->{locale});
  my $dts = DateTime::Format::Strptime->new(pattern => $pattern, locale => $locale,
    time_zone => $self->{tz}, on_error => 'croak');
  my $dt = $dts->parse_datetime($date);
  return $dt->format_cldr($locale->datetime_format_long);
}

# Convert a yearmonth-type string, e.g. '2009-08' to English: 'August 2009'
# Pass 1 as a second parameter to leave it long, otherwise truncates to 3-char abbreviation
sub FormatYearMonth {
  my $self = shift;
  my $ym   = shift;
  my $long = shift;

  my $dts = DateTime::Format::Strptime->new(pattern => '%Y-%m-%d',
    time_zone => $self->{tz}, on_error => 'croak');
  my $locale = DateTime::Locale->load($self->{locale});
  my $dt = $dts->parse_datetime($ym . '-01');
  $dt->set_locale($locale);
  return $dt->format_cldr($long ? $locale->format_for('yMMMM') : $locale->format_for('yMMM'));
}

sub IsWorkingDay {
  my $self = shift;
  my $time = shift || $self->Today();
  use UMCalendar;

  my $cal = Date::Calendar->new($UMCalendar::UMCal);
  my @parts = split '-', substr($time, 0, 10);
  return ($cal->is_full($parts[0], $parts[1], $parts[2]))? 0:1;
}

# Difference between time1 and time2 in days.
# FIXME: use Date::Time::subtract_datetime instead of Time::Piece
sub Timediff {
  my $self = shift;
  my $time1 = shift;
  my $time2 = shift || $self->Now();

  my $t1 = Time::Piece->strptime($time1, "%Y-%m-%d %H:%M:%S");
  my $t2 = Time::Piece->strptime($time2, "%Y-%m-%d %H:%M:%S");
  my $delta = $t1 - $t2;
  return $delta->days;
}

##### ===== TEXT UTILITIES ===== #####
sub Commify {
  my $self = shift;
  my $n    = shift;

  my $n2 = reverse $n;
  $n2 =~ s<(\d\d\d)(?=\d)(?!\d*\.)><$1,>g;
  # Don't just try to "return reverse $n2" as a shortcut. reverse() is weird.
  $n = reverse $n2;
  return $n;
}

sub Pluralize {
  my $self   = shift;
  my $n      = shift;
  my $word   = shift;
  my $plural = shift;

  Carp::confess("non-numeric n") unless $n =~ m/\d+/;
  return $word if $n == 1;
  return (defined $plural)? $plural : $word . 's';
}

# Remove trailing zeroes and point-zeroes from a floating point format.
sub StripDecimal {
  my $self = shift;
  my $dec  = shift;

  $dec =~ s/(\.[1-9]+)0+/$1/g;
  $dec =~ s/\.0*$//;
  return $dec;
}

# Shortcut to App::I18n for views
sub Translate {
  my $self = shift;
  my $key  = shift;

  return App::I18n::Translate($key, undef, @_);
}

##### ===== HTML UTILITIES ===== #####
sub EscapeHTML {
  my $self = shift;

  #my $hex = uc unpack 'H*', pack 'n*', unpack 'W*', shift;
  #return $hex;
  use HTML::Escape;
  return HTML::Escape::escape_html(shift);
}

return 1;
