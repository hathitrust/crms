package Project_frontmatter;

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

  return {'status' => 'no', 'msg' => 'frontmatter project does not take candidates'};
}

# ========== REVIEW ========== #
sub ReviewPartials
{
  return ['top', 'bibdata', 'frontmatter', 'expertDetails'];
}

sub SubmitUserReview
{
  my $self = shift;
  my $id   = shift;
  my $user = shift;
  my $cgi  = shift;

  my $crms = $self->{'crms'};
  my $data;
  eval {
    my $json = JSON::XS->new;
    $data = $json->decode($cgi->param('data'));
  };
  return $@ if $@;
  my $hold = 0;
  foreach my $datum (@{$data})
  {
    unless (defined $datum->[0] && length $datum->[0] &&
            defined $datum->[1] && length $datum->[1])
    {
      $hold = 1;
      last;
    }
  }
  my $params = {'data' => $cgi->param('data'),
                'note' => Encode::decode('UTF-8', $cgi->param('note')),
                'start' => $cgi->param('start'), 'hold' => $hold};
  return $crms->SubmitReview($id, $user, $params);
}

1;
