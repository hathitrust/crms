package Frontmatter;
use parent 'Project';

use strict;
use warnings;

sub new
{
  my $class = shift;
  return $class->SUPER::new(@_);
}

# ========== REVIEW ========== #
sub ReviewPartials
{
  return ['top', 'bibdata', 'frontmatter', 'expertDetails'];
}

# Extract Project-specific data from the CGI into a struct
# that will be encoded as JSON string in the reviewdata table.
# FIXME: how to signal an error? Use Note()?
sub ExtractReviewData
{
  my $self = shift;
  my $cgi  = shift;

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
  return $data;
}

# Return a dictionary ref with the following keys:
# id: the reviewdata id
# format: HTML-formatted data for inline display. May be blank.
# format_long: HTML-formatted data for tooltip display. May be blank.
sub FormatReviewData
{
  my $self = shift;
  my $id   = shift;
  my $json = shift;

  return {'id' => $id,
          'format' => '',
          'format_long' => "<code>$json</code>"};
}

sub ValidateSubmission
{
  my $self = shift;
  my $cgi  = shift;

  return undef;
}

my @TYPES = ('Factual', 'Creative', 'Mixed', "Don't Know");
my @CATEGORIES = ('Frontispiece', 'Title Page', 'Advertisement',
                  'Pub. Information', 'Dedication', 'Pref. Material',
                  'ToC', 'Text', 'Appendix', 'Index',
                  'N/A', 'Mixed');
sub Types
{
  return \@TYPES;
}

sub Categories
{
  return \@CATEGORIES;
}

1;
