package Validator;

use strict;
use warnings;
use vars qw( @ISA @EXPORT @EXPORT_OK );
our @EXPORT = qw(ValidateSubmission);

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
    $pubDate = $self->GetPubDate($id, 1);
    if ($pubDate =~ m/\-/)
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
         (!defined $pub2 || $pub2 < 1923) &&
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
  if (defined $category && $attr ne 'und')
  {
    #my $need = $self->SimpleSqlGet('SELECT COALESCE(need_und,0) FROM categories WHERE name=?', $category);
    my $need = $self->SimpleSqlGet('SELECT need_und FROM categories WHERE name=?', $category);
    if (!defined $need)
    {
      my $sql = 'INSERT INTO note (note) VALUES (?)';
      my $note = 'No need_und found for "' . $category . '"';
      $self->PrepareSubmitSql($sql, $note);
    }
    elsif (1 == $need)
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
  my $stat = shift;

  my %return;
  my $dbh = $self->GetDb();
  my $status = 0;
  my $sql = "SELECT user,attr,reason,renNum,renDate,hold,NOW() FROM reviews WHERE id='$id'";
  my $ref = $dbh->selectall_arrayref($sql);
  my ($user, $attr, $reason, $renNum, $renDate, $hold, $today) = @{ $ref->[0] };
  $renNum = undef unless $renDate;
  $sql = "SELECT user,attr,reason,renNum,renDate,hold FROM reviews WHERE id='$id' AND user!='$user'";
  $ref = $dbh->selectall_arrayref($sql);
  my ($other_user, $other_attr, $other_reason, $other_renNum, $other_renDate, $other_hold) = @{ $ref->[0] };
  $other_renNum = undef unless $other_renDate;
  $attr = $self->TranslateAttr($attr);
  $reason = $self->TranslateReason($reason);
  $other_attr = $self->TranslateAttr($other_attr);
  $other_reason = $self->TranslateReason($other_reason);
  if ($hold && ($today lt $hold || $stat ne 'normal'))
  {
    $return{'hold'} = $user;
  }
  elsif ($other_hold && ($today lt $other_hold || $stat ne 'normal'))
  {
    $return{'hold'} = $other_user;
  }
  # Match if attr/reasons match.
  elsif ($attr eq $other_attr && $reason eq $other_reason)
  {
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
    else #Mark as 4 - two that agree
    {
      $status = 4;
    }
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
  else #Mark as 2 - two that disagree
  {
    $status = 2;
  }
  $return{'status'} = $status;
  return \%return;
}

# FIXME: merge this into the above code
sub CalcPendingStatus
{
  my $self = shift;
  my $id   = shift;
  
  my $pstatus = 0;
  my $sql = "SELECT user,attr,reason,renNum,renDate FROM reviews WHERE id='$id' AND expert IS NULL";
  my $ref = $self->GetDb()->selectall_arrayref($sql);
  if (scalar @{$ref} > 1)
  {
    my ($user, $attr, $reason, $renNum, $renDate) = @{ $ref->[0] };
    my ($other_user, $other_attr, $other_reason, $other_renNum, $other_renDate) = @{ $ref->[1] };
    $attr = $self->TranslateAttr($attr);
    $reason = $self->TranslateReason($reason);
    $other_attr = $self->TranslateAttr($other_attr);
    $other_reason = $self->TranslateReason($other_reason);
    $renNum = undef unless $renDate;
    $other_renNum = undef unless $other_renDate;
    # Match if attr/reasons match; dates must match unless und/nfi.
    if ($attr eq $other_attr && $reason eq $other_reason &&
        (($self->TolerantCompare($renNum, $other_renNum) &&
          $self->TolerantCompare($renDate, $other_renDate))
         ||
         $attr eq 'und'))
    {
      # If both reviewers are non-advanced mark as provisional match
      if (!$self->IsUserAdvanced($user) && !$self->IsUserAdvanced($other_user))
      {
        $pstatus = 3;
      }
      else #Mark as 4 - two that agree
      {
        $pstatus = 4;
      }
    }
    # Do auto for ic vs und
    elsif (($attr eq 'ic' && $other_attr eq 'und') || ($attr eq 'und' && $other_attr eq 'ic'))
    {
      # If both reviewers are non-advanced mark as provisional match
      if ((!$self->IsUserAdvanced($user)) && (!$self->IsUserAdvanced($other_user)))
      {
        $pstatus = 3;
      }
      else #Mark as 8 - two that agree as und/crms
      {
        $pstatus = 8;
      }
    }
    else #Mark as 2 - two that disagree
    {
      $pstatus = 2;
    }
  }
  elsif (scalar @{$ref} == 1)
  {
    $pstatus = 1;
  }
  return $pstatus;
}

1;
