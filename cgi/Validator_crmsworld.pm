package Validator;

use strict;
use warnings;
use vars qw(@ISA @EXPORT @EXPORT_OK);
our @EXPORT = qw(ValidateSubmission CalcStatus CalcPendingStatus DoRightsMatch);

# Returns an error message, or an empty string if no error.
sub ValidateSubmission
{
  my $self = shift;
  my ($id, $user, $attr, $reason, $note, $category, $renNum, $renDate, $oneoff) = @_;
  my $errorMsg = '';
  my $noteError = 0;
  $attr = $self->TranslateAttr($attr);
  $reason = $self->TranslateReason($reason);
  $renDate =~ s/\s+//g if $renDate;
  my $pubDate = undef;
  my $pub2;
  if ($renNum)
  {
    $pubDate = $renDate;
  }
  else
  {
    $pubDate = $self->FormatPubDate($id);
    if ($pubDate =~ m/-/)
    {
      ($pubDate, $pub2) = split '-', $pubDate, 2;
    }
  }
  if ($attr eq 'und' && $reason eq 'nfi' &&
      (!$category ||
       (!$note && 1 == $self->SimpleSqlGet('SELECT need_note FROM categories WHERE name=?', $category))))
  {
    $errorMsg .= 'und/nfi must include note category and note text.';
    $noteError = 1;
  }
  if ($renDate && $renDate !~ m/^-?\d{1,4}$/)
  {
    $errorMsg .= 'The year must be only decimal digits. ';
  }
  elsif (($reason eq 'add' || $reason eq 'exp') && !defined $renDate)
  {
    $errorMsg .= "*/$reason must include a numeric year. ";
  }
  elsif ($pubDate < 1923 && $attr eq 'icus' && $reason eq 'gatt' &&
         (!$pub2 || $pub2 < 1923) &&
         !$self->IsUserExpert() && !$self->IsUserAdmin())
  {
    $errorMsg .= 'Volumes published prior to 1923 are not eligible for icus/gatt. ';
  }
  if ($noteError == 0)
  {
    if ($category && !$note)
    {
      if ($self->SimpleSqlGet('SELECT need_note FROM categories WHERE name=?', $category))
      {
        $errorMsg .= 'Must include a note if there is a category. ';
      }
    }
    elsif ($note && !$category)
    {
      $errorMsg .= 'Must include a category if there is a note. ';
    }
  }
  if (defined $category && length $category && $attr ne 'und')
  {
    my $need = $self->SimpleSqlGet('SELECT need_und FROM categories WHERE name=?', $category);
    if (defined $need && 1 == $need)
    {
      $errorMsg .= "Note category '$category' must be marked und/nfi. ";
    }
  }
  return $errorMsg;
}

sub CalcStatus
{
  my $self = shift;
  my $id   = shift;

  my %return;
  my $status = 0;
  my $sql = 'SELECT r.user,a.name,rs.name,r.renNum,r.renDate,r.hold'.
            ' FROM reviews r INNER JOIN attributes a ON r.attr=a.id'.
            ' INNER JOIN reasons rs ON r.reason=rs.id WHERE r.id=?';
  my $ref = $self->SelectAll($sql, $id);
  my ($user, $attr, $reason, $renNum, $renDate, $hold) = @{$ref->[0]};
  $sql = 'SELECT r.user,a.name,rs.name,r.renNum,r.renDate,r.hold'.
         ' FROM reviews r INNER JOIN attributes a ON r.attr=a.id'.
         ' INNER JOIN reasons rs ON r.reason=rs.id WHERE r.id=? AND r.user!=?';
  $ref = $self->SelectAll($sql, $id, $user);
  my ($other_user, $other_attr, $other_reason, $other_renNum, $other_renDate, $other_hold) = @{ $ref->[0] };
  $other_renNum = undef unless $other_renDate;
  if ($hold)
  {
    $return{'hold'} = $user;
  }
  elsif ($other_hold)
  {
    $return{'hold'} = $other_user;
  }
  # Match if attr/reasons match.
  if (DoRightsMatch($self, $attr, $other_attr, $reason, $other_reason))
  {
    $status = 4;
    # If both reviewers are non-advanced mark as provisional match.
    # Also, mark provisional if date info disagrees, unless und.
    if (((!$self->IsUserAdvanced($user)) && (!$self->IsUserAdvanced($other_user)))
        ||
        ((!$self->TolerantCompare($renNum, $other_renNum)
          ||
          !$self->TolerantCompare($renDate, $other_renDate))
         &&
         $attr ne 'und'))
    {
      $status = 3;
    }
    # Do auto for ic vs und
    elsif (($attr eq 'ic' && $other_attr eq 'und') || ($attr eq 'und' && $other_attr eq 'ic'))
    {
      # If both reviewers are non-advanced mark as provisional match
      if ((!$self->IsUserAdvanced($user)) && (!$self->IsUserAdvanced($other_user)))
      {
         $status = 3;
      }
      else #Mark as 8 - two that agree as und/crms
      {
        $status = 8;
        $return{'attr'} = 5;
        $return{'reason'} = 13;
        $return{'category'} = 'Attr Default';
      }
    }
  }
  else #Mark as 2 - two that disagree
  {
    $status = 2;
  }
  $return{'status'} = $status;
  return \%return;
}

sub CalcPendingStatus
{
  my $self = shift;
  my $id   = shift;

  my $n = $self->SimpleSqlGet('SELECT COUNT(*) FROM reviews WHERE id=?', $id);
  if ($n > 1)
  {
    my $data = CalcStatus($self, $id);
    return (defined $data)? $data->{'status'}:0;
  }
  return $n;
}

sub DoRightsMatch
{
  my $self    = shift;
  my $attr1   = shift;
  my $reason1 = shift;
  my $attr2   = shift;
  my $reason2 = shift;

  return ($attr1 eq $attr2);
}

1;
