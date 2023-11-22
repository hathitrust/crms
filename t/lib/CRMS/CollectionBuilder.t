#!/usr/bin/perl

use strict;
use warnings;

#use Data::Dumper;
use Test::Exception;
use Test::More;

use lib $ENV{'SDRROOT'} . '/crms/lib';
use lib $ENV{'SDRROOT'} . '/crms/t/support';
use CRMS::CollectionBuilder;
use FakeMetadata;

subtest '::new' => sub {
  my $cb = CRMS::CollectionBuilder->new;
  isa_ok($cb, 'CRMS::CollectionBuilder');
  ok(defined $cb->{whoami});
};

subtest '::create_collection_cmd' => sub {
  my $cb = CRMS::CollectionBuilder->new;
  subtest 'with all required parameters' => sub {
    my $cmd = $cb->create_collection_cmd(title => 'Test Title', description => 'Test Description', file => '/path/to/file.txt');
    ok(defined $cmd);
  };

  subtest 'missing title' => sub {
    dies_ok { $cb->create_collection_cmd(description => 'Test Description', file => '/path/to/file.txt'); }
  };

  subtest 'missing description' => sub {
    dies_ok { $cb->create_collection_cmd(title => 'Test Title', file => '/path/to/file.txt'); }
  };

  subtest 'missing file' => sub {
    dies_ok { $cb->create_collection_cmd(title => 'Test Title', description => 'Test Description'); }
  };
};

subtest '::set_visibility_cmd' => sub {
  my $cb = CRMS::CollectionBuilder->new;
  subtest 'with all required parameters' => sub {
    my $cmd = $cb->set_visibility_cmd(coll_id => '00000000');
    ok(defined $cmd);
  };

  subtest 'missing coll_id' => sub {
    dies_ok { $cb->set_visibility_cmd }
  };

  subtest 'bogus visibility' => sub {
    dies_ok { $cb->set_visibility_cmd(coll_id => '00000000', visibility => 'out of phase with the prime material plane'); }
  };
};

done_testing();

1;
