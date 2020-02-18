package UserStats;

use strict;
use warnings;
use vars qw(@ISA @EXPORT @EXPORT_OK);
our @EXPORT = qw(GetAllMonthsInYear GetUserStatsYears CreateUserStatsData
                 CreateUserStatsReport);

my %TITLES = ('pd' => 'PD Reviews', 'ic' => 'IC Reviews',
              'und' => 'UND Reviews', 'total' => 'Total Reviews',
              'valid' => 'Validated Reviews', 'neutral' => 'Neutral Reviews',
              'invalid' => 'Invalidated Reviews',
              'ainvalid' => 'Average Invalidated Reviews',
              'time' => 'Time Reviewing (mins)',
              'tpr' => 'Time per Review (mins)', 'rph' => 'Reviews per Hour',
              'outliers' => 'Outlier Reviews');

# Returns an array of date strings e.g. ('2009-01'...'2009-12') for the (current if no param) year.
sub GetAllMonthsInYear
{
  my $self = shift;
  my $year = shift;

  my ($currYear, $currMonth) = $self->GetTheYearMonth();
  $year = $currYear unless $year;
  my $start = 1;
  my @months = ();
  foreach my $m ($start..12)
  {
    my $ym = sprintf("$year-%.2d", $m);
    last if $ym gt "$currYear-$currMonth";
    push @months, $ym;
  }
  return @months;
}

sub GetUserStatsProjects
{
  my $self = shift;
  my $user = shift || 0;

  my $usersql = '';
  my @params;
  if ($user)
  {
    if ($user =~ m/^\d+$/)
    {
      my @users = map {$_->{'id'};} @{$self->GetInstitutionReviewers($user)};
      return () unless scalar @users;
      $usersql = ' WHERE us.user IN '. $self->WildcardList(scalar @users);
      push @params, $_ for @users;
    }
    else
    {
      $usersql = ' WHERE us.user=?';
      push @params, $user;
    }
  }
  my $sql = 'SELECT DISTINCT us.project FROM userstats us'.
            ' INNER JOIN users u ON us.user=u.id'.
            ' INNER JOIN institutions i ON u.institution=i.id '.
            $usersql. ' ORDER BY project ASC';
  my $ref = $self->SelectAll($sql, @params);
  return map {$_->[0];} @{$ref};
}

# Ordered from newest to oldest.
sub GetUserStatsYears
{
  my $self = shift;
  my $user = shift || 0; # undef for everyone, institution id, or user id
  my $proj = shift;

  my ($usersql, $projsql) = ('', '');
  my @params;
  if ($user)
  {
    if ($user =~ m/^\d+$/)
    {
      $usersql = ' AND u.institution=? ';
      push @params, $user;
    }
    else
    {
      $usersql = ' AND us.user=? ';
      push @params, $user;
    }
  }
  if ($proj)
  {
    $projsql = ' AND us.project=? ';
    push @params, $proj;
  }
  my $sql = 'SELECT DISTINCT us.year FROM userstats us'.
            ' INNER JOIN users u ON us.user=u.id' .
            ' WHERE us.total_reviews>0 '.
            $usersql. $projsql. ' ORDER BY year DESC';
  my $ref = $self->SelectAll($sql, @params);
  my @years = map {$_->[0];} @{$ref};
  return @years;
}

# Returns arrayref of arrayrefs, each being a structure with keys in
# (user,year,proj,id,old) for calls to CreateUserStatsReport for individual users.
sub GetUserStatsQueryParams
{
  my $self    = shift;
  my $user    = shift || 0; # 0 for everyone, institution id, or user id
  my $year    = shift || 0; # 0 for year-by-year, year for month-by-month
  my $project = shift || 0; # 0 for all projects, project id for project

  my $thisyear = $self->GetTheYear();
  my @params;
  my @users = ($user);
  my @years = ($year);
  if ($user eq '0')
  {
    @users = (undef);
    my $sql = 'SELECT id FROM institutions ORDER BY name ASC';
    foreach my $row (@{$self->SelectAll($sql)})
    {
      my $inst = $row->[0];
      push @users, $inst;
      push @users, $_->{'id'} for @{$self->GetInstitutionReviewers($inst)};
    }
  }
  elsif ($user =~ m/^\d+$/)
  {
    @users = map {$_->{'id'};} @{$self->GetInstitutionReviewers($user)};
    unshift @users, $user;
  }
  foreach my $user (@users)
  {
    my @projects = GetUserStatsProjects($self, $user);
    unshift @projects, undef if !$project and scalar @projects > 1;
    foreach my $proj (@projects)
    {
      my $old = 0;
      if (!$project || !$proj || $project == $proj)
      {
        @years = GetUserStatsYears($self, $user, $proj) unless $year;
        foreach my $year2 (@years)
        {
          my $divid = join '_', ($user || 'user', $year2 || 'year', $proj || 'proj');
          $divid =~ s/@//g;
          push @params, {'user' => $user, 'year' => $year2, 'proj' => $proj,
                         'id' => $divid, 'old' => $old};
          $old = 1 if defined $year2 and $year2 le $thisyear;
        }
      }
    }
  }
  return \@params;
}

# Returns a hashref with the following fields:
# title - string
# columns - arrayref of column names
# rows - arrayref of row names
# stats - hashref of keys (from columns) to arrayref of period numbers
# active - number of active reviews
sub CreateUserStatsData
{
  my $self    = shift;
  my $user    = shift || 0; # 0 for everyone, institution id, or user id
  my $year    = shift || 0; # 0 for year-by-year, year for month-by-month
  my $project = shift || 0; # 0 for all projects, project id for project

  my %data;
  my @dates = ($year)? GetAllMonthsInYear($self, $year) :
                       reverse GetUserStatsYears($self, $user);
  unshift @dates, 'TOTAL' if $year;
  unshift @dates, 'CRMS_TOTAL';
  $data{'columns'} = \@dates;
  $data{'rows'} = ['pd', 'ic', 'und', 'total', 'valid', 'neutral', 'invalid',
                   'time', 'tpr', 'rph', 'outliers'];
  $data{'display_rows'} = ['pd', 'ic', 'und', 'total', 'valid', 'neutral', 'invalid',
                           'ainvalid', 'time', 'tpr', 'rph', 'outliers'];
  #$data{'r2i'}->{$data{'rows'}->[$_]} = $_ for (0 .. scalar @{$data{'rows'}} - 1);
  #$data{'i2r'}->{$_} = $data{'rows'}->[$_] for (0 .. scalar @{$data{'rows'}} - 1);
  $data{'stats'}->{$_} = [] for @{$data{'rows'}};
  $data{'active'} = 0;
  my ($username, $projname);
  my @users;
  my ($userclause, $projclause) = ('1=1', '1=1');
  if ($user eq '0')
  {
    $username = 'All Reviewers';
  }
  elsif ($user =~ m/^\d+$/)
  {
    $username = $self->GetInstitutionName($user). ' Reviewers';
    @users = ($user);
    $userclause = 'i.id=?';
  }
  else
  {
    $username = $self->GetUserProperty($user, 'name');
    my $inst = $self->GetUserProperty($user, 'institution');
    my $iname = $self->GetInstitutionName($inst);
    $username .= ' ('. $iname. ' &#x2014; '. $user. ')';
    @users = ($user);
    $userclause = 'us.user=?';
  }
  if ($project)
  {
    $projname = $self->GetProjectRef($project)->{'name'};
    $projclause = 'us.project=?';
  }
  else
  {
    $projname = 'All Projects';
  }
  $username .= ', '. $projname;
  $data{'title'} = $username. ': '. (($year)? $year:'Totals');
  my $sql = 'SELECT SUM(us.total_pd),SUM(us.total_ic),SUM(us.total_und),'.
            'SUM(us.total_reviews),SUM(us.total_correct),SUM(us.total_neutral),'.
            'SUM(us.total_incorrect),SUM(us.total_time),'.
            'SUM(us.total_time)/(SUM(us.total_reviews)-SUM(us.total_outliers)),'.
            '(SUM(us.total_reviews)-SUM(us.total_outliers))/SUM(us.total_time)*60.0,'.
            'SUM(total_outliers)'.
            ' FROM userstats us INNER JOIN users u ON us.user=u.id'.
            ' INNER JOIN institutions i ON u.institution=i.id';
  my $ivsql = 'SELECT COALESCE(SUM(us.total_reviews),0),'.
              'COALESCE(SUM(us.total_incorrect),0)'.
              ' FROM userstats us';
  #print "$sql<br/>\n";
  foreach my $date (@dates)
  {
    my $tclause = '1=1';
    my @args;
    if ($date eq 'TOTAL')
    {
      $tclause = 'year=?';
      push @args, $year;
    }
    elsif ($date eq 'CRMS_TOTAL') {}
    else
    {
      $tclause = ($date =~ m/^\d\d\d\d$/)? 'year=?':'monthyear=?';
      push @args, $date;
    }
    push @args, $project if $project;
    my $sql2 = $ivsql. ' WHERE '. $tclause. ' AND '. $projclause;
    my $rows = $self->SelectAll($sql2, @args);
    foreach my $row (@{$rows})
    {
      my $pct = 0.0;
      eval { $pct = $row->[1] / $row->[0] * 100.0; };
      push @{$data{'stats'}->{'ainvalid'}}, $pct;
    }
    push @args, @users;
    my $sql3 = $sql. ' WHERE '. $tclause. ' AND '. $projclause. ' AND '. $userclause;
    $rows = $self->SelectAll($sql3, @args);
    foreach my $row (@{$rows})
    {
      foreach my $i (0 .. scalar @{$data{'rows'}} - 1)
      {
        push @{$data{'stats'}->{$data{'rows'}->[$i]}}, ($row->[$i] || 0);
      }
    }
  }
  my @args;
  push @args, $user if $user ne '0';
  $sql = 'SELECT COUNT(*) FROM reviews us INNER JOIN queue q ON us.id=q.id'.
         ' INNER JOIN users u ON us.user=u.id'.
         ' INNER JOIN institutions i ON u.institution=i.id'.
         ' WHERE '. $userclause;
  if ($project)
  {
    $sql .= ' AND q.project=?';
    push @args, $project;
  }
  $data{'active'} = $self->SimpleSqlGet($sql, @args);
  return \%data;
}

sub CreateUserStatsReport
{
  my $self    = shift;
  my $user    = shift || 0; # 0 for everyone, institution id, or user id
  my $year    = shift || 0; # 0 for year-by-year, year for month-by-month
  my $project = shift || 0; # 0 for all projects, project id for project
  my $active  = shift || 0; # Show active reviews (only if current year)

  my $data = CreateUserStatsData($self, $user, $year, $project);
  my $nbsps = '&nbsp;&nbsp;&nbsp;&nbsp;';
  $data->{'html'} = "<table class='exportStats'>\n<tr>\n<th></th>";
  $data->{'text'} = "\t";
  my @cols = map {($_ eq 'CRMS_TOTAL')? 'CRMS Total':(($_ eq 'TOTAL')? 'Total '. $year:$_)} @{$data->{'columns'}};
  $data->{'text'} .= join "\t", @cols;
  foreach my $th (@cols)
  {
    $th = $self->YearMonthToEnglish($th) if $th =~ m/^\d\d\d\d-\d\d$/;
    $th =~ s/\s/&nbsp;/g;
    $data->{'html'} .= "<th style='text-align:center;'>$th</th>\n";
  }
  $data->{'html'} .= "</tr>\n";
  my %classes = ('pd' => 'major', 'ic' => 'major', 'und' => 'major',
                 'total' => 'major', 'valid' => 'total', 'neutral' => 'total',
                 'invalid' => 'total', 'ainvalid' => 'purple',
                 'time' => 'minor', 'tpr' => 'minor',
                 'rph' => 'minor', 'outliers' => 'minor');
  foreach my $row (@{$data->{'display_rows'}})
  {
    next if $row eq 'ainvalid' and not $user;
    my $title = $TITLES{$row};
    $data->{'text'} .= "\n". $title;
    my $class = $classes{$row} || '';
    $title =~ s/\s/&nbsp;/g;
    my $padding = ($class eq 'major' || $class eq 'minor' || $class eq 'total')? '':$nbsps;
    my $style = '';
    $style = ' style="text-align:right;"' if $class eq 'total';
    $data->{'html'} .= '<tr>';
    $data->{'html'} .= sprintf("<th$style><span%s>$padding$title</span></th>\n", ($class)? " class='$class'":'');
    my $i = 0;
    foreach my $n (@{$data->{'stats'}->{$row}})
    {
      my $pct;
      if ($row eq 'pd' || $row eq 'ic' || $row eq 'und' ||
          $row eq 'valid' || $row eq 'neutral' || $row eq 'invalid')
      {
        my $total = $data->{'stats'}->{'total'}->[$i];
        $pct = ($total>0)? (sprintf '%.1f', $n/$total*100.0):'';
      }
      my $val = $n;
      $val = sprintf '%.1f', $n if $row eq 'tpr' or $row eq 'rph';
      $val = sprintf '%.1f%%', $n if $row eq 'ainvalid';
      $val =~ s/\s/&nbsp;/g;
      my $astart = '';
      my $aend = '';
      if (($row eq 'invalid' || $row eq 'neutral') && $n > 0 &&
          defined $user && length $user && $user !~ m/^\d+$/)
      {
        my $date = $data->{'columns'}->[$i];
        my $url = URLForHistoricalVerdicts($self, $user, $year, $project, $date, ($row eq 'invalid')? 0:2);
        if ($url)
        {
          $astart = "<a href='$url' target='_blank'>";
          $aend = '</a>';
        }
      }
      $data->{'html'} .= sprintf("  <td%s%s>$astart%s%s$aend</td>\n",
                         ($class)? " class='$class'":'',
                         ' style="text-align:center;"',
                         ($row eq 'total')? "<strong>$val</strong>":$val,
                         ($pct)? "&nbsp;($pct%)":'');
      $data->{'text'} .= "\t$val";
      $i++;
    }
    $data->{'html'} .= "</tr>\n";
  }
  if ($active)
  {
    $data->{'html'} .= '<tr><th style="text-align:right;"><span class="total">Active Reviews</span></th>'. "\n";
    $data->{'html'} .= '<td class="total" style="text-align:center;" colspan="'. scalar @cols. '">'. $data->{'active'}. "\n";
    $data->{'html'} .= '</td></tr>'. "\n";
  }
  $data->{'html'} .= "</table>\n";
  return $data;
}

sub URLForHistoricalVerdicts
{
  my $self    = shift;
  my $user    = shift;
  my $year    = shift;
  my $project = shift;
  my $date    = shift;
  my $verdict = shift; # 0 or 2

  use Date::Calc;
  my $start = '';
  my $end = '';
  if ($date =~ m/^(\d\d\d\d)-(\d\d)$/)
  {
    $start = $date. '-01';
    $end = $date. '-'. Date::Calc::Days_in_Month($1, $2);
  }
  elsif (($date =~ m/^\d\d\d\d$/ || $date eq 'TOTAL') && $year)
  {
    $start = $year. '-01-01';
    $end = $year. '-12-'. Date::Calc::Days_in_Month($year, 12);
  }
  my $proj = '';
  $proj = $self->GetProjectRef($project)->{'name'} if $project;
  my $url = 'crms?p=adminHistoricalReviews;stype=groups;'.
            "search1=UserId&search1value=$user;".
            "search2=Validated;search2value=$verdict;".
            "search3=Project;search3value=$proj;".
            "startDate=$start;endDate=$end;order=Date;dir=ASC";
  return $self->WebPath('cgi', $url);
}

1;
