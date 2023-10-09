package MDPCorrections;
use parent 'Project';

use strict;
use warnings;

sub new
{
  my $class = shift;
  return $class->SUPER::new(@_);
}

# ========== REVIEW ========== #
sub ReviewPartials
{
  return ['top', 'bibdata',
          #'authorities',
          'copyrightForm', 'expertDetails'];
}

1;
