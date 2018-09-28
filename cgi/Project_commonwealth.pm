package Commonwealth;
use parent 'Project';

use strict;
use warnings;

sub new
{
  my $class = shift;
  return $class->SUPER::new(@_);
}

my %TEST_HTIDS = (
    'coo.31924000029250' => 'Australia',
    'bc.ark:/13960/t02z7k303' => 'Canada',
    'bc.ark:/13960/t0bw4939s' => 'UK');

sub tests
{
  my $self = shift;

  my @tests = keys %TEST_HTIDS;
  return \@tests;
}

sub test
{
  use Test::More;
  my $self = shift;

  my $crms = $self->{'crms'};
  foreach my $htid (keys %TEST_HTIDS)
  {
    my $res = $self->EvaluateCandidacy($htid, $crms->GetMetadata($htid), 'ic', 'bib');
    ok(defined $res, "Project::Commonwealth EvaluateCandidacy($htid) defined");
    isa_ok($res, 'HASH', "Project::Commonwealth EvaluateCandidacy($htid)");
    ok(defined $res->{'status'}, "Project::Commonwealth EvaluateCandidacy($htid) status defined");
    is($res->{'status'}, 'yes', "Project::Commonwealth EvaluateCandidacy($htid) YES");
  }
  return 1;
  return $self->SUPER::test();
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

  my $year = $self->{crms}->GetTheYear();
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

1;
