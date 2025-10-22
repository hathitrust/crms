package Graph;

use strict;
use warnings;
use Utilities;

sub CreateExportGraph
{
  my $self = shift;

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
  my $self = shift;

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
  my $self = shift;

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
  my $self = shift;

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
  my $self = shift;
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
  my $self = shift;

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
  my $self = shift;

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

# From Math::Round
sub NearestMultiple
{
  my $mult = abs(shift);
  my $n    = shift;

  my $half = 0.50000000000008;
  return ($n >= 0)? ($mult * int(($n + $half * $mult) / $mult)):
                    ($mult * POSIX::ceil(($n - $half * $mult) / $mult));
 }

return 1;
