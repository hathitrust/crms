package Inserts;

use strict;
use warnings;
use Utilities;

sub new
{
  my ($class, %args) = @_;
  my $self = bless {}, $class;
  my $errors = [];
  $self->set('errors', $errors);
  my $crms = $args{'crms'};
  return undef unless defined $crms;
  $self->set('crms', $crms);
  return $self;
}

sub get
{
  my $self = shift;
  my $key  = shift;

  return $self->{$key};
}

sub set
{
  my $self = shift;
  my $key  = shift;
  my $val  = shift;

  $self->{$key} = $val;
}

sub crms
{
  my $self = shift;

  return $self->get('crms');
}

sub GetInsertPage
{
  my $self = shift;
  my $id   = shift;
  my $iid  = shift;
  my $user = shift;

  my $crms = $self->crms;
  my $sql = 'SELECT page FROM inserts WHERE id=? AND iid=? AND user=?';
  my $page = $crms->SimpleSqlGet($sql, $id, $iid, $user);
  return $page;
}

sub GetInsertsData
{
  my $self = shift;
  my $id   = shift;
  my $user = shift || $self->crms->get('user');
  my $pri  = shift;

  my $crms = $self->crms;
  my $sql = 'SELECT * FROM inserts WHERE id=? AND user=? AND ';
  $sql .= ($pri)? 'iid=0':'iid>0';
  $sql .= ' ORDER BY iid ASC';
  #$crms->Note('GetInsertsData: '. Utilities::StringifySql($sql, $id, $user));
  my $ref = $crms->GetDb()->selectall_hashref($sql, 'iid', undef, $id, $user);
  return ($pri)? $ref->{0}:$ref;
}

sub ConfirmInserts
{
  my $self  = shift;
  my $cgi   = shift;

  my $final = $cgi->param('final');
  my $crms = $self->get('crms');
  my $user = $crms->get('user');
  #$crms->Note("ConfirmInserts($user, $final)");
  my $id = $cgi->param('barcode');
  $self->SubmitInserts($cgi, $id, $user, $final);
  if (!$crms->CountErrors())
  {
    if ($final)
    {
      #$crms->Note("Unlocking $id");
      $self->Unlock($id, $user);
    }
  }
  else
  {
    $crms->Note("ERROR DETECTED");
  }
}

my %nogo = ('p'=>1,'editing'=>1,'barcode'=>1,'count'=>1,'confirm'=>1,
            'sys'=>1,'submit'=>1,'final'=>1,'notApplicable'=>1);
sub SubmitInserts
{
  my $self  = shift;
  my $cgi   = shift;
  my $id    = shift;
  my $user  = shift;
  my $final = shift;

  my $crms = $self->get('crms');
  my $msg = 'SubmitInserts: ';
  foreach my $name ($cgi->param)
  {
    $msg .= sprintf "$name: {%s}\n", join ',', ($cgi->param($name));
  }
  if (!$self->get('noInsertsNote'))
  {
    $crms->Note($msg);
  }
  my %inserts;
  my $count = $cgi->param('count');
  my @fields;
  my @vals;
  # Wipe out irrelevant renewal information from the form
  my $ren = $cgi->param('0renewed');
  if (!$ren)
  {
    $cgi->delete('0renNum', '0renDateY', '0renDateM', '0renDateD');
  }
  foreach my $name ($cgi->param)
  {
    my $val = $cgi->param($name);
    if ($name =~ m/^0(\D+)$/)
    {
      $name = $1;
    }
    next if $name =~ m/^\d/;
    next if $nogo{$name};
    $val = undef unless defined $val and length $val;
    if ($name eq 'start')
    {
      my $dur = $crms->SimpleSqlGet('SELECT TIMEDIFF(NOW(),?)', $val);
      my $sql = 'SELECT timer FROM inserts WHERE user=? AND id=? AND iid=0';
      my $dur2 = $crms->SimpleSqlGet($sql, $user, $id);
      if (defined $dur2)
      {
        $dur = $crms->SimpleSqlGet('SELECT ADDTIME(?,?)', $dur, $dur2);
      }
      push(@fields, 'timer');
      push(@vals, $dur);
    }
    else
    {
      push @fields, $name;
      push @vals, $val;
    }
  }
  push @fields, 'id';
  push @vals, $id;
  my $sql = 'SELECT author,title,pub_date FROM bibdata WHERE id=?';
  my $ref = $crms->SelectAll($sql, $id);
  push @fields, ('author', 'title', 'pub_date');
  push @vals, ($ref->[0]->[0], $ref->[0]->[1], $ref->[0]->[2]);
  my $wc = $crms->WildcardList(scalar @fields);
  $sql = 'REPLACE INTO inserts ('.
          (join ',', @fields) .
          ') VALUES '. $wc;
  if (!$self->get('noInsertsNote'))
  {
    $crms->Note((join ',', @fields) . ' => ' . (join '_', (map {(defined $_)? $_:'<undef>'} @vals)));
  }
  $crms->PrepareSubmitSql($sql, @vals);
  for my $i (1 .. $count)
  {
    # Wipe out irrelevant renewal information from the form
    my $ren = $cgi->param($i.'renewed') || 0;
    if ($ren == 0)
    {
      $cgi->delete($i.'source', $i.'reason', $i.'renNum', $i.'renDateY', $i.'renDateM', $i.'renDateD');
    }
    elsif ($ren == 1)
    {
      $cgi->delete($i.'reason');
    }
    elsif ($ren == 2)
    {
      $cgi->delete($i.'source', $i.'renNum', $i.'renDateY', $i.'renDateM', $i.'renDateD');
    }
    @fields = ();
    @vals = ();
    foreach my $name ($cgi->param)
    {
      next if $name eq 'start';
      next unless $name =~ m/^$i(\D+)$/;
      my $suffix = $1;
      next if $nogo{$suffix};
      push @fields, $suffix;
      my $val = $cgi->param($name);
      $val = undef unless defined $val and length $val > 0;
      push @vals, $val;
    }
    push @fields, 'id';
    push @vals, $id;
    push @fields, 'iid';
    push @vals, $i;
    push @fields, 'user';
    push @vals, $user;
    my $wc = $crms->WildcardList(scalar @fields);
    my $sql = 'REPLACE INTO inserts ('.
              (join ',', @fields) .
              ') VALUES '. $wc;
    $crms->PrepareSubmitSql($sql, @vals);
    if (!$self->get('noInsertsNote'))
    {
      $crms->Note("$i: ". (join ',', @fields) . ' => ' . (join ',', (map {(defined $_)? $_:'<undef>'} @vals)));
    }
  }
  $sql = 'DELETE FROM inserts WHERE user=? AND iid>?';
  $crms->PrepareSubmitSql($sql, $user, $count);
  my $status = ($final)? 5:1;
  if (!$self->get('noInsertsNote'))
  {
    $crms->Note("$id: setting status to $status");
  }
  $sql = 'UPDATE insertsqueue SET status=? WHERE id=?';
  $crms->PrepareSubmitSql($sql, $status, $id);
}

sub GetNextInsertsForReview
{
  my $self = shift;
  my $user = shift;

  my $crms = $self->crms;
  $user = $self->get('user') unless defined $user;
  if (!$self->get('noInsertsNote'))
  {
    $crms->Note("GetNextInsertsForReview($user)");
  }
  my $id = undef;
  my $err = undef;
  my $sql = 'SELECT id FROM insertsqueue WHERE (locked IS NULL AND status=0)'.
            ' OR (id IN (SELECT id FROM inserts WHERE user=?) AND status=1)'.
            ' ORDER BY status DESC';
  if (!$self->get('noInsertsNote'))
  {
    $crms->Note(Utilities::StringifySql($sql, $user));
  }
  eval {
    my $ref = $crms->SelectAll($sql, $user);
    foreach my $row (@{$ref})
    {
      my $id2 = $row->[0];
      $err = $self->Lock($id2, $user);
      if (!$self->get('noInsertsNote'))
      {
        $crms->Note($id2. ': '. $err);
      }
      if (!$err)
      {
        $id = $id2;
        last;
      }
    }
  };
  $crms->SetError($@) if $@;
  if (!$id)
  {
    $err = sprintf "Could not get inserts for $user to review%s.", ($err)? " ($err)":'';
    $err .= "\n$sql";
    $crms->SetError($err);
  }
  return $id;
}

sub GetLockedInserts
{
  my $self = shift;

  my $crms = $self->crms;
  my $user = $crms->get('user');
  my $sql = 'SELECT id FROM insertsqueue WHERE locked=? LIMIT 1';
  return $crms->SimpleSqlGet($sql, $user);
}

sub Lock
{
  my $self = shift;
  my $id   = shift;
  my $user = shift;

  my $crms = $self->crms;
  ## if already locked for this user, that's OK
  return 0 if $self->IsLockedForUser($id, $user);
  # Not locked for user, maybe someone else
  if ($self->IsLocked($id))
  {
    return 'Volume has been locked by another user';
  }
  ## can only have 1 item locked at a time (unless override)
  my $locked = $self->GetLockedInserts($user);
  if (defined $locked)
  {
    return 0 if $locked eq $id;
    return "You already have a locked item ($locked).";
  }
  my $sql = 'UPDATE insertsqueue SET locked=? WHERE id=?';
  $crms->PrepareSubmitSql($sql, $user, $id);
  return 0;
}

sub IsLocked
{
  my $self = shift;
  my $id   = shift;

  my $crms = $self->crms;
  my $sql = 'SELECT id FROM insertsqueue WHERE locked IS NOT NULL AND id=?';
  return ($crms->SimpleSqlGet($sql, $id))? 1:0;
}

sub Unlock
{
  my $self = shift;
  my $id   = shift;
  my $user = shift;

  my $crms = $self->crms;
  $user = $crms->get('user') unless defined $user;
  my $sql = 'UPDATE insertsqueue SET locked=NULL WHERE id=? AND locked=?';
  $crms->PrepareSubmitSql($sql, $id, $user);
}

sub IsLockedForUser
{
  my $self = shift;
  my $id   = shift;
  my $user = shift;

  my $crms = $self->crms;
  my $sql = 'SELECT COUNT(*) FROM insertsqueue WHERE id=? AND locked=?';
  return 1 == $crms->SimpleSqlGet($sql, $id, $user);
}

sub VIAFWarning
{
  my $self = shift;
  my $au   = shift;

  return '' unless defined $au;
  my $crms = $self->crms;
  my $data = $crms->GetVIAFData(undef, $au);
  if (defined $data and scalar keys %{$data} > 0)
  {
    my $country = $data->{'country'};
    if (defined $country && substr($country, 0, 2) ne 'US' &&
        substr($country, 0, 2) ne 'XX')
    {
      my $add = $data->{'add'};
      return '' if defined $add and $add <= 1895;
      my $last = $au;
      $last = $1 if $last =~ m/^(.+?),.*/;
      return "$last ($country)";
    }
  }
  return '';
}

sub URLForYear
{
  my $self = shift;
  my $y    = shift;

  my $url = '';
  if ($y <= 1978)
  {
    if ($y <= 1949)
    {
      $url = 'http://onlinebooks.library.upenn.edu/cce/to1949.html#y'. $y;
    }
    else
    {
      $url = 'http://onlinebooks.library.upenn.edu/cce/'. $y. 'r.html';
    }
  }
  else
  {
    $url = 'http://cocatalog.loc.gov/cgi-bin/Pwebrecon.cgi?DB=local&PAGE=First';
  }
  return $url;
}

# FIXME: create derived list for menus excluding renDate
my @FieldNames = ('Volume ID', 'User', 'Review Date', 'Title', 'Author', 'Pub Date', 'Type', 'Page',
                  'Pub History', 'Renewed', 'RenNum', 'RenDate', 'Source', 'Reason', 'Timer', 'Complete');
my @Fields     = qw(id user reviewDate title author pubDate type page
                    pub_history renewed renNum renDate source reason timer status);
my @Fields2    = ('i.id', 'i.user', 'DATE(i.time)', 'i.title', 'i.author', 'i.pub_date', 'i.type', 'i.page',
                  'i.pub_history', 'i.renewed', 'i.renNum', 'CONCAT(i.renDateY,"-",i.renDateM,"-",i.renDateD)',
                  'i.source', 'i.reason', 'i.timer', 'iq.status', 'i.iid');

sub InsertsTitles
{
  return \@FieldNames;
}

sub InsertsFields
{
  return \@Fields;
}

sub GetInsertsDataRef
{
  my $self         = shift;
  my $order        = shift;
  my $dir          = shift;
  my $search1      = shift;
  my $search1Value = shift;
  my $op1          = shift;
  my $search2      = shift;
  my $search2Value = shift;
  my $startDate    = shift;
  my $endDate      = shift;
  my $offset       = shift;
  my $pagesize     = shift;
  my $download     = shift;

  $pagesize = 20 unless $pagesize and $pagesize > 0;
  $offset = 0 unless $offset and $offset > 0;
  $order = 'id' unless $order;
  $offset = 0 unless $offset;
  my @rest = ();
  my $tester1 = '=';
  my $tester2 = '=';
  if ($search1Value =~ m/.*\*.*/)
  {
    $search1Value =~ s/\*/%/gs;
    $tester1 = ' LIKE ';
  }
  if ($search2Value =~ m/.*\*.*/)
  {
    $search2Value =~ s/\*/%/gs;
    $tester2 = ' LIKE ';
  }
  if ($search1Value =~ m/([<>!]=?)\s*(\d+)\s*/)
  {
    $search1Value = $2;
    $tester1 = $1;
  }
  if ($search2Value =~ m/([<>!]=?)\s*(\d+)\s*/)
  {
    $search2Value = $2;
    $tester2 = $1;
  }
  push @rest, "DATE(i.time)>='$startDate'" if $startDate;
  push @rest, "DATE(i.time)<='$endDate'" if $endDate;
  if ($search1Value ne '' && $search2Value ne '')
  {
    push @rest, "($search1 $tester1 '$search1Value' $op1 $search2 $tester2 '$search2Value')";
  }
  else
  {
    push @rest, "$search1 $tester1 '$search1Value'" if $search1Value ne '';
    push @rest, "$search2 $tester2 '$search2Value'" if $search2Value ne '';
  }
  my $restrict = ((scalar @rest)? 'WHERE ':'') . join(' AND ', @rest);
  my $sql = 'SELECT COUNT(*) FROM inserts i '. $restrict;
  #print "$sql<br/>\n";
  my $totalVolumes = $self->SimpleSqlGet($sql);
  $offset = $totalVolumes-($totalVolumes % $pagesize) if $offset >= $totalVolumes;
  my $limit = ($download)? '':"LIMIT $offset, $pagesize";
  my @return = ();
  my $concat = join ',', @Fields2;
  $sql = "SELECT $concat FROM inserts i INNER JOIN bibdata b".
         ' ON i.id=b.id INNER JOIN insertsqueue iq ON b.id=iq.id'.
         " $restrict ORDER BY $order $dir $limit";
  #$self->Note($sql);
  my $ref = undef;
  eval {
    $ref = $self->SelectAll($sql);
  };
  if ($@)
  {
    $self->SetError($@);
  }
  my $data = join "\t", @FieldNames;
  foreach my $row (@{$ref})
  {
    my %item = ();
    $item{$Fields[$_]} = $row->[$_] for (0 .. scalar @Fields);
    push @return, \%item;
    if ($download)
    {
      $data .= "\n" . join "\t", @{$row};
    }
  }
  if (!$download)
  {
    my $n = POSIX::ceil($offset/$pagesize+1);
    my $of = POSIX::ceil($totalVolumes/$pagesize);
    $n = 0 if $of == 0;
    $data = {'rows' => \@return,
             'volumes' => $totalVolumes,
             'page' => $n,
             'of' => $of
            };
  }
  return $data;
}

# Generates HTML to get the field type menu on the Corrections Data page.
sub InsertsDataSearchMenu
{
  my $self       = shift;
  my $searchName = shift;
  my $searchVal  = shift;

  my $html = "<select title='Search Field' name='$searchName' id='$searchName'>\n";
  foreach my $i (0 .. scalar @Fields - 1)
  {
    $html .= sprintf("  <option value='%s'%s>%s</option>\n",
                     $Fields2[$i], ($searchVal eq $Fields2[$i])? ' selected="selected"':'',
                     $FieldNames[$i]);
  }
  $html .= "</select>\n";
  return $html;
}

sub LinkToInserts
{
  my $self = shift;
  my $id   = shift;
  my $user = shift;

  my $crms = $self->get('crms');
  my $url = $crms->Sysify('/cgi/c/crms/inserts?p=inserts;editing=1;barcode='. $id);
  $url .= ";user=$user" if defined $user;
  return $url;
}

return 1;
