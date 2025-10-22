#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use CGI;
use Data::Dumper;
use Test::More;

use lib $ENV{'SDRROOT'} . '/crms/cgi';
use lib $ENV{'SDRROOT'} . '/crms/t/support';
use CRMS;
use FakeMetadata;

require_ok($ENV{'SDRROOT'}. '/crms/cgi/Project/Core.pm');

my $crms = CRMS->new();
# TODO: Project::for_name would be a much nicer way to do this.
my $sql = 'SELECT id FROM projects WHERE name="Core"';
my $project_id = $crms->SimpleSqlGet($sql);
my $project = Core->new(crms => $crms, id => $project_id);
ok(defined $project);

subtest '#queue_order' => sub {
  ok(defined $project->queue_order, 'Core project defines a queue_order');
};

subtest '#PresentationOrder' => sub {
  ok(defined $project->PresentationOrder, 'Core project defines a PresentationOrder');
};

done_testing();


