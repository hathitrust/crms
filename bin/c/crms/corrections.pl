#!/usr/bin/perl

my $DLXSROOT;
my $DLPS_DEV;
BEGIN 
{ 
  $DLXSROOT = $ENV{'DLXSROOT'};
  $DLPS_DEV = $ENV{'DLPS_DEV'};
  unshift (@INC, $DLXSROOT . '/cgi/c/crms/');
}

use strict;
use CRMS;
use Corrections;
use Jira;
use Getopt::Long qw(:config no_ignore_case bundling);
use Encode;
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
$DLPS_DEV = undef if $production;
die "$usage\n\n" if $help;

my $crmsUS = CRMS->new(
    logFile      =>   $DLXSROOT . '/prep/c/crms/corrections_hist.txt',
    sys          =>   'crms',
    verbose      =>   $verbose,
    root         =>   $DLXSROOT,
    dev          =>   $DLPS_DEV
);

my $crmsWorld = CRMS->new(
    logFile      =>   $DLXSROOT . '/prep/c/crms/corrections_hist.txt',
    sys          =>   'crmsworld',
    verbose      =>   $verbose,
    root         =>   $DLXSROOT,
    dev          =>   $DLPS_DEV
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
        my $cs = $sys->GetCountries(1);
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
  use Mail::Sender;
  my $sender = new Mail::Sender { smtp => 'mail.umdl.umich.edu',
                                  from => $crmsWorld->GetSystemVar('adminEmail', ''),
                                  on_errors => 'undef' }
    or die "Error in mailing: $Mail::Sender::Error\n";
  my $to = join ',', @mails;
  $sender->OpenMultipart({
    to => $to,
    subject => $title,
    ctype => 'text/html',
    encoding => 'utf-8'
    }) or die $Mail::Sender::Error,"\n";
  $sender->Body();
  my $bytes = encode('utf8', $html);
  $sender->SendEnc($bytes);
  if (defined $perm)
  {
    $sender->Attach({description => 'Corrections export summary',
                     ctype => 'text/plain',
                     encoding => 'utf-8',
                     file => $perm
      }) or die $Mail::Sender::Error,"\n";
  }
  $sender->Close();
}
else
{
  print "$html\n" unless defined $quiet;
}

print "Warning (US): $_\n" for @{$crmsUS->GetErrors()};
print "Warning (World): $_\n" for @{$crmsWorld->GetErrors()};
