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
      if (0)#($date > 1963)
      {
        $errorMsg .= 'Renewal no longer required for works published after 1963. ';
      }
      else
      {
        # Blow away everything but the trailing 2 year digits.
        # If submitted while data is still being fetched, this will leave a bogus empty year.
        $renDate =~ s,.*[A-Za-z](.*),$1,;
        $renDate = '19' . $renDate;
        if ($renDate < 1950 && $renDate != 19)
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
    if (0)#($date > 1963)
    {
      $errorMsg .= 'Renewal no longer required for works published after 1963. ';
    }
    elsif ($hasren)
    {
      $errorMsg .= 'pd/ren should not include renewal info. ';
    }
  }
  ## pd/ncn requires a ren number in most cases
  ## For admins, ren info is optional only if Note and category 'Expert Note' for 23-63 and disallowed for 64-77
  ## For non-admins, ren info is required.
  ## For the State gov doc project this is no longer enforced, plus
  ## ncn implies failure to follow formalities, so the legal justification
  ## for these checks is not clear.
  if ($attr == 1 && $reason == 2)
  {
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

# Returns a data structure with the following fields:
# status: the status to set to queue item to
# hold: id of a user with a review on hold
# attr: the final rights attribute (status 8)
# reason: the final rights reason (status 8)
# category: the final determination category (status 8)
sub CalcStatus
{
  my $self = shift;
  my $id   = shift;

  my $return = {'status' => 0};
  my $sql = 'SELECT r.user,a.name,rs.name,r.hold,d.data'.
            ' FROM reviews r INNER JOIN attributes a ON r.attr=a.id'.
            ' INNER JOIN reasons rs ON r.reason=rs.id'.
            ' LEFT JOIN reviewdata d ON r.data=d.id'.
            ' WHERE r.id=? ORDER BY r.time ASC';
  my $ref = $self->SelectAll($sql, $id);
  my ($user, $attr, $reason, $hold, $data) = @{$ref->[0]};
  $sql = 'SELECT r.user,a.name,rs.name,r.hold,d.data'.
         ' FROM reviews r INNER JOIN attributes a ON r.attr=a.id'.
         ' INNER JOIN reasons rs ON r.reason=rs.id'.
         ' LEFT JOIN reviewdata d ON r.data=d.id'.
         ' WHERE r.id=? AND r.user!=? ORDER BY r.time ASC';
  $ref = $self->SelectAll($sql, $id, $user);
  return $return if 0 == scalar @{$ref};
  my ($user2, $attr2, $reason2, $hold2, $data2) = @{$ref->[0]};
  if ($hold)
  {
    $return->{'hold'} = $user;
  }
  if ($hold2)
  {
    $return->{'hold'} = $user2;
  }
  if (DoRightsMatch($self, $attr, $reason, $attr2, $reason2))
  {
    # If both reviewers are non-advanced mark as provisional match
    if ((!$self->IsUserAdvanced($user)) && (!$self->IsUserAdvanced($user2)))
    {
      $status = 3;
    }
    else # Mark as 4 or 8 - two that agree
    {
      $status = 4;
      if ($reason ne $reason2)
      {
        # Nonmatching reasons are resolved as an attr match status 8
        $status = 8;
        $return{'attr'} = $self->TranslateAttr($attr);
        $return{'reason'} = $self->TranslateReason('crms');
        $return{'category'} = 'Attr Match';
      }
      elsif ($attr eq 'ic' && $reason eq 'ren' && $reason2 eq 'ren' &&
             !TolerantCompare($data, $data2))
      {
        $status = 8;
        $return{'attr'} = $self->TranslateAttr($attr);
        $return{'reason'} = $self->TranslateReason($reason);
        $return{'category'} = 'Attr Match';
        $return{'note'} = 'Nonmatching renewals: %s vs %s', $data, $data2;
      }
    }
  }
  else
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

  return ($attr1 eq $attr2)? 1:0;
}

1;
