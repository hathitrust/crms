#!/usr/bin/perl

use strict;
use warnings;
use utf8;

BEGIN {
  die "SDRROOT environment variable not set" unless defined $ENV{'SDRROOT'};
  use lib $ENV{'SDRROOT'} . '/crms/cgi';
  use lib $ENV{'SDRROOT'} . '/crms/lib';
}

use Encode;
use Getopt::Long;

use CRMS;
use CRMS::Cron;
use Utilities;

my $usage = <<END;
USAGE: $0 [-hpqtv] [-m USER [-m USER...]]

Sends accumulated help requests and announcements to and from
crms-experts\@umich.edu.

-h       Print this help message.
-m MAIL  Also send report to MAIL. May be repeated for multiple recipients.
-n       No-op: do not update database or send mail.
-p       Run in production.
-q       Quiet: do not send to crms-experts, just to the recipients on the -m flag.
-t       Run in training.
-v       Emit verbose debugging information. May be repeated.
END

my $help;
my $instance;
my @mails;
my $noop;
my $production;
my $quiet;
my $training;
my $verbose = 0;

Getopt::Long::Configure ('bundling');
die 'Terminating' unless GetOptions('h|?'  => \$help,
           'm:s@' => \@mails,
           'n'    => \$noop,
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
my $cron = CRMS::Cron->new(crms => $crms);

$crms->set('noop', 1) if $noop;
my $default_recipients = $cron->recipients(@mails);

my $sql = 'SELECT user,id,text,uuid,mailto,wait FROM mail WHERE sent IS NULL';
my $ref = $crms->SelectAll($sql);
my $thstyle = ' style="background-color:#000000;color:#FFFFFF;padding:4px 20px 2px 6px;"';
foreach my $row (@{$ref})
{
  my $user = $row->[0];
  my $id = $row->[1];
  my $txt = $row->[2];
  my $uuid = $row->[3];
  my $to = $row->[4];
  my $wait = $row->[5];
  $id = undef if defined $id and $id eq '';
  my %mails;
  $mails{$_} = 1 for @$default_recipients;
  if (!$crms->IsDevArea())
  {
    $mails{$crms->GetSystemVar('experts_email')} = 1 unless $quiet;
  }
  if ($wait && $id)
  {
    $sql = 'SELECT COUNT(*) FROM queue WHERE id=?';
    next if $crms->SimpleSqlGet($sql, $id);
  }
  my $subj = sprintf '%s%s', (defined $to)? 'Message from Expert' : 'Reviewer Inquiry',
                             (defined $id)? " for $id":'';
  $subj .= sprintf ' (project %s)', $crms->GetProjectRef($crms->GetProject($id))->{'name'} if defined $id;
  $subj = $crms->SubjectLine($subj);
  my $msg = $crms->StartHTML($subj);
  if ($id)
  {
    $sql = 'SELECT b.author,b.title FROM bibdata b WHERE id=?';
    my $ref2 = $crms->SelectAll($sql, $id);
    my $author = $ref2->[0]->[0] || '';
    my $title = $ref2->[0]->[1] || '';
    my $page = 'adminReviews';
    if ($to)
    {
      $page = ($wait)? 'adminHistoricalReviews':'editReviews';
    }
    my $link = '<a href="'. $crms->Host().
               $crms->WebPath('cgi', 'crms?p='. $page. '&search1=Identifier&search1value='. $id).
               '">'. $id. '</a>';
    my $table = '<table style="border:1px solid #000000;border-collapse:collapse;">';
    if (!$to)
    {
      my $username = $crms->GetUserProperty($user, 'name') || '';
      $table .= <<END;
    <tr><th$thstyle>User</th>
        <td>$user</td>
    </tr>
    <tr><th$thstyle>User Name</th>
        <td>$username</td>
    </tr>
END
    }
    $table .= <<END;
    <tr><th$thstyle>Volume ID</th>
        <td>$link</td>
    </tr>
    <tr><th$thstyle>Author</th>
        <td>$author</td>
    </tr>
    <tr><th$thstyle>Title</th>
        <td>$title</td>
    </tr>
END
    my $table2 = '';
    if (!$to)
    {
      $sql = 'SELECT r.hold,r.attr,r.reason FROM reviews r INNER JOIN queue q ON r.id=q.id'.
             ' INNER JOIN projects p ON q.project=p.id'.
             ' WHERE r.id=? AND r.user=? ORDER BY r.time DESC LIMIT 1';
      $ref2 = $crms->SelectAll($sql, $id, (defined $to)? $to : $user);
      if (scalar @{$ref2})
      {
        my $hold = ($ref2->[0]->[0])? 'Yes':'No';
        my $attr = $crms->TranslateAttr($ref2->[0]->[1]);
        my $reason = $crms->TranslateReason($ref2->[0]->[2]);
        my $rights =
        $table2 = <<END;
        <tr><th$thstyle>Hold?</th>
            <td>$hold</td>
        </tr>
        <tr><th$thstyle>Rights</th>
            <td>$attr/$reason</td>
        </tr>
END
      }
      else
      {
        $table2 .= "<tr><th$thstyle colspan='2'>No review data</td></tr>\n";
      }
    }
    $table .= $table2;
    $table .= sprintf "<tr><th$thstyle>Tracking</th><td>%s</td></tr>\n", $crms->GetTrackingInfo($id, 1, 1);
    $table .= "</table>\n<br/><br/>\n";
    $msg .= $table;
  }
  $txt = $crms->EscapeHTML($txt);
  $msg .= "<div>User message:<br/><strong>$txt</strong></div>";
  $msg .= '</body></html>';
  if (defined $to)
  {
    # $to can be a comma-delimited list of user ids
    $mails{$_} = 1 for split m/\s*,\s*/, $to;
  }
  my @recipients = keys %mails;
  if (scalar @recipients)
  {
    @recipients = map { $cron->expand_email($_); } @recipients;
    $user = $cron->expand_email($user);
    my $to = join ',', @recipients;
    print "Sending to $to\n" if $verbose;
    use Encode;
    use Mail::Sendmail;
    my $bytes = encode('utf8', $msg);
    my %mail = ('from'         => $user,
                'to'           => $to,
                'cc'           => $user,
                'subject'      => $subj,
                'content-type' => 'text/html; charset="UTF-8"',
                'body'         => $bytes
                );
    if ($noop)
    {
      print "No-op set; not sending e-mail to $to\n" if $verbose;
    }
    else
    {
      sendmail(%mail) || $crms->SetError("Error: $Mail::Sendmail::error\n") unless $noop;
      $crms->PrepareSubmitSql('UPDATE mail SET sent=NOW() WHERE uuid=?', $uuid);
    }
  }
  else
  {
    print "No mails entered.\n" if $verbose;
  }
}


print "Warning: $_\n" for @{$crms->GetErrors()};
