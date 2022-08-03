#!/usr/bin/perl

use strict;
use warnings;
use v5.10;
use utf8;

BEGIN {
  unshift(@INC, $ENV{'SDRROOT'}. '/crms/cgi');
  unshift(@INC, $ENV{'SDRROOT'}. '/crms/lib');
}

binmode(STDOUT, ':encoding(UTF-8)');
use Getopt::Long;
use Term::ANSIColor qw(:constants);
use Perl::Critic;


$Term::ANSIColor::AUTORESET = 1;
my $usage = <<END;
USAGE: $0

Runs Perl::Critic on all .pm, .pl, and extensionless files in lib/, cgi/, and bin/.
This is offered as a sort of sanity check and is not currently part of the
test suite.

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

my @dirs = ($ENV{'SDRROOT'}. '/crms/lib',
  $ENV{'SDRROOT'}. '/crms/cgi',
  $ENV{'SDRROOT'}. '/crms/bin');
my %seen;
my $bads = 0;
while (my $pwd = shift @dirs) {
  opendir(DIR, "$pwd") or die "Can't open $pwd\n";
  my @files = readdir(DIR);
  closedir(DIR);
  foreach my $file (sort @files) {
    next if $file =~ /^\.\.?$/;
    next if $file eq 'legacy';
    my $path = "$pwd/$file";
    if (-d $path) {
      next if $seen{$path};
      $seen{$path} = 1;
      push @dirs, $path;
    }
    my $desc = `file $path`;
    chomp $desc;
    next unless $desc =~ m/perl/i;
    my @violations = $critic->critique($path);
    if (scalar @violations) {
      $bads += scalar @violations;
      print RED "$path\n";
      print BOLD "  $_" for @violations;
    } else {
      print GREEN "$path\n" if $verbose;
    }
  }
}

exit(($bads > 0)? -1 : 0);
