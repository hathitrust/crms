use strict;
use warnings;
BEGIN { unshift(@INC, $ENV{'SDRROOT'}. '/crms/cgi'); }

use Test::Exception;
use Test::More;

use UMCalendar;
use Utilities;

my $utils = Utilities->new();
my $utils2 = Utilities->new();
cmp_ok($utils, '==', $utils2, 'Utilities->new always returns the singleton');

test_StringifySql();
test_WildcardList();
test_Year();
test_Today();
test_Yesterday();
test_Now();
test_FormatDate();
test_FormatTime();
test_FormatYearMonth();
test_IsWorkingDay();
test_EscapeHTML();

subtest "Text Utilities" => sub {
  subtest "Commify" => sub {
    is('1,000', $utils->Commify('1000'));
    is('100', $utils->Commify('100'));
  };

  subtest "Pluralize" => sub {
    is('reviews', $utils->Pluralize(0, 'review'));
    is('review', $utils->Pluralize(1, 'review'));
    is('reviews', $utils->Pluralize(2, 'review'));
    is('indices', $utils->Pluralize(0, 'index', 'indices'));
    is('index', $utils->Pluralize(1, 'index', 'indices'));
    is('indices', $utils->Pluralize(2, 'index', 'indices'));
  };
};


done_testing();

sub test_StringifySql {
  is($utils->StringifySql('SELECT * FROM reviews WHERE id=?', 'mdp.001'),
    'SELECT * FROM reviews WHERE id=? (mdp.001)');
  is($utils->StringifySql('SELECT * FROM reviews WHERE id=?', undef),
    'SELECT * FROM reviews WHERE id=? (<undef>)');
}

sub test_WildcardList {
  is('()', $utils->WildcardList(0));
  is('(?)', $utils->WildcardList(1));
  is('(?,?)', $utils->WildcardList(2));
  is('(?,?,?)', $utils->WildcardList(3));
}

sub test_Year {
  ok($utils->Year() =~ m/\d\d\d\d/);
}

sub test_Today {
  ok($utils->Today() =~ m/\d\d\d\d-\d\d-\d\d/);
}

sub test_Yesterday {
  ok($utils->Yesterday() =~ m/\d\d\d\d-\d\d-\d\d/);
  is($utils->Yesterday('2025-01-01'), '2024-12-31');
  dies_ok { $utils->Yesterday('garbage') };
}

sub test_Now {
  ok($utils->Now() =~ m/\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d/);
}

sub test_FormatDate {
  is($utils->FormatDate('2025-01-01'), 'Wednesday, January 1 2025');
  dies_ok { $utils->FormatDate('garbage') };
}

sub test_FormatTime {
  is($utils->FormatTime('2025-01-01 09:00:00'), 'Wednesday, January 1 2025 at 9:00 AM');
  is($utils->FormatTime('2025-01-01 21:00:00'), 'Wednesday, January 1 2025 at 9:00 PM');
  dies_ok { $utils->FormatTime('garbage') };
}

sub test_FormatYearMonth {
  is($utils->FormatYearMonth('2025-01'), 'Jan 2025');
  is($utils->FormatYearMonth('2025-01', 1), 'January 2025');
  is($utils->FormatYearMonth('2025-12'), 'Dec 2025');
  is($utils->FormatYearMonth('2025-12', 1), 'December 2025');
  dies_ok { $utils->FormatYearMonth('garbage') };
}

sub test_IsWorkingDay {
  ok(!$utils->IsWorkingDay('2025-01-01'));
  ok($utils->IsWorkingDay('2025-01-02'));
  ok(!$utils->IsWorkingDay('2022-12-26'));
  ok(!$utils->IsWorkingDay('2022-12-27'));
  ok(!$utils->IsWorkingDay('2022-12-28'));
  ok(!$utils->IsWorkingDay('2022-12-29'));
  ok(!$utils->IsWorkingDay('2022-12-30'));
}

sub test_EscapeHTML {
  is($utils->EscapeHTML('&'), '&amp;');
}
