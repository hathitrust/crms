#!/usr/bin/perl

use strict;
use warnings;

BEGIN 
{
  unshift(@INC, $ENV{'SDRROOT'}. '/crms/cgi');
}

use v5.10;
binmode(STDOUT, ':encoding(UTF-8)');
use utf8;
use Getopt::Long;
use Term::ANSIColor qw(:constants);
use Perl::Critic;


$Term::ANSIColor::AUTORESET = 1;
my $usage = <<END;
USAGE: $0

Runs Perl::Critic on all .pm, .pl, and extensionless files in cgi/ and bin/.

-h       Print this help message.
-v       Be verbose. May be repeated for increased verbosity.
END

my $help;
my $verbose;

Getopt::Long::Configure ('bundling');
die 'Terminating' unless GetOptions(
           'h|?'  => \$help,
           'v+'   => \$verbose);
die "$usage\n\n" if $help;
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
