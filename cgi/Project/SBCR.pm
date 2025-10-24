package SBCR;
use parent 'Project';

use strict;
use warnings;

sub new {
  my $class = shift;
  return $class->SUPER::new(@_);
}

# ========== REVIEW ========== #
# TODO
sub ValidateSubmission {
  my $self = shift;
  my $cgi  = shift;

  my $rights = $cgi->param('rights');
  return if $rights;
  return 'You must select a rights/reason combination';
}

# Extract Project-specific data from the CGI into a struct
# that will be encoded as JSON string in the reviewdata table.
sub ExtractReviewData {
  my $self = shift;
  my $cgi  = shift;

  my $renNum = $cgi->param('renNum') || '';
  my $renDate = $cgi->param('renDate') || '';
  my $actualPubDate = $cgi->param('actualPubDate') || '';
  my $data = {};
  $data->{'renNum'} = $renNum if $renNum;
  $data->{'renDate'} = $renDate if $renDate;
  $data->{'actualPubDate'} = $actualPubDate if $actualPubDate;
  return $data;
}

sub ReviewPartials {
  return ['top', 'bibdata_sbcr', 'authorities',
          'sbcr_form', 'expertDetails'];
}

1;
