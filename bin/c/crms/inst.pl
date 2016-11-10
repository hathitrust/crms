#!/usr/bin/perl

# This script can be run from crontab

my $DLXSROOT;
my $DLPS_DEV;
BEGIN
{
  $DLXSROOT = $ENV{'DLXSROOT'};
  $DLPS_DEV = $ENV{'DLPS_DEV'};
  unshift (@INC, $DLXSROOT . '/cgi/c/crms/');
}

use strict;
use warnings;
use CRMS;
use Getopt::Long;
use Mail::Sender;

my $usage = <<END;
USAGE: $0 [-hMpqv] [-i INST [-i INST2...]]
          [-m MAIL_ADDR [-m MAIL_ADDR2...]] [-x SYS]

Sends automatic monthly report of institutional stats.

-d DATE  Date covered, in the format YYYY-MM.
-h       Print this help message.
-i INST  Send only for INST (short name)
-m ADDR  Mail the report to ADDR in addition to the supervisor at the institution.
         May be repeated for multiple addresses.
-M       Do not mail to the supervisor (for debugging).
-p       Run in production.
-q       Do not send any emails at all.
-v       Be verbose.
-x SYS   Set SYS as the system to execute.
END

my $date;
my $help;
my @insts;
my $nomail;
my @mails;
my $production;
my $quiet;
my $sys;
my $verbose = 0;

Getopt::Long::Configure ('bundling');
die 'Terminating' unless GetOptions('d:s' => \$date,
           'h|?' => \$help,
           'i:s@' => \@insts,
           'm:s@' => \@mails,
           'M'    => \$nomail,
           'p'    => \$production,
           'q'    => \$quiet,
           'v+'   => \$verbose,
           'x:s'  => \$sys);
$DLPS_DEV = undef if $production;
print "Verbosity $verbose\n" if $verbose;
die "$usage\n\n" if $help;

my $crms = CRMS->new(
    logFile => $DLXSROOT . '/prep/c/crms/inst_hist.txt',
    sys     => $sys,
    verbose => $verbose,
    root    => $DLXSROOT,
    dev     => $DLPS_DEV
);

my $sender = new Mail::Sender { smtp => 'mail.umdl.umich.edu',
                                from => $crms->GetSystemVar('adminEmail', ''),
                                on_errors => 'undef' }
or die "Error in mailing : $Mail::Sender::Error\n";
if (scalar @insts)
{
  my $wc = $crms->WildcardList(scalar @insts);
  @insts = map {$_->[0];} @{$crms->SelectAll('SELECT id FROM institutions WHERE shortname IN '. $wc, @insts)};
  printf "Institutions {%s}\n", join ',', @insts if $verbose;
}
else
{
  @insts = @{$crms->GetInstitutions()};
}
if (defined $date)
{
  die 'Date format YYYY-MM required' unless $date =~ m/^\d\d\d\d-\d\d/;
}
else
{
  $date = $crms->SimpleSqlGet('SELECT DATE_FORMAT(NOW() - INTERVAL 1 MONTH, "%Y-%m")');
}
my $system = $crms->System();
foreach my $inst (@insts)
{
  my $iname = $crms->SimpleSqlGet('SELECT name FROM institutions WHERE id=?', $inst);
  my $mail = $crms->SimpleSqlGet('SELECT GROUP_CONCAT(id SEPARATOR ",") FROM users WHERE institution=? AND extadmin=1', $inst);
  next unless defined $mail;
  
  my $english = $crms->YearMonthToEnglish($date,1);
  my $sql = 'SELECT COUNT(r.id),COUNT(DISTINCT e.id) FROM users u INNER JOIN historicalreviews r' .
            ' ON u.id=r.user INNER JOIN exportdata e ON r.gid=e.gid WHERE ' .
            "r.attr=1 AND e.attr='pd' AND r.validated!=0 AND r.time LIKE '$date%' AND u.institution=?";
  my $ref = $crms->SelectAll($sql, $inst);
  my $rev = $ref->[0]->[0];
  my $det = $ref->[0]->[1];
  $sql = 'SELECT COUNT(r.id) FROM historicalreviews r INNER JOIN users u ON r.user=u.id WHERE ' .
         'r.time LIKE "' . $date . '%" AND u.institution=?';
  $ref = $crms->SelectAll($sql, $inst);
  my $tot = $ref->[0]->[0];
  my $msg = "Monthly statistics for $iname $system Reviewers\n\n" .
            "Total Reviews: $tot\n" .
            "Validated PD Reviews: $rev\n" .
            "Resulting # of volumes made available as full text in HathiTrust: $det\n\n" .
            'Note: This is an automatically generated message from the Copyright Review Management System.';
  my $cc = (join ',', @mails) || undef;
  if ($nomail)
  {
    $mail = $cc;
    $cc = undef;
  }
  printf "Sending to %s, CCing %s for $iname ($english)\n",
        (defined $mail)?$mail:'(no-one)',
        (defined $cc)?$cc:'(no-one)' if $verbose;
  print "========\n$msg\n========\n" if $verbose > 1;
  if (!$quiet)
  {
    $sender->OpenMultipart({
      to => $mail,
      cc => $cc,
      subject => $crms->SubjectLine($iname. ' Statistics for '. $english),
      ctype => 'text/plain',
      encoding => 'quoted-printable'
      }) or die $Mail::Sender::Error,"\n";
    $sender->Body();
    $sender->SendEnc($msg);
    $sender->Close();
  }
}

print "Warning: $_\n" for @{$crms->GetErrors()};
