package Utilities;

use strict;
use warnings;

use Date::Calendar;
use POSIX;
use Time::Piece;
use Time::Seconds;

my $UTILITIES_SINGLETON = undef;

sub new {
  return $UTILITIES_SINGLETON if defined $UTILITIES_SINGLETON;

  my ($class, %args) = @_;
  my $self = bless {}, $class;
  $UTILITIES_SINGLETON = $self;
  Time::Piece->use_locale();
  return $self;
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
  my $self = shift;
  my $date = shift || $self->Today();

  # Avoid "Garbage at end of string in strptime" noise by using correct pattern.
  my $pattern = (length $date > 10) ? '%Y-%m-%d %H:%M:%S' : '%Y-%m-%d';
  my $t = Time::Piece->strptime($date, $pattern);
  return '' unless defined $t;
  my $fmt = $t->strftime('%A, %B %e %Y');
  $fmt =~ s/\s\s+/ /g;
  return $fmt;
}

sub FormatTime {
  my $self = shift;
  my $date = shift || $self->Now();

  my $t = Time::Piece->strptime($date, "%Y-%m-%d %H:%M:%S");
  my $fmt = $t->strftime('%A, %B %e %Y at %l:%M %p');
  $fmt =~ s/\s\s+/ /g;
  return $fmt;
}

# Convert a yearmonth-type string, e.g. '2009-08' to English: 'August 2009'
# Pass 1 as a second parameter to leave it long, otherwise truncates to 3-char abbreviation
sub FormatYearMonth {
  my $self = shift;
  my $ym   = shift;
  my $long = shift;

  my $t = Time::Piece->strptime($ym . '-01', "%Y-%m-%d");
  return $t->strftime($long ? '%B %Y' : '%b %Y');
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

  return $word if $n == 1;
  return (defined $plural)? $plural : $word . 's';
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
