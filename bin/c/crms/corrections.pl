#!/usr/bin/perl

my ($root);
BEGIN 
{ 
  $root = $ENV{'SDRROOT'};
  $root = $ENV{'DLXSROOT'} unless $root and -d $root;
  unshift(@INC, $root. '/crms/cgi');
  unshift(@INC, $root. '/cgi/c/crms');
}

use strict;
use CRMS;
use Corrections;
use Jira;
use Getopt::Long qw(:config no_ignore_case bundling);
use File::Copy;
use Term::ANSIColor qw(:constants);
$Term::ANSIColor::AUTORESET = 1;

my $usage = <<END;
USAGE: $0 [-ehinopqv] [-l LIMIT] [-m MAIL_ADDR [-m MAIL_ADDR2...]]

Loads volumes from all files in the prep directory with the extension
'corrections'. The file format is a tab-delimited file with volume id
and (optional) Jira ticket number.

-e         Skip corrections export.
-h         Print this help message.
-i         Skip corrections import.
-m ADDR    Mail the report to ADDR. May be repeated for multiple addresses.
-n         No-op; reports what would be done but do not modify the database.
-p         Run in production.
-q         Do not emit report (ignored if -m is used).
-v         Emit debugging information.
END

my $noexport;
my $help;
my $instance;
my @mails;
my $noimport;
my $noop;
my $production;
my $quiet;
my $verbose;

Getopt::Long::Configure ('bundling');
die 'Terminating' unless GetOptions(
           'e'    => \$noexport,
           'h|?'  => \$help,
           'i'    => \$noimport,
           'm:s@' => \@mails,
           'n'    => \$noop,
           'p'    => \$production,
           'q'    => \$quiet,
           'v+'   => \$verbose);
$instance = 'production' if $production;
die "$usage\n\n" if $help;

my $crmsUS = CRMS->new(
    sys      => 'crms',
    verbose  => $verbose,
    instance => $instance
);

my $crmsWorld = CRMS->new(
    sys      => 'crmsworld',
    verbose  => $verbose,
    instance => $instance
);

my @systems = ($crmsUS, $crmsWorld);
$verbose = 0 unless defined $verbose;
print "Verbosity $verbose\n" if $verbose;
my $title = 'CRMS Corrections Report';
my $html = $crmsUS->StartHTML($title);

use Corrections;
if (!$noimport)
{
  my $prep = $crmsUS->get('root') . '/prep/c/crms/';
  my $ar = $crmsUS->get('root') . '/prep/c/crms/archive/';
  print "Looking in $prep\n" if $verbose;
  my @files = grep {/\.corrections$/} <$prep/*>;
  my %ids;
  foreach my $file (@files)
  {
    print "$file\n" if $verbose;
    $html .= "<h3>Examining $file</h3>\n";
    open my $fh, $file or die "failed to open: $@ \n";
    foreach my $line (<$fh>)
    {
      chomp $line;
      next unless length $line;
      $ids{$line} = '?';
    }
    close $fh;
  }
  print "Retrieving Jira tickets....\n" if $verbose;
  Corrections::RetrieveTickets($crmsUS, \%ids, $verbose);
  $html .= "<table border='1'><tr><th>Ticket</th><th>ID</th><th>Result</th></tr>\n";
  foreach my $id (sort keys %ids)
  {
    my $status = '';
    my $tx = $ids{$id};
    print "$tx\n" if $verbose;
    $tx = '' if $tx eq '?';
    my $record = $crmsUS->GetMetadata($id);
    if (! defined $record)
    {
      my $id2 = $crmsUS->Dollarize($id, \$record);
      $id = $id2 if defined $id2;
    }
    $crmsUS->ClearErrors();
    if (!defined $record)
    {
      $status = 'Metadata unavailable';
    }
    else
    {
      my $where = $crmsUS->GetRecordPubCountry($id, $record);
      my $obj;
      foreach my $sys (@systems)
      {
        my $cs = $sys->GetCountries();
        if (!defined $cs || $cs->{$where} == 1)
        {
          $obj = $sys;
          printf "Chose %s for $where\n", $sys->System() if $verbose;
          last;
        }
      }
      if (0 == $obj->SimpleSqlGet('SELECT COUNT(*) FROM corrections WHERE id=?', $id))
      {
        my $sql = 'REPLACE INTO corrections (id,ticket) VALUES (?,?)';
        printf "Replacing $id (%s) in %s ($where)\n", (defined $tx)? $tx:'undef', $obj->System() if $verbose;
        $obj->PrepareSubmitSql($sql, $id, $tx) unless $noop;
        $obj->UpdateMetadata($id, 1, $record) unless $noop;
        $status = sprintf "Added to %s ($where)", $obj->System();
      }
      else
      {
        $status = sprintf "Already in %s ($where)", $obj->System();
      }
    }
    $html .= "  <tr><td>$tx</td><td>$id</td><td>$status</td></tr>\n";
  }
  $html .= "<table>\n";
  foreach my $file (@files)
  {
    print "Moving $file to $ar\n" if $verbose;
    File::Copy::move($file, $ar) unless $noop;
  }
  my $sql = 'SELECT COUNT(*) FROM corrections WHERE status IS NULL';
  my $ct = $crmsUS->SimpleSqlGet($sql) + $crmsWorld->SimpleSqlGet($sql);
  $html .= "<h4>After import, there are $ct unchecked corrections</h4>\n";
}

my %data = ('html' => $html, 'verbose' => $verbose );
if (!$noexport)
{
  Corrections::ExportCorrections($crmsUS, $noop, \%data);
  Corrections::ExportCorrections($crmsWorld, $noop, \%data);
  $html = $data{'html'};
}



for (@{$crmsUS->GetErrors()})
{
  s/\n/<br\/>/g;
  $html .= "<i>Warning: $_</i><br/>\n";
}
for (@{$crmsWorld->GetErrors()})
{
  s/\n/<br\/>/g;
  $html .= "<i>Warning: $_</i><br/>\n";
}

$html .= "</body></html>\n";


my $fh = $data{'fh'};
my $temp = $data{'tempfile'};
my $perm = $data{'permfile'};
if (defined $fh)
{
  close $fh;
  print "Moving to $perm.\n" if $verbose;
  rename $temp, $perm;
}
if (scalar @mails)
{
  use Mail::Sendmail;
  use Encode;
  my $to = join ',', @mails;
  my $bytes = encode('utf8', $html);
  my $boundary = "====" . time() . "====";
  my %mail = ('from'         => $crmsUS->GetSystemVar('adminEmail'),
              'to'           => $to,
              'subject'      => $title,
              'content-type' => "multipart/mixed; boundary=\"$boundary\""
              );
  open (F, $perm) or die "Cannot read $perm: $!";
  binmode F; undef $/;
  my $enc = encode('utf8', <F>);
  close F;
  $boundary = '--'.$boundary;
  # FIXME: extract filename for attachment
  $mail{body} = <<END_OF_BODY;
$boundary
Content-Type: text/html; charset="UTF-8"
Content-Transfer-Encoding: quoted-printable

$bytes
Content-Type: text/plain; name="$perm"
Content-Transfer-Encoding: binary
Content-Disposition: attachment; filename="$perm"
Content-Description: Corrections export summary

$enc
$boundary--
END_OF_BODY
  sendmail(%mail) || $crmsUS->SetError("Error: $Mail::Sendmail::error\n");
}
else
{
  print "$html\n" unless defined $quiet;
}

print "Warning (US): $_\n" for @{$crmsUS->GetErrors()};
print "Warning (World): $_\n" for @{$crmsWorld->GetErrors()};
