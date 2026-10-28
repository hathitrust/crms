#!/usr/bin/perl

use strict;
use warnings;

use Data::Dumper;
use File::Spec qw();
use File::Temp qw();
use Test::Exception;
use Test::More;

use lib $ENV{'SDRROOT'} . '/crms/lib';
use CRMS::CollectionBuilder;
use CRMS::Database::HT;

my $mock = File::Spec->catfile($ENV{SDRROOT}, 'crms', 't', 'bin', 'mock_batch_collection.pl');
my $cb = CRMS::CollectionBuilder->new;
my $ht_db = CRMS::Database::HT->new;
# Clean slate
clear_db();

sub clear_db {
  $ht_db->submit('DELETE FROM mb_collection');
}

subtest 'find_collection_by_name' => sub {
  subtest 'with a unique collection name' => sub {
    clear_db();
    my $sql = 'INSERT INTO mb_collection (MColl_ID,collname,owner) VALUES (?,?,?)';
    $ht_db->submit($sql, 1, 'TEST', $CRMS::CollectionBuilder::BATCH_COLLECTION_OWNER);
    my $collection = $cb->find_collection_by_name('TEST');
    isa_ok($collection, 'HASH');
    is($collection->{MColl_ID}, 1);
  };

  subtest 'with duplicate collection names' => sub {
    clear_db();
    my $sql = 'INSERT INTO mb_collection (MColl_ID,collname,owner) VALUES (?,?,?)';
    $ht_db->submit($sql, 1, 'TEST', $CRMS::CollectionBuilder::BATCH_COLLECTION_OWNER);
    $ht_db->submit($sql, 2, 'TEST', $CRMS::CollectionBuilder::BATCH_COLLECTION_OWNER);
    dies_ok { $cb->find_collection_by_name('TEST'); };
  };

  subtest 'missing name' => sub {
    dies_ok { $cb->find_collection_by_name; };
  };
};

subtest 'pdd_collection_target_year' => sub {
  my $cb = CRMS::CollectionBuilder->new(year => 2030);
  subtest 'US' => sub {
    is($cb->pdd_collection_target_year, 1934);
  };

  subtest 'World' => sub {
    is($cb->pdd_collection_target_year(1), 1904);
  };
};

subtest 'pdd_collection_name' => sub {
  my $cb = CRMS::CollectionBuilder->new(year => 2030);
  subtest 'US' => sub {
    is($cb->pdd_collection_name, '1934 Publications');
  };

  subtest 'World' => sub {
    ok($cb->pdd_collection_name(1) =~ /January 2030/);
  };
};

subtest 'pdd_collection_description' => sub {
  my $cb = CRMS::CollectionBuilder->new(year => 2030);
  subtest 'US' => sub {
    ok($cb->pdd_collection_description =~ /published in 1934/);
    ok($cb->pdd_collection_description =~ /in 2030/);
  };

  subtest 'World' => sub {
    ok($cb->pdd_collection_description(1) =~ /January 1, 2030/);
  };
};

subtest 'submit_create_collection' => sub {
  my $cb = CRMS::CollectionBuilder->new(batch_collection_path => $mock);
  my ($temp_fh, $temp_filename) = File::Temp::tempfile();

  subtest 'with all required parameters' => sub {
    my $res = $cb->submit_create_collection('Test Title', 'Test Description', $temp_filename);
    ok(defined $res);
    is($res->{status}, 0, 'zero exit status');
    ok(defined $res->{stderr}, 'STDERR reported');
    ok(defined $res->{stdout}, 'STDOUT reported');
    isa_ok($res->{collection}, 'HASH');
  };

  subtest 'missing title' => sub {
    dies_ok { $cb->submit_create_collection(undef, 'Test Description', $temp_filename); };
  };

  subtest 'missing description' => sub {
    dies_ok { $cb->submit_create_collection('Test Title', undef, $temp_filename); };
  };

  subtest 'missing file' => sub {
    dies_ok { $cb->submit_create_collection('Test Title', $temp_filename); };
  };

  subtest 'nonexistent file' => sub {
    dies_ok { $cb->submit_create_collection('Test Title', 'Test Description', '/no/such/file.txt'); };
  };
};

subtest 'submit_set_featured' => sub {
  my $cb = CRMS::CollectionBuilder->new(batch_collection_path => $mock, year => 2030);
  subtest 'feature' => sub {
    clear_db();
    my $sql = 'INSERT INTO mb_collection (MColl_ID,collname,owner) VALUES (?,?,?)';
    $ht_db->submit($sql, 1, 'TEST', $CRMS::CollectionBuilder::BATCH_COLLECTION_OWNER);
    $cb->submit_set_featured(1, 1);
    my $featured = $ht_db->one('SELECT featured FROM mb_collection WHERE MColl_ID=?', 1);
    is($featured, '2031-01-02');
  };

  subtest 'unfeature' => sub {
    clear_db();
    my $sql = 'INSERT INTO mb_collection (MColl_ID,collname,owner,featured) VALUES (?,?,?,?)';
    $ht_db->submit($sql, 1, 'TEST', $CRMS::CollectionBuilder::BATCH_COLLECTION_OWNER, '2030-01-02');
    $cb->submit_set_featured(1, 0);
    my $featured = $ht_db->one('SELECT featured FROM mb_collection WHERE MColl_ID=?', 1);
    ok(! defined $featured);
  };

  subtest 'missing coll_id' => sub {
    dies_ok { $cb->submit_set_featured(undef, 'public') };
  };  
};

subtest 'submit_set_shared' => sub {
  my $cb = CRMS::CollectionBuilder->new(batch_collection_path => $mock);
  subtest 'with all required parameters' => sub {
    clear_db();
    my $sql = 'INSERT INTO mb_collection (MColl_ID,collname,owner) VALUES (?,?,?)';
    $ht_db->submit($sql, 1, 'TEST', $CRMS::CollectionBuilder::BATCH_COLLECTION_OWNER);
    my $res = $cb->submit_set_shared(1, 'public');
    ok(defined $res);
    is($res->{status}, 0, 'zero exit status');
    ok(defined $res->{stderr}, 'STDERR reported');
    ok(defined $res->{stdout}, 'STDOUT reported');
    my $shared = $ht_db->one('SELECT shared FROM mb_collection WHERE MColl_ID=?', 1);
    is($shared, 1);
  };

  subtest 'missing coll_id' => sub {
    dies_ok { $cb->submit_set_shared(undef, 'public') };
  };

  subtest 'missing shared' => sub {
    dies_ok { $cb->submit_set_shared(0); };
  };

  subtest 'bogus shared' => sub {
    dies_ok { $cb->submit_set_shared(0, 'out of phase with the prime material plane'); };
  };
};

done_testing();
