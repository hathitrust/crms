package CRMS::NewYear;

# A utility package containing logic that relates to the new year Public Domain Day
# rollover of rights.

use strict;
use warnings;
use utf8;

use Data::Dumper;
use List::Util qw();

sub new {
  my $class = shift;

  my $self = { @_ };
  bless($self, $class);
  return $self;
}

# Are the passed-in current rights "attribute" and "reason" names in scope for
# PDD rollover? This excludes pd and CC items, because there's nothing more to be done.
# It also excludes */{con, del, man, pvt, supp} items, because CRMS can't override them
# and there is no point in reporting them.
sub are_rights_in_scope {
  my $self      = shift;
  my $attribute = shift;
  my $reason    = shift;

  if (
    $attribute eq 'pd' ||
    $attribute =~ m/^cc/ ||
    $reason eq 'con' ||
    $reason eq 'del' ||
    $reason eq 'man' ||
    $reason eq 'pvt' ||
    $reason eq 'supp'
  ) {
    return;
  }
  return 1;
}

# Given a set of rights predictions that might reasonably be made based on reviewer data,
# in the form of a hashref of { "pd/add" => 1, "ic/add" => 1, ... } and the current attribute
# name, calculate the most restrictive attribute among the predictions, provided that attribute
# would be a "step up" from the current one (in terms of permissiveness).
# For example, if there is a "pdus" and an "icus" prediction, only consider "icus".
# And then only return it as the new rights if it would make the current rights less restrictive.
#
# Scenario where no prediction is allowed:
# |-----------|
# | 3   pd    |  <----- PREDICTION (cannot use, it is not the most restrictive)
# |-----------|
# | 2  pdus   |  <----- CURRENT RIGHTS
# |-----------|
# | 1  icus   |  <----- PREDICTION (cannot use, would be a downgrade)
# |-----------|
# | 0   ic    |
# |-----------|
#
# Scenario where we do want a new prediction:
# |-----------|
# | 3   pd    |  <----- PREDICTION (cannot use, it is not the most restrictive)
# |-----------|
# | 2  pdus   |  <----- PREDICTION (USE THIS -- it is the most restrictive prediction, and better than icus)
# |-----------|
# | 1  icus   |  <----- CURRENT RIGHTS
# |-----------|
# | 0   ic    |
# |-----------|
#
# In a nutshell: choose minimum prediction and return it if it is greater than current rights
sub choose_rights_prediction {
  my $self        = shift;
  my $attribute   = shift; # current rights attr string
  my $predictions = shift;

  # This map allows us to grade the current rights and the predictions into 0-3 as above.
  my $attr_values = {'pd' => 3, 'pdus' => 2, 'icus' => 1, 'ic' => 0};

  # Get the value for current rights.
  # It should not be terribly unusual to find current rights outside the pd/pdus/icus/ic contionuum
  # although we will filter many of these out with `are_rights_in_scope` above.
  # However, that does allow through rights like und/nfi (at least historically, we no longer export
  # these to the rights DB by default).
  # We can bail out if we get something outside the expected main four attributes.
  my $current_value = $attr_values->{$attribute};
  return unless defined $current_value;

  # Expand predictions into array of { prediction => "attr/reason", value => value }
  my @values = map {
    my ($a, $r) = split('/', $_);
    { prediction => $_, value => $attr_values->{$a} };
  } keys %$predictions;

  # Extract out the "minimum" prediction, conflating undefs (unknown prediction) with ic,
  # neither of which we can return as a viable choice.
  my $min = List::Util::reduce {
    ($a->{value} || 0) < ($b->{value} || 0) ? $a : $b;
  } @values;

  # Bail out if there were no predictions, or if the best we can do is ic or "anything else"
  if (!$min || !$min->{value}) {
    return;
  }

  # Compare the values. If the predicted is greater than current, return that.
  # This will be the benefit of the new year rollover in terms of less restrictive rights.
  if ($min->{value} > $current_value) {
    return $min->{prediction};
  }
  return;
}

1;
