package Utilities;

use strict;
use warnings;

sub StringifySql
{
  my $sql = shift;

  return $sql . ' (' . (join ',', map {(defined $_)? $_:'<undef>'} @_). ')';
}

# TODO: this is only used in one place. Should be removed.
sub ClearArrays
{
  @{$_} = () for @_;
}

sub StackTrace
{
  my $max_depth = 30;
  my $i = 1;
  my $trace = "--- Begin stack trace ---\n";
  while ((my @call_details = (caller($i++))) && ($i<$max_depth))
  {
    $trace .= "$call_details[1] line $call_details[2] at $call_details[3]\n";
  }
  return $trace . "--- End stack trace ---\n";
}

return 1;
