package Utilities;

use strict;
use warnings;

sub HexDump
{
  $_ = shift;

  my $offset = 0;
  my(@array,$format);
  my $dump = '';
  foreach my $data (unpack("a16"x(length($_[0])/16)."a*",$_[0]))
  {
    my($len)=length($data);
    if ($len == 16)
    {
      @array = unpack('N4', $data);
      $format="0x%08x (%05d)   %08x %08x %08x %08x   %s\n";
    }
    else
    {
      @array = unpack('C*', $data);
      $_ = sprintf "%2.2x", $_ for @array;
      push(@array, '  ') while $len++ < 16;
      $format="0x%08x (%05d)" .
           "   %s%s%s%s %s%s%s%s %s%s%s%s %s%s%s%s   %s\n";
    }
    $data =~ tr/\0-\37\177-\377/./;
    $dump .= sprintf $format,$offset,$offset,@array,$data;
    $offset += 16;
  }
  return $dump;
}

sub StringifySql
{
  my $sql = shift;

  return $sql . ' (' . (join ',', @_). ')';
}

sub AppendParam
{
  my $url  = shift;
  my $name = shift;
  my $val  = shift;

  if ($url !~ m/$name=$val/i)
  {
    $url .= '?' unless $url =~ m/\?/;
    $url .= ';' unless $url =~ m/[;?]$/;
    $url .= $name. '='. $val;
  }
  return $url;
}

sub ClearArrays
{
  @{$_} = () for @_;
}

sub HSV2RGB
{
  use POSIX;
  my ($h, $s, $v) = @_;
  if ($s == 0) { return $v, $v, $v; }
  $h /= 60;
  my $i = floor( $h );
  my $f = $h - $i;
  my $p = $v * ( 1 - $s );
  my $q = $v * ( 1 - $s * $f );
  my $t = $v * ( 1 - $s * ( 1 - $f ) );
  if ($i == 0 ) { return $v, $t, $p; }
  elsif ($i == 1) { return $q, $v, $p; }
  elsif ($i == 2) { return $p, $v, $t; }
  elsif ($i == 3) { return $p, $q, $v; }
  elsif ($i == 4) { return $t, $p, $v; }
  else { return $v, $p, $q; }
}

sub StackTrace
{
  my ($path, $line, $subr);
  my $max_depth = 30;
  my $i = 1;
  my $trace = "--- Begin stack trace ---\n";
  while ((my @call_details = (caller($i++))) && ($i<$max_depth))
  {
    $trace .= "$call_details[1] line $call_details[2] in function $call_details[3]\n";
  }
  return $trace . "--- End stack trace ---\n";
}

return 1;
