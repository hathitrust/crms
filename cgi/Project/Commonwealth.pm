package Commonwealth;
use parent 'Project';

use strict;
use warnings;

use Utilities;

sub new
{
  my $class = shift;
  return $class->SUPER::new(@_);
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

  my @errs = ();
  # Check current rights
  push @errs, "current rights $attr/$reason" if ($attr ne 'ic' and $attr ne 'pdus') or $reason ne 'bib';
  # Check well-defined record dates
  # FIXME: this is duplicated in Core, could add fullySpecifiedCopyrightDate method in Metadata.pm
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
  push @errs, "foreign pub ($where)" if $where ne 'United Kingdom' and
                                        $where ne 'Australia' and
                                        $where ne 'Canada';
  if (defined $pub && $pub =~ m/\d\d\d\d/)
  {
    my $min = $self->GetCutoffYear($where, 'minYear');
    my $max = $self->GetCutoffYear($where, 'maxYear');
    push @errs, "$pub not in range $min-$max for $where" if ($pub < $min || $pub > $max);
  }
  push @errs, 'non-BK format' unless $record->isFormatBK($id);
  return {'status' => 'no', 'msg' => join '; ', @errs} if scalar @errs;
  my $src;
  my $lang = $record->language;
  $src = 'language' if 'eng' ne $lang;
  $src = 'translation' if $record->isTranslation;
  my $date = $self->{crms}->FormatPubDate($id, $record);
  $src = 'date range' if $date =~ m/^\d+-(\d+)?$/;
  return {'status' => 'filter', 'msg' => $src} if defined $src;
  return {'status' => 'yes', 'msg' => ''};
}

sub GetCutoffYear
{
  my $self    = shift;
  my $country = shift;
  my $name    = shift;

  my $year = Utilities->new->Year();
  # Generic cutoff for add to queue page.
  if (! defined $country)
  {
    return $year-140 if $name eq 'minYear';
    return $year-51;
  }
  if ($country eq 'United Kingdom')
  {
    return $year-140 if $name eq 'minYear';
    return $year-71;
  }
  elsif ($country eq 'Australia')
  {
    return $year-120 if $name eq 'minYear';
    # FIXME: will this ever change?
    return 1954;
  }
  #elsif ($country eq 'Spain')
  #{
  #  return $year-140 if $name eq 'minYear';
  #  return 1935;
  #}
  return $year-120 if $name eq 'minYear';
  return $year-51;
}


# ========== REVIEW ========== #
sub ReviewPartials
{
  return ['top', 'bibdata', 'authorities',
          'HTView', 'ADDForm', 'ADDCalculator',
          'expertDetails'];
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
  elsif (($reason eq 'add' || $reason eq 'exp') && !$date)
  {
    push @errs, "*/$reason must include a numeric year";
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
  my $fmt = sprintf '%s <strong>%s</strong> %s', ($data->{'pub'})? 'Pub':'ADD', $data->{'date'};
  return {'id' => $id, 'format' => $fmt, 'format_long' => ''};
}

1;
