package Core;
use parent 'Project';

use strict;
use warnings;

sub new
{
  my $class = shift;
  return $class->SUPER::new(@_);
}

# FIXME: can some of these checks be centralized and kicked off by
# querying which checks the module needs done?
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

  my @errs;
  # Check current rights
  push @errs, "current rights $attr/$reason" if $attr ne 'ic' or $reason ne 'bib';
  # Check well-defined record dates
  my $pub = $record->copyrightDate;
  if (!defined $pub || $pub !~ m/\d\d\d\d/)
  {
    my $leader = $record->GetControlfield('008');
    my $type = substr($leader, 6, 1);
    my $date1 = substr($leader, 7, 4);
    my $date2 = substr($leader, 11, 4);
    push @errs, "pub date not completely specified ($date1,$date2,'$type')";
  }
  else
  {
    # Check year range
    my $now = $self->{crms}->GetTheYear();
    my $min = $now - 95 + 1;
    my $max = 1963;
    push @errs, "pub date $pub not in range $min-$max" if $pub < $min or $pub > $max;
  }
  push @errs, 'gov doc' if $self->IsGovDoc($record);
  # Out of scope if published in a non-US country, or if Undetermined country
  # and foreign city or no US city.
  # I.e., explicitly undetermined place requires 1+ US and 0 foreign cities.
  my $where = $record->country;
  my $cities = $record->cities;
  if ($where =~ m/^Undetermined/i)
  {
    if (!scalar @{$cities->{'us'}} || scalar @{$cities->{'non-us'}})
    {
      push @errs, 'undetermined pub place';
    }
  }
  elsif ($where ne 'USA')
  {
    push @errs, "foreign pub ($where)";
  }
  push @errs, 'non-BK format' unless $record->isFormatBK($id, $record);
  #printf "Core candidacy: errors '%s'\n", join ', ', @errs;
  if (scalar @errs)
  {
    return {'status' => 'no', 'msg' => join '; ', @errs};
  }
  my $src;
  $src = 'gov' if $record->IsProbableGovDoc();
  my %langs = ('   ' => 1, '|||' => 1, 'emg' => 1,
               'eng' => 1, 'enm' => 1, 'mul' => 1,
               'new' => 1, 'und' => 1);
  $src = 'language' if !$langs{$record->language};
  $src = 'dissertation' if $record->isThesis;
  $src = 'translation' if $record->isTranslation;
  #$src = 'foreign' if $self->IsReallyForeignPub($record);
  return {'status' => 'filter', 'msg' => $src} if defined $src;
  return {'status' => 'yes', 'msg' => ''};
}

# 008:28 is 'f' byte.
sub IsGovDoc
{
  my $self   = shift;
  my $record = shift;

  my $is = undef;
  eval {
    my $leader = $record->GetControlfield('008');
    $is = (length $leader > 28 && substr($leader, 28, 1) eq 'f');
  };
  $self->{crms}->SetError($record->id . " failed in IsGovDoc(): $@") if $@;
  return $is;
}

# ========== REVIEW ========== #
sub ReviewPartials
{
  return ['top', 'bibdata', 'authorities',
          'HTView', 'copyrightForm', 'expertDetails'];
}

# Extract Project-specific data from the CGI into a struct
# that will be encoded as JSON string in the reviewdata table.
sub ExtractReviewData
{
  my $self = shift;
  my $cgi  = shift;

  my $renNum = $cgi->param('renNum');
  my $renDate = $cgi->param('renDate');
  my $data;
  if ($renNum || $renDate)
  {
    $data = {'renNum' => $renNum, 'renDate' => $renDate};
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

  my $jsonxs = JSON::XS->new->utf8->canonical(1)->pretty(0);
  my $data = $jsonxs->decode($json);
  my $fmt = sprintf '<strong>%s</strong> %s', $data->{'renNum'}, $data->{'renDate'};
  #my $cgi = new CGI;
  #my $long = $cgi->escapeHTML("<code>$json</code>");
  my $long = '';
  return {'id' => $id, 'format' => $fmt, 'format_long' => $long};
}

1;
