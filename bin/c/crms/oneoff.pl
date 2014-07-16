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
use Getopt::Long qw(:config no_ignore_case bundling);
use Encode;
use File::Copy;
use Term::ANSIColor qw(:constants);
$Term::ANSIColor::AUTORESET = 1;
use Jira;

my $usage = <<END;
USAGE: $0 [-hnopqv] [-l LIMIT] [-m MAIL_ADDR [-m MAIL_ADDR2...]]
       [-t TICKET [-t TICKET2...]]

Loads one-off reviews from Jira.

-h         Print this help message.
-l LIMIT   Limit the number of tickets to LIMIT.
-m ADDR    Mail the report to ADDR. May be repeated for multiple addresses.
-n         No-op; reports what would be done but do not modify the database.
-p         Run in production.
-q         Do not emit report (ignored if -m is used).
-t TICKET  Limit to the Jira ticket(s) specified.
-v         Emit debugging information.
END

my $help;
my $lim;
my @mails;
my $noop;
my $production;
my $quiet;
my @tix;
my $verbose;

Getopt::Long::Configure ('bundling');
die 'Terminating' unless GetOptions(
           'h|?'  => \$help,
           'l:s'  => \$lim,
           'm:s@' => \@mails,
           'n'    => \$noop,
           'p'    => \$production,
           'q'    => \$quiet,
           't:s@' => \@tix,
           'v+'   => \$verbose);
$DLPS_DEV = undef if $production;
die "$usage\n\n" if $help;

my $crmsUS = CRMS->new(
    logFile      =>   $DLXSROOT . '/prep/c/crms/oneoff_hist.txt',
    sys          =>   'crms',
    verbose      =>   $verbose,
    root         =>   $DLXSROOT,
    dev          =>   $DLPS_DEV
);

my $crmsWorld = CRMS->new(
    logFile      =>   $DLXSROOT . '/prep/c/crms/W_oneoff_hist.txt',
    sys          =>   'crmsworld',
    verbose      =>   $verbose,
    root         =>   $DLXSROOT,
    dev          =>   $DLPS_DEV
);

my @systems = ($crmsUS, $crmsWorld);
$verbose = 0 unless defined $verbose;
print "Verbosity $verbose\n" if $verbose;
my $title = 'CRMS One-off Review Report';
my $html = $crmsUS->StartHTML($title);
my %data = ('html' => $html, 'verbose' => $verbose );
my $ua = Jira::Login($crmsUS);

my @noids;
my @systemserials;
my $hash = OneoffQuery(\@noids, \@systemserials);
$html .= "<h3>One-off reviews imported from Jira</h3>\n";
$html .= '<table border="1"><tr><th>Ticket</th><th>ID</th>'.
         '<th>Author</th><th>Title</th><th>Tracking</th>'.
         "<th>Comments</th><th>Disposition</th></tr>\n";
my $closed = $crmsWorld->GetClosedTickets();
foreach my $tx (keys %{$closed})
{
  my $url = Jira::LinkToJira($tx);
  my $stat = $closed->{$tx};
  if ($stat eq 'Status unknown')
  {
    $html .= "  <tr><td>$url</td><td/><td/><td/><td/>".
      '<td><span style="color:red;">In queue; unable to get current Jira status</span></td><td/></tr>' . "\n";
  }
  else
  {
    $html .= "  <tr><td>$url</td><td/><td/><td/><td/>".
      '<td><span style="color:blue;">Ticket marked as '.$stat.'; deleted</span></td><td>&#x2715;</td></tr>' . "\n";
    my $sql = 'DELETE FROM queue WHERE source=?';
    $crmsWorld->PrepareSubmitSql($sql, $tx) unless $noop;
  }
}
foreach my $tx (@noids)
{
  my $url = Jira::LinkToJira($tx);
  $html .= "  <tr><td>$url</td><td/><td/><td/><td/>".
    '<td><span style="color:red;">No Zephir or Hathi IDs could be extracted from the ticket</span></td><td/></tr>' . "\n";
}
foreach my $tx (@systemserials)
{
  my $url = Jira::LinkToJira($tx);
  $html .= '  <tr><td>' .$url. '</td><td/><td/><td/><td/><td><span style="color:red;">'.
           'Could not find Hathi id(s) to review because the item appears to be a serial</span></td><td/></tr>' . "\n";
}
foreach my $tx (sort keys %{$hash})
{
  my $ids = $hash->{$tx};
  my $status = '';
  my $prev = HasPreviousOneOff($tx);
  if (defined $prev)
  {
    print "  Previous one-off detected from $prev; skipping\n" if $verbose;
    my $msg = "Previous one-off by $prev";
    $msg = 'Already in queue' if $prev eq 'queue';
    $msg = 'Already exported' if $prev eq 'exportdata';
    $html .= '  <tr><td>'. Jira::LinkToJira($tx).
             '</td><td/><td/><td/><td/><td><span style="color:red;">'.
             "$msg</span></td><td/></tr>\n";
    next;
  }
  my $i = 0;
  foreach my $id (keys %{$ids})
  {
    my $added = '';
    print "  $id\n" if $verbose;
    next unless $id =~ m/\./;
    my $record = $crmsUS->GetMetadata($id);
    if (! defined $record)
    {
      my $id2 = $crmsUS->Dollarize($id, \$record);
      $id = $id2 if defined $id2;
    }
    my $track = '';
    $crmsUS->ClearErrors();
    if (!defined $record)
    {
      $status = 'Metadata unavailable';
    }
    else
    {
      $track = $crmsWorld->GetTrackingInfo($id, 1, 0, 1);
      if ($track eq '')
      {
        $track = $crmsUS->GetTrackingInfo($id, 1, 0, 1);
        $track = '(US) '. $track if $track ne '';
      }
      print "  Adding $id\n" if $verbose;
      my $err = '0';
      my $pri = 4;
      my $jpri = Jira::GetIssuePriority($crmsUS, $ua, $tx);
      if (defined $jpri && $jpri < 3)
      {
        $pri = 4.1 if $jpri == 3;
        $pri = 4.2 if $jpri == 2;
        $pri = 4.3 if $jpri == 1;
        $status = sprintf '<span style="color:green">CRMS priority %s from Jira priority %s</span>', $pri, $jpri;
      }
      $err = $crmsWorld->AddItemToQueueOrSetItemActive($id, $pri, 1, $tx, 'oneoff') unless $noop;
      if ('1' eq substr $err, 0, 1)
      {
        $status = sprintf '<span style="color:red">%s</span>', substr $err, 1, -1;
        print BOLD RED "  $id: $status\n";
      }
      elsif ('0' eq substr $err, 0, 1)
      {
        $added = '&#x2713;';
      }
    }
    my $url = '';
    $url = my $url = Jira::LinkToJira($tx) if $i == 0;
    $html .= sprintf "  <tr><td>$url</td><td style='white-space:nowrap;'>$id</td><td>%s</td><td>%s</td><td>$track</td><td>$status</td>",
                        $record->author, $record->title;
    $html .= "<td>$added</td></tr>\n";
    $i++;
  }
}
$html .= "</table>\n";


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


if (scalar @mails)
{
  if ($verbose)
  {
    print "Sending mail to:\n";
    print "  $_\n" for @mails;
  }
  #if (!$noop)
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
    $sender->Close();
  }
}
else
{
  print "$html\n" unless defined $quiet;
}


sub OneoffQuery
{
  my $noids = shift;
  my $systemserials = shift;
  my $mail = 'copyrightinquiry@umich.edu';
  my %txs;
  return unless defined $ua;
  my $url = 'https://wush.net/jira/hathitrust/rest/api/2/search?jql="HathiTrust%20Contact"~"' .
             $mail . '" AND (status=1 OR status=4 OR status=3)';
  if (scalar @tix)
  {
     $url = sprintf 'https://wush.net/jira/hathitrust/rest/api/2/search?jql=issueKey in (%s)',
           join ',', @tix;
  }
  else
  {
    $url .= '&maxResults=' . $lim if defined $lim;
  }
  print "$url\n" if $verbose;
  my $req = HTTP::Request->new(GET => $url);
  my $res = $ua->request($req);
  if (!$res->is_success())
  {
    $crmsUS->SetError("Got " . $res->code() . " getting $url\n");
    return;
  }
  my $json = JSON::XS->new;
  my $content = $res->content;
  #print "$content\n";
  eval {
    my $data = $json->decode($content);
    my $of = ($data->{'total'}<$data->{'maxResults'})? $data->{'total'}:$data->{'maxResults'};
    foreach my $i (0 .. $of-1)
    {
      my $htidsonly = 1;
      my $item = $data->{'issues'}->[$i];
      my $tx = $item->{'key'};
      printf "$tx (%d of $of)\n", $i+1 if $verbose;
      my @fields = ('customfield_10040','customfield_10041');
      foreach my $field (@fields)
      {
        my $desc = $item->{'fields'}->{$field};
        print "  Desc '$desc'\n" if $verbose > 2;
        if (defined $desc)
        {
          my @lines = split /([\r|\n]+)|([;,\s*])/, $desc;
          foreach my $line (@lines)
          {
            next if $line =~ m/catalog\.hathitrust\.org\/api\/volumes\/oclc/;
            if ($line =~ m/handle\.net\/.+?\/([a-z0-9]+\.[^;,\s]+)/ ||
                $line =~ m/hathitrust.org\/cgi\/pt\?id=([a-z0-9]+\.[^;,\s]+)/)
            {
              print "  HTID $1 from $line\n" if $verbose and !defined $txs{$tx}->{$1};
              $txs{$tx}->{$1} = 1;
            }
            elsif ($line =~ m/Record\/(\d+)/ || $desc =~ m/ItemID=([a-z]+\.[^;,\s]+)/)
            {
              print "  SYSID $1 from $line\n" if $verbose and !defined $txs{$tx}->{$1};
              $txs{$tx}->{$1} = $1;
              $htidsonly = 0;
            }
            elsif ($line =~ m/([a-z0-9]+\.[^;,\s]+)/)
            {
              print "  HTID $1 from $line\n" if $verbose and !defined $txs{$tx}->{$1};
              $txs{$tx}->{$1} = 1;
            }
          }
        }
      }
      if (defined $txs{$tx})
      {
        my $comments = Jira::GetComments($crmsWorld, $ua, $tx);
        my $bail = 0;
        foreach my $comment (@$comments)
        {
          print "$tx comment: '$comment'\n\n" if $verbose > 2;
          if ($comment =~ m/\[CRMS\s+do\s+not\s+ingest\]/i)
          {
            print RED "$tx: ingest disabled by '$comment'\n" if $verbose;
            $bail = 1;
            last;
          }
        }
        if ($bail)
        {
          delete $txs{$tx};
        }
        else
        {
          AddDuplicates($tx, \%txs) unless $htidsonly == 1;
          my @k = keys %{$txs{$tx}};
          if (scalar @k == 1 && $k[0] !~ m/\./)
          {
            print BOLD RED "$tx: no Hathi ID found for probable serial\n" if $verbose;
            push @$systemserials, $tx;
            delete $txs{$tx};
          }
        }
      }
      else
      {
        print BOLD RED "Warning: could not find ids for $tx\n" if $verbose;
        push @$noids, $tx;
      }
    }
  };
  $crmsUS->SetError("Error: $@") if $@;
  return \%txs;
}

sub AddDuplicates
{
  my $tx  = shift;
  my $txs = shift;
  my $ids = $txs->{$tx};
  my %seen;
  foreach my $id (sort keys %{$ids})
  {
    #print "  Duplicates for $id\n";
    my $record = $crmsUS->GetMetadata($id);
    my $sysid = $record->sysid;
    next if defined $seen{$sysid};
    if (! defined $record && $id =~ m/\./)
    {
      my $id2 = $crmsUS->Dollarize($id, \$record);
      if (defined $id2)
      {
        print "  $id dollarized to $id2\n" if $verbose;
        delete $ids->{$id};
        $ids->{$id2} = 1;
        $id = $id2;
      }
    }
    if (! defined $record)
    {
      print BOLD RED "  Warning: could not get metadata for $id\n" if $verbose;
      next;
    }
    if (IsFormatSerial($record))
    {
      print "  $id is serial, skipping duplicates\n"  if $verbose;
      $seen{$id} = 1;
      next;
    }
    my $rows2 = $crmsUS->VolumeIDsQuery($sysid, $record);
    if ($crmsUS->DoesRecordHaveChron($sysid, $record))
    {
      my $hasid = 0;
      if ($id !~ m/\./)
      {
        foreach my $line (@{$rows2})
        {
          my ($id2,$chron,$rights) = split '__', $line;
          if (defined $ids->{$id2})
          {
            $hasid = 1;
            last;
          }
        }
      }
      if ($hasid)
      {
        print "  $id has chron, skipping duplicates\n" if $verbose;
        $seen{$id} = 1;
        next;
      }
    }
    foreach my $line (@{$rows2})
    {
      my ($id2,$chron,$rights) = split '__', $line;
      if (! defined $ids->{$id2})
      {
        print "  duplicate HTID $id2 from $id\n" if $verbose;
        $ids->{$id2} = $ids->{$id};
      }
    }
  }
}

# Look at leader[6] and leader[7]
# If leader[6] is in {a t} and leader[7] is 's' then Serial
sub IsFormatSerial
{
  my $record = shift;

  my $ldr  = $record->xml->findvalue('//*[local-name()="leader"]');
  my $type = substr $ldr, 6, 1;
  my $lev  = substr $ldr, 7, 1;
  my %types = ('a'=>1, 't'=>1);
  my %levs = ('s'=>1);
  return 1 if $types{$type}==1 && $levs{$lev}==1;
  return 0;
}

sub HasPreviousOneOff
{
  my $tx = shift;

  foreach my $crms ($crmsUS, $crmsWorld)
  {
    my $sql = 'SELECT COUNT(*) FROM queue WHERE source=?';
    return 'queue' if $crms->SimpleSqlGet($sql, $tx) >= 1;
    my $sql = 'SELECT COUNT(*) FROM exportdata WHERE src=?';
    return 'exportdata' if $crms->SimpleSqlGet($sql, $tx) >= 1;
    $sql = "SELECT COUNT(*) FROM historicalreviews WHERE note LIKE '%$tx%'";
    if ($crms->SimpleSqlGet($sql) >= 1)
    {
      $sql = "SELECT CONCAT_WS(',',user) FROM historicalreviews WHERE note LIKE '%$tx%'";
      return $crms->SimpleSqlGet($sql);
    }
  }
  return undef;
}

print "Warning (US): $_\n" for @{$crmsUS->GetErrors()};
print "Warning (World): $_\n" for @{$crmsWorld->GetErrors()};
