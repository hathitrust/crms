package Project_mdpcorrections;

use strict;
use warnings;

sub new
{
  my $class = shift;
  my $self = { crms => shift };
  return bless $self, $class;
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
  return ['top', 'bibdata',
          #'authorities',
          'HTView', 'copyrightForm', 'expertDetails'];
}

1;
