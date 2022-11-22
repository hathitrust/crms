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

Runs Perl::Critic on all .pm, .pl, and extensionless files in cgi/ and bin/.
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

my @dirs = ($ENV{'SDRROOT'}. '/crms/cgi', $ENV{'SDRROOT'}. '/crms/bin');
my %seen;
while (my $pwd = shift @dirs)
{
  opendir(DIR, "$pwd") or die "Can't open $pwd\n";
  my @files = readdir(DIR);
  closedir(DIR);
  foreach my $file (sort @files)
  {
    next if $file =~ /^\.\.?$/;
    next if $file eq 'legacy';
    my $path = "$pwd/$file";
    if (-d $path)
    {
      next if $seen{$path};
      $seen{$path} = 1;
      push @dirs, $path;
    }
    my $desc = `file $path`;
    chomp $desc;
    next unless $desc =~ m/perl/i;
    my @violations = $critic->critique($path);
    if (scalar @violations)
    {
      print RED "$path\n";
      print BOLD "  $_" for @violations;
    }
    else
    {
      print GREEN "$path\n";
    }
  }
}
