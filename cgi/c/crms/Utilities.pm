package Utilities;

use strict;
use warnings;

sub HexDump
{
  my $dump = '';
  my $offset = 0;
        
  foreach my $chunk (unpack "(a16)*", $_[0])
  {
      my $hex = unpack "H*", $chunk; # hexadecimal magic
      $chunk =~ tr/ -~/./c;          # replace unprintables
      $hex   =~ s/(.{1,8})/$1 /gs;   # insert spaces
      $dump .= sprintf "0x%08x (%05u)  %-*s %s\n",
          $offset, $offset, 36, $hex, $chunk;
      $offset += 16;
  }
  return $dump;
}

sub StringifySql
{
  my $sql = shift;

  return $sql . ' (' . (join ',', map {(defined $_)? $_:'<undef>'} @_). ')';
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
    $trace .= "$call_details[1] line $call_details[2] at $call_details[3]\n";
  }
  return $trace . "--- End stack trace ---\n";
}

sub GenerateID
{
  my @chars = ('a' .. 'z', 0 .. 9);
  return join '', @chars[ map { rand @chars } 1 .. 8 ];
}

sub NearestPowerOfTen
{
  my $self = shift;
  my $num  = shift;

  my $roundto = 10 ** max(int(log(abs($num))/log(10))-1,1);
  return int(ceil($num/$roundto))*$roundto;
}

return 1;
