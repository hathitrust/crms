package CRI;
use vars qw(@ISA @EXPORT @EXPORT_OK);

use strict;
use warnings;
use CGI;

sub new
{
  my ($class, %args) = @_;
  my $self = bless {}, $class;
  my $errors = [];
  $self->set('errors', $errors);
  my $crms = $args{'crms'};
  die "Metadata module needs CRMS instance." unless defined $crms;
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

  delete $self->{$key} unless defined $val;
  $self->{$key} = $val if defined $key and defined $val;
}

sub SetError
{
  my $self   = shift;
  my $error  = shift;

  $self->get('crms')->SetError($error);
}

sub GetUser
{
  my $self   = shift;
  my $error  = shift;

  $self->get('crms')->get('user');
}

sub GetReviewsRef
{
  my $self    = shift;
  my $gid     = shift;
  my $pubDate = shift;

  my $crms = $self->get('crms');
  my @results;
  my $sql = 'SELECT r.id,r.user,r.attr,r.reason,r.note,r.category,r.renDate,r.renNum FROM historicalreviews r'.
            ' INNER JOIN users u ON r.user=u.id WHERE r.gid=?'.
            ' AND (r.category IS NULL OR category!="Expert Accepted")'.
            ' ORDER BY u.expert DESC,u.advanced DESC, u.id ASC';
  my $ref = $crms->SelectAll($sql, $gid);
  foreach my $row (@{$ref})
  {
    my $data = {'id'       => $row->[0],
                'user'     => $row->[1],
                'attr'     => $crms->TranslateAttr($row->[2]),
                'reason'   => $crms->TranslateReason($row->[3]),
                'note'     => $row->[4],
                'category' => $row->[5],
                'renDate'  => $row->[6],
                'renNum'   => $row->[7]};
    #my $rid = $crms->PredictRights($row->[0], $row->[6], $row->[7], $row->[5], undef, $pubDate);
    #my $pa = $crms->TranslateAttr($crms->SimpleSqlGet("SELECT attr FROM rights WHERE id=$rid"));
    #my $pr = $crms->TranslateReason($crms->SimpleSqlGet("SELECT reason FROM rights WHERE id=$rid"));
    #$data->{'attr'} = $pa;
    #$data->{'reason'} = $pr;
    push @results, $data;
  }
  return \@results;
}

sub GetNextVolumeForReview
{
  my $self = shift;
  my $user = shift || $self->GetUser();

  my $crms = $self->get('crms');
  my $sql = 'SELECT c.id FROM cri c INNER JOIN bibdata b ON c.id=b.id'.
            ' WHERE c.locked IS NULL AND c.status IS NULL ORDER BY b.author ASC,b.title ASC';
  my $ref = $crms->SelectAll($sql);
  my ($id, $gid);
  foreach my $row (@{$ref})
  {
    my $id2 = $row->[0];
    my $err = $self->LockItem($id2, $user);
    if (!$err)
    {
      $id = $id2;
      last;
    }
  }
  return $id;
}

sub GetGID
{
  my $self = shift;
  my $id   = shift;
  my $user = shift || $self->GetUser();

  my $crms = $self->get('crms');
  my $sql = 'SELECT gid FROM cri WHERE id=? AND locked=?';
  return $crms->SimpleSqlGet($sql, $id, $user);
}

sub HasLockedItem
{
  my $self = shift;
  my $user = shift || $self->GetUser();

  my $crms = $self->get('crms');
  my $sql = 'SELECT COUNT(*) FROM cri WHERE locked=? LIMIT 1';
  return ($crms->SimpleSqlGet($sql, $user))? 1:0;
}

# Returns 0 on success, error message on error.
sub LockItem
{
  my $self = shift;
  my $id   = shift;
  my $user = shift || $self->GetUser();

  my $crms = $self->get('crms');
  ## if already locked for this user, that's OK
  return 0 if $self->IsLockedForUser($id, $user);
  # Not locked for user, maybe someone else
  if ($self->IsLocked($id))
  {
    return 'Volume has been locked by another user';
  }
  ## can only have 1 item locked at a time (unless override)
  my $locked = $self->GetLockedItem($user);
  if (defined $locked)
  {
    return 0 if $locked eq $id;
    return "You already have a locked item ($locked).";
  }
  my $sql = 'UPDATE cri SET locked=? WHERE id=?';
  $crms->PrepareSubmitSql($sql, $user, $id);
  #$crms->Note("Lock $id for $user");
  return 0;
}

sub IsLockedForUser
{
  my $self = shift;
  my $id   = shift;
  my $user = shift || $self->GetUser();

  my $crms = $self->get('crms');
  my $sql = 'SELECT COUNT(*) FROM cri WHERE id=? AND locked=?';
  return 1 == $crms->SimpleSqlGet($sql, $id, $user);
}

sub IsLockedForOtherUser
{
  my $self = shift;
  my $id   = shift;
  my $user = shift || $self->GetUser();

  my $crms = $self->get('crms');
  my $lock = $crms->SimpleSqlGet('SELECT locked FROM cri WHERE id=?', $id);
  return ($lock && $lock ne $user)? $lock:undef;
}

sub GetLockedItem
{
  my $self = shift;
  my $user = shift || $self->GetUser();

  my $crms = $self->get('crms');
  my $sql = 'SELECT id,gid FROM cri WHERE locked=? LIMIT 1';
  return $crms->SimpleSqlGet($sql, $user);
}

sub IsLocked
{
  my $self = shift;
  my $id   = shift;

  my $crms = $self->get('crms');
  my $sql = 'SELECT id FROM cri WHERE locked IS NOT NULL AND id=?';
  return ($crms->SimpleSqlGet($sql, $id))? 1:0;
}

sub UnlockItem
{
  my $self = shift;
  my $id   = shift;
  my $user = shift || $self->GetUser();

  my $crms = $self->get('crms');
  my $sql = 'UPDATE cri SET locked=NULL WHERE id=? AND locked=?';
  $crms->PrepareSubmitSql($sql, $id, $user);
}

sub LinkToReview
{
  my $self  = shift;
  my $id    = shift;
  my $text  = shift;
  #my $user  = shift;

  my $crms = $self->get('crms');
  $text = CGI::escapeHTML($text);
  my $url = $crms->Sysify("/cgi/c/crms/crms?p=cri;htid=$id;editing=1");
  #$url .= ";importUser=$user" if $user;
  #$self->ClearErrors();
  return "<a href='$url' target='_blank'>$text</a>";
}

# Used by the getCRIInfo CGI for updating the interface via AJAX
sub GetCRIInfo
{
  my $self = shift;
  my $id   = shift;

  my $crms = $self->get('crms');
  my %data;
  my $sql = 'SELECT locked,status from cri WHERE id=?';
  my $ref = $crms->SelectAll($sql, $id);
  $data{'locked'} = $ref->[0]->[0];
  $data{'status'} = $ref->[0]->[1];
  return \%data;
}

my @FieldNames = ('Volume ID', 'GID', 'Source Status', 'Determination',
                  'Locked', 'Status', 'Author', 'Title', 'Pub Date');
my @Fields     = qw(id gid source_status determination
                    locked status author title pubdate);
my @DBFields   = ('c.id', 'c.gid', 'e.status', 'CONCAT(e.attr,"/",e.reason)',
                  'c.locked', 'c.status', 'b.author', 'b.title', 'b.pub_date');
# Map from @Field to @DBFields
my %FieldMap;
$FieldMap{$Fields[$_]} = $DBFields[$_] for (0 .. scalar @Fields - 1);

sub Titles
{
  return \@FieldNames;
}

sub Fields
{
  return \@Fields;
}

sub DataRef
{
  my $self         = shift;
  my $order        = shift;
  my $dir          = shift;
  my $search1      = shift;
  my $search1Value = shift;
  my $op1          = shift;
  my $search2      = shift;
  my $search2Value = shift;
  my $offset       = shift;
  my $pagesize     = shift;

  my $crms = $self->get('crms');
  $pagesize = 20 unless $pagesize and $pagesize > 0;
  $offset = 0 unless $offset and $offset > 0;
  $order = $FieldMap{$order} if $order;
  $order = 'b.author' unless $order;
  $offset = 0 unless $offset;
  my @rest = ('c.exported=0');
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
  if ($search1Value ne '' && $search2Value ne '')
  {
    push @rest, "($search1 $tester1 '$search1Value' $op1 $search2 $tester2 '$search2Value')";
  }
  else
  {
    $search1 = $FieldMap{$search1} if $search1;
    $search2 = $FieldMap{$search2} if $search2;
    push @rest, "$search1 $tester1 '$search1Value'" if $search1Value ne '';
    push @rest, "$search2 $tester2 '$search2Value'" if $search2Value ne '';
  }
  my $restrict = ((scalar @rest)? 'WHERE ':'') . join(' AND ', @rest);
  my $sql = 'SELECT COUNT(*) FROM cri c  INNER JOIN bibdata b ON c.id=b.id'.
            ' INNER JOIN exportdata e ON e.gid=c.gid '. $restrict;
  #print "$sql<br/>\n";
  my $totalVolumes = $crms->SimpleSqlGet($sql);
  $offset = $totalVolumes-($totalVolumes % $pagesize) if $offset >= $totalVolumes;
  my $limit = "LIMIT $offset, $pagesize";
  my @return = ();
  my $concat = join ',', @DBFields;
  $sql = "SELECT $concat FROM cri c INNER JOIN bibdata b ON c.id=b.id".
         " INNER JOIN exportdata e ON e.gid=c.gid $restrict ORDER BY $order $dir $limit";
  #print "$sql<br/>\n";
  my $ref = undef;
  eval {
    $ref = $crms->SelectAll($sql);
  };
  if ($@)
  {
    $self->SetError($@);
  }
  foreach my $row (@{$ref})
  {
    my %item = ();
    $item{$Fields[$_]} = $row->[$_] for (0 ... scalar @Fields-1);
    $item{'pubdate'} = $crms->FormatPubDate($row->[0]);
    push @return, \%item;
    
  }
  my $n = POSIX::ceil($offset/$pagesize+1);
  my $of = POSIX::ceil($totalVolumes/$pagesize);
  $n = 0 if $of == 0;
  my $data = {'rows' => \@return,
             'volumes' => $totalVolumes,
             'page' => $n,
             'of' => $of
            };
  return $data;
}

# Can edit if it has NULL status, or if numeric and the user is the one who reviewed it,
# but only if it is unexported. Rejected CRI can be edited by anyone because
# we don't keep a record of who did the rejection (no corresponding queue entry).
sub CanEditCri
{
  my $self = shift;
  my $id   = shift;
  my $user = shift || $self->GetUser();

  my $crms = $self->get('crms');
  my $sql = 'SELECT status FROM cri WHERE id=?';
  my $status = $crms->SimpleSqlGet($sql, $id);
  return 1 if !defined $status or $status == 0;
  $sql = 'SELECT COUNT(*) FROM reviews r INNER JOIN queue q ON r.id=q.id'.
         ' INNER JOIN cri c ON r.id=c.id'.
         ' WHERE r.id=? AND r.user=? AND q.source="cri" AND c.exported=0';
  return $crms->SimpleSqlGet($sql, $id, $user);
}

# Generates HTML to get the field type menu on the CRI Data page.
sub DataSearchMenu
{
  my $self       = shift;
  my $searchName = shift;
  my $searchVal  = shift;

  my $html = "<select title='Search Field' name='$searchName' id='$searchName'>\n";
  foreach my $i (0 .. scalar @Fields - 1)
  {
    $html .= sprintf("  <option value='%s'%s>%s</option>\n",
                     $Fields[$i], ($searchVal eq $Fields[$i])? ' selected="selected"':'',
                     $FieldNames[$i]);
  }
  $html .= "</select>\n";
  return $html;
}

sub ConfirmCRI
{
  my $self = shift;
  my $id   = shift;
  my $user = shift || $self->GetUser();
  my $cgi  = shift;

  my $crms = $self->get('crms');
  my $und = $cgi->param('und');
  my $qstatus = $crms->AddItemToQueueOrSetItemActive($id, 0, 1, 'cri');
  my $err = join '; ', @{$crms->GetErrors()};
  if (!$err)
  {
    $err = $qstatus->{'msg'} if $qstatus->{'status'} eq '1';
  }
  if (!$err)
  {
    my $gid = $crms->SimpleSqlGet('SELECT gid FROM cri WHERE id=?', $id);
    my $note = Encode::decode("UTF-8", $cgi->param('note'));
    my $start = $cgi->param('start');
    my $seluser = $cgi->param('seluser');
    my $sql = 'SELECT attr,reason,category,renNum,renDate FROM historicalreviews WHERE user=? AND gid=?';
    my $ref = $crms->SelectAll($sql, $seluser, $gid);
    my $predictedRights = $cgi->param('predictedRights');
    my ($attr, $reason);
    $attr = $ref->[0]->[0];
    $reason = $ref->[0]->[1];
    my $category = $ref->[0]->[2];
    $category = 'Expert Note' unless defined $category and length $category;
    if ($predictedRights)
    {
      my ($a,$r) = split '/', $predictedRights;
      $attr = $crms->TranslateAttr($a);
      $reason = $crms->TranslateReason($r);
    }
    if ($und)
    {
      $attr = $crms->TranslateAttr('und');
      $reason = $crms->TranslateReason('nfi');
    }
    my ($renNum, $renDate) = ($ref->[0]->[3], $ref->[0]->[4]);
    $err = $crms->ValidateSubmission($id, $user, $attr, $reason, $note, $category,
                                     $renNum, $renDate) unless $err;
    my $stat = $crms->GetSystemStatus();
    my $status = $stat->[1];
    $err = "The CRMS is not currently accepting reviews (status '$status'). Please Cancel." if $stat->[1] ne 'normal';
    if (!$err)
    {
      $crms->SubmitReview($id, $user, $attr, $reason, $note, $renNum, $crms->IsUserExpert($user),
                          $renDate, $category, undef, undef, undef, $start);
      my $ref = $crms->GetErrors();
      $err = $ref->[0] if $ref && $ref->[0];
    }
  }
  if (!$err)
  {
    my $status = ($und)? 2:1;
    $crms->PrepareSubmitSql('UPDATE cri SET status=? WHERE id=?', $status, $id);
  }
  return $err;
}

# Set status to 0 (rejected).
# In case of a revised review, removes queue entry and review if any.
sub RejectCRI
{
  my $self = shift;
  my $id   = shift;
  my $user = shift || $self->GetUser();

  my $crms = $self->get('crms');
  $crms->PrepareSubmitSql('UPDATE cri SET status=0 WHERE id=?', $id);
  my $err = join '; ', @{$crms->GetErrors()};
  if (!defined $err || $err eq '')
  {
    my $sql = 'DELETE FROM reviews WHERE id=? AND user=?';
    $crms->PrepareSubmitSql($sql, $id, $user);
    $sql = 'DELETE FROM queue WHERE id=? AND source="cri"';
    $crms->PrepareSubmitSql($sql, $id);
  }
  return $err;
}

# To be called after data moves from reviews to historical, and from queue to exportdata.
# For each unexported cri with non-NULL status, update by marking as exported and adding
# the determination's gid (if any).
sub ProcessCRI
{
  my $self = shift;

  my $crms = $self->get('crms');
  my $sql = 'SELECT id,status FROM cri WHERE status IS NOT NULL AND exported=0';
  my $ref = $crms->SelectAll($sql);
  foreach my $row (@{$ref})
  {
    my $id = $row->[0];
    my $status = $row->[1];
    my $newgid;
    if ($status == 1 || $status == 2)
    {
      $sql = 'SELECT gid FROM exportdata WHERE id=? AND src="cri" ORDER BY time DESC LIMIT 1';
      $newgid = $crms->SimpleSqlGet($sql, $id);
      print "Processing status $status CRI $id with gid $newgid\n";
    }
    elsif ($status == 0)
    {
      print "Checking status $status CRI $id for candidacy\n";
      $crms->CheckAndLoadItemIntoCandidates($id);
    }
    $sql = 'UPDATE cri SET exported=1,newgid=? WHERE id=?';
    $crms->PrepareSubmitSql($sql, $newgid, $id);
  }
}

sub LikeQuery
{
  my $self = shift;
  my $str  = shift;

  my ($best, $bestlen) = ('', 0);
  my @words = split /\s/, $str;
  foreach my $word (@words)
  {
    $word =~ s/[.,;:"\$\(\)\[\]]+//g;
    if ($word =~ m/[A-Za-z0-9']/)
    {
      if (length $word > $bestlen)
      {
        $best = $word;
        $bestlen = length $word;
      }
    }
  }
  my $q = $best. '%';
  #print "$best\n";
  $q = '%'. $q unless $str =~ m/^$best/;
  return $q;
}

# Returns the gid of the determination selected, or undef
sub CheckVolume
{
  my $self = shift;
  my $id   = shift;

  my $crms = $self->get('crms');
  return undef if $crms->SimpleSqlGet('SELECT COUNT(*) FROM cri WHERE id=?', $id);
  my $author = $crms->GetAuthor($id) || '';
  my $title = $crms->GetTitle($id) || '';
  return undef unless length $author and length $title;
  my $sysid = $crms->BarcodeToId($id);
  my $restr = '';
  $restr .= sprintf ' AND b.author LIKE "%s"', $self->LikeQuery($author);
  $restr .= sprintf ' AND b.title LIKE "%s"', $self->LikeQuery($title);
  $author =~ s/[^A-Za-z0-9]//g;
  $title =~ s/[^A-Za-z0-9]//g;
  my %seen;
  my $sql = 'SELECT e.id,e.status,e.gid FROM exportdata e INNER JOIN bibdata b on e.id=b.id'.
           ' WHERE b.id!=? AND b.sysid!=? AND e.src!="inherited"'.
           ' AND (e.attr="pd" OR e.attr="pdus" OR e.attr="icus" OR e.attr="und")'.
           $restr. ' ORDER BY e.time DESC';
  my ($best4, $best5, $best7);
  my $ref2 = $crms->SelectAll($sql, $id, $sysid);
  foreach my $row2 (@{$ref2})
  {
    my $id2 = $row2->[0];
    next if $seen{$id2};
    my $status2 = $row2->[1];
    my $gid2 = $row2->[2];
    $seen{$id2} = 1;
    my $author2 = $crms->GetAuthor($id2) || '';
    $author2 =~ s/[^A-Za-z0-9]//g;
    my $title2 = $crms->GetTitle($id2) || '';
    $title2 =~ s/[^A-Za-z0-9]//g;
    if ($author.$title eq $author2.$title2)
    {
      my $rights = $crms->GetCurrentRights($id);
      my $rights2 = $crms->GetCurrentRights($id2);
      if ($rights ne $rights2)
      {
        $best4 = $gid2 if $status2 == 4 and not defined $best4;
        $best5 = $gid2 if $status2 == 5 and not defined $best5;
        $best7 = $gid2 if $status2 == 7 and not defined $best7;
        last if defined $best5;
      }
    }
  }
  if (defined $best4 or defined $best5 or defined $best7)
  {
    return (defined $best5)? $best5:
                            ((defined $best7)? $best7:$best4);
  }
  return undef;
}

return 1;
