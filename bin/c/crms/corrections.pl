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

my $usage = <<END;
USAGE: $0 [-ehinopv]

Loads volumes from all files in the prep directory with the extension
'corrections'. The file format is a tab-delimited file with volume id
and (optional) Jira ticket number.

-e         Skip corrections export.
-h         Print this help message.
-i         Skip corrections import.
-n         No-op; reports what would be done but do not modify the database.
-o         Skip one-off import.
-p         Run in production.
-v         Emit debugging information.
END

my $noexport;
my $help;
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
  foreach my $id (keys %{$hash})
  {
    my $tx = $hash->{$id};
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
    my $where = $crmsUS->GetRecordPubCountry($id, $record);
    my $obj;
    foreach my $sys (@systems)
    {
      my $cs = $sys->GetCountries(1);
      if (!defined $cs || $cs->{$where} == 1)
      {
        $obj = $sys;
        last;
      }
    }
    if (!defined $obj)
    {
      print "Error: could not find a system for $id ($where)\n";
      next;
    }
    printf "Adding $id (%s) in %s ($where)\n", (defined $tx)? $tx:'undef', $obj->System() if $verbose;
    next if $noop;
    my $err = $obj->AddItemToQueueOrSetItemActive($id, 4, 1, $tx, 'oneoff');
    if ('0' ne substr $err, 0, 1)
    {
      print "$id: $tx $err\n";
    }
  }
}

sub OneoffQuery
{
  my $mail = 'copyrightinquiry@umich.edu';

  use Jira;
  my $ua = Jira::Login($crmsUS);
  my %ids;
  return unless defined $ua;
  my $url = 'https://wush.net/jira/hathitrust/rest/api/2/search?jql="HathiTrust%20Contact"~"' .
             $mail . '" AND (status=1 OR status=4 OR status=3)&maxResults=1000';
  my $req = HTTP::Request->new(GET => $url);
  my $res = $ua->request($req);
  if (!$res->is_success())
  {
    $crmsUS->SetError("Got " . $res->code() . " getting $url\n");
    return;
  }
  my $json = JSON::XS->new;
  my $content = $res->content;
  eval {
    my $data = $json->decode($content);
    my $of = $data->{'total'};
    foreach my $i (0 .. $of-1)
    {
      my $id;
      my $item = $data->{'issues'}->[$i];
      my $tx = $item->{'key'};
      my $desc = $item->{'fields'}->{'description'};
      #printf "1 %s\n", $item->{'key'} unless defined $desc;
      if (defined $desc && $desc =~ m/\/pt\?.*?id=([a-z]+\.[^;,\s]+)/)
      {
        $id = $1;
        #print "1 $i $tx ($id)\n";
      }
      $desc = $item->{'fields'}->{'customfield_10040'};
      #printf "2 %s\n", $item->{'key'} unless defined $desc;
      if (!defined $id && defined $desc && $desc =~ m/handle\.net\/.+\/([a-z]+\.[^;,\s]+)/)
      {
        $id = $1;
        #print "2 $i $tx ($id)\n";
      }
      $desc = $item->{'fields'}->{'summary'};
      #printf "2 %s\n", $item->{'key'} unless defined $desc;
      if (!defined $id && defined $desc &&
          ($desc =~ m/RecordNo=(\d+)/ || $desc =~ m/ItemID=([a-z]+\.[^;,\s]+)/))
      {
        $id = $1;
        #print "3 $i $tx ($id)\n";
      }
      if (defined $id)
      {
        if ($id !~ m/\./)
        {
          my $rows = $crmsUS->VolumeIDsQuery($id);
          foreach my $line (@{$rows})
          {
            my ($id2,$chron,$rights) = split '__', $line;
            $ids{$id2} = $tx;
          }
        }
        else
        {
          $ids{$id} = $tx;
        }
      }
      else
      {
        print "No item ID found for $tx\n" if $verbose;
      }
    }
  };
  $crmsUS->SetError("Error: $@") if $@;
  return \%ids;
}


print "Warning (US): $_\n" for @{$crmsUS->GetErrors()};
print "Warning (World): $_\n" for @{$crmsWorld->GetErrors()};
