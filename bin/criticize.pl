#!/usr/bin/perl

use strict;
use warnings;
use utf8;

BEGIN {
  die "SDRROOT environment variable not set" unless defined $ENV{'SDRROOT'};
  use lib $ENV{'SDRROOT'} . '/crms/cgi';
}

use v5.10;

use Getopt::Long;
use Term::ANSIColor qw(:constants);
use Perl::Critic;

binmode(STDOUT, ':encoding(UTF-8)');

$Term::ANSIColor::AUTORESET = 1;
my $usage = <<END;
USAGE: $0

Runs Perl::Critic on all .pm, .pl, and extensionless files in bin/, cgi/, lib/, and t/.
This is not currently part of the test suite.

-h       Print this help message.
-v       Emit verbose debugging information. May be repeated.
END

my $help;
my $verbose;

Getopt::Long::Configure ('bundling');
die 'Terminating' unless GetOptions(
           'h|?'  => \$help,
           'v+'   => \$verbose);
if ($help) { print $usage. "\n"; exit(0); }
print "Verbosity $verbose\n" if $verbose;

my $critic = Perl::Critic->new();

my $exit_status = 0;
my @dirs = map { $ENV{SDRROOT} . $_; } ('/crms/bin', '/crms/cgi', '/crms/lib', '/crms/t');
my %seen;
while (my $dir = shift @dirs) {
  opendir(DIR, "$dir") or die "Can't open $dir\n";
  my @files = readdir(DIR);
  closedir(DIR);
  foreach my $file (sort @files) {
    next if $file =~ /^\.\.?$/;
    my $path = "$dir/$file";
    if (-d $path) {
      next if $seen{$path};
      $seen{$path} = 1;
      push @dirs, $path;
    }
    my $desc = `file $path`;
    chomp $desc;
    if ($desc =~ m/perl/i || $path =~ m/\.pm$/ || $path =~ m/\.t$/) {
      my @violations = $critic->critique($path);
      if (scalar @violations) {
        print RED "$path\n";
        print BOLD "  $_" for @violations;
        $exit_status = 1;
      }
      else {
        print GREEN "$path\n" if $verbose;
      }
    }
  }
}
exit($exit_status);
