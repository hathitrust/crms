package Frontmatter;
use parent 'Project';

use strict;
use warnings;

my $TYPES = [{id => 0, code => 'factual', name => 'Factual'},
             {id => 1, code => 'creative', name => 'Creative'},
             {id => 2, code => 'mixed', name => 'Mixed'},
             {id => 3, code => 'no_content', name => "No Content"}];
my $CATEGORIES = [{id => 0, code => 'image', name => 'Image'},
                  {id => 1, code => 'title', name => 'Title'},
                  {id => 2, code => 'ad', name => 'Advertisement'},
                  {id => 3, code => 'pub_info', name => 'Pub. Information'},
                  {id => 4, code => 'dedication', name => 'Dedication'},
                  {id => 5, code => 'pref_text', name => 'Prefatory Text'},
                  {id => 6, code => 'list', name => 'List of Content'},
                  {id => 7, code => 'main_text', name => 'Main Text'},
                  {id => 8, code => 'appendix', name => 'Appendix'},
                  {id => 9, code => 'cover', name => 'Cover'},
                  {id => 10, code => 'epigraph', name => 'Epigraph'},
                  {id => 11, code => 'poem', name => 'Poem'},
                  {id => 12, code => 'no_content', name => 'No Content'}];
my $TYPE_ID_NAME_MAP = { map {$_->{'id'} => $_->{'name'}} @{$TYPES} };
my $TYPE_ID_CODE_MAP = { map {$_->{'id'} => $_->{'code'}} @{$TYPES} };
my $TYPE_CODE_NAME_MAP = { map {$_->{'code'} => $_->{'name'}} @{$TYPES} };
my $CATEGORY_ID_NAME_MAP = { map {$_->{'id'} => $_->{'name'}} @{$CATEGORIES} };
my $CATEGORY_ID_CODE_MAP = { map {$_->{'id'} => $_->{'code'}} @{$CATEGORIES} };
my $CATEGORY_CODE_NAME_MAP = { map {$_->{'code'} => $_->{'name'}} @{$CATEGORIES} };


sub new
{
  my $class = shift;
  return $class->SUPER::new(@_);
}

# ========== REVIEW ========== #
sub ReviewPartials
{
  return ['top', 'bibdata_frontmatter', 'authorities', 'frontmatter'];
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
    my $jsonxs = JSON::XS->new->utf8;
    $data = $jsonxs->decode($cgi->param('data'));
  };
  $cgi->delete('note');
  if ($@)
  {
    $self->{'crms'}->SetError($@);
    return undef;
  }
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

  my $fmt = '';
  eval {
    my $jsonxs = JSON::XS->new;
    my $data = $jsonxs->decode($json);
    foreach my $page (@{$data})
    {
      $fmt .= sprintf "{%s, %s, '%s'}<br/>", $TYPE_CODE_NAME_MAP->{$page->[0]},
                      $CATEGORY_CODE_NAME_MAP->{$page->[1]}, $page->[2];
    }
  };
  #$fmt = $json;
  return {'id' => $id,
          'format' => '',
          'format_long' => "<code>$fmt</code>"};
}

sub ValidateSubmission
{
  my $self = shift;
  my $cgi  = shift;

  return undef;
}

sub Types
{
  return $TYPES;
}

sub Categories
{
  return $CATEGORIES;
}

1;
