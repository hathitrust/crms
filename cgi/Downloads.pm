package Downloads;

use strict;
use warnings;
use CGI;
use vars qw(@ISA @EXPORT @EXPORT_OK);
our @EXPORT = qw(Download);

sub Download
{
  my $crms = shift;
  my $cgi  = shift;

  my $page         = $cgi->param('p');
  my $order        = $cgi->param('order');
  my $dir          = $cgi->param('dir');
  my $search1      = $cgi->param('search1');
  my $search1value = $cgi->param('search1value');
  my $op1          = $cgi->param('op1');
  my $search2      = $cgi->param('search2');
  my $search2value = $cgi->param('search2value');
  my $startDate    = $cgi->param('startDate');
  my $endDate      = $cgi->param('endDate');
  my $offset       = $cgi->param('offset');
  my $records      = $cgi->param('records');
  my $stype        = $cgi->param('stype');
  my $q            = $cgi->param('q');

  my $res = 1;
  if ($page eq 'track')
  {
    DownloadTracking($crms, $q);
  }
  elsif ($page eq 'queue')
  {
    DownloadQueue($crms, $order, $dir, $search1, $search1value, $op1,
                  $search2, $search2value, $startDate, $endDate,
                  $offset, $records);
  }
  elsif ($page eq 'candidates')
  {
    DownloadCandidates($crms, $order, $dir, $search1, $search1value, $op1,
                       $search2, $search2value, $startDate, $endDate,
                       $offset, $records);
  }
  elsif ($page eq 'determinationStats')
  {
    my $monthly = $cgi->param('monthly');
    my $priority = $cgi->param('priority');
    my $pre = $cgi->param('pre');
    DownloadDeterminationStats($crms, $startDate, $endDate, $monthly,
                               $priority, $pre);
  }
  elsif ($page eq 'exportData')
  {
    DownloadExportData($crms, $order, $dir, $search1, $search1value, $op1,
                       $search2, $search2value, $startDate, $endDate,
                       $offset, $records);
  }
  else
  {
    my $op2 = $cgi->param('op2');
    my $search3 = $cgi->param('search3');
    my $search3value = $cgi->param('search3value');
    DownloadReviews($crms, $page, $order, $dir, $search1, $search1value, $op1,
                           $search2, $search2value, $op2, $search3, $search3value,
                           $startDate, $endDate, $offset, $records, $stype);
  }
}

sub DownloadSpreadsheet
{
  my $buff = shift;

  if ($buff)
  {
    print CGI::header(-type => 'text/plain', -charset => 'utf-8');
    print $buff;
  }
}

sub DownloadTracking
{
  my $crms = shift;
  my $q    = shift;

  my $data = $crms->TrackingQuery($q);
  my $buff = (join "\t", ('Volume', 'Enum/Chron', 'CRMS Status',
                          'U.S. Rights', 'Attribute', 'Reason', 'Source',
                          'User', 'Time', 'Note', 'Access Profile')) . "\n";
  foreach my $row (@{$data->{'data'}})
  {
    $buff .= (join "\t", @{$row}). "\n";
  }
  DownloadSpreadsheet($buff);
}

sub DownloadQueue
{
  my $crms         = shift;
  my $order        = shift;
  my $dir          = shift;
  my $search1      = shift;
  my $search1Value = shift;
  my $op1          = shift;
  my $search2      = shift;
  my $search2Value = shift;
  my $startDate    = shift;
  my $endDate      = shift;
  my $offset       = shift || 0;
  my $pagesize     = shift || 0;

  my $buff = $crms->GetQueueRef($order, $dir, $search1, $search1Value, $op1,
                                $search2, $search2Value, $startDate, $endDate,
                                $offset, $pagesize, 1);
  DownloadSpreadsheet($buff);
}

sub DownloadCandidates
{
  my $crms         = shift;
  my $order        = shift;
  my $dir          = shift;
  my $search1      = shift;
  my $search1Value = shift;
  my $op1          = shift;
  my $search2      = shift;
  my $search2Value = shift;
  my $startDate    = shift;
  my $endDate      = shift;
  my $offset       = shift || 0;
  my $pagesize     = shift || 0;

  my $buff = $crms->GetCandidatesRef($order, $dir, $search1, $search1Value, $op1,
                                     $search2, $search2Value, $startDate, $endDate,
                                     $offset, $pagesize, 1);
  DownloadSpreadsheet($buff);
}

sub DownloadDeterminationStats
{
  my $crms      = shift;
  my $startDate = shift;
  my $endDate   = shift;
  my $monthly   = shift;
  my $priority  = shift;
  my $pre       = shift;

  my $buff;
  if ($pre)
  {
    $buff = $crms->CreatePreDeterminationsBreakdownData($startDate, $endDate, $monthly, undef, $priority);
  }
  else
  {
    $buff = $crms->CreateDeterminationsBreakdownData($startDate, $endDate, $monthly, undef, $priority);
  }
  DownloadSpreadsheet($buff);
}

sub DownloadExportData
{
  my $crms         = shift;
  my $order        = shift;
  my $dir          = shift;
  my $search1      = shift;
  my $search1Value = shift;
  my $op1          = shift;
  my $search2      = shift;
  my $search2Value = shift;
  my $startDate    = shift;
  my $endDate      = shift;
  my $offset       = shift || 0;
  my $pagesize     = shift || 0;

  my $buff = $crms->GetExportDataRef($order, $dir, $search1, $search1Value, $op1,
                                     $search2, $search2Value, $startDate, $endDate,
                                     $offset, $pagesize, 1);
  DownloadSpreadsheet($buff);
}

sub DownloadReviews
{
  my $crms           = shift;
  my $page           = shift;
  my $order          = shift;
  my $dir            = shift;
  my $search1        = shift;
  my $search1value   = shift;
  my $op1            = shift;
  my $search2        = shift;
  my $search2value   = shift;
  my $op2            = shift;
  my $search3        = shift;
  my $search3value   = shift;
  my $startDate      = shift;
  my $endDate        = shift;
  my $offset         = shift || 0;
  my $pagesize       = shift || 0;
  my $stype          = shift;

  $stype = 'reviews' unless $stype;
  my $table = 'reviews';
  my $top = 'bibdata b';
  if ($page eq 'adminHistoricalReviews')
  {
    $table = 'historicalreviews';
    $top = 'exportdata q INNER JOIN bibdata b ON q.id=b.id';
  }
  else
  {
    $top = 'queue q INNER JOIN bibdata b ON q.id=b.id';
  }
  my ($sql,$totalReviews,$totalVolumes,$n,$of) = $crms->CreateSQL($stype, $page, $order, $dir, $search1,
                                                                  $search1value, $op1, $search2, $search2value,
                                                                  $op2, $search3, $search3value, $startDate,
                                                                  $endDate, $offset, $pagesize, 1);
  my $ref = $crms->SelectAll($sql);
  my $buff = '';
  if (scalar @{$ref} == 0)
  {
    $buff = 'No Results Found.';
  }
  else
  {
    if ($page eq 'userReviews')
    {
      $buff .= qq{id\ttitle\tauthor\tdate\tattr\treason\tcategory\tnote};
    }
    elsif ($page eq 'editReviews' || $page eq 'holds')
    {
      $buff .= qq{id\ttitle\tauthor\tdate\tattr\treason\tcategory\tnote\thold};
    }
    elsif ($page eq 'conflicts' || $page eq 'provisionals')
    {
      $buff .= qq{id\ttitle\tauthor\tdate\tstatus\tuser\tattr\treason\tcategory\tnote}
    }
    elsif ($page eq 'adminReviews' || $page eq 'adminHolds')
    {
      $buff .= qq{id\ttitle\tauthor\tdate\tstatus\tuser\tattr\treason\tcategory\tnote\tswiss\thold};
    }
    elsif ($page eq 'adminHistoricalReviews')
    {
      $buff .= qq{id\tsystem id\ttitle\tauthor\tpub date\tdate\tstatus\tlegacy\tuser\tattr\treason\tcategory\tnote\tvalidated\tswiss};
    }
    $buff .= sprintf("%s\n", ($crms->IsUserAdmin())? "\tpriority":'');
    if ($stype eq 'reviews')
    {
      $buff .= UnpackResults($crms, $page, $ref);
    }
    else
    {
      #$order = 'Identifier' if $order eq 'SysID';
      $order = $crms->ConvertToSearchTerm($order, 1);
      foreach my $row (@{$ref})
      {
        my $id = $row->[0];
        my $qrest = ($page ne 'adminHistoricalReviews')? ' AND r.id=q.id':'';
        $sql = 'SELECT r.id,r.time,r.duration,r.user,r.attr,r.reason,r.note,r.data,r.expert,'.
               'r.category,r.legacy,q.priority,r.swiss,q.status,q.project,b.title,b.author,'.
               (($page eq 'adminHistoricalReviews')?'r.validated':'r.hold ').
               " FROM $top INNER JOIN $table r ON b.id=r.id".
               " WHERE r.id='$id' $qrest ORDER BY $order $dir";
        #print "$sql<br/>\n";
        my $ref2;
        eval { $ref2 = $crms->SelectAll($sql); };
        if ($@)
        {
          #$crms->SetError("SQL failed: '$sql' ($@)");
          DownloadSpreadsheet("SQL failed: '$sql' ($@)");
          return;
        }
        $buff .= $crms->UnpackResults($page, $ref2);
      }
    }
  }
  DownloadSpreadsheet($buff);
}

sub UnpackResults
{
  my $crms = shift;
  my $page = shift;
  my $ref  = shift;

  my $buff = '';
  foreach my $row (@{$ref})
  {
    $row->[1] =~ s,(.*) .*,$1,;
    for (my $i = 0; $i < scalar @{$row}; $i++)
    {
      $row->[$i] =~ s/[\n\r\t]+/ /gs;
    }
    my $id         = $row->[0];
    my $time       = $row->[1];
    my $duration   = $row->[2];
    my $user       = $row->[3];
    my $attr       = $crms->TranslateAttr($row->[4]);
    my $reason     = $crms->TranslateReason($row->[5]);
    my $note       = $row->[6];
    my $data       = $row->[7];
    my $expert     = $row->[8];
    my $category   = $row->[9];
    my $legacy     = $row->[10];
    my $priority   = $crms->StripDecimal($row->[11]);
    my $swiss      = $row->[12];
    my $status     = $row->[13];
    my $project    = $row->[14];
    my $title      = $row->[15];
    my $author     = $row->[16];
    my $holdval    = $row->[17];
    if ($page eq 'userReviews') # FIXME: is this ever used??
    {
      $buff .= qq{$id\t$title\t$author\t$time\t$attr\t$reason\t$category\t$note};
    }
    elsif ($page eq 'editReviews' || $page eq 'holds')
    {
      $buff .= qq{$id\t$title\t$author\t$time\t$attr\t$reason\t$category\t$note\t$holdval};
    }
    elsif ($page eq 'conflicts' || $page eq 'provisionals')
    {
      $buff .= qq{$id\t$title\t$author\t$time\t$status\t$user\t$attr\t$reason\t$category\t$note}
    }
    elsif ($page eq 'adminReviews' || $page eq 'adminHolds')
    {
      $buff .= qq{$id\t$title\t$author\t$time\t$status\t$user\t$attr\t$reason\t$category\t$note\t$swiss\t$holdval};
    }
    elsif ($page eq 'adminHistoricalReviews')
    {
      my $pubdate = $crms->SimpleSqlGet('SELECT YEAR(pub_date) FROM bibdata WHERE id=?', $id);
      $pubdate = '?' unless $pubdate;
      my $sysid = $crms->SimpleSqlGet('SELECT sysid FROM bibdata WHERE id=?', $id);
      #id, title, author, review date, status, user, attr, reason, category, note, validated
      $buff .= qq{$id\t$sysid\t$title\t$author\t$pubdate\t$time\t$status\t$legacy\t$user\t$attr\t$reason\t$category\t$note\t$holdval\t$swiss};
    }
    $buff .= sprintf("%s\n", ($crms->IsUserAdmin())? "\t$priority":'');
  }
  return $buff;
}

return 1;
