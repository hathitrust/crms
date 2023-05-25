package CRMS::Country;

# Used mainly by Metadata.pm for looking up country names from 008 language codes
# Example usage:
# my $country = CRMS::Country->new;
# say $country->from_code('fr');
# > "France"
# say $country->from_code('miu', 1);
# > "USA (Michigan)"
#
# The from_name arrays can be useful for scoping queries against ht.hf.pub_place.
# But watch for two-character codes, for example:
# select htid,pub_place from hf where pub_place regexp 'iv.' and pub_place != 'iv';
# What you do depends on your tolerance for messy data.

use strict;
use warnings;
use utf8;

use YAML::XS;

use constant {
  COUNTRY_DATA_PATH => "$ENV{SDRROOT}/crms/data/country_data.yml"
};

my $SINGLETON_INSTANCE;

sub new {
  return $SINGLETON_INSTANCE if $SINGLETON_INSTANCE;
  my ($class, %args) = @_;
  my $self = bless {}, $class;
  $self->{country_data} = YAML::XS::LoadFile(COUNTRY_DATA_PATH);
  $SINGLETON_INSTANCE = $self;
  return $self;
}

sub country_data {
  my $self = shift;

  return $self->{country_data};
}

# Returns country name e.g. 'United Kingdom' from code e.g. 'wlk'
# If $long, returns 'United Kingdom (Wales)'.
# If input is 'xx' or not in table, returns 'Undetermined' with passed-in code.
# $country->from_code('blah') => 'Undetermined [blah]'
sub from_code {
  my $self = shift;
  my $code = shift;
  my $long = shift;

  $code = defined $code ? $code : 'undef';
  # $orig is the printable version we want to preprocess minimally
  my $orig = $code;
  $code =~ s/[^a-z]//gi;
  my $country = $self->{country_data}->{$code} || 'Undetermined';
  $country .= " [$orig]" if $country eq 'Undetermined';
  $country = $self->_truncate($country) unless $long;
  return $country;
}

# Returns a sorted arrayref of country codes based on truncated nane.
# If no such name, return empty arrayref.
sub from_name {
  my $self = shift;
  my $name = shift;

  my $codes = $self->_reverse_table->{$name} || [];
  return [ sort @$codes ];
}

sub _reverse_table {
  my $self = shift;

  if (!defined $self->{reverse_table}) {
    foreach my $code (keys %{$self->{country_data}}) {
      my $name = $self->from_code($code);
      $name = $self->_truncate($name);
      $self->{reverse_table}->{$name} = [] unless defined $self->{reverse_table}->{$name};
      push @{$self->{reverse_table}->{$name}}, $code;
    }
  }
  return $self->{reverse_table};
}

# Remove final parenthesized subentity
# wlk: United Kingdom (Wales) -> United Kingdom
# Does not remove internal parenthesized material e.g. xb: Cocos (Keeling) Islands
sub _truncate {
  my $self = shift;
  my $name = shift;

  $name =~ s/\s*\(.*?\)$//;
  return $name;
}

1;
