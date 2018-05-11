#!/usr/bin/perl


my ($root_dir);
BEGIN 
{ 
  $root_dir = $ENV{'DLXSROOT'};
  $root_dir = $ENV{'SDRROOT'} unless $root_dir;
  unshift(@INC, $root_dir . '/cgi/c/crms');
}

use strict;
use warnings;
use CRMS;
use Getopt::Long;
use Encode;
use Mail::Sendmail;

my $usage = <<'END';
USAGE: $0 [-hpqv] [-m USER [-m USER...]] [-x SYS]

Sends weekly inactivity reports.

-h       Print this help message.
-m USER  Check activity only for USER. May be repeated for multiple users.
         Appends '@umich.edu' in e-mail if necessary.
-p       Run in production.
-q       Do not send any emails at all.
-v       Be verbose.
-x SYS   Set SYS as the system to execute.
END

my $help;
my $instance;
my $nomail;
my @mails;
my $production;
my $quiet;
my $sys;
my $verbose = 0;

Getopt::Long::Configure ('bundling');
die 'Terminating' unless GetOptions('h|?' => \$help,
           'm:s@' => \@mails,
           'p'    => \$production,
           'q'    => \$quiet,
           'v+'   => \$verbose,
           'x:s'  => \$sys);
$instance = 'production' if $production;
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
my %seen;
if (!scalar @mails)
{
  my $sql = 'SELECT u.id FROM users u INNER JOIN institutions i ON u.institution=i.id'.
            ' WHERE u.reviewer+u.advanced+u.expert>0'.
            ' AND i.shortname!="Michigan" AND NOT u.id LIKE "%-%"';
  my $ref = $crms->SelectAll($sql);
  push @mails, $_->[0] for @{$ref};
}
foreach my $user (@mails)
{
  my @identities = ($user);
  next if $seen{$user};
  my $k = $crms->SimpleSqlGet('SELECT kerberos FROM users WHERE id=?', $user);
  if ($k)
  {
    my $sql = 'SELECT id FROM users WHERE kerberos=? AND id!=?';
    push @identities, $_->[0] for @{$crms->SelectAll($sql , $k, $user)};
  }
  my $n = 0;
  foreach my $id (@identities)
  {
    my $sql = 'SELECT COUNT(id) FROM reviews WHERE user=? AND time>DATE_SUB(NOW(), INTERVAL 1 WEEK)';
    $n += $crms->SimpleSqlGet($sql, $id);
    $sql = 'SELECT COUNT(id) FROM historicalreviews WHERE user=? AND time>DATE_SUB(NOW(), INTERVAL 1 WEEK)';
    $n += $crms->SimpleSqlGet($sql, $id);
  }
  printf "%s: $n\n", join ', ', @identities if $verbose;
  push @recips, $user if $n==0;
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
