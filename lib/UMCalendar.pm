package UMCalendar;

use strict;
use Date::Calc qw(:all);
use Date::Calendar;
use Date::Calendar::Profiles;
use vars qw( @ISA @EXPORT @EXPORT_OK $UMCal );

$UMCal = {
  "New Year's Day"      => \&Date::Calendar::Profiles::US_New_Year,
  "Memorial Day"        => "5/Mon/May",
  "Independence Day"    => \&Date::Calendar::Profiles::US_Independence,
  "Labor Day"           => "1/Mon/Sep",
  "Thanksgiving Day"    => "4/Thu/Nov",
  "Thanksgiving Fri"    => "4/Fri/Nov",
  "Christmas Day"       => \&Date::Calendar::Profiles::US_Christmas,
  "Season 1"            => \&Season1,
  "Season 2"            => \&Season2,
  "Season 3"            => \&Season3,
  "Season 4"            => \&Season4
};

sub Season1
{
  my ($year, $label) = @_;
  return Date::Calendar::Profiles::Next_Monday_or_Tuesday(Date::Calendar::Profiles::US_Christmas($year));
}

sub Season2
{
  my ($year, $label) = @_;
  return Date::Calendar::Profiles::Next_Monday_or_Tuesday(Add_Delta_Days(Season1($year), 1));
}

sub Season3
{
  my ($year, $label) = @_;
  return Date::Calendar::Profiles::Next_Monday_or_Tuesday(Add_Delta_Days(Season2($year), 1));
}

sub Season4
{
  my ($year, $label) = @_;
  return Date::Calendar::Profiles::Next_Monday_or_Tuesday(Add_Delta_Days(Season3($year), 1));
}

1;
