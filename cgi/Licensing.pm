package Licensing;
use vars qw(@ISA @EXPORT @EXPORT_OK);

use strict;
use warnings;

sub new
{
  my ($class, %args) = @_;
  my $self = bless {}, $class;
  my $crms = $args{crms};
  die "Licensing module needs CRMS instance." unless defined $crms;
  $self->{crms} = $crms;
  return $self;
}

sub query
{
  my $self = shift;
  my $ids  = shift;

  my $crms = $self->{crms};
  my $result = { errors => [], data => [] };
  my %seen_htid;
  my %seen_sysid;
  my %htid_to_metadata;
  my %sysid_to_metadata;
  my %sysid_order;
  my $sysid_count = 0;
  foreach my $id (@$ids)
  {
    my $record;
    my @htids = ();
    if ($id =~ m/\./)
    {
      next if $seen_htid{$id};
      $record = $htid_to_metadata{$id} || $crms->GetMetadata($id);
      $htid_to_metadata{$id} = $record;
      push @htids, $id;
    }
    else
    {
      next if $seen_sysid{$id};
      $record = $sysid_to_metadata{$id} || $crms->GetMetadata($id);
      $sysid_to_metadata{$id} = $record;
      push @htids, @{$record->allHTIDs};
      $seen_sysid{$id} = 1;
    }
    unless (defined $record)
    {
      $crms->ClearErrors();
      push @{$result->{errors}}, "Unable to retrieve metadata for $id";
      next;
    }
    $sysid_order{$record->sysid} = $sysid_count;
    $sysid_count++;
    foreach my $htid (@htids)
    {
      my $data = {};
      $data->{htid} = $htid;
      $data->{sysid} = $record->sysid;
      $data->{chron} = $record->enumchron($htid);
      $data->{author} = $record->author;
      $data->{title} = $record->title;
      $data->{date} = $record->copyrightDate;
      $data->{tracking} = $crms->GetTrackingInfo($htid, 1);
      $data->{rights} = $crms->RightsQuery($htid, 1)->[0];
      $data->{already} = defined $self->GetData($htid);
      push @{$result->{data}}, $data;
      $seen_htid{$htid} = 1;
    }
  }
  @{$result->{data}} = sort { $sysid_order{$a->{sysid}} <=> $sysid_order{$b->{sysid}} ||
                              $a->{chron} cmp $b->{chron} ||
                              $a->{htid} cmp $b->{htid}; } @{$result->{data}};
  return $result;
}

sub attributes
{
  my $self = shift;

  my $crms = $self->{crms};
  my $sql = 'SELECT id,name FROM attributes' .
            ' WHERE (name LIKE "cc%" AND name NOT LIKE "%3.0%")'.
            ' OR name="nobody" OR name="pd-pvt" OR name="ic"' .
            ' ORDER BY name ASC';
  my @attrs = map { { id => $_->[0], name => $_->[1] }; } @{$crms->SelectAll($sql)};
  return \@attrs;
}

sub reasons
{
  my $self = shift;

  my $crms = $self->{crms};
  my $sql = 'SELECT id,name FROM reasons' .
            ' WHERE name IN ("con","man","pvt")' .
            ' ORDER BY name ASC';
  my @attrs = map { { id => $_->[0], name => $_->[1] }; } @{$crms->SelectAll($sql)};
  return \@attrs;
}

sub submit
{
  my $self = shift;
  my $cgi  = shift;

  my $crms = $self->{crms};
  my $result = { errors => [], added => {} };
  my $now = $crms->GetNow();
  my $sql = 'INSERT INTO licensing'.
            ' (htid,time,user,attr,reason,ticket,rights_holder)'.
            ' VALUES (?,?,?,?,?,?,?)';
  my @ids = $cgi->param('htid');
  my %exclude = map { $_ => 1 } $cgi->param('exclude');
  my $user = $crms->get('user');
  foreach my $id (@ids)
  {
    next if $exclude{$id};
    eval {
      $crms->PrepareSubmitSql($sql, $id, $now, $user, $cgi->param('attr'),
                              $cgi->param('reason'), $cgi->param('ticket'),
                              $cgi->param('rights_holder'));
    };
    if ($@)
    {
      push @{$result->{errors}}, "$id: $@";
    }
    else
    {
      $crms->UpdateMetadata($id, 1);
      $self->{crms}->SafeRemoveFromQueue($id);
      my $attr = $crms->TranslateAttr($cgi->param('attr'));
      my $reason = $crms->TranslateReason($cgi->param('reason'));
      $result->{added}->{$id} = "$attr/$reason";
    }
  }
  if (scalar @{$result->{errors}})
  {
    $sql = 'DELETE FROM licensing WHERE time=? AND user=?';
    $crms->PrepareSubmitSql($sql, $now, $user);
    $result->{added} = {};
  }
  return $result;
}

# Returns a hashref:
# hash->{ids} => arrayref of row ids (not HTIDs)
# hash->{rights_data} => tab-delimited .rights file content
sub rights_data {
  my $self = shift;

  my $retval = {ids => [], rights_data => ''};
  my $crms = $self->{crms};
  my $sql = 'SELECT id,htid,attr,reason,user,ticket,rights_holder FROM licensing'.
            ' WHERE rights_file IS NULL'.
            ' ORDER BY time, id';
  my $ref = $crms->SelectAll($sql);
  foreach my $row (@$ref) {
    my ($id, $htid, $attr, $reason, $user, $ticket, $rights_holder) = @$row;
    push @{$retval->{ids}}, $id;
    my $note = $ticket || '';
    if ($rights_holder) {
      $note .= ' ' if length $note;
      $note .= " ($rights_holder)" if $rights_holder;
    }
    $retval->{rights_data} .= join("\t", ($htid, $crms->TranslateAttr($attr),
                                   $crms->TranslateReason($reason),
                                   'crms', 'null', $note)) . "\n";
  }
  return $retval;
}

sub GetData
{
  my $self = shift;
  my $id   = shift;

  my $sql = 'SELECT l.id, l.time, l.user, CONCAT(a.name,"/",rs.name),'.
              'l.ticket,l.rights_holder,l.rights_file'.
              ' FROM licensing l'.
              ' INNER JOIN attributes a ON l.attr=a.id'.
              ' INNER JOIN reasons rs ON l.reason=rs.id'.
              ' WHERE l.htid=?'.
              ' ORDER BY l.time ASC LIMIT 1';
    my $ref = $self->{crms}->SelectAll($sql, $id);
    return unless $ref && scalar @$ref;
    return {id => $ref->[0]->[0],
            htid => $id,
            user => $ref->[0]->[2],
            rights => $ref->[0]->[3],
            ticket => $ref->[0]->[4],
            rights_holder => $ref->[0]->[5],
            rights_file => $ref->[0]->[6]};
}

return 1;
