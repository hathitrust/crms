use strict;
use warnings;
BEGIN { unshift(@INC, $ENV{'SDRROOT'}. '/crms/lib'); }

use Test::More;

use CRMS::Languages;

ok(ref CRMS::Languages::GetLanguages() eq 'HASH');

is(CRMS::Languages::TranslateLanguage('eng'), 'English');
is(CRMS::Languages::TranslateLanguage(), 'Undetermined [undef]');
is(CRMS::Languages::TranslateLanguage('zzz', 1), 'Undetermined [zzz]');

done_testing();
