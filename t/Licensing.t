#!/usr/bin/perl

use strict;
use warnings;
BEGIN { unshift(@INC, $ENV{'SDRROOT'}. '/crms/cgi'); }

use Test::More;
use CRMS;

my $crms = CRMS->new();
$crms->AttrReasonSync();

###==== new() ====###
my $licensing = Licensing->new('crms' => $crms);
ok($licensing , 'new returns a value');

###==== attributes() ====###
my %attr_map = ( 'cc-zero' => 1,
                 'cc-by-4.0' => 1,
                 'cc-by-nd-4.0' => 1,
                 'cc-by-nc-nd-4.0' => 1,
                 'cc-by-nc-4.0' => 1,
                 'cc-by-nc-sa-4.0' => 1,
                 'cc-by-sa-4.0' => 1,
                 'ic' => 1,
                 'nobody' => 1,
                 'pd-pvt' => 1 );
my $attrs = $licensing->attributes();
ok(ref $attrs eq 'ARRAY', 'Licensing->attributes returns arrayref');
is(scalar keys %attr_map, scalar @$attrs, 'Licensing->attributes element count');
foreach my $attr (@$attrs)
{
  ok($attr_map{$attr->{'name'}} == 1, "Licensing->attributes contains $attr->{name}");
}

###==== reasons() ====###
my %reason_map = ( 'con' => 1,
                   'man' => 1,
                   'pvt' => 1 );
my $reasons = $licensing->reasons();
ok(ref $reasons eq 'ARRAY', 'Licensing->reasons returns arrayref');
is(scalar keys %reason_map, scalar @$reasons, 'Licensing->reasons element count');
foreach my $reason (@$reasons)
{
  ok($reason_map{$reason->{'name'}} == 1, "Licensing->reasons contains $reason->{name}");
}

###==== rights_data() ====###
$crms->PrepareSubmitSql('DELETE FROM licensing');
my $sql = 'INSERT INTO institutions (name,shortname,suffix) VALUES ("Test Institution", "Test", "test.edu")';
$crms->PrepareSubmitSql($sql);
$sql = 'INSERT INTO users (id,name,institution) VALUES ("test_user","Test User",(SELECT id FROM institutions ORDER BY RAND() LIMIT 1))';
$crms->PrepareSubmitSql($sql);
my $data = $licensing->rights_data();
ok(ref $data eq 'HASH', 'Licensing->rights_data returns hashref');
ok(ref $data->{ids} eq 'ARRAY', 'Licensing->rights_data returns ids hashref');
ok(ref $data->{rights_data} eq '', 'Licensing->rights_data returns a rights_data string');
is(scalar @{$data->{ids}}, 0, 'Licensing->rights_data empty if no entries');
$sql = 'INSERT INTO licensing (htid,user,attr,reason,ticket,rights_holder)'.
       ' VALUES ("mdp.1","test_user",1,1,"HT-0000","Nobody")';
$crms->PrepareSubmitSql($sql);
$data = $licensing->rights_data();
is(scalar @{$data->{ids}}, 1, 'Licensing->rights_data returns one entry');
ok($data->{rights_data} =~ m/HT-0000 \(Nobody\)/, 'Licensing->rights_data returns properly-formatted note');
$crms->PrepareSubmitSql('DELETE FROM licensing WHERE ticket="HT-0000"');
$crms->PrepareSubmitSql('DELETE FROM users WHERE id="test_user"');
$crms->PrepareSubmitSql('DELETE FROM institutions WHERE name="Test Institution"');

done_testing();

