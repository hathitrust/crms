#!/usr/bin/perl

use strict;
use warnings;
BEGIN { unshift(@INC, $ENV{'SDRROOT'}. '/crms/cgi'); }

use Test::More;
use CRMS;

my $crms = CRMS->new();
$crms->AttrReasonSync();
my $licensing = Licensing->new('crms' => $crms);
ok($licensing , 'new returns a value');
my $attrs = $licensing->attributes();
my $reasons = $licensing->reasons();
my %attr_map = ( 'cc-zero' => 1,
                 'cc-by-4.0' => 1,
                 'cc-by-nd-4.0' => 1,
                 'cc-by-nc-nd-4.0' => 1,
                 'cc-by-nc-4.0' => 1,
                 'cc-by-nc-sa-4.0' => 1,
                 'cc-by-sa-4.0' => 1,
                 'nobody' => 1,
                 'pd-pvt' => 1 );
my %reason_map = ( 'con' => 1,
                   'man' => 1,
                   'pvt' => 1 );
ok(ref $attrs eq 'ARRAY', 'Licensing->attributes returns arrayref');
is(scalar keys %attr_map, scalar @$attrs, 'Licensing->attributes element count');
foreach my $attr (@$attrs)
{
  ok($attr_map{$attr->{'name'}} == 1, "Licensing->attributes contains $attr->{name}");
}
ok(ref $reasons eq 'ARRAY', 'Licensing->reasons returns arrayref');
is(scalar keys %reason_map, scalar @$reasons, 'Licensing->reasons element count');
foreach my $reason (@$reasons)
{
  ok($reason_map{$reason->{'name'}} == 1, "Licensing->reasons contains $reason->{name}");
}
done_testing();

