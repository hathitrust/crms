#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use lib "$ENV{SDRROOT}/crms/cgi";

use File::Slurp;
use Test::More;

my $TEST_JSON = File::Slurp::read_file("$ENV{SDRROOT}/crms/t/fixtures/metadata/001502282.json");

require_ok($ENV{'SDRROOT'}. '/crms/cgi/CRMS.pm');
my $cgi = CGI->new();
my $crms = CRMS->new('cgi' => $cgi, 'verbose' => 0);
ok(defined $crms, 'CRMS object created');

subtest 'CRMS::WriteRightsFile' => sub {
  my $rights_data = join "\t", ('mdp.001', '1', '1', 'crms', 'null', '鬼塚英吉');
  $crms->WriteRightsFile($rights_data);
  my $path = $crms->get('export_path');
  ok(-f $path, "WriteRightsFile export path exists");
  open my $fh, '<:encoding(UTF-8)', $path;
  read $fh, my $buffer, -s $path;
  my @fields = split "\t", $buffer;
  is($fields[5], '鬼塚英吉', "WriteRightsFile Unicode characters survive round trip");
  close $fh;
};

subtest 'CRMS::CanExportVolume' => sub {
  subtest 'CRMS::CanExportVolume und/nfi' => sub {
    is(0, $crms->CanExportVolume('mdp.001', 'und', 'nfi', 1));
  };

  subtest 'CRMS::CanExportVolume und/crms' => sub {
    is(0, $crms->CanExportVolume('mdp.001', 'und', 'crms', 1));
  };
};


subtest '#GetMetadata' => sub {
  $ENV{CRMS_METADATA_FIXTURES_PATH} = $ENV{SDRROOT} . '/crms/t/fixtures/metadata';
  subtest 'without bibdata_cache' => sub {
    $crms->PrepareSubmitSql('DELETE FROM bibdata_cache');
    my $record = $crms->GetMetadata('coo.31924000029250');
    isa_ok($record, 'Metadata');
    ok(!$record->is_error);
  };
  subtest 'with bibdata_cache' => sub {
    # Put JSON in cache with a bogus htid (that Metadata.pm can't do anything with)
    # and expect that we can create a metadata object using that HTID; it has to come
    # from bibdata_cache.
    my $id = 'test.GetMetadata';
    $crms->PrepareSubmitSql('DELETE FROM bibdata_cache');
    $crms->AddCachedMetadata($id, $TEST_JSON);
    my $record = $crms->GetMetadata($id);
    isa_ok($record, 'Metadata');
    ok(!$record->is_error);
  };
  delete $ENV{CRMS_METADATA_FIXTURES_PATH};
};

subtest '#GetCachedMetadata' => sub {
  my $id = 'test.GetCachedMetadata';
  $crms->PrepareSubmitSql('DELETE FROM bibdata_cache');
  $crms->AddCachedMetadata($id, $TEST_JSON);
  my $db_count = $crms->SimpleSqlGet('SELECT COUNT(*) FROM bibdata_cache WHERE id=?', $id);
  is($db_count, 1);
  my $db_json = $crms->SimpleSqlGet('SELECT data FROM bibdata_cache WHERE id=?', $id);
  is($db_json, $TEST_JSON);
};

subtest '#AddCachedMetadata' => sub {
  my $id = 'test.AddCachedMetadata';
  $crms->PrepareSubmitSql('DELETE FROM bibdata_cache');
  $crms->AddCachedMetadata($id, $TEST_JSON);
  my $db_count = $crms->SimpleSqlGet('SELECT COUNT(*) FROM bibdata_cache WHERE id=?', $id);
  is($db_count, 1);
  my $db_json = $crms->SimpleSqlGet('SELECT data FROM bibdata_cache WHERE id=?', $id);
  is($db_json, $TEST_JSON);
};

subtest '#DeleteCachedMetadata' => sub {
  my $id = 'test.DeleteCachedMetadata';
  $crms->PrepareSubmitSql('DELETE FROM bibdata_cache');
  $crms->AddCachedMetadata($id, $TEST_JSON);
  $crms->DeleteCachedMetadata($id);
  my $db_count = $crms->SimpleSqlGet('SELECT COUNT(*) FROM bibdata_cache WHERE id=?', $id);
  is($db_count, 0);
};

subtest '#LinkToJira' => sub {
  is($crms->LinkToJira('DEV-000'),
    '<a href="https://hathitrust.atlassian.net/browse/DEV-000" target="_blank">DEV-000</a>');
};

done_testing();
