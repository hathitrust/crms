package Graph;

use strict;
use warnings;
use Utilities;

sub CreateExportGraph
{
  my $self  = shift;

  my %data = ('chart'=>{'type'=>'spline'}, 'title'=>{'text'=>undef},
              'tooltip'=>{'pointFormat'=>'<strong>{point.y}</strong>'},
              'xAxis'=>{'categories'=>[], 'labels'=>{'rotation'=>45}},
              'yAxis'=>{'min'=>0, 'title'=>{'text'=>'Volumes'}},
              'legend'=>{'enabled'=>JSON::XS::false},
              'credits'=>{'enabled'=>JSON::XS::false},
              'series'=>[{'name'=>'Exports', 'data'=>[]}]);
  my $sql = 'SELECT DATE_FORMAT(date,"%b %Y") AS fmt,SUM(count) FROM exportstats'.
            ' GROUP BY DATE_FORMAT(date,"%Y-%m")';
  my $ref = $self->SelectAll($sql);
  foreach my $row (@{$ref})
  {
    push @{$data{'xAxis'}->{'categories'}}, $row->[0];
    push @{$data{'series'}->[0]->{'data'}}, int($row->[1]);
  }
  return \%data;
}

sub CreateExportBreakdownGraph
{
  my $self  = shift;

  my %data = ('chart'=>{'type'=>'spline'}, 'title'=>{'text'=>undef},
              'tooltip'=>{'pointFormat'=>'<strong>{point.y}</strong>'},
              'xAxis'=>{'categories'=>[], 'labels'=>{'rotation'=>45}},
              'yAxis'=>{'min'=>0, 'title'=>{'text'=>'Volumes'}},
              'legend'=>{'enabled'=>JSON::XS::true},
              'credits'=>{'enabled'=>JSON::XS::false},
              'series'=>[{'name'=>'All PD', 'data'=>[]},{'name'=>'All IC', 'data'=>[]},{'name'=>'All UND', 'data'=>[]}]);
  my $sql = 'SELECT DISTINCT DATE_FORMAT(DATE(time),"%b %Y") FROM exportdata ORDER BY DATE(time) ASC';
  my $ref = $self->SelectAll($sql);
  my @colors = PickColors(3, 1);
  $data{'series'}->[$_]->{'color'} = $colors[$_] for (0..2);
  foreach my $row (@{$ref})
  {
    my $t = $row->[0];
    push @{$data{'xAxis'}->{'categories'}}, $t;
    $sql = 'SELECT COALESCE(SUM(count),0) FROM exportstats'.
           ' WHERE (attr="pd" OR attr="pdus") AND DATE_FORMAT(date, "%b %Y")=?';
    my $n = $self->SimpleSqlGet($sql, $t);
    push @{$data{'series'}->[0]->{'data'}}, int($n);
    $sql = 'SELECT COALESCE(SUM(count),0) FROM exportstats'.
           ' WHERE (attr="ic" OR attr="icus") AND DATE_FORMAT(date, "%b %Y")=?';
    $n = $self->SimpleSqlGet($sql, $t);
    push @{$data{'series'}->[1]->{'data'}}, int($n);
    $sql = 'SELECT COALESCE(SUM(count),0) FROM exportstats'.
           ' WHERE attr="und" AND DATE_FORMAT(date, "%b %Y")=?';
    $n = $self->SimpleSqlGet($sql, $t);
    push @{$data{'series'}->[2]->{'data'}}, int($n);
  }
  return \%data;
}

sub CreateDeterminationsBreakdownGraph
{
  my $self  = shift;

  my %data = ('chart'=>{'type'=>'spline'}, 'title'=>{'text'=>undef},
              'tooltip'=>{'pointFormat'=>'<strong>{point.y}</strong>'},
              'xAxis'=>{'categories'=>[], 'labels'=>{'rotation'=>45}},
              'yAxis'=>{'min'=>0, 'title'=>{'text'=>'Volumes'}},
              'legend'=>{'enabled'=>JSON::XS::true},
              'credits'=>{'enabled'=>JSON::XS::false},
              'series'=>[]);
  my @titles = ('Status 4', 'Status 5', 'Status 6', 'Status 7', 'Status 8', 'Status 9');
  my @colors = PickColors(scalar @titles, 1);
  my $i = 0;
  foreach my $title (@titles)
  {
    my $h = {'color'=>$colors[$i], 'name'=>$title, 'data'=>[]};
    push @{$data{'series'}}, $h;
    $i++;
  }
  $data{'series'}->[$_]->{'color'} = $colors[$_] for (0..2);
  my $sql = 'SELECT DATE_FORMAT(date,"%b %Y") AS fmt,SUM(s4),SUM(s5),SUM(s6),SUM(s7),SUM(s8),SUM(s9)'.
            ' FROM determinationsbreakdown'.
            ' GROUP BY fmt ORDER BY date ASC';
  my $ref = $self->SelectAll($sql);
  foreach my $row (@{$ref})
  {
    push @{$data{'xAxis'}->{'categories'}}, $row->[0];
    push(@{$data{'series'}->[$_]->{'data'}}, int($row->[$_+1])) for (0..5);
  }
  return \%data;
}

sub CreateCandidatesData
{
  my $self = shift;

  my $cnt = $self->GetCandidatesSize();
  my $sql = 'SELECT cd.ym,cd.cnt,ed.cnt FROM' .
            ' (SELECT EXTRACT(YEAR_MONTH FROM c.time) AS ym,SUM(c.addedamount) AS cnt FROM candidatesrecord c GROUP BY ym) cd' .
            ' RIGHT JOIN' .
            ' (SELECT EXTRACT(YEAR_MONTH FROM e.time) AS ym,COUNT(e.id) AS cnt FROM exportdata e' .
            '  WHERE e.src="candidates" OR src="inherited" GROUP BY EXTRACT(YEAR_MONTH FROM e.time)) ed' .
            ' ON (ed.ym=cd.ym) ORDER BY cd.ym DESC';
  my $ref = $self->SelectAll($sql);
  my $report = '';
  foreach my $row (@{$ref})
  {
    my $ym = $row->[0];
    my $added = $row->[1];
    my $exported = $row->[2];
    $exported = 0 unless $exported;
    #print "$ym $added $exported\n";
    $ym = $self->YearMonthToEnglish(substr($ym, 0, 4) . '-' . substr($ym, 4, 2));
    $report = "$ym\t$cnt\n" . $report;
    $cnt -= $added;
    $cnt += $exported;
  }
  return "Volumes in Candidates\n" . $report;
}

sub CreateCandidatesGraph
{
  my $self  = shift;

  my %data = ('chart'=>{'type'=>'spline'}, 'title'=>{'text'=>undef},
              'tooltip'=>{'pointFormat'=>'<strong>{point.y}</strong>'},
              'xAxis'=>{'categories'=>[], 'labels'=>{'rotation'=>45}},
              'yAxis'=>{'min'=>0, 'title'=>{'text'=>'Volumes'}},
              'legend'=>{'enabled'=>JSON::XS::false},
              'credits'=>{'enabled'=>JSON::XS::false},
              'series'=>[{'name'=>'Candidates', 'data'=>[]}]);
  my $data = CreateCandidatesData($self);
  my @lines = split m/\n/, $data;
  shift @lines;
  my @titles;
  my @vals;
  foreach my $line (@lines)
  {
    my ($ym,$val) = split "\t", $line;
    push @titles, $ym;
    push @vals, $val;
  }
  foreach my $i (0 .. scalar @vals - 1)
  {
    push @{$data{'xAxis'}->{'categories'}}, $titles[$i];
    push @{$data{'series'}->[0]->{'data'}}, int($vals[$i]);
  }
  return \%data;
}

sub CreateExportsPieChart
{
  my $self  = shift;

  my %data = ('chart'=>{'type'=>'pie'}, 'title'=>{'text'=>undef},
              'tooltip'=>{'pointFormat'=>'<strong>{point.percentage:.1f}%</strong><br/>({point.y})'},
              'plotOptions'=>{'pie'=>{'cursor'=>'pointer', size=>'70%',
                                      'dataLabels'=>{'enabled'=>JSON::XS::true,'format'=>'{point.name}'},
                                      'colors'=>[]}},
              'series'=>[{'name'=>'Exports', 'data'=>[]}]);
  my $sql = 'SELECT SUBSTRING(attr,1,2) AS rights,SUM(count) FROM exportstats'.
            ' GROUP BY rights ORDER BY rights="pd" DESC';
  my $ref = $self->SelectAll($sql);
  my $i = 0;
  my @colors = PickColors(scalar @{$ref}, 1);
  foreach my $row (@{$ref})
  {
    my $attr = $row->[0];
    $attr = 'und' if $attr eq 'un';
    my $n = $row->[1];
    my %h = ('y'=>int($n), 'name'=>$attr);
    push @{$data{'series'}->[0]->{'data'}}, \%h;
    push @{$data{'plotOptions'}->{'pie'}->{'colors'}}, $colors[$i];
    $i++;
  }
  return \%data;
}

sub CreateCountriesGraph
{
  my $self  = shift;
  my %data = ('chart'=>{'type'=>'pie'}, 'title'=>{'text'=>undef},
              'tooltip'=>{'pointFormat'=>'<strong>{point.percentage:.1f}%</strong><br/>({point.y})'},
              'plotOptions'=>{'pie'=>{'cursor'=>'pointer', size=>'70%',
                                     'dataLabels'=>{'enabled'=>'false','format'=>'{point.name}'},
                                     'colors'=>[]}},
              'series'=>[{'name'=>'Institutions', 'data'=>[]}]);
  my $sql = 'SELECT b.country,COUNT(e.id) AS cnt FROM bibdata b INNER JOIN exportdata e ON b.id=e.id' .
            ' WHERE (b.country="United Kingdom" OR b.country="Canada" OR b.country="Australia")' .
            ' AND e.exported=1 GROUP BY b.country';
  my $ref = $self->SelectAll($sql);
  my @colors = PickColors(3);
  my $i = 0;
  foreach my $row (@{$ref})
  {
    my $country = $row->[0];
    last unless defined $country;
    my $n = $row->[1];
    my %h = ('y'=>int($n), 'name'=>$country);
    push @{$data{'series'}->[0]->{'data'}}, \%h;
    push @{$data{'plotOptions'}->{'pie'}->{'colors'}}, $colors[$i];
    $i++;
  }
  return \%data;
}

sub CreateUndGraph
{
  my $self  = shift;

  my %data = ('chart'=>{'type'=>'pie'}, 'title'=>{'text'=>''},
              'tooltip'=>{'pointFormat'=>'<strong>{point.percentage:.1f}%</strong><br/>({point.y})'},
              'plotOptions'=>{'pie'=>{'cursor'=>'pointer', size=>'70%',
                                      'dataLabels'=>{'enabled'=>JSON::XS::true,'format'=>'{point.name}'},
                                      'colors'=>[]}},
              'series'=>[{'name'=>'Institutions', 'data'=>[]}]);
  my $sql = 'SELECT src,COUNT(id) FROM und GROUP BY src ORDER BY src ASC';
  my $ref = $self->SelectAll($sql);
  my @colors = PickColors(scalar @{$ref}, 1);
  my $i = 0;
  foreach my $row (@{$ref})
  {
    my $src = $row->[0];
    my $n = $row->[1];
    my %h = ('y'=>int($n), 'name'=>$src);
    push @{$data{'series'}->[0]->{'data'}}, \%h;
    push @{$data{'plotOptions'}->{'pie'}->{'colors'}}, $colors[$i];
    $i++
  }
  return \%data;
}

sub CreateNamespaceGraph
{
  my $self = shift;

  my %data = ('chart'=>{'type'=>'column'}, 'title'=>{'text'=>undef},
              'tooltip'=>{'pointFormat'=>'<strong>{point.y}</strong>'},
              'xAxis'=>{'type'=>'category', 'labels'=>{'rotation'=>45}},
              'yAxis'=>{'min'=>0, 'title'=>{'text'=>'Determinations'}},
              'legend'=>{'enabled'=>JSON::XS::false},
              'credits'=>{'enabled'=>JSON::XS::false},
              'series'=>[{'name'=>'Namespace', 'data'=>[]}]);
  my @data;
  foreach my $ns (sort $self->Namespaces())
  {
    my $sql = 'SELECT COUNT(DISTINCT id) FROM exportdata WHERE id LIKE "' . $ns . '.%"';
    my $n = $self->SimpleSqlGet($sql);
    next unless $n;
    push @data, [$ns,$n];
  }
  @data = sort {$b->[1] <=> $a->[1]} @data;
  @data = @data[0 .. 9] if scalar @data > 10;
  my @labels = map {$_->[0]} @data;
  my @vals = map {$_->[1]} @data;
  foreach my $i (0 .. scalar @vals - 1)
  {
    push @{$data{'series'}->[0]->{'data'}}, [$labels[$i], int($vals[$i])];
  }
  return \%data;
}

sub CreateReviewInstitutionGraph
{
  my $self  = shift;

  my %data = ('chart'=>{'type'=>'pie'}, 'title'=>{'text'=>undef},
              'tooltip'=>{'pointFormat'=>'<strong>{point.percentage:.1f}%</strong><br/>({point.y})'},
              'plotOptions'=>{'pie'=>{'cursor'=>'pointer', size=>'70%',
                                     'dataLabels'=>{'enabled'=>JSON::XS::true,'format'=>'{point.name}'},
                                     'colors'=>[]}},
              'series'=>[{'name'=>'Institutions', 'data'=>[]}]);
  my $sql = 'SELECT i.shortname,COUNT(h.id) AS n FROM historicalreviews h'.
            ' INNER JOIN users u ON h.user=u.id'.
            ' INNER JOIN institutions i ON u.institution=i.id WHERE h.legacy=0'.
            ' AND h.user!="autocrms" GROUP BY i.shortname ORDER BY n DESC';
  my $ref = $self->SelectAll($sql);
  my $i = 0;
  my @colors = PickColors(scalar @{$ref}, 1);
  foreach my $row (@{$ref})
  {
    my $inst = $row->[0];
    my $n = $row->[1];
    my %h = ('y'=>int($n), 'name'=>$inst);
    push @{$data{'series'}->[0]->{'data'}}, \%h;
    push @{$data{'plotOptions'}->{'pie'}->{'colors'}}, $colors[$i];
    $i++;
  }
  return \%data;
}

sub CreateReviewerGraph
{
  my $self  = shift;
  my $type  = shift || 1;
  my $start = shift;
  my $end   = shift;
  my @users = @_;

  return CreateFlaggedGraph($self, @users) if $type == 3;
  my %data = ('chart'=>{'type'=>'spline'}, 'title'=>{'text'=>undef},
              'tooltip'=>{'pointFormat'=>'{series.name}: <strong>{point.y}</strong>'},
              'xAxis'=>{'categories'=>[], 'labels'=>{'rotation'=>45}},
              'yAxis'=>{'min'=>0, 'title'=>{'text'=>'Volumes'}},
              'legend'=>{'enabled'=>JSON::XS::true},
              'credits'=>{'enabled'=>JSON::XS::false},
              'series'=>[]);
  $start =~ s/(\d\d\d\d-\d\d)-\d\d/$1/ if defined $start;
  $end =~ s/(\d\d\d\d-\d\d)-\d\d/$1/ if defined $end;
  $start = $self->SimpleSqlGet('SELECT MIN(monthyear) FROM userstats') unless $start;
  $end = $self->SimpleSqlGet('SELECT MAX(monthyear) FROM userstats') unless $end;
  my %users;
  my %titles = (0=>'Review Count', 1=>'Time Reviewing',
                2=>'Invalidation Rate', 3=>'Flagged Reviews');
  my %sel = (0=>'SUM(s.total_reviews)',
             1=>'SUM(s.total_time/60)',
             2=>'ROUND(100*SUM(s.total_incorrect)/SUM(s.total_reviews),2)',
             3=>'SUM(s.total_flagged)');
  $type = 0 unless defined $titles{$type};
  my $title = $titles{$type};
  my $sql = 'SELECT DISTINCT monthyear FROM userstats WHERE monthyear>=? AND monthyear<=? ORDER BY monthyear ASC';
  #print "$sql, $start,  $end\n";
  my @dates;
  my $ref = $self->SelectAll($sql, $start, $end);
  foreach my $row (@{$ref})
  {
    my $date = $row->[0];
    push @dates, $date;
    push @{$data{'xAxis'}->{'categories'}}, $self->YearMonthToEnglish($date);
  }
  my $i = 0;
  $data{'yAxis'}->{'title'}->{'text'} = $title;
  $data{'yAxis'}->{'labels'}->{'format'} = '{value}%' if $type == 2;
  $data{'tooltip'}->{'pointFormat'} = '{series.name}: <strong>{point.y}%</strong>' if $type == 2;
  my @colors = PickColors(scalar @users);
  foreach my $user (@users)
  {
    my $ids = $self->GetUserIncarnations($user);
    my $name = $self->GetUserProperty($user, 'name');
    my $comm = $self->SimpleSqlGet('SELECT commitment FROM users WHERE id=?', $user);
    my @counts; # For the inval rate tip
    my $wc = $self->WildcardList(scalar @{$ids});
    my $h = {'color'=>$colors[$i], 'name'=>$name, 'data'=>[]};
    push @{$data{'series'}}, $h;
    foreach my $date (@dates)
    {
      my $sql = 'SELECT ' . $sel{$type} . ' FROM userstats s'.
                ' WHERE s.monthyear=? AND s.user IN '. $wc;
      my $val = $self->SimpleSqlGet($sql, $date, @{$ids});
      $val = 0 unless $val;
      my $count = 0;
      if ($type == 2)
      {
        $sql = 'SELECT SUM(s.total_reviews) FROM userstats s'.
               ' WHERE s.monthyear=? AND s.user IN '. $wc;
        $count = $self->SimpleSqlGet($sql, $date, @{$ids});
      }
      if ($type == 1)
      {
        $sql = 'SELECT COALESCE(SUM(TIME_TO_SEC(r.duration)),0)/3600.0 from reviews r'.
               ' INNER JOIN users u ON r.id=u.id'.
               ' WHERE CONCAT(YEAR(DATE(r.time)),"-",MONTH(DATE(r.time)))=?'.
               ' AND r.user IN '. $wc;
        $val += $self->SimpleSqlGet($sql, $date, @{$ids});
      }
      $val = int($val) if $type == 0;
      $val = $val + 0.0 if $type > 0;
      if ($type == 1 && defined $comm && 160.0*$comm <= $val)
      {
        $val = {'y'=>$val, 'marker'=>{'radius'=>8}};
      }
      elsif ($type == 2 && $val < 6.0 && $count > 0)
      {
        $val = {'y'=>$val, 'marker'=>{'radius'=>8}};
      }
      push @{$data{'series'}->[$i]->{'data'}}, $val;
    }
    $i++;
  }
  return \%data;
}

sub CreateFlaggedGraph
{
  my $self  = shift;
  my @users = @_;

  my %data = ('chart'=>{'type'=>'spline'}, 'title'=>{'text'=>undef},
              'tooltip'=>{'pointFormat'=>'{series.name}: <strong>{point.y}</strong>'},
              'xAxis'=>{'categories'=>[], 'labels'=>{'rotation'=>45}},
              'yAxis'=>{'min'=>0, 'title'=>{'text'=>'Volumes'}},
              'legend'=>{'enabled'=>JSON::XS::true},
              'credits'=>{'enabled'=>JSON::XS::false},
              'series'=>[],
              'users'=>[]);
  my $sql = 'SELECT DISTINCT DATE(time) d FROM historicalreviews'.
            ' WHERE time>=DATE_SUB(NOW(), INTERVAL 1 MONTH)'.
            ' AND user IN ('. join(',',map {"\"$_\"";} @users). ')'.
            ' ORDER BY d ASC';
  #print "$sql\n";
  my @dates;
  my $ref = $self->SelectAll($sql);
  foreach my $row (@{$ref})
  {
    my $date = $row->[0];
    push @dates, $date;
    push @{$data{'xAxis'}->{'categories'}}, $date;
  }
  my $i = 0;
  $data{'yAxis'}->{'title'}->{'text'} = 'Flagged Reviews';
  my @colors = PickColors(scalar @users);
  foreach my $user (@users)
  {
    my $ids = $self->GetUserIncarnations($user);
    my $name = $self->GetUserProperty($user, 'name');
    my $wc = $self->WildcardList(scalar @{$ids});
    my $h = {'color'=>$colors[$i], 'name'=>$name, 'data'=>[]};
    push @{$data{'series'}}, $h;
    foreach my $date (@dates)
    {
      my $sql = 'SELECT COUNT(id) FROM historicalreviews WHERE flagged IS NOT NULL'.
                ' AND flagged>0 AND DATE(time)=? AND user in '. $wc;
      my $val = int($self->SimpleSqlGet($sql, $date, @{$ids}));
      $val = 0 unless $val;
      push @{$data{'series'}->[$i]->{'data'}}, $val;
    }
    $i++;
  }
  return \%data;
}

sub CreateCandidatesGraph2
{
  my $self  = shift;

  my %data = ('chart'=>{'type'=>'spline'}, 'title'=>{'text'=>undef},
              'tooltip'=>{'pointFormat'=>'<strong>{point.y}</strong>'},
              'xAxis'=>{'categories'=>[], 'labels'=>{'rotation'=>45}},
              'yAxis'=>{'min'=>0, 'title'=>{'text'=>'Volumes'}},
              'legend'=>{'enabled'=>JSON::XS::false},
              'credits'=>{'enabled'=>JSON::XS::false},
              'series'=>[{'name'=>'Candidates', 'data'=>[]}]);
  my $sql = 'SELECT DATE(time),size FROM candidatessize'.
           ' WHERE DATE(time)=(SELECT MIN(DATE(time)) FROM candidatessize)'.
           ' OR DATE(time)=(SELECT MAX(DATE(time)) FROM candidatessize)'.
           ' OR DATE(time) LIKE "%-01"'.
           ' ORDER BY DATE(time) ASC';
  my $ref = $self->SelectAll($sql);
  my @titles;
  my @vals;
  foreach my $row (@{$ref})
  {
    my ($d,$cnt) = ($row->[0], $row->[1]);
    push @titles, $d;
    push @vals, $cnt;
  }
  foreach my $i (0 .. scalar @vals - 1)
  {
    push @{$data{'xAxis'}->{'categories'}}, $titles[$i];
    push @{$data{'series'}->[0]->{'data'}}, int($vals[$i]);
  }
  return \%data;
}

sub CreateCandidatesGraph3
{
  my $self  = shift;

  my %data = ('chart'=>{'type'=>'spline'}, 'title'=>{'text'=>undef},
              'tooltip'=>{'pointFormat'=>'<strong>{point.y}</strong>'},
              'xAxis'=>{'categories'=>[], 'labels'=>{'rotation'=>45}},
              'yAxis'=>{'min'=>0, 'title'=>{'text'=>'Volumes'}},
              'legend'=>{'enabled'=>JSON::XS::false},
              'credits'=>{'enabled'=>JSON::XS::false},
              'series'=>[{'name'=>'Candidates', 'data'=>[]}]);
  my $sql = 'SELECT DISTINCT(DATE(time)) FROM exportdata'.
           ' WHERE DATE(time)=(SELECT MIN(DATE(time)) FROM exportdata)'.
           ' OR DATE(time)=(SELECT MAX(DATE(time)) FROM exportdata)'.
           ' OR DATE(time) LIKE "%-01"'.
           ' ORDER BY DATE(time) DESC';
  my $size = $self->GetCandidatesSize();
  my $ref = $self->SelectAll($sql);
  my @titles;
  my @vals;
  my $i;
  push @titles, $ref->[0]->[0];
  push @vals, $size;
  #print "Starting size $size\n";
  foreach my $i (1 .. scalar @{$ref} - 2)
  {
    # second date is earlier
    $sql = 'SELECT COUNT(*) FROM exportdata WHERE DATE(time)>? AND DATE(time)<=? AND (src="candidates" OR src="cri" OR src="inherited")';
    my $cnt = $self->SimpleSqlGet($sql, $ref->[$i+1]->[0], $ref->[$i]->[0]);
    $size += $cnt;
    #printf "%s to %s: $cnt, size now $size\n", $ref->[$i+1]->[0], $ref->[$i]->[0];
    push @titles, $ref->[$i]->[0];
    push @vals, $size;
  }
  $sql = 'SELECT COUNT(*) FROM exportdata WHERE DATE(time)<=? AND (src="candidates" OR src="cri" OR src="inherited")';
  my $cnt = $self->SimpleSqlGet($sql, $ref->[scalar @{$ref}-2]->[0]);
  push @titles, $ref->[scalar @{$ref}-1]->[0];
  push @vals, $size+$cnt;
  @titles = reverse @titles;
  @vals = reverse @vals;
  foreach my $i (0 .. scalar @vals - 1)
  {
    push @{$data{'xAxis'}->{'categories'}}, $titles[$i];
    push @{$data{'series'}->[0]->{'data'}}, int($vals[$i]);
  }
  return \%data;
}

sub CreateProgressGraph
{
  my $self  = shift;

  my $sql = 'SELECT COUNT(*) FROM exportdata WHERE src="candidates" AND DATE(time)>"2016-10-01"';
  my $val = $self->SimpleSqlGet($sql);
  $sql = 'SELECT COUNT(*) FROM candidates';
  my $n = $self->SimpleSqlGet($sql);
  my $total = $val + $n;
  use Math::Round;
  my $max = Math::Round::nearest(100, $total);
  my $fmt = '<div style="text-align:center">'.
            '<span style="font-size:25px;color:black">{y} of '. $total. '</span><br/>'.
            '<span style="font-size:12px;color:silver">determinations</span></div>';
  my %data = ('chart'=>{'type'=>'solidgauge'},
              'title'=>{'text'=>'<span style="font-size:25px;color:black">October-December 2016</span><br/>'.
                                '<span style="font-size:25px;color:black">Final Stretch</span>'},
              'pane'=>{'center'=>['50%','85%'],
                       'size'=>'120%',
                       'startAngle'=>'-90',
                       'endAngle'=>'90',
                       'background'=>{'backgroundColor'=>'#EEE',
                                      'innerRadius'=>'60%',
                                      'outerRadius'=>'100%',
                                      'shape'=>'arc'}},
              'yAxis'=>{'stops'=>[[0.0, '#DF5353'],[0.5, '#DDDF0D'],[1.0, '#55BF3B']],
                        'min'=>0,
                        'max'=>$max,
                        'lineWidth'=>1,
                        'minorTickInterval'=>undef,
                        'tickInterval'=>500,
                        'tickWidth'=>1,
                        'title'=>{'y'=>-70},
                        'labels'=>{'y'=>16}},
              'plotOptions'=>{'solidgauge'=>{'dataLabels'=>{'y'=>5,'borderWidth'=>0,'useHTML'=>JSON::XS::true}}},
              'credits'=>{'enabled'=>JSON::XS::false},
              'series'=>[{'name'=>'Determinations',
                          'data'=>[int $val],
                          'dataLabels'=>{'format'=>$fmt},
                          }]);
  return \%data;
}

sub CreateInheritanceGraph
{
  my $self  = shift;

  my %data = ('chart'=>{'type'=>'spline'}, 'title'=>{'text'=>undef},
              'tooltip'=>{'pointFormat'=>'<strong>{point.y}</strong>'},
              'xAxis'=>{'categories'=>[], 'labels'=>{'rotation'=>45}},
              'yAxis'=>{'min'=>0, 'title'=>{'text'=>'Inheritances'}},
              'legend'=>{'enabled'=>JSON::XS::false},
              'credits'=>{'enabled'=>JSON::XS::false},
              'series'=>[{'name'=>'Exports', 'data'=>[]}]);
  my $sql = 'SELECT DATE_FORMAT(DATE(time),"%b %Y") AS fmt,COUNT(*) FROM exportdata'.
            ' WHERE src="inherited" GROUP BY DATE_FORMAT(DATE(time),"%Y-%m")';
  my $ref = $self->SelectAll($sql);
  foreach my $row (@{$ref})
  {
    push @{$data{'xAxis'}->{'categories'}}, $row->[0];
    push @{$data{'series'}->[0]->{'data'}}, int($row->[1]);
  }
  return \%data;
}

sub PickColors
{
  my $count   = shift;
  my $shuffle = shift;

  my @cols;
  my $delta = ($count>0)? 360/$count:360;
  for (my $hue = 109; $hue < 469; $hue += $delta)
  {
    my $h2 = $hue;
    $h2 -= 360 if $h2 >= 360;
    my @col = Utilities::HSV2RGB($h2, 1, .75);
    @col = map {int($_ * 255);} @col;
    push @cols, sprintf '#%02X%02X%02X', $col[0], $col[1], $col[2];
  }
  if ($shuffle)
  {
    my ($i,$j) = (1,2);
    while ($i <= scalar @cols-2)
    {
      @cols[$i,$j] = @cols[$j,$i];
      $i += 2;
      $j += 2;
    }
  }
  return @cols;
}

return 1;
