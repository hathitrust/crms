#!/usr/bin/perl

use strict;
use warnings;
BEGIN { unshift(@INC, $ENV{'SDRROOT'}. '/crms/cgi'); }

use CRMS;
use Getopt::Long;
use JSON::XS;
use Utilities;
use Encode;
use File::Copy;
use Term::ANSIColor qw(:constants);
$Term::ANSIColor::AUTORESET = 1;

my $usage = <<END;
USAGE: $0 [-hnpqv] [-m MAIL [-m MAIL...]]

Produces TSV file of HT institution name and identifier for download at
https://www.hathitrust.org/institution_identifiers

Data hosted on macc-ht-web-000 etc at /htapps/www/sites/www.hathitrust.org/files

-h       Print this help message.
-m MAIL  Send note to MAIL. May be repeated for multiple recipients.
-n       No-op; do not send e-mail or move file into hathitrust.org filesystem.
-p       Run in production.
-v       Be verbose. May be repeated for increased verbosity.
END

my $help;
my $instance;
my $nomail;
my @mails;
my $noop;
my $production;
my $verbose = 0;

Getopt::Long::Configure ('bundling');
die 'Terminating' unless GetOptions('h|?'  => \$help,
           'm:s@' => \@mails,
           'n'    => \$noop,
           'p'    => \$production,
           'v+'   => \$verbose);
$instance = 'production' if $production;
if ($help) { print $usage. "\n"; exit(0); }
print "Verbosity $verbose\n" if $verbose;

my $crms = CRMS->new(
    verbose  => $verbose,
    instance => $instance
);

my $outfile = $crms->FSPath('prep', 'ht_institutions.tsv');
my $msg = $crms->StartHTML();
$msg .= <<'END';
<h2>HathiTrust institution report</h2>
<p>Wrote __N__ records in __OUTFILE__ to
<a href="https://www.hathitrust.org/files/ht_institutions.tsv">HathiTrust</a>.
</p>
END

my $n = CheckInstitutions();
$msg =~ s/__N__/$n/g;
$msg =~ s/__OUTFILE__/$outfile/g;

if ($noop)
{
  $crms->set('noop', 1);
  print "Noop set: not moving file to new location.\n";
  $msg .= '<strong>Noop set: not moving file to new location.</strong>';
}
else
{
  eval {
    File::Copy::move $outfile, '/htapps/www/sites/www.hathitrust.org/files';
  };
  if ($@)
  {
    $msg .= '<strong>Error moving TSV file: $@</strong>';
  }
}
$msg .= "<p>Warning: $_</p>\n" for @{$crms->GetErrors()};
$msg .= '</body></html>';

my $subject = $crms->SubjectLine('HathiTrust Institution Report');
@mails = map { ($_ =~ m/@/)? $_:($_ . '@umich.edu'); } @mails;
my $to = join ',', @mails;
if ($noop || scalar @mails == 0)
{
  print "No-op or no mails set; not sending e-mail to {$to}\n" if $verbose;
  print "$msg\n" if $verbose;
}
else
{
  if (scalar @mails)
  {
    use Encode;
    use Mail::Sendmail;
    my $bytes = encode('utf8', $msg);
    my %mail = ('from'         => $crms->GetSystemVar('senderEmail'),
                'to'           => $to,
                'subject'      => $subject,
                'content-type' => 'text/html; charset="UTF-8"',
                'body'         => $bytes
               );
    sendmail(%mail) || $crms->SetError("Error: $Mail::Sendmail::error\n");
  }
}

# Returns number of entries written.
sub CheckInstitutions
{
  my $sdr_dbh = $crms->ConnectToSdrDb('ht_repository');
  open my $out, '>:encoding(UTF-8)', $outfile;
  my $sql = 'SELECT inst_id,name FROM ht_institutions ORDER BY inst_id ASC';
  my $ref;
  my $n = 0;
  eval {
    $ref = $sdr_dbh->selectall_arrayref($sql);
  };
  if (defined $ref)
  {
    $n = scalar @$ref;
    foreach my $row (@{$ref})
    {
      my $id = $row->[0];
      my $name = $row->[1];
      print $out "$id\t$name\n";
    }
  }
  close $out;
  return $n;
}

