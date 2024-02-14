package CRMS::Field008Formatter;

# Displays a 008 field with subparts separated out and bit positions numbered.

use strict;
use warnings;
use utf8;

sub new {
  my ($class, %args) = @_;
  my $self = bless {}, $class;
  return $self;
}

sub format {
  my $self = shift;
  my $f008 = shift;

  $f008 =~ s/\s/⊔/g;
  my $f008_1 = substr $f008, 0, 6;
  my $f008_2 = substr $f008, 6, 9;
  my $f008_3 = substr $f008, 15, 3;
  my $f008_4 = substr $f008, 18, 17;
  my $f008_5 = substr $f008, 35, 3;
  my $f008_6 = substr $f008, 38, 1;
  my $f008_7 = substr $f008, 39, 1;

  my $format = <<END;
<span class="f008">$f008_1
  <span class="f008-annotation tooltip">00 01 02 03 04 05
    <span class="tooltiptext">Date entered on file Date entered on file Date entered on file</span>
  </span>
</span>
<span class="f008">$f008_2
  <span class="f008-annotation">06 07 08 09 10 11 12 13 14</span>
</span>
<span class="f008">$f008_3
  <span class="f008-annotation">15 16 17</span>
</span>
<span class="f008">$f008_4
  <span class="f008-annotation">18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34</span>
</span>
<span class="f008">$f008_5
  <span class="f008-annotation">35 36 37</span>
</span>
<span class="f008">$f008_6
  <span class="f008-annotation tooltip">38
    <span class="tooltiptext">Modified record</span>
  </span>
</span>
<span class="f008">$f008_7
  <span class="f008-annotation">
    <span data-tooltip data-tooltip-message="Cataloging source">39</span>
  </span>
</span>
END
  return $format;
}

1;
