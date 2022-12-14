#!/usr/bin/perl

use strict;
use warnings;
use utf8;

BEGIN {
  die "SDRROOT environment variable not set" unless defined $ENV{'SDRROOT'};
  use lib $ENV{'SDRROOT'} . '/crms/cgi';
}

use CRMS;
use Getopt::Long;
#use Utilities;
#use Encode;
use Data::Dumper;
use URI::Encode;

my $usage = <<END;
USAGE: $0 [-hpv]

Creates LaTeX title reports for each State Gov Docs reviewer.

-h       Print this help message.
-p       Run in production.
-v       Emit verbose debugging information. May be repeated.
END

my $help;
my $instance;
my $production;
my $verbose = 0;

Getopt::Long::Configure ('bundling');
die 'Terminating' unless GetOptions('h|?'  => \$help,
           'p'    => \$production,
           'v+'   => \$verbose);
$instance = 'production' if $production;
if ($help) { print $usage. "\n"; exit(0); }
print "Verbosity $verbose\n" if $verbose;

my $crms = CRMS->new(
    verbose  => $verbose,
    instance => $instance
);

my $data = {}; # Map of user id -> arrayref of "title<tab>rights<tab>HathiTrust item link
my $sql = 'SELECT r.id,r.user,b.title,b.sysid,e.attr FROM historicalreviews r'.
          ' INNER JOIN bibdata b ON r.id=b.id'.
          ' INNER JOIN exportdata e ON r.gid=e.gid'.
          ' INNER JOIN projects p ON e.project=p.id'.
          ' WHERE p.name="State Gov Docs" AND r.user!="autocrms" AND r.user!="rereport05"'.
          ' ORDER BY b.title ASC';
my $ref = $crms->SelectAll($sql);
foreach my $row (@{$ref})
{
  my $id = $row->[0];
  my $user = $row->[1];
  if ($user =~ m/(.+?)-expert$/ || $user =~ m/(.+?)-reviewer$/ || $user =~ m/(.+?)123$/)
  {
    $user = $1;
  }
  if ($user !~ /@/)
  {
    $user .= '@umich.edu';
  }
  my $title = $row->[2];
  my $sysid = $row->[3];
  my $rights = $row->[4];

  push @{$data->{$user}}, "$title\t$rights\t$id";
}

mkdir 'title_reports' unless -d 'title_reports';

my $template = <<'END';
\documentclass[10pt]{report}
\usepackage{fontspec}
\usepackage[colorlinks=true,urlcolor=red]{hyperref}
\addtolength{\oddsidemargin}{-.6in}
\addtolength{\evensidemargin}{-.6in}
\addtolength{\textwidth}{1.2in}
\setlength{\parindent}{0pt}
\addtolength{\topmargin}{-.87in}
\addtolength{\textheight}{1.7in}

\begin{document}

\title{Title list of all US state documents reviewed by __USER__}
\author{HathiTrust Copyright Review Program}
\maketitle

\fbox{
  \begin{minipage}{26em}
  \begin{itemize}
  \item \textbf{pdus}: Public domain in the United States
  \item \textbf{ic}: In copyright
  \item \textbf{und}: Copyright could not be determined
  \end{itemize}
  \end{minipage}
}

\begin{itemize}
\setlength\itemsep{.2em}
__WORKS__
\end{itemize}

\end{document}
END

foreach my $user (keys %$data)
{
  my $works = '';
  foreach my $line (@{$data->{$user}})
  {
    my ($title, $rights, $id) = split "\t", $line;
    my $link = 'https://hdl.handle.net/2027/'. $id;
    my $readable_link = $link;
    $readable_link =~ s/([#%&\$\\_])/\\$1/g;
    $link = URI::Encode::uri_encode($link);
    $link =~ s/%/\\%/g;
    $title = LatexEscape($title);
    $works .= "\\item \\textit{$title}\\\\\\textbf{$rights} \\href{$link}{$readable_link}\n";
  }
  my $tmpl = $template;
  $tmpl =~ s/__USER__/$user/g;
  $tmpl =~ s/__WORKS__/$works/g;
  open my $latexFile, '>:encoding(UTF-8)', 'title_reports/'. $user. '_SGD_Report.tex';
  print $latexFile "$tmpl\n";
  close $latexFile;
}


sub LatexEscape
{
  my $s = shift;

  if ($s =~ m/^"(.+?)"$/)
  {
    $s = $1;
  }
  $s =~ s/([#%&\$\\_])/\\$1/g;
  my $new = '';
  my $oq;
  my @chars = split m//, $s;
  foreach my $char (@chars)
  {
    if ($char eq '"')
    {
      unless ($oq)
      {
        $char = '``';
        $oq = 1;
      }
      else
      {
        $oq = 0;
      }
    }
    $new .= $char;
  }
  $new .= '"' if $oq;
  return $new;
}

print "Warning: $_\n" for @{$crms->GetErrors()};
