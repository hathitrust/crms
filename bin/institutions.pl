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
use File::Copy;
use Getopt::Long;
use JSON::XS;
use Term::ANSIColor qw(:constants);

use CRMS;
use CRMS::Cron;
use Utilities;

$Term::ANSIColor::AUTORESET = 1;

my $usage = <<END;
USAGE: $0 [-hnpqv] [-m MAIL [-m MAIL...]]

Produces TSV files of HT institution name, identifier, and SAML entity ID for
download at https://www.hathitrust.org/institution_identifiers and for use by
institutions for WAYFless login or login with Dex
(https://tools.lib.umich.edu/confluence/display/HAT/OIDC+%3C-%3E+SAML+proxy+via+Dex)

Data hosted on macc-ht-web-000 etc at /htapps/www/sites/www.hathitrust.org/files

-h       Print this help message.
-m MAIL  Send note to MAIL. May be repeated for multiple recipients.
-n       No-op; do not send e-mail or move file into hathitrust.org filesystem.
-p       Run in production.
-v       Emit verbose debugging information. May be repeated.
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
my $cron = CRMS::Cron->new(crms => $crms);

my $outfile_instid = $crms->FSPath('prep', 'ht_institutions.tsv');
my $outfile_entityid = $crms->FSPath('prep', 'ht_saml_entity_ids.tsv');
my $msg = $crms->StartHTML();
$msg .= <<'END';
<h2>HathiTrust institution report</h2>
<p>Wrote __N__ records in __OUTFILE_INSTID__, __OUTFILE_ENTITYID__ to
<a href="https://www.hathitrust.org/files/ht_institutions.tsv">HathiTrust</a>.
</p>
END

my $n = CheckInstitutions();
$msg =~ s/__N__/$n/g;
$msg =~ s/__OUTFILE_INSTID__/$outfile_instid/g;
$msg =~ s/__OUTFILE_ENTITYID__/$outfile_entityid/g;

if ($noop)
{
  $crms->set('noop', 1);
  print "Noop set: not moving file to new location.\n";
  $msg .= '<strong>Noop set: not moving file to new location.</strong>';
}
else
{
  eval {
    File::Copy::move $outfile_instid, '/htapps/www/sites/www.hathitrust.org/files';
    File::Copy::move $outfile_entityid, '/htapps/www/sites/www.hathitrust.org/files';
  };
  if ($@)
  {
    $msg .= '<strong>Error moving TSV file: $@</strong>';
  }
}
$msg .= "<p>Warning: $_</p>\n" for @{$crms->GetErrors()};
$msg .= '</body></html>';

my $subject = $crms->SubjectLine('HathiTrust Institution Report');
my $recipients = $cron->recipients(@mails);
my $to = join ',', @$recipients;
if ($noop || scalar @$recipients == 0)
{
  print "No-op or no mails set; not sending e-mail to {$to}\n" if $verbose;
  print "$msg\n" if $verbose;
}
else
{
  if (scalar @$recipients > 0)
  {
    use Encode;
    use Mail::Sendmail;
    my $bytes = encode('utf8', $msg);
    my %mail = ('from'         => $crms->GetSystemVar('sender_email'),
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
  open my $out_instid, '>:encoding(UTF-8)', $outfile_instid;
  open my $out_entityid, '>:encoding(UTF-8)', $outfile_entityid;
  my $sql = 'SELECT inst_id,name,entityID,enabled FROM ht_institutions WHERE enabled!=0'.
            ' ORDER BY inst_id ASC';
  my $ref;
  my $n = 0;
  eval {
    $ref = $crms->htdb->all($sql);
  };
  if (defined $ref)
  {
    $n = scalar @$ref;
    foreach my $row (@{$ref})
    {
      my ($id,$name,$entityID,$enabled) = @$row;
      print $out_instid "$id\t$name\n";
      print $out_entityid "$entityID\t$name\n" if $enabled == 1;
    }
  }
  close $out_instid;
  close $out_entityid;
  return $n;
}

