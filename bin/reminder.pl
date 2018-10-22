#!/usr/bin/perl

BEGIN 
{ 
  unshift(@INC, $ENV{'SDRROOT'}. '/crms/cgi');
}

use strict;
use warnings;
use CRMS;
use Getopt::Long;
use Encode;
use Mail::Sendmail;

my $usage = <<END;
USAGE: $0 [-hpqtv] [-x SYS]

Sends weekly inactivity reports.

-h       Print this help message.
-p       Run in production.
-q       Do not send any emails at all.
-t       Run in training.
-v       Be verbose.
-x SYS   Set SYS as the system to execute.
END

my $help;
my $instance;
my $nomail;
my $production;
my $quiet;
my $sys;
my $training;
my $verbose = 0;

Getopt::Long::Configure ('bundling');
die 'Terminating' unless GetOptions('h|?' => \$help,
           'p'    => \$production,
           'q'    => \$quiet,
           't'    => \$training,
           'v+'   => \$verbose,
           'x:s'  => \$sys);
$instance = 'production' if $production;
$instance = 'crms-training' if $training;
print "Verbosity $verbose\n" if $verbose;
die "$usage\n\n" if $help;

my $crms = CRMS->new(
    sys      => $sys,
    verbose  => $verbose,
    instance => $instance
);

my $system = $crms->System();
my @recips;
my $msg = <<'END';
Automated Reminder: CRMS Review Time - 7 Days out of the system

The CRMS system indicates you have not reviewed in over a week.  Please notify us if there has been a change in your time commitment or availability on the CRMS copyright review project.
Time missed due to vacation and illness does not need to be made up, but please inform us of extended absences.  If you have already done so, thank you! This automated email reminder will run anyway.

-- If you have any questions about your CRMS time commitment, please check with your supervisor.
For additional questions or assistance, contact the CRMS Team:

Kristina Eden: 734-764-9602, keden@umich.edu
END
my $sql = 'SELECT u.id FROM users u INNER JOIN institutions i ON u.institution=i.id'.
          ' WHERE u.reviewer+u.advanced>0 AND u.expert=0'.
          ' AND i.shortname!="Michigan" AND NOT u.id LIKE "%-%"'.
          ' ORDER BY u.id ASC';
my $ref = $crms->SelectAll($sql);
foreach my $row (@{$ref})
{
  my $user = $row->[0];
  next if $crms->IsUserIncarnationExpertOrHigher($user);
  $sql = 'SELECT COUNT(id) FROM reviews WHERE user=?'.
         ' AND time>DATE_SUB(NOW(), INTERVAL 1 WEEK)';
  my $n = $crms->SimpleSqlGet($sql, $user);
  $sql = 'SELECT COUNT(id) FROM historicalreviews WHERE user=? AND time>DATE_SUB(NOW(), INTERVAL 1 WEEK)';
  $n += $crms->SimpleSqlGet($sql, $user);
  printf "$user: $n\n" if $verbose;
  push @recips, $user if $n == 0;
}
my $bytes = encode('utf8', $msg);
foreach my $user (@recips)
{
  print "Sending to $user\n" if $verbose;
  if (!$quiet)
  {
    my %mail = ('from'         => 'crms-mailbot@umich.edu',
                'to'           => $user,
                'subject'      => $crms->SubjectLine('7 Day Out-of-System Automated Reminder'),
                'content-type' => 'text/html; charset="UTF-8"',
                'body'         => $bytes
                );
    sendmail(%mail) || $crms->SetError("Error: $Mail::Sendmail::error\n");
  }
}

print "Warning: $_\n" for @{$crms->GetErrors()};
