package Corrections;

use strict;
use warnings;
use vars qw(@ISA @EXPORT @EXPORT_OK);
our @EXPORT = qw(CorrectionsTitles CorrectionsFields GetCorrectionsDataRef CorrectionsDataSearchMenu
                 ExportCorrections RetrieveTicket);

my @FieldNames = ('Volume ID','Ticket','Time','Status','User','Locked','Note','Exported');
my @Fields     = qw(id ticket time status user locked note exported);

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
  my $sql = "SELECT COUNT(*) FROM corrections $restrict\n";
  #print "$sql<br/>\n";
  my $totalVolumes = $self->SimpleSqlGet($sql);
  $offset = $totalVolumes-($totalVolumes % $pagesize) if $offset >= $totalVolumes;
  my $limit = ($download)? '':"LIMIT $offset, $pagesize";
  my @return = ();
  my $concat = join ',', @Fields;
  $sql = " SELECT $concat FROM corrections $restrict ORDER BY $order $dir $limit";
  #print "$sql<br/>\n";
  my $ref = undef;
  eval {
    $ref = $self->GetDb()->selectall_arrayref($sql);
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
sub ExportCorrections
{
  my $self = shift;
  my $noop = shift;

  my %exports;
  my $sql = 'SELECT id,ticket,status FROM corrections WHERE exported=0 AND user IS NOT NULL';
  my $ref = $self->GetDb()->selectall_arrayref($sql);
  return unless scalar @{$ref} > 0;
  foreach my $row (@{$ref})
  {
    my $id = $row->[0];
    my $tx = $row->[1];
    my $st = $row->[2];
    if ($st eq 'fixed' || $st eq 'added')
    {
      $exports{$id}->{'exported'} = (defined $tx)? 0:1;
      $exports{$id}->{'jira'} = $tx if defined $tx;
    }
  }
  if (scalar keys %exports == 0)
  {
    $sql = 'UPDATE corrections SET exported=1 WHERE exported=0 AND user IS NOT NULL';
    $self->PrepareSubmitSql($sql) unless $noop;
    print "No corrections to export\n";
    return;
  }
  print "Exporting volumes to Jira.\n";
  CorrectionsToJira($self, \%exports, $noop);
  my ($fh, $temp, $perm) = GetCorrectionsExportFh($self);
  printf "Exporting %d volumes to $temp.\n", scalar keys %exports;
  my $n = 0;
  foreach my $id (sort keys %exports)
  {
    my $tx = $exports{$id}->{'jira'};
    my $ex = $exports{$id}->{'exported'};
    printf "Processing $id, ticket %s, exported=%d\n", (defined $tx)? $tx:'(none)', (defined $ex)? $ex:0;
    if (1 == $exports{$id}->{'exported'})
    {
      my $line = $id . ((defined $tx)? "\t$tx":'') . "\n";
      print $fh $line;
      my $id2 = $self->Undollarize($id);
      if (defined $id2)
      {
        $line = $id2 . ((defined $tx)? "\t$tx":'') . "\n";
        print $fh $line;
      }
      $n++;
    }
  }
  close $fh;
  print "Moving to $perm.\n";
  rename $temp, $perm;
  my $err;
  if ($n > 0 && !$noop)
  {
    eval { EmailCorrections($self, $n, $perm); };
    if ($@)
    {
      $err = 1;
      $self->SetError("EmailCorrections() failed: $@");
    }
  }
  foreach my $id (sort keys %exports)
  {
    # Set as exported anything marked exported by Jira,
    # and anything non-Jira as long as there was no email error.
    my $tx = $exports{$id}->{'jira'};
    my $ex = $exports{$id}->{'exported'};
    if ((defined $tx && 1 == $ex) ||
        (!defined $tx && !$err))
    {
      $sql = 'UPDATE corrections SET exported=1 WHERE id=?';
      $self->PrepareSubmitSql($sql, $id) unless $noop;
    }
  }
}

# Returns a triplet of (filehandle, temp name, permanent name)
# Filehande is to the temp file; after it is closed it needs
# to be renamed to the permanent name.
sub GetCorrectionsExportFh
{
  my $self = shift;

  my $date = $self->GetTodaysDate();
  $date    =~ s/:/_/g;
  $date    =~ s/ /_/g;
  my $perm = $self->get('root') . '/prep/c/crms/' . $self->get('sys') . '_' . $date . '.status.txt';
  my $temp = $perm . '.tmp';
  if (-f $temp) { die "file already exists: $temp\n"; }
  open (my $fh, '>', $temp) || die "failed to open exported file ($temp): $!\n";
  return ($fh, $temp, $perm);
}

# Send email with corrections data.
sub EmailCorrections
{
  my $self  = shift;
  my $count = shift;
  my $file  = shift;

  my $where = ($self->WhereAmI() or 'Prod');
  if ($where eq 'Prod' || 1)
  {
    my $subject = sprintf('%s %s: %d volume(s) fixed', $self->System(), $where, $count);
    use Mail::Sender;
    my $sender = new Mail::Sender
      {smtp => 'mail.umdl.umich.edu',
       from => $self->GetSystemVar('adminEmail')};
    $sender->MailFile({to => $self->GetSystemVar('correctionsEmailTo'),
             subject => $subject,
             msg => 'See attachment.',
             file => $file});
    $sender->Close;
  }
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
  my $root = $self->get('root');
  my $sys = $self->get('sys');
  my $cfg = $root . '/bin/c/crms/' . $sys . 'pw.cfg';
  my %d = $self->ReadConfigFile($cfg);
  my $username   = $d{'jiraUser'};
  my $password = $d{'jiraPasswd'};
  my $ua = new LWP::UserAgent;
  $ua->cookie_jar( {} );
  my $url = 'http://wush.net/jira/hathitrust/rest/auth/1/session';
  my $req = HTTP::Request->new(POST => $url);
  $req->content_type('application/json');
  $req->content(<<END);
    {
        "username": "$username",
        "password": "$password"
    }
END
  my $res = $ua->request($req);
  if (!$res->is_success())
  {
    warn("Got " . $res->code() . " logging in at $url\n" . $res->content() . "\n");
    return;
  }
  foreach my $id (sort keys %{$exports})
  {
    my $tx = $exports->{$id}{'jira'};
    next unless defined $tx;
    $url = 'https://wush.net/jira/hathitrust/rest/api/2/issue/' . $tx . '/transitions';
    print "$url\n";
    next if $noop;
    $req = HTTP::Request->new(POST => $url);
    $req->content_type('application/json');
    $req->content($json);
    $res = $ua->request($req);
    if ($res->is_success())
    {
      $exports->{$id}->{'exported'} = 1;
    }
    else
    {
      warn("Got " . $res->code() . " posting $url\n");
      #printf "%s\n", $res->content();
    }
  }
}

sub RetrieveTickets
{
  my $self    = shift;
  my $ids     = shift;
  my $verbose = shift;
  
  my $root = $self->get('root');
  my $sys = $self->get('sys');
  my $cfg = $root . '/bin/c/crms/' . $sys . 'pw.cfg';
  my %d = $self->ReadConfigFile($cfg);
  my $username   = $d{'jiraUser'};
  my $password = $d{'jiraPasswd'};
  my $ua = new LWP::UserAgent;
  $ua->cookie_jar( {} );
  my $url = 'http://wush.net/jira/hathitrust/rest/auth/1/session';
  my $req = HTTP::Request->new(POST => $url);
  $req->content_type('application/json');
  $req->content(<<END);
    {
        "username": "$username",
        "password": "$password"
    }
END
  my $res = $ua->request($req);
  if (!$res->is_success())
  {
    warn("Got " . $res->code() . " logging in at $url\n" . $res->content() . "\n");
    return;
  }
  foreach my $id (sort keys %{$ids})
  {
    $url = 'https://wush.net/jira/hathitrust/rest/api/2/search?jql=summary~"' . $id . '" AND (status=1 OR status=4 OR status=3)';
    print "$url\n" if $verbose;
    $req = HTTP::Request->new(GET => $url);
    $res = $ua->request($req);
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
