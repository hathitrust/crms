package Project_frontmatter;

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

sub ReviewPage
{
  return 'frontmatter';
}


sub ReviewPartials
{
  return ['Partial_reviewTop.tt', 'Partial_bibdata.tt',
          'Partial_frontmatter.tt', 'Partial_expertDetails.tt'];
}


sub SubmitUserReview
{
  my $self = shift;
  my $id   = shift;
  my $user = shift;
  my $cgi  = shift;

  my $crms = $self->{'crms'};
  #$crms->Note('SubmitUserReview for frontmatter');
  my $params = {'data' => $cgi->param('data'),
                'note' => Encode::decode('UTF-8', $cgi->param('note')),
                'start' => $cgi->param('start')};
  return $crms->SubmitReview($id, $user, $params);
  
}

1;
