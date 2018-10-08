#!/usr/bin/perl

BEGIN 
{
  unshift(@INC, $ENV{'SDRROOT'}. '/crms/cgi');
}

use strict;
use warnings;
use CRMS;
use Getopt::Long;
use Utilities;
use JSON::XS;
use Term::ANSIColor qw(:constants);
$Term::ANSIColor::AUTORESET = 1;
use Data::Dumper;

my $usage = <<END;
USAGE: $0 [-hnpv] [-m USER [-m USER...]]

Migrates data from CRMS-World to CRMS-US.

-h       Print this help message.
-p       Run in production.
-t       Run in training.
-v       Be verbose.
END

my $help;
my $instance;
my $production;
my $training;
my $verbose = 0;

Getopt::Long::Configure ('bundling');
die 'Terminating' unless GetOptions(
           'h|?'  => \$help,
           'p'    => \$production,
           't'    => \$training,
           'v+'   => \$verbose);
$instance = 'production' if $production;
$instance = 'crms_training' if $training;
print "Verbosity $verbose\n" if $verbose;
die "$usage\n\n" if $help;


my $crmsWorld = CRMS->new(
    sys      => 'crmsworld',
    verbose  => $verbose,
    instance => $instance
);
my $crmsUS = CRMS->new(
    sys      => 'crms',
    verbose  => $verbose,
    instance => $instance
);
my $json = JSON::XS->new->utf8->canonical(1)->pretty(0);
my %projmap; # Map of World project id to US id.
my %authmap; # Map of World authority id to US id.
my %rightsmap; # Map of World rights id to US id.
my %catmap; # Map of World category id to US id.
my %instmap; # Map of World institution id to US id.
my $dbhWorld = $crmsWorld->GetDb();

Reset();
MigrateSources();
MigrateUsers();
MigrateProjects();
#MigrateCandidates();
#MigrateQueue();
#MigrateExportdata();
#UpdateStats();

sub Reset
{
  my $newProj = $crmsUS->SimpleSqlGet('SELECT id FROM projects WHERE name="Commonwealth"');
  if ($newProj)
  {
    $crmsUS->PrepareSubmitSql('DELETE FROM candidates WHERE project>=?', $newProj);
    $crmsUS->PrepareSubmitSql('DELETE FROM reviews WHERE id IN (SELECT id FROM queue WHERE project>=?)', $newProj);
    $crmsUS->PrepareSubmitSql('DELETE FROM queue WHERE project>=?', $newProj);
    $crmsUS->PrepareSubmitSql('DELETE FROM historicalreviews WHERE id IN (SELECT id FROM exportdata WHERE project>=?)', $newProj);
    $crmsUS->PrepareSubmitSql('DELETE FROM exportdata WHERE project>=?', $newProj);
    $crmsUS->PrepareSubmitSql('DELETE FROM projectauthorities WHERE project>=?', $newProj);
    $crmsUS->PrepareSubmitSql('DELETE FROM projectcategories WHERE project>=?', $newProj);
    $crmsUS->PrepareSubmitSql('DELETE FROM projectrights WHERE project>=?', $newProj);
    $crmsUS->PrepareSubmitSql('DELETE FROM projectusers WHERE project>=?', $newProj);
    $crmsUS->PrepareSubmitSql('DELETE FROM projects WHERE id>=?', $newProj);
  }
  $crmsUS->PrepareSubmitSql('DELETE FROM rights WHERE id>24');
  $crmsUS->PrepareSubmitSql('DELETE FROM authorities WHERE id>33');
  $crmsUS->PrepareSubmitSql('DELETE FROM categories WHERE id>51');
}

sub MigrateSources
{
  my $sql = 'SELECT id,attr,reason,description FROM rights ORDER BY attr,reason';
  my $ref = $crmsWorld->SelectAll($sql);
  foreach my $row (@{$ref})
  {
    my $usid = $crmsUS->SimpleSqlGet('SELECT id FROM rights WHERE attr=? AND reason=?', $row->[1], $row->[2]);
    if (!$usid)
    {
      $sql = 'INSERT INTO rights (attr,reason,description) VALUES (?,?,?)';
      $crmsUS->PrepareSubmitSql($sql, $row->[1], $row->[2], $row->[3]);
      $usid = $crmsUS->SimpleSqlGet('SELECT MAX(id) FROM rights');
    }
    $rightsmap{$row->[0]} = $usid;
  }
  $sql = 'SELECT id,name,url FROM authorities WHERE url IS NOT NULL AND url!=""';
  $ref = $crmsWorld->SelectAll($sql);
  foreach my $row (@{$ref})
  {
    my $usid = $crmsUS->SimpleSqlGet('SELECT id FROM authorities WHERE name=?', $row->[1]);
    if (!$usid)
    {
      $sql = 'INSERT INTO authorities (name,url) VALUES (?,?)';
      $crmsUS->PrepareSubmitSql($sql, $row->[1], $row->[2]);
      $usid = $crmsUS->SimpleSqlGet('SELECT MAX(id) FROM authorities');
    }
    $authmap{$row->[0]} = $usid;
  }
  $sql = 'SELECT id,name,restricted,interface,need_note,need_und FROM categories';
  $ref = $ref = $crmsWorld->SelectAll($sql);
  foreach my $row (@{$ref})
  {
    my $usid = $crmsUS->SimpleSqlGet('SELECT id FROM categories WHERE name=?', $row->[1]);
    if (!$usid)
    {
      $sql = 'INSERT INTO categories (name,restricted,interface,need_note,need_und) VALUES (?,?,?,?,?)';
      $crmsUS->PrepareSubmitSql($sql, $row->[1], $row->[2], $row->[3], $row->[4], $row->[5]);
      $usid = $crmsUS->SimpleSqlGet('SELECT MAX(id) FROM categories');
    }
    $catmap{$row->[0]} = $usid;
  }
}

sub MigrateUsers
{
  my $sql = 'SELECT id,name,shortname,suffix FROM institutions';
  my $ref = $crmsWorld->SelectAll($sql);
  foreach my $row (@{$ref})
  {
    my $usid = $crmsUS->SimpleSqlGet('SELECT id FROM institutions WHERE shortname=?', $row->[2]);
    if (!$usid)
    {
      $sql = 'INSERT INTO institutions (name,shortname,suffix) VALUES (?,?,?)';
      $crmsUS->PrepareSubmitSql($sql, $row->[1], $row->[2], $row->[3]);
      $usid = $crmsUS->SimpleSqlGet('SELECT MAX(id) FROM institutions');
    }
    $instmap{$row->[0]} = $usid;
  }
  $sql = 'SELECT * FROM users';
  $ref = $dbhWorld->selectall_hashref($sql, 'id');
  foreach my $id (sort keys %{$ref})
  {
    if (!$crmsUS->SimpleSqlGet('SELECT COUNT(*) FROM users WHERE id=?', $id))
    {
      my $row = $ref->{$id};
      my @fields;
      my @values;
      foreach my $key (keys %{$row})
      {
        my $val = $row->{$key};
        $val = $instmap{$val} if $key eq 'institution';
        push @fields, $key;
        push @values, $val;
      }
      $sql = sprintf 'INSERT INTO users (%s) VALUES %s', join(',', @fields),
                                                         $crmsUS->WildcardList(scalar @values);
      $crmsUS->PrepareSubmitSql($sql, @values);
    }
  }
}

sub MigrateProjects
{
  my $sql = 'SELECT id,name,color,autoinherit,group_volumes FROM projects'.
            ' ORDER BY id ASC';
  my $ref = $crmsWorld->SelectAll($sql);
  foreach my $row (@{$ref})
  {
    my ($id, $name, $color, $autoinherit, $group_volumes) = @{$row};
    my $usid;
    $name = 'Commonwealth' if $name eq 'Core';
    $usid = $crmsUS->SimpleSqlGet('SELECT id FROM projects WHERE name=?', $name);
    if (!$usid)
    {
      $sql = 'INSERT INTO projects (name,color,autoinherit,group_volumes) VALUES (?,?,?,?)';
      $crmsUS->PrepareSubmitSql($sql, $name, $color, $autoinherit, $group_volumes);
      $usid = $crmsUS->SimpleSqlGet('SELECT MAX(id) FROM projects WHERE name=?', $name);
    }
    $projmap{$id} = $usid;
  }
  $sql = 'SELECT project,authority FROM projectauthorities';
  $ref = $crmsWorld->SelectAll($sql);
  foreach my $row (@{$ref})
  {
    my @values = ($projmap{$row->[0]}, $authmap{$row->[1]});
    $sql = 'INSERT INTO projectauthorities (project,authority) VALUES (?,?)';
    $crmsUS->PrepareSubmitSql($sql, @values);
  }
  $sql = 'SELECT project,category FROM projectcategories';
  $ref = $crmsWorld->SelectAll($sql);
  foreach my $row (@{$ref})
  {
    my @values = ($projmap{$row->[0]}, $catmap{$row->[1]});
    $sql = 'INSERT INTO projectcategories (project,category) VALUES (?,?)';
    $crmsUS->PrepareSubmitSql($sql, @values);
  }
  $sql = 'SELECT project,rights FROM projectrights';
  $ref = $crmsWorld->SelectAll($sql);
  foreach my $row (@{$ref})
  {
    my @values = ($projmap{$row->[0]}, $rightsmap{$row->[1]});
    $sql = 'INSERT INTO projectrights (project,rights) VALUES (?,?)';
    $crmsUS->PrepareSubmitSql($sql, @values);
  }
  $sql = 'SELECT project,user FROM projectusers';
  $ref = $crmsWorld->SelectAll($sql);
  foreach my $row (@{$ref})
  {
    my @values = ($projmap{$row->[0]}, $row->[1]);
    $sql = 'INSERT INTO projectusers (project,user) VALUES (?,?)';
    $crmsUS->PrepareSubmitSql($sql, @values);
  }
}


sub MigrateCandidates
{
  my $sql = 'SELECT * FROM bibdata';
  my $ref = $dbhWorld->selectall_hashref($sql, 'id');
  foreach my $id (sort keys %{$ref})
  {
    if (!$crmsUS->SimpleSqlGet('SELECT COUNT(*) FROM bibdata WHERE id=?', $id))
    {
      my $row = $ref->{$id};
      my @fields = keys %{$row};
      my @values = map {$row->{$_};} @fields;
      $sql = sprintf 'INSERT INTO bibdata (%s) VALUES %s', join(',', @fields),
                                                         $crmsUS->WildcardList(scalar @values);
      $crmsUS->PrepareSubmitSql($sql, @values);
    }
  }
  $sql = 'SELECT * FROM candidates';
  $ref = $dbhWorld->selectall_hashref($sql, 'id');
  foreach my $id (sort keys %{$ref})
  {
    if (!$crmsUS->SimpleSqlGet('SELECT COUNT(*) FROM candidates WHERE id=?', $id))
    {
      my $row = $ref->{$id};
      $row->{'project'} = $projmap{$row->{'project'}};
      my @fields = keys %{$row};
      my @values = map {$row->{$_};} @fields;
      $sql = sprintf 'INSERT INTO candidates (%s) VALUES %s', join(',', @fields),
                                                         $crmsUS->WildcardList(scalar @values);
      $crmsUS->PrepareSubmitSql($sql, @values);
    }
  }
}

# prepopulated HT catalog (value = 1) or VIAF (value = 2)
# World renNum is NULL or 'on'
sub MigrateQueue
{
  my $sql = 'SELECT * FROM queue';
  my $ref = $dbhWorld->selectall_hashref($sql, 'id');
  foreach my $id (sort keys %{$ref})
  {
    if (!$crmsUS->SimpleSqlGet('SELECT COUNT(*) FROM queue WHERE id=?', $id))
    {
      my $row = $ref->{$id};
      $row->{'project'} = $projmap{$row->{'project'}};
      my @fields = keys %{$row};
      my @values = map {$row->{$_};} @fields;
      $sql = sprintf 'INSERT INTO queue (%s) VALUES %s', join(',', @fields),
                                                         $crmsUS->WildcardList(scalar @values);
      $crmsUS->PrepareSubmitSql($sql, @values);
    }
    next if $crmsUS->SimpleSqlGet('SELECT COUNT(*) FROM reviews WHERE id=?', $id);
    $sql = 'SELECT * FROM reviews WHERE id=?';
    my $ref2 = $dbhWorld->selectall_hashref($sql, 'user', undef, $id);
    foreach my $user (sort keys %{$ref2})
    {
      print "MigrateQueue: $id/$user review\n";
      my $row = $ref2->{$user};
      # renNum or renDate must be defined and nonzero-length for an entry to be made.
      my $did;
      if ((defined $row->{'renNum'} && length $row->{'renNum'}) ||
          (defined $row->{'renDate'} && length $row->{'renDate'}))
      {
        my $data = {(($row->{'renNum'})? 'pub':'ADD') => $row->{'renDate'}};
        if ($row->{'prepopulated'})
        {
          $data->{'src'} = ($row->{'prepopulated'} == 2)? 'VIAF':'catalog';
        }
        my $encdata = $json->encode($data);
        $sql = 'SELECT id FROM reviewdata WHERE data=? LIMIT 1';
        $did = $crmsUS->SimpleSqlGet($sql, $encdata);
        if (!$did)
        {
          $sql = 'INSERT INTO reviewdata (data) VALUES (?)';
          $crmsUS->PrepareSubmitSql($sql, $encdata);
          $sql = 'SELECT MAX(id) FROM reviewdata WHERE data=?';
          $did = $crmsUS->SimpleSqlGet($sql, $encdata);
        }
      }
      my @fields = keys %{$row};
      my @values = map {$row->{$_};} @fields;
      if ($did)
      {
        push @fields, 'data';
        push @values, $did;
      }
      $sql = sprintf 'INSERT INTO reviews (%s) VALUES %s', join(',', @fields),
                                                         $crmsUS->WildcardList(scalar @values);
      $crmsUS->PrepareSubmitSql($sql, @values);
    }
  }
}

sub MigrateExportdata
{
  my $sql = 'SELECT * FROM exportdata';
  my $ref = $dbhWorld->selectall_hashref($sql, 'gid');
  foreach my $gid (sort keys %{$ref})
  {
    my $row = $ref->{$gid};
    $row->{'project'} = $projmap{$row->{'project'}};
    delete $row->{'gid'};
    my @fields = keys %{$row};
    my @values = map {$row->{$_};} @fields;
    $sql = sprintf 'INSERT INTO exportdata (%s) VALUES %s', join(',', @fields),
                                                       $crmsUS->WildcardList(scalar @values);
    $crmsUS->PrepareSubmitSql($sql, @values);
    $sql = 'SELECT gid FROM exportdata WHERE id=? AND time=?';
    $gid = $crmsUS->SimpleSqlGet($sql, $row->{'id'}, $row->{'time'});
    $sql = 'SELECT * FROM historicalreviews WHERE gid=?';
    my $ref2 = $dbhWorld->selectall_hashref($sql, 'user', undef, $gid);
    foreach my $user (sort keys %{$ref2})
    {
      print "MigrateExportdata: $gid/$user review\n";
      my $row = $ref2->{$user};
      delete $row->{'gid'};
      # renNum or renDate must be defined and nonzero-length for an entry to be made.
      my $did;
      if ((defined $row->{'renNum'} && length $row->{'renNum'}) ||
          (defined $row->{'renDate'} && length $row->{'renDate'}))
      {
        my $data = {'date' => $row->{'renDate'}};
        $data->{'pub'} = 1 if $row->{'renNum'};
        if ($row->{'prepopulated'})
        {
          $data->{'src'} = ($row->{'prepopulated'} == 2)? 'VIAF':'catalog';
        }
        if ($row->{'category'} && $row->{'category'} eq 'Crown Copyright')
        {
          $data->{'crown'} = 1;
        }
        my $encdata = $json->encode($data);
        $sql = 'SELECT id FROM reviewdata WHERE data=? LIMIT 1';
        $did = $crmsUS->SimpleSqlGet($sql, $encdata);
        if (!$did)
        {
          $sql = 'INSERT INTO reviewdata (data) VALUES (?)';
          $crmsUS->PrepareSubmitSql($sql, $encdata);
          $sql = 'SELECT MAX(id) FROM reviewdata WHERE data=?';
          $did = $crmsUS->SimpleSqlGet($sql, $encdata);
        }
      }
      my @fields = keys %{$row};
      my @values = map {$row->{$_};} @fields;
      if ($did)
      {
        push @fields, 'data';
        push @values, $did;
      }
      $sql = sprintf 'INSERT INTO historicalreviews (%s) VALUES %s', join(',', @fields),
                                                         $crmsUS->WildcardList(scalar @values);
      $crmsUS->PrepareSubmitSql($sql, @values);
    }
  }
}

sub UpdateStats
{
  my $sql = 'SELECT DISTINCT DATE(time) FROM exportdata';
  my $ref = $crmsUS->SelectAll($sql);
  foreach my $row (@{$ref})
  {
    my $date = $row->[0];
    print "UpdateStats($date)\n" if $verbose;
    $crmsUS->UpdateDeterminationsBreakdown($date);
    $crmsUS->UpdateExportStats($date);
  }
}

print "Warning: $_\n" for @{$crmsUS->GetErrors()};
print "Warning: $_\n" for @{$crmsWorld->GetErrors()};
