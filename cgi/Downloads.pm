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
    $crms->DownloadTracking($q)
  }
  elsif ($page eq 'queue')
  {
    $res = $crms->DownloadQueue($order, $dir, $search1, $search1value, $op1,
                                $search2, $search2value, $startDate, $endDate,
                                $offset, $records);
  }
  elsif ($page eq 'determinationStats')
  {
    my $monthly = $cgi->param('monthly');
    my $priority = $cgi->param('priority');
    my $pre = $cgi->param('pre');
    $res = $crms->DownloadDeterminationStats($startDate, $endDate, $monthly,
                                             $priority, $pre);
  }
  elsif ($page eq 'exportData')
  {
    $res = $crms->DownloadExportData($order, $dir, $search1, $search1value, $op1,
                                     $search2, $search2value, $startDate, $endDate,
                                     $offset, $records);
  }
  else
  {
    my $op2 = $cgi->param('op2');
    my $search3 = $cgi->param('search3');
    my $search3value = $cgi->param('search3value');
    $res = $crms->DownloadReviews($page, $order, $dir, $search1, $search1value, $op1,
                                  $search2, $search2value, $op2, $search3, $search3value,
                                  $startDate, $endDate, $offset, $records, $stype);
  }
  return $res;
}

return 1;
