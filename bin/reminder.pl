#!/usr/bin/perl

use strict;
use warnings;
BEGIN { unshift(@INC, $ENV{'SDRROOT'}. '/crms/cgi'); }

use CRMS;
use Getopt::Long;
use Encode;
use Mail::Sendmail;

my $usage = <<END;
USAGE: $0 [-hpqtv]

Send reminder e-mail to active reviewers who have not submitted reviews in
the past two weeks.

-h       Print this help message.
-p       Run in production.
-q       Do not send any emails at all.
-t       Run in training.
-v       Be verbose. May be repeated for increased verbosity.
END

my $help;
my $instance;
my $nomail;
my $production;
my $quiet;
my $training;
my $verbose = 0;

Getopt::Long::Configure ('bundling');
die 'Terminating' unless GetOptions('h|?' => \$help,
           'p'    => \$production,
           'q'    => \$quiet,
           't'    => \$training,
           'v+'   => \$verbose);
$instance = 'production' if $production;
$instance = 'crms-training' if $training;
if ($help) { print $usage. "\n"; exit(0); }
print "Verbosity $verbose\n" if $verbose;

my $crms = CRMS->new(
    verbose  => $verbose,
    instance => $instance
);

my $msg = <<'END';
<p>Automated Reminder: CRMS Review Time - 14 Days out of the system</p>

<p>The CRMS system indicates you have not reviewed in over two weeks.
Please notify us if there has been a change in your time commitment or
availability on the CRMS copyright review project.
Time missed due to vacation and illness does not need to be made up,
but please inform us of extended absences. If you have already done so,
thank you! This automated email reminder will run anyway.</p>

<p><i>If you have any questions about your CRMS time commitment,
please check with your supervisor. For additional questions or assistance,
contact Kristina Hall: keden@hathitrust.org</i></p>
END
my $sql = 'SELECT u.id FROM users u INNER JOIN institutions i ON u.institution=i.id'.
          ' WHERE u.reviewer+u.advanced>0 AND u.expert=0'.
          ' AND i.shortname!="Michigan" AND u.id NOT LIKE "%-reviewer"'.
          ' AND u.id NOT LIKE "%-expert"'.
          ' ORDER BY u.id ASC';
my $ref = $crms->SelectAll($sql);
my @mails;
foreach my $row (@{$ref})
{
  my $user = $row->[0];
  next if $crms->IsUserIncarnationExpertOrHigher($user);
  $sql = 'SELECT COUNT(id) FROM reviews WHERE user=?'.
         ' AND time>DATE_SUB(NOW(), INTERVAL 2 WEEK)';
  my $n = $crms->SimpleSqlGet($sql, $user);
  $sql = 'SELECT COUNT(id) FROM historicalreviews WHERE user=?'.
         ' AND time>DATE_SUB(NOW(), INTERVAL 2 WEEK)';
  $n += $crms->SimpleSqlGet($sql, $user);
  printf "$user: $n\n" if $verbose;
  push @mails, $user if $n == 0;
}
my $bytes = encode('utf8', $msg);

foreach my $user (@mails)
{
  print "Sending to $user\n" if $verbose;
  if (!$quiet)
  {
    my %mail = ('from'         => $crms->GetSystemVar('senderEmail'),
                'to'           => $user,
                'subject'      => $crms->SubjectLine('14 Day Out-of-System Automated Reminder'),
                'content-type' => 'text/html; charset="UTF-8"',
                'body'         => $bytes
                );
    sendmail(%mail) || $crms->SetError("Error: $Mail::Sendmail::error\n");
  }
}

print "Warning: $_\n" for @{$crms->GetErrors()};
