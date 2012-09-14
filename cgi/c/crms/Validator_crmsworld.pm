package Validator;

use strict;
use warnings;
use vars qw( @ISA @EXPORT @EXPORT_OK );
our @EXPORT = qw(ValidateSubmission);

# Returns an error message, or an empty string if no error.
sub ValidateSubmission
{
  my $self = shift;
  my ($id, $user, $attr, $reason, $note, $category, $renNum, $renDate) = @_;
  my $errorMsg = '';
  #$renDate =~ s/\D//g;
  my $noteError = 0;
  $attr = $self->TranslateAttr($attr);
  $reason = $self->TranslateReason($reason);
  $renDate =~ s/\s+//g if $renDate;
  if ($attr eq 'und' && $reason eq 'nfi' && ((!$note) || (!$category)))
  {
    $errorMsg .= 'und/nfi must include note category and note text.';
    $noteError = 1;
  }
  if ($renDate && $renDate !~ m/^\-?\d{1,4}$/)
  {
    $errorMsg .= sprintf("The year of %s must be only decimal digits. ",
                         ($renNum)? 'publication':'death');
  }
  # FIXME: check that renDate is defined, format was checked above.
  elsif (($reason eq 'add' || $reason eq 'exp') && $renDate !~ m/^\-?\d{1,4}$/)
  {
    $errorMsg .= "*/$reason must include a numeric year. ";
  }
  if ($noteError == 0)
  {
    if ($category && !$note)
    {
      if ($category ne 'Expert Accepted' && $category ne 'Crown Copyright')
      {
        $errorMsg .= 'Must include a note if there is a category. ';
      }
    }
    elsif ($note && !$category)
    {
      $errorMsg .= 'Must include a category if there is a note. ';
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
  my $ref = $dbh->selectall_arrayref( $sql );
  my ($user, $attr, $reason, $renNum, $renDate, $hold, $today) = @{ $ref->[0] };
  $renNum = undef unless $renDate;
  $sql = "SELECT user,attr,reason,renNum,renDate,hold FROM reviews WHERE id='$id' AND user!='$user'";
  $ref = $dbh->selectall_arrayref( $sql );
  my ($other_user, $other_attr, $other_reason, $other_renNum, $other_renDate, $other_hold) = @{ $ref->[0] };
  $other_renNum = undef unless $other_renDate;
  if ($hold && ($today lt $hold || $stat ne 'normal'))
  {
    $return{'hold'} = $user;
  }
  elsif ($other_hold && ($today lt $other_hold || $stat ne 'normal'))
  {
    $return{'hold'} = $other_user;
  }
  elsif ($attr == $other_attr && $reason == $other_reason &&
         $self->TolerantCompare($renNum, $other_renNum) &&
         $self->TolerantCompare($renDate, $other_renDate))
  {
    # If both reviewers are non-advanced mark as provisional match
    if ((!$self->IsUserAdvanced($user)) && (!$self->IsUserAdvanced($other_user)))
    {
       $status = 3;
    }
    else #Mark as 4 - two that agree
    {
      $status = 4;
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
  my $ref = $self->GetDb()->selectall_arrayref( $sql );
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
    $renNum = undef unless $renDate;
    $other_renNum = undef unless $other_renDate;
    if ($attr == $other_attr && $reason == $other_reason)
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
