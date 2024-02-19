#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use lib "$ENV{SDRROOT}/crms/cgi";

use File::Temp;
use Test::More;

require_ok($ENV{'SDRROOT'}. '/crms/cgi/CRMS.pm');
my $cgi = CGI->new();
my $crms = CRMS->new('cgi' => $cgi, 'verbose' => 0);
ok(defined $crms, 'CRMS object created');

subtest 'CRMS::MoveToHathitrustFiles' => sub {
  my $tempdir = File::Temp::tempdir(CLEANUP => 1);
  my $save_hathitrust_files_directory = $ENV{'CRMS_HATHITRUST_FILES_DIRECTORY'};
  $ENV{'CRMS_HATHITRUST_FILES_DIRECTORY'} = $tempdir;
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

subtest '#LinkToJira' => sub {
  is($crms->LinkToJira('DEV-000'),
    '<a href="https://hathitrust.atlassian.net/browse/DEV-000" target="_blank">DEV-000</a>');
};

subtest '#Field008Formatter' => sub {
  isa_ok $crms->Field008Formatter, "CRMS::Field008Formatter";
};

done_testing();
