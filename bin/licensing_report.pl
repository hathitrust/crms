#!/usr/bin/perl

use strict;
use warnings;
use utf8;

BEGIN {
  die "SDRROOT environment variable not set" unless defined $ENV{'SDRROOT'};
  use lib $ENV{'SDRROOT'} . '/crms/cgi';
}

use Getopt::Long;
use Mail::Sendmail;
use Encode;

use CRMS;
use Jira;

my $usage = <<END;
USAGE: $0 [-hnpv] [-m MAIL [-m MAIL2...]]

Daily summary of licensing exports.

-h       Print this help message.
-m MAIL  Send report to MAIL. May be repeated for multiple recipients.
-n       No-op. Do not alter database or write .rights file.
-p       Run in production.
-v       Be verbose.
END

my $help;
my $instance;
my @mails;
my $noop;
my $production;
my $verbose = 0;

Getopt::Long::Configure('bundling');
die 'Terminating' unless Getopt::Long::GetOptions(
           'h|?'  => \$help,
           'm:s@' => \@mails,
           'n'    => \$noop,
           'p'    => \$production,
           'v+'   => \$verbose);
$instance = 'production' if $production;
if ($help) { print $usage. "\n"; exit(0); }

my $crms = CRMS->new(
    verbose  => $verbose,
    instance => $instance
);

my $sql = 'SELECT l.id,l.htid,a.name,rs.name,l.user,l.ticket,l.rights_holder,'.
         'b.title FROM licensing l'.
         ' LEFT JOIN bibdata b ON l.htid=b.id'.
         ' INNER JOIN attributes a ON l.attr=a.id'.
         ' INNER JOIN reasons rs ON l.reason=rs.id'.
         ' WHERE l.time >= DATE_SUB(NOW(), INTERVAL 1 DAY)'.
         ' ORDER BY l.ticket, l.htid';
my $ref = $crms->SelectAll($sql);
exit(0) unless scalar @$ref;

my $subj = $crms->SubjectLine('Licensing Daily Report');
my $styles = <<END;
<style>
  table { border:1px solid #000000; border-collapse:collapse; }
  th { background-color:#000000; color:#FFFFFF; padding:4px 20px 2px 6px;}
</style>
END
my $report = $crms->StartHTML($subj, $styles);

$report .= "<p>Licensing entries from the previous 24 hours.</p>";
$report .= <<END;
<table>
<tr>
  <th>Volume ID</th>
  <th>Attribute</th>
  <th>Reason</th>
  <th>Ticket</th>
  <th>Rights Holder</th>
  <th>Title</th>
</tr>
END

my @ids;
my $rights_data = '';
foreach my $row (@$ref)
{
  my ($id, $htid, $attr, $reason, $user,
      $ticket, $rights_holder, $title) = map { defined $_ ? $_ : ''; } @$row;
  push @ids, $id;
  $rights_data .= join("\t", ($htid, $attr, $reason, 'crms', 'null', $ticket)) . "\n";
  $report .= <<END
<tr>
  <td>$htid</td>
  <td>$attr</td>
  <td>$reason</td>
  <td>$ticket</td>
  <td>$rights_holder</td>
  <td>$title</td>
</tr>
END
}

$report .= "</table>\n</body>\n</html>\n";
AddJiraComments() if $production;
EmailReport() if scalar @mails;

print "Warning: $_\n" for @{$crms->GetErrors()};

sub EmailReport
{
  @mails = map { ($_ =~ m/@/)? $_:($_ . '@umich.edu'); } @mails;
  my $to = join ',', @mails;
  my $bytes = Encode::encode('utf8', $report);
  my %mail = ('from'         => $crms->GetSystemVar('sender_email'),
              'to'           => $to,
              'subject'      => $subj,
              'content-type' => 'text/html; charset="UTF-8"',
              'body'         => $bytes
              );
  sendmail(%mail) || $crms->SetError("Error: $Mail::Sendmail::error\n");
}

sub AddJiraComments
{
  #my $summary = '';
  my $sql = 'SELECT DISTINCT ticket FROM licensing'.
            ' WHERE time >= DATE_SUB(NOW(), INTERVAL 1 DAY)';
  my $ref = $crms->SelectAll($sql);
  my @txs = map { $_->[0]; } @$ref;
  foreach my $tx (@txs)
  {
    my $comment = "Rights have been updated for the following volumes:\n";
    $sql = 'SELECT DISTINCT a.name FROM licensing l'.
         ' INNER JOIN attributes a ON l.attr=a.id'.
         ' WHERE l.ticket=?'.
         ' ORDER BY a.name';
    $ref = $crms->SelectAll($sql, $tx);
    my @licenses = map { $_->[0]; } @$ref;
    foreach my $license (@licenses)
    {
      $comment .= "New license: $license\n";
      $sql = 'SELECT l.htid FROM licensing l'.
             ' INNER JOIN attributes a ON l.attr=a.id'.
             ' WHERE l.ticket=? AND a.name=?'.
             ' ORDER BY l.htid';
      $ref = $crms->SelectAll($sql, $tx, $license);
      $comment .= sprintf("%s\n", $_->[0]) for @$ref;
    }
    my $err = Jira::AddComment($tx, $comment);
    $crms->SetError($err) if defined $err;
    #$summary .= "<p>Jira comment for $tx:</p><code>$comment</code>";
  }
  #return $summary;
}
