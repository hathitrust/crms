#!/usr/bin/perl

# This script can be run from crontab

my $DLXSROOT;
my $DLPS_DEV;
BEGIN
{
  $DLXSROOT = $ENV{'DLXSROOT'};
  $DLPS_DEV = $ENV{'DLPS_DEV'};
  unshift (@INC, $DLXSROOT . '/cgi/c/crms/');
}

use strict;
use CRMS;
use Getopt::Std;

my %opts;
my $ok = getopts('hpvx:', \%opts);

my $help       = $opts{'h'};
my $production = $opts{'p'};
my $verbose    = $opts{'v'};
my $sys        = $opts{'x'};

if ($help || !$ok)
{
  die "USAGE: $0 [-hpv] [-X SYS] [date]\n\n";
}
$DLPS_DEV = undef if $production;
my $crms = CRMS->new(
    logFile => "$DLXSROOT/prep/c/crms/gov_hist.txt",
    sys     => $sys,
    verbose => $verbose,
    root    => $DLXSROOT,
    dev     => $DLPS_DEV
);

my %confs = (
'ic/ren vs und/nfi' => '__',
'ic/ren vs pd/ren' => '__',
'ic/ren vs pd/cdpp' => '__',
'ic/ren vs ic/cdpp' => '__',
'pd/ren vs und/nfi' => '__',
'pd/ren vs pd/cdpp' => '__',
'pd/ren vs ic/cdpp' => '__',
'pd/ncn vs pd/ren' => '__',
'pd/ncn vs und/nfi' => '__',
'pd/ncn vs ic/ren' => '__',
'pd/ncn vs pd/cdpp' => '__',
'und/nfi vs pd/cdpp' => '__',
'und/nfi vs ic/cdpp' => '__',
'pd/cdpp vs ic/cdpp' => '__',
'ic/ren vs ic/ren' => '__'
);


my $sql = 'SELECT DISTINCT e.id,e.gid FROM exportdata e INNER JOIN historicalreviews r ' .
          'ON e.gid=r.gid WHERE r.status=5 AND r.time>="2010-05-01 00:00:00"';
my $r = $crms->SelectAll($sql);
my $n = 0;
foreach my $blah (@{$r})
{
  my $id = $blah->[0];
  my $gid = $blah->[1];
  my $ar1 = undef;
  #my $rn1 = undef;
  #my $rd1 = undef;
  my $ar2 = undef;
  #my $rn2 = undef;
  #my $rd2 = undef;
  my $are = undef;
  #my $rne = undef;
  #my $rde = undef;
  $sql = "SELECT attr,reason,renDate,renNum,expert FROM historicalreviews WHERE gid='$gid' ORDER BY time ASC";
  #print "$sql\n";
  my $r1 = $crms->SelectAll($sql);
  my $exp = 0;
  my $same = 1;
  foreach my $row (@{$r1})
  {
    my $attr = $row->[0];
    my $reason = $row->[1];
    my $renDate = $row->[2];
    my $renNum = $row->[3];
    my $expert = $row->[4];
    my $ar = $crms->GetAttrReasonCom($crms->GetCodeFromAttrReason($attr,$reason));
    if ($expert)
    {
      $are = $ar;
      #$rne = $renNum;
      #$rde = $renDate;
      last;
    }
    elsif (!$ar1)
    {
      $ar1 = $ar;
      #$rn1 = $renNum;
      #$rd1 = $renDate;
    }
    elsif (!$ar2)
    {
      $ar2 = $ar;
      #$rn2 = $renNum;
      #$rd2 = $renDate;
    }
  }
  if ($ar1 && $ar2 && $are)
  {
    my $key = "$ar1 vs $ar2";
    $key = "$ar2 vs $ar1" unless exists $confs{$key};
    #die "Can't find a key for $ar1 and $ar2 ($key)" unless exists $confs{$key};
    if (!exists $confs{$key})
    {
      print "?? $key for $id\n";
      next;
    }
    my $val = $confs{$key};
    $val = {'count' => 0} if $val eq '__';
    $val->{'count'}++;
    $val->{$are}++;
    $confs{$key} = $val;
    #print "$id\n" if $key eq 'pd/ncn vs pd/ren' and $are eq 'und/nfi';
  }
}
printf "Checked %d exported determinations\n", scalar @{$r};
my %cols = ();
foreach my $key (keys %confs)
{
  my $val = $confs{$key};
  next if $val eq '__';
  foreach my $final (keys %{ $val })
  {
    next if $final eq 'count';
    $cols{$final} = 1;
  }
}

printf "Conflict\tCount\t%s\n", join "\t", sort keys %cols;

foreach my $key (sort keys %confs)
{
  my $val = $confs{$key};
  $val = {'count' => 0} if $val eq '__';
  my $total = $val->{'count'};
  printf "$key\t%s", $total;
  foreach my $col (sort keys %cols)
  {
    my $cnt = $val->{$col};
    if ($cnt)
    {
      my $pct = 0.0;
      eval { $pct = 100.0*$cnt/$total; };
      printf "\t%d (%.1f%%)", $cnt, $pct;
    }
    else
    {
      print "\t";
    }
  }
  print "\n";
}

my $r = $crms->GetErrors();
foreach my $w (@{$r})
{
  print "Warning: $w\n";
}

