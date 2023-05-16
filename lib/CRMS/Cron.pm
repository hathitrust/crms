package CRMS::Cron;

# Routines for handling cron and cron_recipients tables.
# This class is mainly intended to be used from within
# cron scripts located in bin/
use strict;
use warnings;
use utf8;

use File::Basename;

use CRMS::DB;

my $DEFAULT_EMAIL_DOMAIN = 'umich.edu';
my $DEFAULT_EMAIL_SUFFIX = '@' . $DEFAULT_EMAIL_DOMAIN;

sub new {
  my ($class, %args) = @_;
  my $self = bless {}, $class;
  # FIXME: once we have a standalone DB module this can go away.
  #my $crms = $args{crms};
  #die "CRMS::Cron module needs CRMS instance." unless defined $crms;
  #$self->{crms} = $crms;
  $self->{db} = CRMS::DB->new;
  $self->{script_name} = File::Basename::basename($0, '.pl');
  return $self;
}

# Add default e-mail suffix to bare name.
sub expand_email {
  my $self  = shift;
  my $email = shift;

  $email .= $DEFAULT_EMAIL_SUFFIX unless $email =~ m/@/;
  return $email;
}

# Input: array of e-mail recipients passed on the command line with -m flag.
# Output: the same array, or the recipients in crms.cron_recipients if none.
# All recipients are postprocessed to add @umich.edu if needed.
sub recipients {
  my $self  = shift;
  my @mails = @_;

  if (scalar @mails == 0) {
    my $sql = 'SELECT id FROM cron WHERE script=?';
    my $cron_id = $self->{db}->one($sql, $self->script_name);
    if (defined $cron_id) {
      $sql = 'SELECT email FROM cron_recipients WHERE cron_id=?';
      my $ref = $self->{db}->all($sql, $cron_id);
      push(@mails, $_->[0]) for @$ref;
    }
  }
  @mails = map { $self->expand_email($_); } @mails;
  return \@mails;
}

# Basename of the currently-running script.
# Used for looking up cron.script column
sub script_name {
  my $self = shift;

  return $self->{script_name};
}

1;
