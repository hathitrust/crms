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

my $usage = <<END;
USAGE: $0 [-ehinopv] [-l LIMIT]

Loads volumes from all files in the prep directory with the extension
'corrections'. The file format is a tab-delimited file with volume id
and (optional) Jira ticket number.

-e         Skip corrections export.
-h         Print this help message.
-i         Skip corrections import.
-l LIMIT   Limit the number of one-off tickets to LIMIT
-n         No-op; reports what would be done but do not modify the database.
-o         Skip one-off import.
-p         Run in production.
-v         Emit debugging information.
END

my $noexport;
my $help;
my $lim;
my $noimport;
my $noop;
my $nooneoff;
my $production;
my $verbose;

Getopt::Long::Configure ('bundling');
die 'Terminating' unless GetOptions(
           'e'    => \$noexport,
           'h|?'  => \$help,
           'i'    => \$noimport,
           'l:s'  => \$lim,
           'n'    => \$noop,
           'o'    => \$nooneoff,
           'p'    => \$production,
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
print "Verbosity $verbose\n" if $verbose;

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
  foreach my $id (sort keys %ids)
  {
    my $tx = $ids{$id};
    print "$tx\n" if $verbose;
    $tx = undef if $tx eq '?';
    my $record = $crmsUS->GetMetadata($id);
    if (! defined $record)
    {
      my $id2 = $crmsUS->Dollarize($id, \$record);
      $id = $id2 if defined $id2;
    }
    if (!defined $record)
    {
      print "Warning: could not get metadata for $id\n";
      next;
    }
    else
    {
      $crmsUS->ClearErrors();
    }
    # FIXME: what if the metadata is not available at all?
    my $where = $crmsUS->GetRecordPubCountry($id, $record);
    my $obj;
    foreach my $sys (@systems)
    {
      my $cs = $sys->GetCountries(1);
      if (!defined $cs || $cs->{$where} == 1)
      {
        $obj = $sys;
        printf "Chose %s for $where\n", $sys->System();
        last;
      }
    }
    if (0 == $obj->SimpleSqlGet('SELECT COUNT(*) FROM corrections WHERE id=?', $id))
    {
      my $sql = 'REPLACE INTO corrections (id,ticket) VALUES (?,?)';
      printf "Replacing $id (%s) in %s ($where)\n", (defined $tx)? $tx:'undef', $obj->System() if $verbose;
      $obj->PrepareSubmitSql($sql, $id, $tx) unless $noop;
      $obj->UpdateMetadata($id, 1, $record) unless $noop;
    }
    else
    {
      printf "Skipping $id (%s); already in %s ($where)\n", (defined $tx)? $tx:'undef', $obj->System() if $verbose;
    }
  }
  foreach my $file (@files)
  {
    print "Moving $file to $ar\n";
    File::Copy::move($file, $ar) unless $noop;
  }
}

if (!$noexport)
{
  Corrections::ExportCorrections($crmsUS, $noop);
  Corrections::ExportCorrections($crmsWorld, $noop);
}

if (!$nooneoff)
{
  my $hash = OneoffQuery();
  foreach my $tx (keys %{$hash})
  {
    print "$tx (add phase)\n";
    my $ids = $hash->{$tx};
    my $prev = HasPreviousOneOff($tx);
    if (defined $prev)
    {
      print "  Previous one-off detected from $prev; skipping\n";
      next;
    }
    foreach my $id (keys %{$ids})
    {
      next unless $id =~ m/\./;
      my $record = $crmsUS->GetMetadata($id);
      if (! defined $record)
      {
        my $id2 = $crmsUS->Dollarize($id, \$record);
        $id = $id2 if defined $id2;
      }
      if (!defined $record)
      {
        print "  Warning: could not get metadata for $id\n";
        next;
      }
      else
      {
        $crmsUS->ClearErrors();
      }
      print "  Adding $id\n" if $verbose;
      next if $noop;
      my $err = $crmsWorld->AddItemToQueueOrSetItemActive($id, 4, 1, $tx, 'oneoff');
      if ('1' eq substr $err, 0, 1)
      {
        print "  $id: $err\n";
      }
      elsif ($verbose > 1)
      {
        print "  $id: $err\n";
      }
    }
  }
}

sub OneoffQuery
{
  my $mail = 'copyrightinquiry@umich.edu';

  use Jira;
  my $ua = Jira::Login($crmsUS);
  my %txs;
  return unless defined $ua;
  my $url = 'https://wush.net/jira/hathitrust/rest/api/2/search?jql="HathiTrust%20Contact"~"' .
             $mail . '" AND (status=1 OR status=4 OR status=3)';
  $url .= '&maxResults=' . $lim if defined $lim;
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
      my $item = $data->{'issues'}->[$i];
      my $tx = $item->{'key'};
      printf "$tx (%d of $of)\n", $i+1;
      my @fields = ('customfield_10040','customfield_10041');
      foreach my $field (@fields) # FOREACH FIELD
      {
        my $desc = $item->{'fields'}->{$field};
        print "  Desc '$desc'\n" if $verbose > 2;
        if (defined $desc)
        {
          my @lines = split /([\r|\n]+)|([;,\s*])/, $desc;
          foreach my $line (@lines)
          {
            if ($line =~ m/handle\.net\/.+?\/([a-z0-9]+\.[^;,\s]+)/ ||
                $line =~ m/hathitrust.org\/cgi\/pt\?id=([a-z0-9]+\.[^;,\s]+)/)
            {
              print "  HTID $1 from $line\n" if $verbose and !defined $txs{$tx}->{$1};
              $txs{$tx}->{$1} = 1;
            }
            elsif ($line =~ m/Record\/(\d+)/ || $desc =~ m/ItemID=([a-z]+\.[^;,\s]+)/)
            {
              print "  SYSID $1 from $line\n" if $verbose;
              $txs{$tx}->{$1} = $1;
            }
            elsif ($line =~ m/([a-z0-9]+\.[^;,\s]+)/)
            {
              print "  HTID $1 from $line\n" if $verbose and !defined $txs{$tx}->{$1};
              $txs{$tx}->{$1} = 1;
            }
          }
          print BOLD RED "Warning: could not find ids for $tx\n" unless defined $txs{$tx};
        }
      }
      AddDuplicates($tx, \%txs);
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
        print "  $id dollarized to $id2\n";
        delete $ids->{$id};
        $ids->{$id2} = 1;
        $id = $id2;
      }
    }
    if (! defined $record)
    {
      print "  Warning: could not get metadata for $id\n";
      next;
    }
    if (IsFormatSerial($record))
    {
      print "  $id is serial, skipping duplicates\n";
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
        print "  $id has chron, skipping duplicates\n";
        $seen{$id} = 1;
        next;
      }
    }
    foreach my $line (@{$rows2})
    {
      my ($id2,$chron,$rights) = split '__', $line;
      if (! defined $ids->{$id2})
      {
        print "  duplicate HTID $id2 from $id\n";
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
    my $sql = 'SELECT COUNT(*) FROM exportdata WHERE src=?';
    return $tx if $crms->SimpleSqlGet($sql, $tx) >= 1;
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
