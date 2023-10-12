use strict;
use warnings;
use utf8;

package CRMS::OpResult;

# A class to hold result code and human-readable message returned by the likes of
# CRMS::AddItemToCandidates and CRMS::AddItemToQueueOrSetItemActive

use constant {
  OK      => 0,
  ERROR   => 1,
  WARNING => 2
};

sub new {
  my ($class, %args) = @_;
  my $self = bless {}, $class;
  $self->{messages} = [];
  return $self;
}

# Add an informational message to the result.
sub message {
  my $self = shift;
  my $msg  = shift;

  push @{$self->{messages}}, {status => OK, message => $msg};
  return $self;
}

# Add an error message to the result.
sub error {
  my $self = shift;
  my $msg  = shift;

  push @{$self->{messages}}, {status => ERROR, message => $msg};
  return $self;
}

# Add a warning message to the result.
sub warning {
  my $self = shift;
  my $msg  = shift;

  push @{$self->{messages}}, {status => WARNING, message => $msg};
  return $self;
}

sub messages {
  my $self = shift;

  return $self->select_status(OK);
}

sub errors {
  my $self = shift;

  return $self->select_status(ERROR);
}

sub warnings {
  my $self = shift;

  return $self->select_status(WARNING);
}

sub level {
  my $self = shift;

  return ERROR if scalar @{$self->errors};
  return WARNING if scalar @{$self->warnings};
  return OK;
}

# Add the contents of a CRMS::OpResult to this one
sub append {
  my $self = shift;
  my $res  = shift;

  foreach my $msg (@{$res->{messages}}) {
    push @{$self->{messages}}, $msg;
  }
  return $self;
}
  

# Return string with errors, warning, then messages each on a line.
sub to_string {
  my $self = shift;
  my %args = @_;

  my $str = '';
  if (scalar @{$self->errors}) {
    $str .= join('; ', @{$self->errors}) . "\n";
  }
  if (scalar @{$self->warnings}) {
    $str .= join('; ', @{$self->warnings}) . "\n";
  }
  if (scalar @{$self->messages}) {
    $str .= join('; ', @{$self->messages});
  }
  return $str;
}

sub select_status {
  my $self   = shift;
  my $status = shift;

  my @map = map { ($_->{status} == $status) ? $_->{message} : (); } @{$self->{messages}};
  return \@map;
}

1;

