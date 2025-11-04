package CRMS::NewYear;

# A utility package containing logic that relates to the new year Public Domain Day
# rollover of rights.

use strict;
use warnings;
use utf8;

use Data::Dumper;

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

1;
