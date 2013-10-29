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
USAGE: $0 [-hnpv] [-x SYS]

Loads volumes from all files in the prep directory with the extension
'corrections'. The file format is a tab-delimited file with volume id
and (optional) Jira ticket number.

-h         Print this help message.
-n         No-op; reports what would be done but do not modify the database.
-p         Run in production.
-v         Emit debugging information.
END

my $help;
my $noop;
my $production;
my $verbose;

Getopt::Long::Configure ('bundling');
die 'Terminating' unless GetOptions(
           'h|?'  => \$help,
           'n'    => \$noop,
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

print "Verbosity $verbose\n" if $verbose;

my $prep = $crmsUS->get('root') . '/prep/c/crms/';
my $ar = $crmsUS->get('root') . '/prep/c/crms/archive/';
print "Looking in $prep\n" if $verbose;
my @files = grep {/\.corrections$/} <$prep/*>;
foreach my $file (@files)
{
  print "$file\n" if $verbose;
  open my $fh, $file or die "failed to open: $@ \n";
  foreach my $line (<$fh>)
  {
    chomp $line;
    next unless length $line;
    my ($id,$ticket) = split "\t", $line;
    my $record = $crmsUS->GetMetadata($id);
    if (!defined $record && $id =~ m/uc1\.b\d{1,6}$/)
    {
      $crmsUS->ClearErrors();
      my $id2 = $id;
      $id2 =~ s/b/\$b/;
      $record = $crmsUS->GetMetadata($id2);
      if (!defined $record)
      {
        print "$id ($id2) record undefined\n";
        next;
      }
      print "Adding $id as $id2\n" if $verbose;
      $id = $id2;
    }
    print "Warning: could not get metadata for $id\n" unless defined $record;
    # FIXME: what if the metadata is not available at all?
    my $where = $crmsUS->GetRecordPubCountry($id, $record);
    # FIXME: maybe make this an API exposed by the Candidates_sys modules.
    my $obj = ($where eq 'USA')? $crmsUS:$crmsWorld;
    my $sql = 'REPLACE INTO corrections (id,ticket) VALUES (?,?)';
    printf "Replacing $id (%s) in %s ($where)\n", (defined $ticket)? $ticket:'undef', $obj->System() if $verbose;
    $obj->PrepareSubmitSql($sql, $id, $ticket) unless $noop;
    $obj->UpdateMetadata($id, 1, $record) unless $noop;
  }
  close $fh;
  print "Moving $file to archive $ar\n" if $verbose;
  File::Copy::move($file, $ar);
}

Corrections::ExportCorrections($crmsUS, $noop);
Corrections::ExportCorrections($crmsWorld, $noop);

print "Warning (US): $_\n" for @{$crmsUS->GetErrors()};
print "Warning (World): $_\n" for @{$crmsWorld->GetErrors()};
