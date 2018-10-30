#!/usr/bin/perl

BEGIN 
{
  unshift(@INC, $ENV{'SDRROOT'}. '/crms/cgi');
}

use strict;
use warnings;
use CRMS;
use Getopt::Long;
use Utilities;
use Encode;

my $usage = <<END;
USAGE: $0 [-hpqtv] [-m USER [-m USER...]] [-x SYS]

Sends accumulated help requests to crms-experts\@umich.edu.

-h       Print this help message.
-m MAIL  Also send report to MAIL. May be repeated for multiple recipients.
-p       Run in production.
-q       Quiet: do not send to crms-experts, just to the recipients on the -m flag.
-t       Run in training.
-v       Be verbose.
END

my $help;
my $instance;
my @mails;
my $production;
my $quiet;
my $training;
my $verbose = 0;

Getopt::Long::Configure ('bundling');
die 'Terminating' unless GetOptions('h|?'  => \$help,
           'm:s@' => \@mails,
           'p'    => \$production,
           'q'    => \$quiet,
           't'    => \$training,
           'v+'   => \$verbose);
$instance = 'production' if $production;
$instance = 'crms-training' if $training;
print "Verbosity $verbose\n" if $verbose;
die "$usage\n\n" if $help;

my %mails;
my $crms = CRMS->new(
    verbose  => $verbose,
    instance => $instance
);

$mails{$_} = 1 for @mails;
$mails{$crms->GetSystemVar('expertsEmail')} = 1 unless $quiet;
my $sql = 'SELECT user,id,text,uuid FROM mail WHERE sent IS NULL';
my $ref = $crms->SelectAll($sql);
my $thstyle = ' style="background-color:#000000;color:#FFFFFF;padding:4px 20px 2px 6px;"';
foreach my $row (@{$ref})
{
  my $user = $row->[0];
  my $id = $row->[1];
  my $txt = $row->[2];
  my $uuid = $row->[3];
  my $subj = sprintf 'Reviewer Inquiry%s', (defined $id)? " for $id":'';
  $subj .= sprintf ' (project %s)', $crms->GetProjectName($id) if defined $id;
  $subj = $crms->SubjectLine($subj);
  my $msg = $crms->StartHTML($subj);
  if ($id)
  {
    $sql = 'SELECT b.author,b.title FROM bibdata b WHERE id=?';
    my $ref2 = $crms->SelectAll($sql, $id);
    my $author = $ref2->[0]->[0] || '';
    my $title = $ref2->[0]->[1] || '';
    $sql = 'SELECT r.hold,r.attr,r.reason FROM reviews r INNER JOIN queue q ON r.id=q.id'.
           ' INNER JOIN projects p ON q.project=p.id'.
           ' WHERE r.id=? AND r.user=? ORDER BY r.time DESC LIMIT 1';
    $ref2 = $crms->SelectAll($sql, $id, $user);
    my $link = '<a href="'. $crms->Host().
               $crms->WebPath('cgi', 'crms?p=adminReviews&search1=Identifier&search1value='. $id).
               '">'. $id. '</a>';
    my $username = $crms->GetUserProperty($user, 'name');
    my $table = <<END;
    <table style="border:1px solid #000000;border-collapse:collapse;">
    <tr><th$thstyle>User</th>
        <td>$user</td>
    </tr>
    <tr><th$thstyle>User Name</th>
        <td>$username</td>
    </tr>
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
    $table .= $table2;
    $table .= sprintf "<tr><th$thstyle>Tracking</th><td>%s</td></tr>\n", $crms->GetTrackingInfo($id, 1, 1);
    $table .= "</table>\n<br/><br/>\n";
    $msg .= $table;
  }
  $txt = $crms->EscapeHTML($txt);
  $msg .= "<div>User message:<br/><strong>$txt</strong></div>";
  $msg .= '</body></html>';
  @mails = keys %mails;
  if (scalar @mails)
  {
    @mails = map { ($_ =~ m/@/)? $_:($_ . '@umich.edu'); } @mails;
    $user .= '@umich.edu' unless $user =~ m/@/;
    my $to = join ',', @mails;
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
    sendmail(%mail) || $crms->SetError("Error: $Mail::Sendmail::error\n");
    # FIXME: error checking
    $crms->PrepareSubmitSql('UPDATE mail SET sent=NOW() WHERE uuid=?', $uuid);
  }
  else
  {
    print "No mails entered.\n" if $verbose;
  }
}


print "Warning: $_\n" for @{$crms->GetErrors()};
