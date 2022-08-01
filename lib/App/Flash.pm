package App::Flash;

use strict;
use warnings;


my $FLASH_KEYS = ['alert', 'warning', 'notice']; # In orer displayed
my $DEFAULT_FLASH_KEY = 'notice';

sub new {
  my ($class, %args) = @_;
  my $self = bless {}, $class;
  $self->{keys} = {};
  foreach my $key ($FLASH_KEYS) {
    $self->{keys}->{$key} = [];
  }
  return $self;
}

sub keys {
  my $self = shift;

  return $FLASH_KEYS;
}

sub get {
  my $self = shift;
  my $key  = shift || $DEFAULT_FLASH_KEY;

  return $self->{keys}->{$key};
}

sub add {
  my $self = shift;
  my $key  = shift || $DEFAULT_FLASH_KEY;
  my $msg  = shift || '[empty message]';

  push @{$self->{keys}->{$key}}, $msg;
}

return 1;
