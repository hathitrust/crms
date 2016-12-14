package Corrections;

use strict;
use warnings;
use Jira;
use vars qw(@ISA @EXPORT @EXPORT_OK);
our @EXPORT = qw(ConfirmCorrection CorrectionsTitles CorrectionsFields GetCorrectionsDataRef
                 CorrectionsDataSearchMenu ExportCorrections RetrieveTicket);

my @FieldNames = ('Volume ID','Ticket','Time','Status','User','Locked','Note','Exported');
my @Fields     = qw(id ticket time status user locked note exported);


sub ConfirmCorrection
{
  my $self = shift;
  my $id   = shift;
  my $user = shift || $self->get('user');
  my $cgi  = shift;

  my $page = $cgi->param('p');
  my $note    = Encode::decode("UTF-8", $cgi->param('note'));
  my $fixed   = $cgi->param('fixed');
  my $inScope = $cgi->param('inScope');
  my $status = ($fixed)? (($inScope)? 'added':'fixed'):'unfixed';
  my $qstatus = $self->AddItemToQueueOrSetItemActive($id, 0, 1, 'correction') if $status eq 'added';
  my $ref = $self->GetErrors();
  my $err = $ref->[0] if $ref && $ref->[0];
  if (!$err)
  {
    $err = $qstatus->{'msg'} if $qstatus->{'status'} eq '1';
  }
  if (!$err)
  {
    my $sql = 'UPDATE corrections SET status=?,user=?,note=?,time=CURRENT_TIMESTAMP WHERE id=?';
    $self->PrepareSubmitSql($sql, $status, $user, $note, $id);
    $self->UnlockItem($id, $user, $page);
  }
  return $err;
}

sub CorrectionsTitles
{
  return \@FieldNames;
}

sub CorrectionsFields
{
  return \@Fields;
}

sub GetCorrectionsDataRef
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
  push @rest, "added >= '$startDate'" if $startDate;
  push @rest, "added <= '$endDate'" if $endDate;
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
  my $sql = 'SELECT COUNT(*) FROM corrections '. $restrict;
  #print "$sql<br/>\n";
  my $totalVolumes = $self->SimpleSqlGet($sql);
  $offset = $totalVolumes-($totalVolumes % $pagesize) if $offset >= $totalVolumes;
  my $limit = ($download)? '':"LIMIT $offset, $pagesize";
  my @return = ();
  my $concat = join ',', @Fields;
  $concat =~ s/,time,/,DATE(time),/;
  $sql = "SELECT $concat FROM corrections $restrict ORDER BY $order $dir $limit";
  #print "$sql<br/>\n";
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
    $item{$Fields[$_]} = $row->[$_] for (0 ... 8);
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
sub CorrectionsDataSearchMenu
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

# Send the fixed non-Jira corrections to a text file in prep/c/crms and mail it.
# Comment and close the Jira corrections.
# $data is a hashref with the following fields
# ->{'html'}     In-progress HTML to be sent to recipients
# ->{'fh'}       The open handle to tempfile
# ->{'tempfile'} The name of the temp file
# ->{'permfile'} The name of the permanent file that will be attached
# ->{'verbose'}  Verbosity level
sub ExportCorrections
{
  my $self = shift;
  my $noop = shift;
  my $data = shift;

  my $verbose = $data->{'verbose'};
  my %exports;
  my $sql = 'SELECT id,ticket,DATE(time),note FROM corrections'.
            ' WHERE (status="fixed" OR status="added") AND exported=0'.
            ' ORDER BY time DESC';
  my $ref = $self->SelectAll($sql);
  my $html = $data->{'html'};
  $html .= sprintf "<h3>Exporting %d corrections from %s</h3>\n", scalar @{$ref}, $self->System();
  if (scalar @{$ref} > 0)
  {
    foreach my $row (@{$ref})
    {
      my $id = $row->[0];
      my $tx = $row->[1];
      my $date = $row->[2];
      my $note = $row->[3];
      $exports{$id}->{'jira'} = $tx if defined $tx;
      $exports{$id}->{'date'} = $date;
      $exports{$id}->{'note'} = $note;
    }
    my $ua = CorrectionsToJira($self, \%exports, $noop);
    my $fh = $data->{'fh'};
    my $temp = $data->{'tempfile'};
    my $perm = $data->{'permfile'};
    if (!defined $fh)
    {
      ($fh, $temp, $perm) = GetCorrectionsExportFh($self);
      $data->{'fh'} = $fh;
      $data->{'tempfile'} = $temp;
      $data->{'permfile'} = $perm;
    }
    printf "Exporting %d volumes to $temp.\n", scalar keys %exports if $verbose;
    my $n = 0;
    foreach my $id (sort keys %exports)
    {
      my $tx = $exports{$id}->{'jira'};
      my $ex = $exports{$id}->{'exported'};
      printf "Processing $id, ticket %s, exported=%d\n",
              (defined $tx)? $tx:'(none)',
              (defined $ex)? $ex:0 if $verbose>1;
      if (1 == $ex)
      {
        my $line = $id . ((defined $tx)? "\t$tx":'');
        print $fh $line . "\n";
        $n++;
      }
    }
    $html .= '<table border=1><tr><th>ID</th><th>Ticket</th><th>Date</th>'.
             '<th>Reviewer Note</th><th>Jira Status</th><th>Exported</th>'.
             '<th>Message</th><tr>'. "\n";
    foreach my $id (sort keys %exports)
    {
      # Set as exported anything marked exported by Jira,
      # and anything non-Jira.
      my $tx = $exports{$id}->{'jira'};
      my $ex = $exports{$id}->{'exported'};
      my $msg = $exports{$id}->{'message'};
      $msg = '' unless defined $msg;
      $msg = '<span style="color:red;">' . $msg . '</span>' if length $msg;
      if (1 == $ex)
      {
        $sql = 'UPDATE corrections SET exported=1 WHERE id=?';
        $self->PrepareSubmitSql($sql, $id) unless $noop;
      }
      $html .= sprintf "<tr><td>$id</td><td>%s</td><td>%s</td>".
                       "<td>%s</td><td>%s</td><td>%s</td><td>$msg</td><tr>\n",
              Jira::LinkToJira($tx), $exports{$id}->{'date'},
              $exports{$id}->{'note'},
              Jira::GetIssueStatus($self, $ua, $tx), ($ex)? '&#x2713;':'';
    }
    $html .= "</table>\n";
  }
  $sql = 'SELECT COUNT(*) FROM corrections WHERE status IS NULL';
  my $ct = $self->SimpleSqlGet($sql);
  $ct = 'no' if $ct == 0;
  $html .= "<h4>After export, there are $ct unchecked corrections</h4>\n";
  $data->{'html'} = $html;
}

# Returns a triplet of (filehandle, temp name, permanent name)
# Filehande is to the temp file; after it is closed it needs
# to be renamed to the permanent name.
sub GetCorrectionsExportFh
{
  my $self = shift;

  my $date = $self->GetTodaysDate();
  $date =~ s/:/_/g;
  $date =~ s/ /_/g;
  my $perm = $self->get('root') . '/prep/c/crms/' . $self->get('sys') . '_' . $date . '.status.txt';
  my $temp = $perm . '.tmp';
  if (-f $temp) { die "file already exists: $temp\n"; }
  open (my $fh, '>', $temp) || die "failed to open exported file ($temp): $!\n";
  return ($fh, $temp, $perm);
}

sub CorrectionsToJira
{
  my $self    = shift;
  my $exports = shift;
  my $noop    = shift;

  my $msg = 'CRMS re-reviewed this volume and was able to make a copyright determination. That closes this ticket.';
  my $json = <<END;
{
  "update":
  {
    "comment":
    [
      {
        "add":
        {
          "body":"$msg"
        }
      }
    ]
  },
  "fields":
  {
    "resolution":
    {
      "name":"Fixed"
    }
  },
  "transition":
  {
    "id":"141"
  }
}
END
  my $ua = Jira::Login($self);
  return unless defined $ua;
  foreach my $id (sort keys %{$exports})
  {
    my $tx = $exports->{$id}{'jira'};
    if (!defined $tx)
    {
      $exports->{$id}->{'exported'} = 1;
      next;
    }
    my $url = 'https://wush.net/jira/hathitrust/rest/api/2/issue/' . $tx . '/transitions';
    my $ok = 1;
    my $code;
    if (!$noop)
    {
      print "$url\n";
      my $req = HTTP::Request->new(POST => $url);
      $req->content_type('application/json');
      $req->content($json);
      my $res = $ua->request($req);
      $ok = $res->is_success();
      $code = $res->code();
    }
    else
    {
      print "No-op, not submitting on $tx\n";
    }
    if ($ok)
    {
      $exports->{$id}->{'exported'} = 1;
    }
    else
    {
      $exports->{$id}->{'exported'} = 0;
      $exports->{$id}->{'message'} = 'Got ' . $code . " posting $url\n";
      #printf "%s\n", $res->content();
    }
  }
  return $ua;
}

sub RetrieveTickets
{
  my $self    = shift;
  my $ids     = shift;
  my $verbose = shift;

  my $ua = Jira::Login($self);
  return unless defined $ua;
  foreach my $id (sort keys %{$ids})
  {
    my $url = 'https://wush.net/jira/hathitrust/rest/api/2/search?jql=summary~"' .
               $id . '" AND (status=1 OR status=4 OR status=3)';
    print "$url\n" if $verbose;
    my $req = HTTP::Request->new(GET => $url);
    my $res = $ua->request($req);
    if ($res->is_success())
    {
      my $json = JSON::XS->new;
      my $content = $res->content;
      eval {
        my $data = $json->decode($content);
        my $of = $data->{'total'};
        if ($of == 0)
        {
          print "Warning: found no results for $id\n";
        }
        elsif ($of > 1)
        {
          my @alltx = map {$data->{'issues'}->[$_]->{'key'}} (0 .. $of-1);
          printf "Warning: found %d results for $id: %s\n", $of, join ', ', @alltx;
        }
        else
        {
          my $tx = $data->{'issues'}->[0]->{'key'};
          $ids->{$id} = $tx;
        }
      }
    }
    else
    {
      warn("Got " . $res->code() . " getting $url\n");
      #printf "%s\n", $res->content();
    }
  }
}

1;
