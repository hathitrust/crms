use strict;
use warnings;
BEGIN { unshift(@INC, $ENV{'SDRROOT'}. '/crms/lib'); }

use Test::More;

use CRMS::Countries;

ok(ref CRMS::Countries::GetCountries() eq 'HASH');

is(CRMS::Countries::TranslateCountry('miu'), 'USA');
is(CRMS::Countries::TranslateCountry('miu', 1), 'USA (Michigan)');
is(CRMS::Countries::TranslateCountry('xxx'), 'Undetermined [xxx]');
is(CRMS::Countries::TranslateCountry('xxx', 1), 'Undetermined [xxx]');
is(CRMS::Countries::TranslateCountry('xx '), 'Undetermined [xx ]');
is(CRMS::Countries::TranslateCountry(undef), 'Undetermined [xx]');

done_testing();
