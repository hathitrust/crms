package Project;

use strict;
use warnings;

sub new {
  my ($class, %args) = @_;
  my $self = bless {}, $class;
  $self->{$_} = $args{$_} for keys %args;
  my $id = $args{id};
  die 'No ID passed to project' unless $args{id};
  my $sql = 'SELECT * FROM projects WHERE id=?';
  my $ref = CRMS::DB->new(instance => $args{instance})->dbh->selectall_hashref($sql, 'id', undef, $id);
  $self->{$_} = $ref->{$id}->{$_} for keys %{$ref->{$id}};
  return $self;
}

sub id
{
  my $self = shift;

  return $self->{'id'};
}

sub name
{
  my $self = shift;

  return $self->{'name'};
}

sub color
{
  my $self = shift;

  return $self->{'color'};
}

sub queue_size
{
  my $self = shift;

  return $self->{'queue_size'};
}

sub autoinherit
{
  my $self = shift;

  return $self->{'autoinherit'};
}

sub group_volumes
{
  my $self = shift;

  return $self->{'group_volumes'};
}

sub single_review
{
  my $self = shift;

  return $self->{'single_review'};
}

sub primary_authority
{
  my $self = shift;

  return $self->{'primary_authority'};
}

sub secondary_authority
{
  my $self = shift;

  return $self->{'secondary_authority'};
}

# Return a list of HTIDs that should be claimed by this project.
sub tests
{
  my $self = shift;

  return [];
}

sub EvaluateCandidacy
{
  my $self   = shift;
  my $id     = shift;
  my $record = shift;
  my $attr   = shift;
  my $reason = shift;

  return {'status' => 'no', 'default' => 'yes',
          'msg' => $self->{'name'}. ' project does not take candidates'};
}

# ========== REVIEW INTERFACE ========== #
# Called by CRMS::GetNextItemForReview to order volumes.
# Return undef for no additional order (the default), or
# a column name in bibdata (b.*) or the queue (q.*).
# Example: 'b.author DESC'
sub PresentationOrder
{
  my $self = shift;

  return;
}

sub ReviewPartials
{
  return ['top', 'bibdata'];
}

# Show the country of publication in the bibdata partial.
sub ShowCountry
{
  return 0;
}

# Show the publication/copyright date in the bibdata partial.
sub ShowPubDate
{
  return 1;
}

# Check Experts' "do not invalidate" checkbox on page load
sub SwissByDefault
{
  return 0;
}

# ========== REVIEW SUBMISSION ========== #
# Extract Project-specific data from the CGI into a struct
# that will be encoded as JSON string in the reviewdata table.
sub ExtractReviewData
{
  my $self = shift;
  my $cgi  = shift;

  return;
}

# Return a hashref with the following keys:
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

# Check the CGI parameters and return undef if there is not issue, or an
# error message if there is an issue to be displayed in the Review page.
sub ValidateSubmission
{
  my $self = shift;
  my $cgi  = shift;

  my $rights = $cgi->param('rights');
  return 'You must select a rights/reason combination' unless $rights;
  my ($attr, $reason) = $self->{'crms'}->TranslateAttrReasonFromCode($rights);
  my @errs;
  my $renNum = $cgi->param('renNum');
  my $renDate = $cgi->param('renDate');
  my $note = $cgi->param('note');
  my $category = $cgi->param('category');
  my $hasren = ($renNum && $renDate);
  ## und/nfi
  if ($attr eq 'und' && $reason eq 'nfi' && (!$category || !$note))
  {
    push @errs, 'und/nfi must include note category and note text';
  }
  ## ic/ren requires a nonexpired renewal if 1963 or earlier
  if ($attr eq 'ic' && $reason eq 'ren')
  {
    if ($hasren)
    {
      # Blow away everything but the trailing 2 year digits.
      # If submitted while data is still being fetched, this will leave a bogus empty year.
      $renDate =~ s,.*[A-Za-z](.*),$1,;
      $renDate = '19'. $renDate;
      if ($renDate < 1950 && $renDate != 19)
      {
        push @errs, "renewal ($renDate) has expired: volume is pd";
      }
    }
    else
    {
      push @errs, 'ic/ren must include renewal id and renewal date';
    }
  }
  ## pd/ren should not have a ren number or date, and is not allowed for post-1963 works.
  if ($attr eq 'pd' && $reason eq 'ren')
  {
    if ($hasren)
    {
      push @errs, 'pd/ren should not include renewal info';
    }
  }
  ## pd*/cdpp must not have a ren number
  if (($attr eq 'pd' || $attr eq 'pdus') && $reason eq 'cdpp' && ($renNum || $renDate))
  {
    push @errs, "$attr/$reason must not include renewal info";
  }
  if ($attr eq 'pd' && $reason eq 'cdpp' && (!$note || !$category))
  {
    push @errs, 'pd/cdpp must include note category and note text';
  }
  ## ic/cdpp requires a ren number
  if ($attr eq 'ic' && $reason eq 'cdpp' && ($renNum || $renDate))
  {
    push @errs, 'ic/cdpp should not include renewal info';
  }
  if ($attr eq 'ic' && $reason eq 'cdpp' && (!$note || !$category))
  {
    push @errs, 'ic/cdpp must include note category and note text';
  }
  ## und/ren must have Note Category Inserts/No Renewal
  if ($attr eq 'und' && $reason eq 'ren')
  {
    if ($category ne 'Inserts/No Renewal')
    {
      push @errs, 'und/ren must have note category Inserts/No Renewal';
    }
  }
  ## and vice versa
  if ($category eq 'Inserts/No Renewal')
  {
    if ($attr ne 'und' || $reason ne 'ren')
    {
      push @errs, 'Inserts/No Renewal must have rights code und/ren. ';
    }
  }
  if ($category && !$note)
  {
    if ($self->{'crms'}->SimpleSqlGet('SELECT need_note FROM categories WHERE name=?', $category))
    {
      push @errs, 'must include a note if there is a category. ';
    }
  }
  elsif ($note && !$category)
  {
    push @errs, 'must include a category if there is a note. ';
  }
  return join ', ', @errs;
}

# ========== INHERITANCE ========== #
sub InheritanceAllowed
{
  return 1;
}

# ========== MISCELLANEOUS ========== #
# Duration of review at which review becomes an outlier and we
# assume the reviewer just walked away from the computer.
# This is always just a stupid heuristic.
sub OutlierSeconds
{
  return 300;
}

1;
