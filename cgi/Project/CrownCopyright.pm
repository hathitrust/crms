package CrownCopyright;
use parent 'Project';

use strict;
use warnings;

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

  my @errs = ();
  # Current rights pdus/*, ic/bib, or und/bib
  if ($attr ne 'pdus' && ($attr ne 'ic' || $reason ne 'bib') && ($attr ne 'und' || $reason ne 'bib'))
  {
    push @errs, "current rights $attr/$reason";
  }
  # Need fully-specified copyright date
  
  my $pub = $record->copyrightDate;
  if (!defined $pub || $pub !~ m/\d\d\d\d/)
  {
    my $leader = $record->GetControlfield('008');
    my $type = substr($leader, 6, 1);
    my $date1 = substr($leader, 7, 4);
    my $date2 = substr($leader, 11, 4);
    push @errs, "pub date not completely specified ($date1,$date2,'$type')";
  }
  my $where = $record->country;
  my $countries = {'Canada' => 1,
                   'United Kingdom' => 1,
                   'Australia' => 1};
  push @errs, "foreign pub ($where)" unless $countries->{$where};
  if (defined $pub && $pub =~ m/\d\d\d\d/)
  {
    my $min = 1880;
    my $max = $self->{'crms'}->GetTheYear() - 50;
    push @errs, "$pub not in range $min-$max" if ($pub < $min || $pub > $max);
  }
  my $leader = $record->GetControlfield('008');
  push @errs, 'not a crown document' if length $leader <= 28 || substr($leader, 28, 1) ne 'f';
  my $fmt = $record->fmt;
  push @errs, "disqualifying format $fmt" unless $fmt eq 'Book' or $fmt eq 'Serial';
  return {'status' => 'no', 'msg' => join '; ', @errs} if scalar @errs;
  my $src;
  my $lang = $record->language;
  $src = 'language' if 'eng' ne $lang;
  $src = 'translation' if $record->isTranslation;
  return {'status' => 'filter', 'msg' => $src} if defined $src;
  return {'status' => 'yes', 'msg' => ''};
}

# ========== REVIEW ========== #
sub PresentationOrder
{
  return 'b.author ASC';
}

sub ReviewPartials
{
  return ['top', 'bibdata', 'authorities',
          'HTView', 'crownCopyrightForm', 'expertDetails'];
}

# Show the country of publication in the bibdata partial.
sub ShowCountry
{
  return 1;
}

sub ValidateSubmission
{
  my $self = shift;
  my $cgi  = shift;

  my @errs;
  my ($attr, $reason) = $self->{'crms'}->TranslateAttrReasonFromCode($cgi->param('rights'));
  my $date = $cgi->param('date');
  my $pub = $cgi->param('pub');
  my $note = $cgi->param('note');
  my $category = $cgi->param('category');
  $date =~ s/\s+//g if $date;
  #my $actual = $cgi->param('actual');
  my ($pubDate, $pubDate2);
  $pubDate = $date if $pub;
  #$pubDate = $actual if $actual;
  if (!defined $pubDate)
  {
    $pubDate = $self->{'crms'}->FormatPubDate($cgi->param('htid'));
    if ($pubDate =~ m/-/)
    {
      ($pubDate, $pubDate2) = split '-', $pubDate, 2;
    }
  }
  if ($attr eq 'und' && $reason eq 'nfi' &&
      (!$category ||
       (!$note && 1 == $self->{'crms'}->SimpleSqlGet('SELECT need_note FROM categories WHERE name=?', $category))))
  {
    push @errs, 'und/nfi must include note category and note text';
  }
  if ($date && $date !~ m/^-?\d{1,4}$/)
  {
    push @errs, 'year must be only decimal digits';
  }
  elsif ($pubDate < 1923 && $attr eq 'icus' && $reason eq 'gatt' &&
         (!$pubDate2 || $pubDate2 < 1923))
  {
    push @errs, 'volumes published before 1923 are ineligible for icus/gatt';
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
  my $data;
  if ($date)
  {
    $data = {'date' => $date};
    $data->{'pub'} = 1 if $cgi->param('pub');
    $data->{'crown'} = 1 if $cgi->param('crown');
    $data->{'src'} = $cgi->param('src') if $cgi->param('src');
    $data->{'actual'} = $cgi->param('actual') if $cgi->param('actual');
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
  my $fmt = sprintf 'Pub <strong>%s</strong> %s', $data->{'date'};
  return {'id' => $id, 'format' => $fmt, 'format_long' => ''};
}

1;
