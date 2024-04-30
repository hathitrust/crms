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
# This is a static load project, so we only accept volumes that are already
# in candidates.
sub EvaluateCandidacy
{
  my $self   = shift;
  my $id     = shift;
  my $record = shift;
  my $attr   = shift;
  my $reason = shift;

  my $status = 'no';
  my $msg = $self->{'name'}. ' project does not take candidates';
  my $sql = 'SELECT COUNT(*) FROM candidates WHERE id=?';
  if ($self->{'crms'}->SimpleSqlGet($sql, $id) > 0)
  {
    if ($attr eq 'und' && $reason eq 'bib')
    {
      $status = 'yes';
      $msg = 'Volume is part of existing static load';
    }
    else
    {
      $msg = "Rights have changed from und/bib to $attr/$reason";
    }
  }
  return {'status' => $status, 'msg' => $msg};
}


# ========== REVIEW ========== #
sub ReviewPartials
{
  return ['top', 'bibdata', 'authorities',
          'pubDateForm', 'expertDetails'];
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

# Return array of label -> date range string
sub Dates
{
  my $self = shift;

  my $year = $self->{crms}->GetTheYear;
  return [['pd', sprintf("1000-%s", $year - 125 - 1)],
          ['pdus', sprintf('%s-%s', $year - 125, $year - 95 - 1)],
          ['ic', sprintf('%s-%s', $year - 95, $year)]];
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
  my $approximate = $cgi->param('approximate');
  my $data;
  if (defined $date || defined $approximate)
  {
    $data = {};
    $data->{'date'} = $date if defined $date and length $date;
    $data->{'approximate'} = $approximate if defined $approximate and length $approximate;
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
  if ($data->{'date'})
  {
    my $date = $data->{'date'};
    $date = '&#x2245;'. $date if $data->{'approximate'};
    push @fmts, $date;
  }
  my $fmt = (scalar @fmts)? join(', ', @fmts) : undef;
  return {'id' => $id, 'format' => $fmt, 'format_long' => ''};
}

1;
