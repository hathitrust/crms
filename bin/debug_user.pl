#!/usr/bin/perl

use strict;
use warnings;
use utf8;

BEGIN {
  die "SDRROOT environment variable not set" unless defined $ENV{'SDRROOT'};
  use lib $ENV{'SDRROOT'} . '/crms/cgi';
}

#use Encode;
use Getopt::Long qw(:config no_ignore_case bundling);
use Data::Dumper;
#use File::Slurp;
#use MARC::Record;
#use MARC::File::XML(BinaryEncoding => 'utf8');

#use BibRights;

binmode(STDOUT, ':encoding(UTF-8)');

my $usage = <<END;
USAGE: $0 [-hp] [-i path/to/file] [htid_or_cid_1 [htid_or_cid_2 ...]]

Reports on the volumes to queued up next for a given reviewer.
This is mainly for debugging purposes.

-h, -?    Print this help message.
-p         Run in production.
-t      Run in training.
END

my $instance;
my $help;
my $production;
my $training;

Getopt::Long::Configure('bundling');
die 'Terminating' unless GetOptions(
  'h|?'  => \$help,
  'p'    => \$production,
  't'    => \$training,
);

if ($help) { print $usage. "\n"; exit(0); }

$instance = 'production' if $production;
$instance = 'crms-training' if $training;

die "Please provide a single user id" unless 1 == scalar @ARGV;
my $user = $ARGV[0];

my $crms = CRMS->new(instance => $instance);

my $ref = $crms->select_from_queue_for_user($user);
foreach my $row (@$ref) {
  my ($htid, $count, $hash, $priority, $project, $sysid) = @$row;

  printf "$htid ($sysid) [%s] %s ($count, %s...) (P %s Proj %s)\n",
    $crms->GetAuthor($htid) || '',
    $crms->GetTitle($htid) || '',
    uc substr($hash, 0, 8),
    $priority,
    $project;
}
