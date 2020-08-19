#!/usr/bin/perl

use strict;
use warnings;
BEGIN { unshift(@INC, $ENV{'SDRROOT'}. '/crms/cgi'); }

use CRMS;
use Getopt::Long;
use Time::HiRes;

my $usage = <<END;
USAGE: $0 [-fhptv]

Call imgsrv script to cache frontmatter page images for volumes in the queue.

-f       Force imgsrv to overwrite existing derivatives.
-h       Print this help message.
-m MAIL  Send note to MAIL. May be repeated for multiple recipients.
-n       No-op. Do not call imgsrv script.
-p       Run in production.
-t       Run in training.
-v       Be verbose.
END

my $force;
my $help;
my $instance;
my @mails;
my $noop;
my $production;
my $root;
my $training;
my $verbose = 0;

Getopt::Long::Configure('bundling');
die 'Terminating' unless Getopt::Long::GetOptions(
           'f'    => \$force,
           'h|?'  => \$help,
           'm:s@' => \@mails,
           'n'    => \$noop,
           'p'    => \$production,
           't'    => \$training,
           'v+'   => \$verbose);
$instance = 'production' if $production;
$instance = 'crms-training' if $training;
if ($help) { print $usage. "\n"; exit(0); }

my $t1 = Time::HiRes::time();

my $binary = $ENV{'SDRROOT'}. '/imgsrv/scripts/cache_frontmatter_role.pl';
die "Can't find $binary, aborting\n" unless -f $binary;

$ENV{'FORCE'} = '1' if $force;
# imgsrv/scripts/cache_frontmatter_role.pl is quite verbose when this is on.
#$ENV{'DEBUG'} = '1' if $verbose;

my $crms = CRMS->new(
    verbose  => $verbose,
    instance => $instance
);

$crms->set('messages', '');
$crms->ReportMsg("Verbosity $verbose") if $verbose;
my $sql = 'SELECT id FROM queue ORDER BY id';
my $ref = $crms->SelectAll($sql);
foreach my $row (@$ref)
{
  my $id = $row->[0];
  my $cmd = "$binary $id crms";
  $crms->ReportMsg("$cmd", 1) if $verbose;
  if (!$noop)
  {
    my $ret = system($cmd);
    $crms->ReportMsg("WARNING command '$cmd' returned $ret", 1) if $ret;
  }
}

my $t2 = Time::HiRes::time();
my $hours = int(($t2 - $t1)/3600.0);
my $minutes = int((($t2 - $t1) - ($hours * 3600.0))/60.0);
my $seconds = int((($t2 - $t1) - ($hours * 3600.0) - ($minutes * 60.0)));
$crms->ReportMsg((sprintf "Took %d hours, %d minutes, %d seconds", $hours, $minutes, $seconds), 1);

$crms->ReportMsg("Warning: $_", 1) for @{$crms->GetErrors()};
$crms->ClearErrors();

my $subject = $crms->SubjectLine('Nightly Cache Warming');
@mails = map { ($_ =~ m/@/)? $_:($_ . '@umich.edu'); } @mails;
my $to = join ',', @mails;
if ($noop || scalar @mails == 0)
{
  print "No-op or no mails set; not sending e-mail to {$to}\n" if $verbose;
  print $crms->get('messages') if $verbose;
}
else
{
  if (scalar @mails)
  {
    use Encode;
    use Mail::Sendmail;
    my $bytes = encode('utf8', $crms->get('messages'));
    my %mail = ('from'         => $crms->GetSystemVar('senderEmail'),
                'to'           => $to,
                'subject'      => $subject,
                'content-type' => 'text/html; charset="UTF-8"',
                'body'         => $bytes
               );
    sendmail(%mail) || $crms->SetError("Error: $Mail::Sendmail::error\n");
  }
}

print "Warning: $_\n" for @{$crms->GetErrors()};
