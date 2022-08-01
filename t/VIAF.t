use strict;
use warnings;
use utf8;

use FindBin;
use Test::More;

use lib "$FindBin::Bin/../lib";

use CRMS::VIAF;


is(CRMS::VIAF::VIAFLink('Bob Example'),
  'https://viaf.org/viaf/search?query=local.personalNames+all+%22Bob%20Example%22&stylesheet=/viaf/xsl/results.xsl&sortKeys=holdingscount');
is(CRMS::VIAF::VIAFCorporateLink('Bob Example'),
  'https://viaf.org/viaf/search?query=local.corporateNames+all+%22Bob%20Example%22&stylesheet=/viaf/xsl/results.xsl&sortKeys=holdingscount');

done_testing();
