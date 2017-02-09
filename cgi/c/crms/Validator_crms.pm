package Validator;

use strict;
use warnings;
use vars qw(@ISA @EXPORT @EXPORT_OK);
our @EXPORT = qw(ValidateSubmission);

# Returns an error message, or an empty string if no error.
sub ValidateSubmission
{
  my $self = shift;
  my ($id, $user, $attr, $reason, $note, $category, $renNum, $renDate, $oneoff) = @_;
  my $errorMsg = '';

  my $noteError = 0;
  my $hasren = ($renNum && $renDate);
  my $date = $self->GetPubDate($id);
  ## und/nfi
  if ($attr == 5 && $reason == 8 &&
      (!$category ||
       (!$note && 1 == $self->SimpleSqlGet('SELECT need_note FROM categories WHERE name=?', $category))))
  {
    $errorMsg .= 'und/nfi must include note category and note text.';
    $noteError = 1;
  }
  ## ic/ren requires a nonexpired renewal if 1963 or earlier
  if ($attr == 2 && $reason == 7)
  {
    if ($hasren)
    {
      if ($date > 1963)
      {
        $errorMsg .= 'Renewal no longer required for works published after 1963. ';
      }
      else
      {
        $renDate =~ s,.*[A-Za-z](.*),$1,;
        $renDate = '19' . $renDate;
        if ($renDate < 1950)
        {
          $errorMsg .= "Renewal has expired; volume is pd. Date entered is $renDate. ";
        }
      }
    }
    else
    {
      $errorMsg .= 'ic/ren must include renewal id and renewal date. ';
    }
  }
  ## pd/ren should not have a ren number or date, and is not allowed for post-1963 works.
  if ($attr == 1 && $reason == 7)
  {
    if ($date > 1963)
    {
      $errorMsg .= 'Renewal no longer required for works published after 1963. ';
    }
    elsif ($hasren)
    {
      $errorMsg .= 'pd/ren should not include renewal info. ';
    }
  }
  ## pd/ncn requires a ren number in most cases
  ## For superadmins, ren info is optional for 23-63 and disallowed for 64-77
  ## For admins, ren info is optional only if Note and category 'Expert Note' for 23-63 and disallowed for 64-77
  ## For non-admins, ren info is required.
  ## For the State gov doc project this is no longer enforced, plus
  ## ncn implies failure to follow formalities, so the legal justification
  ## for these checks is not clear.
  if ($attr == 1 && $reason == 2)
  {
    #if ($self->IsUserSuperAdmin($user))
    #{
    #  $errorMsg .= 'Renewal no longer required for works published after 1963. ' if $date > 1963 && $hasren;
    #  #$errorMsg .= 'pd/ncn must include renewal id and renewal date. ' if $date <= 1963 && !$hasren;
    #}
    #elsif ($self->IsUserAdmin($user))
    if ($self->IsUserAdmin($user))
    {
      $errorMsg .= 'Renewal no longer required for works published after 1963. ' if $date > 1963 && $hasren;
      #if ($date <= 1963 && (!$self->TolerantCompare($category, 'Expert Note')) && !$hasren)
      #{
      #  $errorMsg .= 'pd/ncn must include either renewal id and renewal date, or note category "Expert Note". ';
      #}
    }
    #else
    #{
    #  $errorMsg .= 'pd/ncn must include renewal id and renewal date. ' unless $hasren;
    #}
  }
  ## pd/cdpp must not have a ren number
  if ($attr == 1 && $reason == 9 && ($renNum || $renDate))
  {
    $errorMsg .= 'pd/cdpp should not include renewal info. ';
  }
  if ($attr == 1 && $reason == 9 && (!$note || !$category))
  {
    $errorMsg .= 'pd/cdpp must include note category and note text. ';
    $noteError = 1;
  }
  ## ic/cdpp requires a ren number
  if ($attr == 2 && $reason == 9 && ($renNum || $renDate))
  {
    $errorMsg .= 'ic/cdpp should not include renewal info. ';
  }
  if ($attr == 2 && $reason == 9 && (!$note || !$category))
  {
    $errorMsg .= 'ic/cdpp must include note category and note text. ';
    $noteError = 1;
  }
  ## pd/add can only be submitted by an admin and requires note and category
  if ($attr == 1 && $reason == 14)
  {
    if (!$self->IsUserAdmin($user))
    {
      $errorMsg .= 'pd/add requires admin privileges.';
    }
    elsif ($renNum || $renDate)
    {
      $errorMsg .= 'pd/add should not include renewal info. ';
    }
    if (!$note || !$category)
    {
      $errorMsg .= 'pd/add must include note category and note text. ';
      $noteError = 1;
    }
    elsif ($category ne 'Expert Note' && $category ne 'Foreign Pub' && $category ne 'Misc')
    {
      $errorMsg .= 'pd/add requires note category "Expert Note", "Foreign Pub" or "Misc". ';
    }
  }
  ## pd/exp can only be submitted by an admin and requires note and category
  if ($attr == 1 && $reason == 15)
  {
    if (!$self->IsUserAdmin($user))
    {
      $errorMsg .= 'pd/exp requires admin privileges.';
    }
    elsif ($renNum || $renDate)
    {
      $errorMsg .= 'pd/exp should not include renewal info. ';
    }
    if (!$note || !$category)
    {
      $errorMsg .= 'pd/exp must include note category and note text. ';
      $noteError = 1;
    }
    elsif ($category ne 'Expert Note' && $category ne 'Foreign Pub' && $category ne 'Misc')
    {
      $errorMsg .= 'pd/exp requires note category "Expert Note", "Foreign Pub" or "Misc". ';
    }
  }
  ## pdus/cdpp must not have a ren number
  if ($attr == 9 && $reason == 9)
  {
    if ($renNum || $renDate)
    {
      $errorMsg .= 'pdus/cdpp should not include renewal info. ';
    }
  }
  ## und/ren must have Note Category Inserts/No Renewal
  if ($attr == 5 && $reason == 7)
  {
    if ($category ne 'Inserts/No Renewal')
    {
      $errorMsg .= 'und/ren must have note category Inserts/No Renewal. ';
    }
  }
  ## and vice versa
  if ($category eq 'Inserts/No Renewal')
  {
    if ($attr != 5 || $reason != 7)
    {
      $errorMsg .= 'Inserts/No Renewal must have rights code und/ren. ';
    }
  }
  if ($noteError == 0)
  {
    if ($category && !$note)
    {
      if ($self->SimpleSqlGet('SELECT need_note FROM categories WHERE name=?', $category))
      {
        $errorMsg .= 'must include a note if there is a category. ';
      }
    }
    elsif ($note && !$category)
    {
      $errorMsg .= 'must include a category if there is a note. ';
    }
  }
  return $errorMsg;
}

sub CalcStatus
{
  my $self = shift;
  my $id   = shift;
  my $stat = shift; # FIXME: should this be pushed up into caller?

  my %return;
  my $status = 0;
  my $sql = 'SELECT user,attr,reason,renNum,renDate,hold FROM reviews WHERE id=?';
  my $ref = $self->SelectAll($sql, $id);
  my ($user, $attr, $reason, $renNum, $renDate, $hold) = @{$ref->[0]};
  $sql = 'SELECT user,attr,reason,renNum,renDate,hold FROM reviews WHERE id=? AND user!=?';
  $ref = $self->SelectAll($sql, $id, $user);
  my ($other_user, $other_attr, $other_reason, $other_renNum, $other_renDate, $other_hold) = @{$ref->[0]};
  if ($hold)
  {
    $return{'hold'} = $user;
  }
  if ($other_hold)
  {
    $return{'hold'} = $other_user;
  }
  elsif ($attr == $other_attr)
  {
    # If both reviewers are non-advanced mark as provisional match
    if ((!$self->IsUserAdvanced($user)) && (!$self->IsUserAdvanced($other_user)))
    {
       $status = 3;
    }
    else #Mark as 4 or 8 - two that agree
    {
      if ($reason != $other_reason)
      {
        $status = 8;
        $return{'attr'} = $attr;
        $return{'reason'} = 13;
        $return{'category'} = 'Attr Match';
      }
      elsif ($attr == 2 && $reason == 7 && $other_reason == 7 && ($renNum ne $other_renNum || $renDate ne $other_renDate))
      {
        $status = 8;
        $return{'attr'} = $attr;
        $return{'reason'} = $reason;
        $return{'category'} = 'Attr Match';
        $return{'note'} = sprintf 'Nonmatching renewals: %s (%s) vs %s (%s)', $renNum, $renDate, $other_renNum, $other_renDate;
      }
      else
      {
        $status = 4;
      }
    }
  }
  # Do auto for ic vs und
  elsif (($attr == 2 && $other_attr == 5) || ($attr == 5 && $other_attr == 2))
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
  my $sql = 'SELECT user,attr,reason,renNum,renDate FROM reviews WHERE id=? AND expert IS NULL';
  my $ref = $self->SelectAll($sql, $id);
  if (scalar @{$ref} > 1)
  {
    my $row = @{$ref}[0];
    my $user    = $row->[0];
    my $attr    = $row->[1];
    my $reason  = $row->[2];
    my $renNum  = $row->[3];
    my $renDate = $row->[4];
    $row = @{$ref}[1];
    my $other_user    = $row->[0];
    my $other_attr    = $row->[1];
    my $other_reason  = $row->[2];
    my $other_renNum  = $row->[3];
    my $other_renDate = $row->[4];
    if ($attr == $other_attr)
    {
      # If both reviewers are non-advanced mark as provisional match
      if ((!$self->IsUserAdvanced($user)) && (!$self->IsUserAdvanced($other_user)))
      {
        $pstatus = 3;
      }
      else #Mark as 4 or 8 - two that agree
      {
        $pstatus = 4;
        if ($reason != $other_reason)
        {
          $pstatus = 8;
        }
        elsif ($attr == 2 && $reason == 7 && $other_reason == 7 && ($renNum ne $other_renNum || $renDate ne $other_renDate))
        {
          $pstatus = 8;
        }
      }
    }
    # Do auto for ic vs und
    elsif (($attr == 2 && $other_attr == 5) || ($attr == 5 && $other_attr == 2))
    {
      # If both reviewers are non-advanced mark as provisional match
      if ((!$self->IsUserAdvanced($user)) && (!$self->IsUserAdvanced($other_user)))
      {
        $pstatus = 3;
      }
      else #Mark as 8 - two that sort of agree
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
