#!/usr/bin/perl

use strict;
use warnings;
use v5.10;
binmode(STDOUT, ':encoding(UTF-8)'); # prints characters in utf8
use utf8;

use Data::Dumper;
use Encode;
use FindBin;
use Getopt::Long;
use Term::ANSIColor qw(:constants);

use lib "$FindBin::Bin/../cgi";
use lib "$FindBin::Bin/../lib";

use CRMS;
use CRMS::OpResult;

$Term::ANSIColor::AUTORESET = 1;
Getopt::Long::Configure ('bundling');

die "Input file is required" unless $ARGV[0];

my $usage = <<END;
USAGE: $0 [-chpqtv] -P PROJECT -r PRIORITY -T TICKET -u USER HTID_FILE

Read list of HTIDs from file HTID_FILE and add them to the CRMS queue or candidates.
HTID_FILE can be one-HTID-per-line format, or it can be a TSV but the HTID must be the
first field.

Prints to STDOUT one line per HTID indicating success or failure.

-c           Add to crms.candidates.
-h           Print this help message.
-p           Run against production database.
-P PROJECT   Add to project named PROJECT (required).
-q           Add to crms.queue.
-r PRIORITY  Add at queue.priority PRIORITY (default 0).
-t           Run against training database.
-T TICKET    Specify Jira TICKET if -q (default NULL).
-u USER      crms.users key for queue.added_by (default `whoami`).
-v           Be verbose. May be repeated.
END

my ($candidates, $help, $priority, $production, $project, $queue, $ticket, $training, $user, $verbose);

die 'Terminating' unless GetOptions(
           'c'    => \$candidates,
           'h|?'  => \$help,
           'p'    => \$production,
           'q'    => \$queue,
           'P=s'  => \$project,
           'r=i'  => \$priority,
           't'    => \$training,
           'T=s'  => \$ticket,
           'u=s'  => \$user,
           'v+'   => \$verbose);
my $instance;
$instance = 'production' if $production;
$instance = 'crms-training' if $training;
if ($help) {
  print $usage. "\n";
  exit(0);
}
unless (defined $project) {
  print "missing required option -P PROJECT\n";
  exit(1);
}

my $crms = CRMS->new(instance => $instance);

$priority = 0 unless $priority;
$user = `whoami` unless $user;

my $sql = 'SELECT id FROM projects WHERE name=?';
my $project_id = $crms->SimpleSqlGet($sql, $project);
die "Unable to find id for project '$project'" unless $project_id;

open(my $fh, '<:encoding(UTF-8)', $ARGV[0]);
while (my $line = <$fh>) {
  chomp $line;
  my @fields = split "\t", $line;
  my $htid = $fields[0];
  my $record = $crms->GetMetadata($htid);
  unless (defined $record) {
    print RED "🚫 $htid: no metadata\n";
    next;
  }
  if ($candidates) {
    # Silence STDOUT messages, we want the return structures
    $crms->set('messages', '');
    load_candidate($htid, $project_id, $record);
  }
  if ($queue) {
    load_queue_item($htid, $priority, $user, $record, $project_id, $ticket);
  }
}
close $fh;

sub load_queue_item {
  my $htid       = shift;
  my $priority   = shift;
  my $user       = shift;
  my $record     = shift;
  my $project_id = shift;
  my $ticket     = shift;

  my $result = $crms->AddItemToQueueOrSetItemActive($htid, $priority, 0, 'load_queue.pl',
    $user, $record, $project_id, $ticket);
  if ($result->{status} == 1) {
    print RED "🚫 $htid: $result->{msg}\n";
  } elsif ($result->{status} == 0) {
    print GREEN "✅ $htid\n";
  } elsif ($result->{status} == 2) {
    print YELLOW "⚠️ $htid: $result->{msg}\n";
  }
}

sub load_candidate {
  my $htid       = shift;
  my $project_id = shift;
  my $record     = shift;

  my $result;
  my $eval = $crms->EvaluateCandidacy($htid, $record, $project_id);
  if ($eval->{'status'} eq 'yes') {
    $result = $crms->AddItemToCandidates($htid, $project_id, undef, $record);
  } else {
    $result = CRMS::OpResult->new;
    if ($eval->{'status'} eq 'no') {
      $result->error($eval->{msg});
    } else {
      $result->warning($eval->{msg});
    }
  }
  
  if ($result->level == CRMS::OpResult::ERROR) {
    print RED "🚫 $htid: " . join('; ', @{$result->errors}) . "\n";
  } elsif ($result->level == CRMS::OpResult::OK) {
    print GREEN "✅ $htid: " . join('; ', @{$result->messages}) . "\n";
  } elsif ($result->level == CRMS::OpResult::WARNING) {
    print YELLOW "⚠️ $htid: " . join('; ', @{$result->warnings}) . "\n";
  }
}
