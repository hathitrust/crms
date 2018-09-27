package Project_mdpcorrections;

use strict;
use warnings;

sub new
{
  my ($class, %args) = @_;
  my $self = bless {}, $class;
  $self->{'crms'} = $args{'crms'};
  $self->{'id'}   = $args{'id'};
  $self->{'name'} = $args{'name'};
  return $self;
}

# ========== CANDIDACY ========== #
# Returns undef for failure, or hashref with two fields:
# status in {'yes', 'no', 'filter'}
# msg potentially empty explanation.
sub EvaluateCandidacy
{
  my $self   = shift;
  my $id     = shift;
  my $record = shift;
  my $attr   = shift;
  my $reason = shift;

  return {'status' => 'no', 'msg' => 'mdp corrections project does not take candidates'};
}

# ========== REVIEW ========== #
sub ReviewPartials
{
  return ['top', 'bibdata',
          #'authorities',
          'HTView', 'copyrightForm', 'expertDetails'];
}

1;
