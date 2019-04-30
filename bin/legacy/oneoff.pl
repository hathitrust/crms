#!/usr/bin/perl
BEGIN 
{
  unshift(@INC, $ENV{'SDRROOT'}. '/crms/cgi');
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
USAGE: $0 [-hjnopqv] [-l LIMIT] [-m MAIL_ADDR [-m MAIL_ADDR2...]]
       [-t TICKET [-t TICKET2...]]

Reports CRMS status for Jira copyrightinquiry\@umich.edu tickets.

-h         Print this help message.
-j         Jira no-op; do not submit any changes to jira even if -n flag is unset.
-l LIMIT   Limit the number of tickets to LIMIT.
-m ADDR    Mail the report to ADDR. May be repeated for multiple addresses.
-n         No-op; reports what would be done but do not modify the database.
-p         Run in production.
-q         Do not emit report (ignored if -m is used).
-t TICKET  Limit to the Jira ticket(s) specified.
-v         Emit debugging information. May be repeated for increased verbosity.
END

my $help;
my $instance;
my $nojira;
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
           'j'    => \$nojira,
           'l:s'  => \$lim,
           'm:s@' => \@mails,
           'n'    => \$noop,
           'p'    => \$production,
           'q'    => \$quiet,
           't:s@' => \@tix,
           'v+'   => \$verbose);
$instance = 'production' if $production;
die "$usage\n\n" if $help;

my $crmsUS = CRMS->new(
    verbose  => $verbose,
    instance => $instance
);

my $crms = CRMS->new(
    sys      => 'crmsworld',
    verbose  => $verbose,
    instance => $instance
);

$verbose = 0 unless defined $verbose;
print "Verbosity $verbose\n" if $verbose;
print "No-op set\n" if $noop and $verbose;
print "Jira no-op set\n" if $nojira and $verbose;
my $title = 'CRMS Jira Copyright Inquiry Report';
my $html = $crmsUS->StartHTML($title);
my %data = ('html' => $html, 'verbose' => $verbose );
my $ua = Jira::Login($crmsUS);

my %txs; # map of ticket id -> arrayref if HTIDs
my %errs; # map of ticket id -> associated error message
my %assignees; # map of ticket id -> assignee
my %created; # map of ticket id -> creation date
OneoffQuery();
$html .= sprintf "<h3> %d unique %s</h3>\n", scalar keys %txs, $crms->Pluralize('ticket', scalar keys %txs);
$html .= '<table border="1"><tr><th>Ticket</th><th>Created</th><th>ID</th>'.
         '<th>Author</th><th>Title</th><th>Pub Date</th><th>Note</th>'.
         "<th>Assignee</th></tr>\n";
#my $closed = GetClosedTickets($crms, $ua);
#foreach my $tx (keys %{$closed})
#{
#  my $url = Jira::LinkToJira($tx);
#  my $stat = $closed->{$tx};
#  if ($stat eq 'Status unknown')
#  {
#    $html .= "  <tr><td>$url</td><td/><td/><td/><td/><td/>".
#      '<td><span style="color:red;">In queue; unable to get current Jira status</span></td><td/></tr>' . "\n";
#  }
#  else
#  {
#    $html .= "  <tr><td>$url</td><td/><td/><td/><td/><td/>".
#      '<td><span style="color:blue;">Ticket marked as '.$stat.'; deleted</span></td><td>&#x2715;</td></tr>' . "\n";
#  }
#}
my @sorted = sort {
    my $aa = lc $assignees{$a};
    my $ba = lc $assignees{$b};
    #print "'$aa' cmp '$ba'?\n";
    $aa cmp $ba
    ||
    $a cmp $b;
  } keys %txs;
foreach my $tx (@sorted)
{
  my $ids = $txs{$tx};
  #my $prev = HasPreviousOneOff($tx);
  my $i = 0;
  #if (defined $prev)
  #{
  #  print "  Previous one-off detected from $prev; skipping\n" if $verbose;
  #  my $msg = "Previous one-off by $prev";
  #  $msg = 'Already in queue' if $prev eq 'queue';
  #  $msg = 'Already exported' if $prev eq 'exportdata';
  #  $html .= '  <tr><td>'. Jira::LinkToJira($tx).
  #           '</td><td/><td/><td/><td/><td><td/><span style="color:red;">'.
  #           "$msg</span></td><td/></tr>\n";
  #}
  #else
  my $addcount = 0;
  my %seen;
  foreach my $id (sort keys %{$ids})
  {
    my $a = '';
    my $t = '';
    my $d = '';
    #my $added = '';
    my $url = '';
    my $url2 = '';
    my $created = '';
    my $note = ''; # Error message or comment
    my $noteStyle = ''; # e.g. color:red;
    if ($id eq 'error')
    {
      $url = Jira::LinkToJira($tx);
      $note = ucfirst $errs{$tx};
      $noteStyle = 'color:red;';
    }
    else
    {
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
        $note = 'Metadata unavailable';
        $noteStyle = 'color:red;';
      }
      else
      {
        my $sysid = $record->sysid;
        print "Note was '$note'\n" if $verbose > 2;
        $track = GetTrackingString($id);
        $note = $track if length $track;
        print "Note now '$note'\n" if $verbose > 2;
        my $status;
        my $pri = 2;
        my $jpri = Jira::GetIssuePriority($crmsUS, $ua, $tx);
        if (defined $jpri && $jpri < 3)
        {
          $pri = 2.1 if $jpri == 3;
          $pri = 2.2 if $jpri == 2;
          $pri = 2.3 if $jpri == 1;
        }
        my $exp = $crms->SimpleSqlGet('SELECT COUNT(*) FROM exportdata WHERE id=?', $id);
        if ((!$seen{$sysid} || $record->countEnumchron) && !$exp)
        {
          print "$id: trying to add\n" if $verbose > 2;
          $status = $crms->AddItemToQueueOrSetItemActive($id, $pri, 0, $tx, 'Jira', $noop, $record);
        }
        else
        {
          $status = {'status' => 2, 'msg' => '(duplicate)'};
        }
        $seen{$sysid} = $status->{'status'};
        if ('1' eq $status->{'status'})
        {
          $note = ucfirst $status->{'msg'};
          if ($note =~ m/current\s+rights\s+pd\//i)
          {
            $note .= '; <b>possible takedown</p>' if $note =~ m/current\s+rights\s+pd\/(?!bib)/i;
          }
          $noteStyle = 'color:red';
          print BOLD RED "  $id: $note\n" if $verbose;
        }
        elsif ('0' eq $status->{'status'})
        {
          $note = 'Added to queue; '. $crms->GetTrackingInfo($id, 1, 0, 1);
          $noteStyle = 'color:blue;';
          $addcount++;
        }
        #else
        #{
          #$status = sprintf '<span style="color:blue">%s</span>', substr $err, 1;
          #$addcount++;
        #}
        #$crms->PrepareSubmitSql('INSERT INTO tickets (ticket,id) VALUES (?,?)', $tx, $id) unless $noop;
      }
      $url = Jira::LinkToJira($tx) if $i == 0;
      $created = $created{$tx} if $i == 0;
      $created =~ m/^(\d\d\d\d-\d\d-\d\d).*/;
      $created = $1;
      $url2 = $crms->LinkToPT($id, $id);
      my $ec = $record->enumchron;
      $t = $record->title . (($ec)? " [$ec]":'');
      $a = $record->author;
      $d = $crms->FormatPubDate($id, $record);
    }
    $html .= sprintf "  <tr><td>$url</td><td>$created</td><td style='white-space:nowrap;'>$url2</td>".
                     "<td>$a</td><td>$t</td><td>$d</td>".
                     "<td><span style='$noteStyle'>$note</span></td>".
                     "<td>%s</td></tr>\n", $assignees{$tx};
    $i++;
  } # foreach id
  if ($addcount == 0)
  {
    #my $msg = 'CRMS could not find any HathiTrust volumes that are in-scope for review.';
    #Jira::AddComment($crms, $tx, $msg, $ua, $noop|$nojira);
    #print "Jira::AddComment to $tx\n" if $verbose;
  }
  #$crms->PrepareSubmitSql('INSERT INTO tickets (ticket) VALUES (?)', $tx) if $i == 0 and !$noop;
} # foreach tx
$html .= "</table>\n";

# Close and report tickets that have been fully resolved
#my $ref = $crms->SelectAll('SELECT DISTINCT(ticket) FROM tickets WHERE id IS NOT NULL AND closed=0');
#if (scalar @{$ref})
#{
#  my $didheader = 0;
#  foreach my $row (@{$ref})
#  {
#    my $tx = $row->[0];
#    if (IsTicketResolved($tx))
#    {
#      my @ids;
#      my $dispo = "Reviewed by CRMS with the following results:\n\n";
#      push @ids, $_->[0] for @{$crms->SelectAll('SELECT id FROM tickets WHERE id IS NOT NULL AND ticket=?', $tx)};
#      foreach my $id (@ids)
#      {
#        print "$tx: $id\n";
#        my $sql = 'SELECT CONCAT(attr,"/",reason) FROM exportdata WHERE id=? AND src=? ORDER BY time DESC LIMIT 1';
#        my $rights = $crms->SimpleSqlGet($sql, $id, $tx);
#        $dispo .= "  $id: $rights\n";
#      }
#      my $dispo2 = $dispo;
#      $dispo2 =~ s/\n/<br\/>/g;
#      my $stat = Jira::GetIssueStatus($crms, $ua, $tx);
#      $html .= "<h3>One-off requests closed in Jira</h3>\n" unless $didheader;
#      $html .= "<table border='1'><tr><th>Ticket</th><th>Disposition</th><th>Jira Status</th></tr>\n" unless $didheader;
#      $didheader = 1;
#      $html .= "  <tr><td>$tx</td><td>$dispo2</td><td>$stat</td></tr>\n";
#      $crms->PrepareSubmitSql('UPDATE tickets SET closed=1 WHERE ticket=?', $tx) unless $noop;
#      print GREEN "Closing $tx with disposition: '$dispo'\n" if $verbose;
#      Jira::AddComment($crms, $tx, $dispo, $ua, $noop|$nojira);
#    }
#  }
#  $html .= "</table>\n" if $didheader;
#}

for (@{$crmsUS->GetErrors()})
{
  s/\n/<br\/>\n/g;
  $html .= "<i>Warning: $_</i><br/>\n";
}
for (@{$crms->GetErrors()})
{
  s/\n/<br\/>\n/g;
  $html .= "<i>Warning: $_</i><br/>\n";
}

$html .= "</body></html>\n";


if (scalar @mails)
{
  @mails = map { ($_ =~ m/@/)? $_:($_ . '@umich.edu'); } @mails;
  if ($verbose)
  {
    print "Sending mail to:\n";
    print "  $_\n" for @mails;
  }
  #if (!$noop)
  {
    use Mail::Sendmail;
    my $bytes = encode('utf8', $html);
    my %mail = ('from'         => 'crms-mailbot@umich.edu',
                'to'           => join ',', @mails,
                'subject'      => $title,
                'content-type' => 'text/html; charset="UTF-8"',
                'body'         => $bytes);
    sendmail(%mail) || $crms->SetError("Error: $Mail::Sendmail::error\n");
  }
}
else
{
  print "$html\n" unless defined $quiet;
}

sub OneoffQuery
{
  return unless defined $ua;
  my $url = 'https://wush.net/jira/hathitrust/rest/api/2/search?jql="HathiTrust%20Contact"~"'.
            'copyrightinquiry@umich.edu" AND (status=1 OR status=3 OR status=4)&maxResults=200';
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
      if (0 < $crms->SimpleSqlGet('SELECT COUNT(*) FROM tickets WHERE ticket=?', $tx))
      {
        print BLUE "$tx: already checked\n" if $verbose;
        next;
      }
      my @fields = ('customfield_10040','customfield_10041');
      foreach my $field (@fields)
      {
        my $desc = $item->{'fields'}->{$field};
        print "  $field desc '$desc'\n" if $verbose > 2;
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
              my $sysid = $1;
              my $delta = 9 - length $sysid;
              #print "Delta $delta from $sysid\n" if $verbose and $delta > 0;
              $sysid = ('0'x$delta) . $sysid if $delta > 0;
              print "  SYSID $sysid from $line\n" if $verbose and !defined $txs{$tx}->{$sysid};
              $txs{$tx}->{$sysid} = $sysid;
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
      my $assign = $item->{'fields'}->{'assignee'}->{'emailAddress'};
      $assignees{$tx} = $assign;
      $created{$tx} = $item->{'fields'}->{'created'};
      if (defined $txs{$tx})
      {
        my $comments = Jira::GetComments($crms, $ua, $tx);
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
          AddDuplicates($tx) unless $htidsonly == 1;
          my @k = keys %{$txs{$tx}};
          if (scalar @k == 1 && $k[0] !~ m/\./)
          {
            print BOLD RED "$tx: no Hathi ID found for probable serial\n" if $verbose;
            $errs{$tx} = 'no Hathi IDs found for probable serial';
            $txs{$tx} = {'error'};
          }
        }
      }
      else
      {
        print BOLD RED "Warning: could not find ids for $tx\n" if $verbose;
        $errs{$tx} = 'no Hathi IDs found for probable serial';
        $txs{$tx} = {'error'};
      }
    }
  };
  $crmsUS->SetError("Error: $@") if $@;
}

sub AddDuplicates
{
  my $tx  = shift;

  my $ids = $txs{$tx};
  my %seen;
  foreach my $id (sort keys %{$ids})
  {
    #print "  Duplicates for $id\n";
    my $record = $crmsUS->GetMetadata($id);
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
    my $sysid = $record->sysid;
    next if defined $seen{$sysid};
    if (IsFormatSerial($record))
    {
      print "  $id is serial, skipping duplicates\n"  if $verbose;
      $seen{$id} = 1;
      next;
    }
    my $rows2 = $crmsUS->VolumeIDsQuery($sysid, $record);
    if ($record->countEnumchron)
    {
      my $hasid = 0;
      if ($id !~ m/\./)
      {
        foreach my $ref (@{$rows2})
        {
          my $id2 = $ref->{'id'};
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

  foreach my $crms ($crmsUS, $crms)
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

sub GetTrackingString
{
  my $id = shift;

  my $track = $crms->GetTrackingInfo($id, 1, 0, 1);
  if (length $track)
  {
    $track = 'CRMS World: '. lcfirst $track;
  }
  else
  {
    $track = $crmsUS->GetTrackingInfo($id, 1, 0, 1);
    $track = 'CRMS US: '. lcfirst $track if length $track;
  }
  $track =~ s/exported/determined/;
  return $track;
}

sub IsTicketResolved
{
  my $tx = shift;

  my $n = $crms->SimpleSqlGet('SELECT COUNT(*) FROM exportdata WHERE src=?', $tx);
  my $of = $crms->SimpleSqlGet('SELECT COUNT(*) FROM tickets WHERE ticket=?', $tx);
  return ($n == $of);
}

sub GetClosedTickets
{
  my $self = shift;
  my $ua   = shift;

  my $sql = 'SELECT DISTINCT source FROM queue WHERE source LIKE "HTS%"';
  my @txs;
  my %stats2;
  push @txs, $_->[0] for @{$self->SelectAll($sql)};
  if (scalar @txs > 0)
  {
    use Jira;
    $ua = Jira::Login($self) unless defined $ua;
    my $stats = Jira::GetIssuesStatus($self, $ua, \@txs);
    foreach my $tx (keys %{$stats})
    {
      my $stat = $stats->{$tx};
      $stats2{$tx} = $stat if $stat eq 'Closed' or $stat eq 'Resolved' or $stat eq 'Status unknown';
    }
  }
  return \%stats2;
}

print "Warning (US): $_\n" for @{$crmsUS->GetErrors()};
print "Warning (World): $_\n" for @{$crms->GetErrors()};

