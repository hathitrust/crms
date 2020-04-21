package PublicationDate;
use parent 'Project';

use strict;
use warnings;
use utf8;

sub new
{
  my $class = shift;
  return $class->SUPER::new(@_);
}

#my %TEST_HTIDS = (
#    'coo.31924000029250' => 'Australia',
#    'bc.ark:/13960/t02z7k303' => 'Canada',
#    'bc.ark:/13960/t0bw4939s' => 'UK');

#sub tests
#{
#  my $self = shift;
#
#  my @tests = keys %TEST_HTIDS;
#  return \@tests;
#}

# ========== CANDIDACY ========== #
# Use default superclass behavior -- project does not take candidates for the moment.


# ========== REVIEW ========== #
sub ReviewPartials
{
  return ['top', 'bibdata', 'authorities',
          'HTView', 'pubDateForm', 'expertDetails'];
}

# Show the country of publication in the bibdata partial.
sub ShowCountry
{
  return 1;
}

# Show the date of publication in the bibdata partial.
sub ShowPubDate
{
  return 0;
}

sub ValidateSubmission
{
  my $self = shift;
  my $cgi  = shift;

  my @errs;
  my $rights = $cgi->param('rights');
  return 'You must select a rights/reason combination' unless $rights;
  my ($attr, $reason) = $self->{'crms'}->TranslateAttrReasonFromCode($rights);
  return 'Unknown rights combination' unless defined $attr and defined $reason;
  my $date = $cgi->param('date') || '';
  my $note = $cgi->param('note');
  my $country = $cgi->param('country') || '';
  my $countries = Countries::GetCountries();
  my $category = $cgi->param('category');
  $date =~ s/\s+//g if $date;
  if ($attr ne 'und')
  {
    if (!length $date)
    {
      push @errs, 'Actual Publication Date is required';
    }
    elsif ($date !~ m/^\d{4}(-\d{4})?$/)
    {
      push @errs, 'Actual Publication Date must be a date or a date range (DDDD or DDDD-DDDD)';
    }
    if (!$cgi->param('c_spec'))
    {
      if (!length $country)
      {
        push @errs, 'Country of Publication is required';
      }
    }
  }
  if (length $country && !$countries->{$country})
  {
    push @errs, "Country of Publication ($country) not recognized – please check MARC country codes";
  }
  if ($attr eq 'und' && $reason eq 'nfi' &&
      (!$category ||
       (!$note && 1 == $self->{'crms'}->SimpleSqlGet('SELECT need_note FROM categories WHERE name=?', $category))))
  {
    push @errs, 'und/nfi must include note category and note text';
  }
  if ($category && !$note)
  {
    if ($self->{'crms'}->SimpleSqlGet('SELECT need_note FROM categories WHERE name=?', $category))
    {
      push @errs, 'must include a note if there is a category';
    }
  }
  elsif ($note && !$category)
  {
    push @errs, 'must include a category if there is a note';
  }
  return join ', ', @errs;
}

# Extract Project-specific data from the CGI into a struct
# that will be encoded as JSON string in the reviewdata table.
sub ExtractReviewData
{
  my $self = shift;
  my $cgi  = shift;

  my $date = $cgi->param('date');
  my $country = $cgi->param('country');
  my $data;
  if (defined $date || defined $country)
  {
    $data = {};
    $data->{'date'} = $date if defined $date and length $date;
    $data->{'country'} = $country if defined $country and length $country;
  }
  return $data;
}

# Return a dictionary ref with the following keys:
# id: the reviewdata id
# format: HTML-formatted data for inline display. May be blank.
# format_long: HTML-formatted data for tooltip display. May be blank.
# e.g., {"date":"1881","pub":1,"src":"VIAF"}
sub FormatReviewData
{
  my $self = shift;
  my $id   = shift;
  my $json = shift;

  my $jsonxs = JSON::XS->new->utf8->canonical(1)->pretty(0);
  my $data = $jsonxs->decode($json);
  my @fmts;
  push @fmts, Countries::TranslateCountry($data->{'country'}) if $data->{'country'};
  push @fmts, $data->{'date'} if $data->{'date'};
  my $fmt = (scalar @fmts)? join(', ', @fmts) : undef;
  return {'id' => $id, 'format' => $fmt, 'format_long' => ''};
}

1;
