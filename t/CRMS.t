#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use File::Temp;
use Test::More;

use lib "$ENV{SDRROOT}/crms/cgi";
use CRMS;

my $cgi = CGI->new();
my $crms = CRMS->new('cgi' => $cgi, 'verbose' => 0);
ok(defined $crms, 'CRMS object created');

subtest '#Version' => sub {
  ok($crms->Version);
};

subtest '#extract_env_email' => sub {
  my $tests = [
    # Each is [INPUT, OUTPUT, TEST_COMMENT]
    [undef, [], 'empty array if no email defined'],
    ['', [], 'empty array if empty string'],
    ['someone@somewhere.edu', ['someone@somewhere.edu'], 'extracts single value'],
    ['someone@somewhere.edu;someone_else@somewhere.edu', ['someone@somewhere.edu', 'someone_else@somewhere.edu'], 'extracts multiple values'],
    [';someone@somewhere.edu', ['someone@somewhere.edu'], 'ignores leading semicolon'],
    ['someone@somewhere.edu;', ['someone@somewhere.edu'], 'ignores trailing semicolon'],
    ['someone@umich.edu', ['someone'], 'strips @umich.edu'],
    ['someone@somewhere.edu;someone@somewhere.edu', ['someone@somewhere.edu'], 'merges duplicates'],
    ['SOMEONE@SOMEWHERE.EDU', ['someone@somewhere.edu'], 'downcases']
  ];
  my $save_email = $ENV{email};
  delete $ENV{email};
  foreach my $test (@$tests) {
    is_deeply($crms->extract_env_email($test->[0]), $test->[1], $test->[2]);
  }
  $ENV{email} = 'someone@somewhere.edu';
  is_deeply($crms->extract_env_email, ['someone@somewhere.edu'], 'uses ENV{email} if no parameter');
  $ENV{email} = $save_email;
};

subtest 'CRMS::MoveToHathitrustFiles' => sub {
  my $tempdir = File::Temp::tempdir(CLEANUP => 1);
  my $save_hathitrust_files_directory = $ENV{'CRMS_HATHITRUST_FILES_DIRECTORY'};
  $ENV{'CRMS_HATHITRUST_FILES_DIRECTORY'} = $tempdir;
  # Reload to pick up changes to ENV
  CRMS::Config->new(reinitialize => 1);
  my $crms = CRMS->new('cgi' => $cgi);
  my $src1 = $crms->FSPath('prep', 'test_1.txt');
  my $src2 = $crms->FSPath('prep', 'test_2.txt');
  `touch $src1`;
  `touch $src2`;
  $crms->MoveToHathitrustFiles($src1, $src2);
  ok(-f "$tempdir/test_1.txt");
  ok(-f "$tempdir/test_2.txt");
  $ENV{'CRMS_HATHITRUST_FILES_DIRECTORY'} = $save_hathitrust_files_directory;
};

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

subtest '#UpdateMetadata' => sub {
  $ENV{CRMS_METADATA_FIXTURES_PATH} = $ENV{'SDRROOT'} . '/crms/t/fixtures/metadata';
  my $htid = 'coo.31924000029250';
  my $record = Metadata->new('id' => $htid);
  $crms->UpdateMetadata($htid, 1, $record);
  my $count = $crms->SimpleSqlGet('SELECT COUNT(*) FROM bibdata WHERE id=?', $htid);
  is($count, 1, 'coo.31924000029250 appears in bibdata');
  # Clean up
  $crms->PrepareSubmitSql('DELETE FROM bibdata WHERE id=?', $htid);
  delete $ENV{CRMS_METADATA_FIXTURES_PATH};
};

subtest '#LinkToJira' => sub {
  is($crms->LinkToJira('DEV-000'),
    '<a href="https://hathitrust.atlassian.net/browse/DEV-000" target="_blank">DEV-000</a>');
};

subtest '#MenuItems' => sub {
  subtest 'with menu id' => sub {
    my $items = $crms->MenuItems(1, 'autocrms');
    isa_ok($items, 'ARRAY', 'returns arrayref');
    ok(scalar @$items > 0, 'returns at least one item');
    is(scalar @{$items->[0]}, 4, 'items are 4-element arrayrefs');
  };

  subtest 'with "docs" special keyword' => sub {
    my $items = $crms->MenuItems('docs', 'autocrms');
    isa_ok($items, 'ARRAY', 'returns arrayref');
    ok(scalar @$items > 0, 'returns at least one item');
    is(scalar @{$items->[0]}, 4, 'items are 4-element arrayrefs');
  };
};

subtest '#GetProjectsRef' => sub {
  isa_ok($crms->GetProjectsRef, 'ARRAY');
};

subtest '#Field008Formatter' => sub {
  isa_ok $crms->Field008Formatter, "CRMS::Field008Formatter";
};

done_testing();
