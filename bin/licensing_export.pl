#!/usr/bin/perl

use strict;
use warnings;
BEGIN {
  unshift(@INC, $ENV{'SDRROOT'}. '/crms/cgi');
  unshift(@INC, $ENV{'SDRROOT'}. '/crms/lib');
}

use CRMS;
use Getopt::Long;
use Mail::Sendmail;
use Encode;

my $usage = <<END;
USAGE: $0 [-hnpv] [-m MAIL [-m MAIL2...]]

Exports .rights file based on unexported crms.licensing table entries.
This is expected to run every 15 minutes or so.

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

my $licensing = $crms->Licensing();
my $data = $licensing->rights_data();
exit(0) unless scalar @{$data->{ids}};

unless ($noop) {
  my $rights_file = $crms->WriteRightsFile($data->{rights_data});
  my $sql = 'UPDATE licensing SET rights_file=? WHERE id=?';
  $crms->PrepareSubmitSql($sql, $rights_file, $_) for @{$data->{ids}};
}

EmailReport() if scalar @mails;

print "Warning: $_\n" for @{$crms->GetErrors()};

sub EmailReport {
  my $subj = $crms->SubjectLine('Licensing Export');
  my $body = $crms->StartHTML($subj);
  my $file = $crms->get('export_file');
  my $path = $crms->get('export_path');
  $body .= "<p>Rights file for licensing entry exported and attached below.</p>";
  @mails = map { ($_ =~ m/@/)? $_:($_ . '@umich.edu'); } @mails;
  my $to = join ',', @mails;
  my $contentType = 'text/html; charset="UTF-8"';
  my $message = $body;
  if ($file && $path) {
    my $boundary = "====" . time() . "====";
    $contentType = "multipart/mixed; boundary=\"$boundary\"";
    open (my $FH, '<', $path) or die "Cannot read $path: $!";
    binmode $FH; undef $/;
    my $enc = <$FH>;
    close $FH;
    $boundary = '--'.$boundary;
    $message = <<END_OF_BODY;
$boundary
Content-Type: text/html; charset="UTF-8"
Content-Transfer-Encoding: quoted-printable

$body
$boundary
Content-Type: text/plain; charset="UTF-8"; name="$file"
Content-Transfer-Encoding: base64
Content-Disposition: attachment; filename="$file"

$enc
$boundary--
END_OF_BODY
  }
  my $bytes = Encode::encode('utf8', $message);
  my %mail = ('from'         => $crms->GetSystemVar('senderEmail'),
              'to'           => $to,
              'subject'      => $subj,
              'content-type' => $contentType,
              'body'         => $message
              );
  sendmail(%mail) || $crms->SetError("Error: $Mail::Sendmail::error\n");
}

