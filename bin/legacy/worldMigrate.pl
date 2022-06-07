#!/usr/bin/perl

use strict;
use warnings;
BEGIN { unshift(@INC, $ENV{'SDRROOT'}. '/crms/cgi'); }

use CRMS;
use Getopt::Long;
use Utilities;
use JSON::XS;
use Term::ANSIColor qw(:constants);
$Term::ANSIColor::AUTORESET = 1;
use Data::Dumper;

my $usage = <<END;
USAGE: $0 [-hnpv] [-m USER [-m USER...]]

One-off script to migrate data from CRMS-World to CRMS-US.

-h       Print this help message.
-p       Run in production.
-t       Run in training.
-v       Emit verbose debugging information. May be repeated.
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
$instance = 'crms-training' if $training;
if ($help) { print $usage. "\n"; exit(0); }
print "Verbosity $verbose\n" if $verbose;

my $crmsWorld = CRMS->new(
    sys      => 'crmsworld',
    verbose  => $verbose,
    instance => $instance
);
my $dbhWorld = ConnectToWorldDb($crmsWorld);
$crmsWorld->set('dbh', $dbhWorld);

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



# +----------------------------+
# | Tables_in_crms             |
# +----------------------------+
# | attributes                 | # OK, handle automatically
# | authorities                | # MigrateSources()
# | bibdata                    | # MigrateCandidates()
# | candidates                 | # MigrateCandidates()
# | candidatesrecord           | # MigrateCandidates()
# | categories                 | # OK, handle automatically
# | corrections                | # MigrateCorrections()
# | cri                        | # LEAVE ALONE FOR NOW
# | determinationsbreakdown    | # UpdateStats()
# | exportdata                 | # MigrateExportdata()
# | exportrecord               | # FIXME: DELETE
# | exportstats                | # UpdateStats()
# | historicalreviews          | # MigrateExportdata()
# | inherit                    | # OK, nothing in world??
# | inserts                    | # OK, nothing in world
# | insertsqueue               | # OK, nothing in world
# | insertstotals              | # OK, nothing in world
# | institutions               | # MigrateUsers()
# | mail                       | # OK, nothing in world
# | menuitems                  | # OK, UI
# | menus                      | # OK, UI
# | note                       | # OK, ephemeral
# | orphan                     | # OK, nothing in world
# | predeterminationsbreakdown | # MigratePredeterminationsbreakdown()
# | processstatus              | # MigrateExportdata()
# | projectauthorities         | # MigrateProjects()
# | projectcategories          | # MigrateProjects()
# | projectrights              | # MigrateProjects()
# | projects                   | # MigrateProjects()
# | projectusers               | # MigrateProjects()
# | publishers                 | # OK, identical
# | queue                      | # MigrateQueue()
# | queuerecord                | # MigrateQueue()
# | reasons                    | # OK, handle automatically
# | reviewdata                 | # OK, nothing in world
# | reviews                    | # MigrateQueue()
# | rights                     | # MigrateSources()
# | sdrerror                   | # FIXME: DELETE
# | stanford                   | # OK, nothing in world
# | systemstatus               | # OK, UI
# | systemvars                 | # OK, nothing to see here
# | unavailable                | # FIXME: unused??
# | und                        | # MigrateCandidates()
# | users                      | # MigrateUsers()
# | userstats                  | # UpdateStats()
# | viaf                       | # OK, nothing to see here
# +----------------------------+

$crmsUS->set('die', 1);
$crmsWorld->set('die', 1);

%projmap = (1 => 11, 3 => 13, 5 => 15, 7 => 17);

Reset();
MigrateSources();
MigrateUsers();
MigrateProjects();
MigrateCandidates();
MigrateQueue();
MigrateExportdata();
MigrateCorrections();
MigratePredeterminationsbreakdown();
UpdateStats();



sub ConnectToWorldDb
{
  my $self = shift;

  my $db_server = $self->get('mysqlServerDev');
  my $instance  = $self->get('instance') || '';

  my %d = $self->ReadConfigFile('crmsworldpw.cfg');
  my $db_user   = $d{'mysqlUser'};
  my $db_passwd = $d{'mysqlPasswd'};
  if ($instance eq 'production' || $instance eq 'crms-training')
  {
    $db_server = $self->get('mysqlServer');
  }
  my $db = 'crmsworld';
  $db .= '_training' if $instance && $instance eq 'crms-training';
  my $dbh = DBI->connect("DBI:mysql:$db:$db_server", $db_user, $db_passwd,
            { PrintError => 0, RaiseError => 1, AutoCommit => 1 }) || die "Cannot connect: $DBI::errstr";
  $dbh->{mysql_enable_utf8} = 1;
  $dbh->{mysql_auto_reconnect} = 1;
  $dbh->do('SET NAMES "utf8";');
  return $dbh;
}

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
  #$crmsUS->PrepareSubmitSql('DELETE FROM rights WHERE id>24');
  #$crmsUS->PrepareSubmitSql('DELETE FROM authorities WHERE id>33');
  #$crmsUS->PrepareSubmitSql('DELETE FROM categories WHERE id>51');
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
  my %instmap; # Map of World institution id to US id.
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
  my $sql = 'SELECT id,name,color,autoinherit,group_volumes,primary_authority,secondary_authority FROM projects'.
            ' ORDER BY id ASC';
  my $ref = $crmsWorld->SelectAll($sql);
  foreach my $row (@{$ref})
  {
    my ($id, $name, $color, $autoinherit, $group_volumes, $primary_authority, $secondary_authority) = @{$row};
    my $usid;
    $name = 'Commonwealth' if $name eq 'Core';
    $usid = $crmsUS->SimpleSqlGet('SELECT id FROM projects WHERE name=?', $name);
    if (!$usid)
    {
      $sql = 'INSERT INTO projects (name,color,autoinherit,group_volumes,'.
             'primary_authority,secondary_authority) VALUES (?,?,?,?,?,?)';
      printf "%s\n", Utilities->new->StringifySql($sql, $name, $color, $autoinherit,
                                $group_volumes, $authmap{$primary_authority},
                                $authmap{$secondary_authority});
      $crmsUS->PrepareSubmitSql($sql, $name, $color, $autoinherit,
                                $group_volumes, $authmap{$primary_authority},
                                $authmap{$secondary_authority});
      $usid = $crmsUS->SimpleSqlGet('SELECT MAX(id) FROM projects WHERE name=?', $name);
    }
    $projmap{$id} = $usid;
  }
  $sql = 'SELECT project,authority FROM projectauthorities';
  $ref = $crmsWorld->SelectAll($sql);
  foreach my $row (@{$ref})
  {
    my @values = ($projmap{$row->[0]}, $authmap{$row->[1]});
    if (!$crmsUS->SimpleSqlGet('SELECT COUNT(*) FROM projectauthorities WHERE project=? AND authority=?', @values))
    {
      $sql = 'INSERT INTO projectauthorities (project,authority) VALUES (?,?)';
      printf "%s\n", Utilities->new->StringifySql($sql, @values);
      $crmsUS->PrepareSubmitSql($sql, @values);
    }
  }
  $sql = 'SELECT project,category FROM projectcategories';
  $ref = $crmsWorld->SelectAll($sql);
  foreach my $row (@{$ref})
  {
    my @values = ($projmap{$row->[0]}, $catmap{$row->[1]});
    if (!$crmsUS->SimpleSqlGet('SELECT COUNT(*) FROM projectcategories WHERE project=? AND category=?', @values))
    {
      $sql = 'INSERT INTO projectcategories (project,category) VALUES (?,?)';
      printf "%s\n", Utilities->new->StringifySql($sql, @values);
      $crmsUS->PrepareSubmitSql($sql, @values);
    }
  }
  $sql = 'SELECT project,rights FROM projectrights';
  $ref = $crmsWorld->SelectAll($sql);
  foreach my $row (@{$ref})
  {
    my @values = ($projmap{$row->[0]}, $rightsmap{$row->[1]});
    if (!$crmsUS->SimpleSqlGet('SELECT COUNT(*) FROM projectrights WHERE project=? AND rights=?', @values))
    {
      $sql = 'INSERT INTO projectrights (project,rights) VALUES (?,?)';
      printf "%s\n", Utilities->new->StringifySql($sql, @values);
      $crmsUS->PrepareSubmitSql($sql, @values);
    }
  }
  $sql = 'SELECT project,user FROM projectusers';
  $ref = $crmsWorld->SelectAll($sql);
  foreach my $row (@{$ref})
  {
    my @values = ($projmap{$row->[0]}, $row->[1]);
    if (!$crmsUS->SimpleSqlGet('SELECT COUNT(*) FROM projectusers WHERE project=? AND user=?', @values))
    {
      $sql = 'INSERT INTO projectusers (project,user) VALUES (?,?)';
      printf "%s\n", Utilities->new->StringifySql($sql, @values);
      $crmsUS->PrepareSubmitSql($sql, @values);
    }
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
      printf "%s\n", Utilities->new->StringifySql($sql, @values);
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
      printf "%s\n", Utilities->new->StringifySql($sql, @values);
      $crmsUS->PrepareSubmitSql($sql, @values);
    }
  }
  $sql = 'SELECT * FROM und';
  $ref = $dbhWorld->selectall_hashref($sql, 'id');
  foreach my $id (sort keys %{$ref})
  {
    if (!$crmsUS->SimpleSqlGet('SELECT COUNT(*) FROM und WHERE id=?', $id))
    {
      my $row = $ref->{$id};
      my @fields = keys %{$row};
      my @values = map {$row->{$_};} @fields;
      $sql = sprintf 'INSERT INTO und (%s) VALUES %s', join(',', @fields),
                                                         $crmsUS->WildcardList(scalar @values);
      printf "%s\n", Utilities->new->StringifySql($sql, @values);
      $crmsUS->PrepareSubmitSql($sql, @values);
    }
  }
  $sql = 'SELECT time,addedamount FROM candidatesrecord';
  $ref = $crmsWorld->SelectAll($sql);
  foreach my $row (@{$ref})
  {
    $sql = 'INSERT INTO candidatesrecord (time,addedamount) VALUES (?,?)';
    printf "%s\n", Utilities->new->StringifySql($sql, $row->[0], $row->[1]);
    $crmsUS->PrepareSubmitSql($sql, $row->[0], $row->[1]);
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
      printf "%s\n", Utilities->new->StringifySql($sql, @values);
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
      $row->{'data'} = $did if $did;
      my @fields = keys %{$row};
      my @values = map {$row->{$_};} @fields;
      $sql = sprintf 'INSERT INTO reviews (%s) VALUES %s', join(',', @fields),
                                                         $crmsUS->WildcardList(scalar @values);
      $crmsUS->PrepareSubmitSql($sql, @values);
    }
  }
  # FIXME: coalesce these if possible if same time and source
  $sql = 'SELECT time,itemcount,source FROM queuerecord';
  $ref = $crmsWorld->SelectAll($sql);
  foreach my $row (@{$ref})
  {
    $sql = 'INSERT INTO queuerecord (time,itemcount,source) VALUES (?,?,?)';
    $crmsUS->PrepareSubmitSql($sql, $row->[0], $row->[1], $row->[1]);
  }
}

sub MigrateExportdata
{
  my $sql = 'SELECT * FROM exportdata';
  my $ref = $dbhWorld->selectall_hashref($sql, 'gid');
  foreach my $worldgid (sort keys %{$ref})
  {
    my $row = $ref->{$worldgid};
    $row->{'project'} = $projmap{$row->{'project'}};
    delete $row->{'gid'};
    my @fields = keys %{$row};
    my @values = map {$row->{$_};} @fields;
    $sql = sprintf 'INSERT INTO exportdata (%s) VALUES %s', join(',', @fields),
                                                       $crmsUS->WildcardList(scalar @values);
    printf "%s\n", Utilities->new->StringifySql($sql, @values);
    $crmsUS->PrepareSubmitSql($sql, @values);
    $sql = 'SELECT gid FROM exportdata WHERE id=? AND time=?';
    my $usgid = $crmsUS->SimpleSqlGet($sql, $row->{'id'}, $row->{'time'});
    die "undef US GID from World GID $worldgid" unless defined $usgid;
    print "US GID $usgid, World GID $worldgid\n";
    $sql = 'SELECT * FROM historicalreviews WHERE gid=?';
    my $ref2 = $dbhWorld->selectall_hashref($sql, 'user', undef, $worldgid);
    #print Dumper $ref2;
    foreach my $user (sort keys %{$ref2})
    {
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
      $row->{'data'} = $did if $did;
      $row->{'gid'} = $usgid;
      my @fields = keys %{$row};
      my @values = map {$row->{$_};} @fields;
      $sql = sprintf 'INSERT INTO historicalreviews (%s) VALUES %s', join(',', @fields),
                                                         $crmsUS->WildcardList(scalar @values);
      printf "%s\n", Utilities->new->StringifySql($sql, @values);
      $crmsUS->PrepareSubmitSql($sql, @values);
    }
  }
  $sql = 'SELECT time,itemcount FROM exportrecord';
  $ref = $crmsWorld->SelectAll($sql);
  foreach my $row (@{$ref})
  {
    $sql = 'INSERT INTO exportrecord (time,itemcount) VALUES (?,?)';
    printf "%s\n", Utilities->new->StringifySql($sql, $row->[0], $row->[1]);
    $crmsUS->PrepareSubmitSql($sql, $row->[0], $row->[1]);
  }
  $sql = 'SELECT time FROM processstatus';
  $ref = $crmsWorld->SelectAll($sql);
  foreach my $row (@{$ref})
  {
    my $time = $row->[0];
    $sql = 'SELECT COUNT(*) FROM processstatus WHERE time=?';
    if (!$crmsUS->SimpleSqlGet($sql, $time))
    {
      $sql = 'INSERT INTO processstatus (time) VALUES (?)';
      printf "%s\n", Utilities->new->StringifySql($sql, $time);
      $crmsUS->PrepareSubmitSql($sql, $time);
    }
  }
}

sub MigrateCorrections
{
  my $sql = 'SELECT * FROM corrections';
  my $ref = $dbhWorld->selectall_hashref($sql, 'id');
  foreach my $id (sort keys %{$ref})
  {
    $sql = 'SELECT COUNT(*) FROM corrections WHERE id=?';
    if (!$crmsUS->SimpleSqlGet($sql, $id))
    {
      my $row = $ref->{$id};
      my @fields;
      my @values;
      foreach my $key (keys %{$row})
      {
        push @fields, $key;
        push @values, $row->{$key};
      }
      $sql = sprintf 'INSERT INTO corrections (%s) VALUES %s', join(',', @fields),
                                                         $crmsUS->WildcardList(scalar @values);
      printf "%s\n", Utilities->new->StringifySql($sql, @values);
      $crmsUS->PrepareSubmitSql($sql, @values);
    }
  }
  $crmsUS->PrepareSubmitSql('UPDATE corrections SET locked=NULL');
}

sub MigratePredeterminationsbreakdown
{
  my $sql = 'SELECT date,s2,s3,s4,s8 FROM predeterminationsbreakdown';
  my $ref = $crmsWorld->SelectAll($sql);
  foreach my $row (@{$ref})
  {
    my $date = $row->[0];
    $sql = 'SELECT COUNT(*) FROM predeterminationsbreakdown WHERE date=?';
    if ($crmsUS->SimpleSqlGet($sql, $date))
    {
      $sql = 'UPDATE predeterminationsbreakdown SET s2=s2+?,s3=s3+?,s4=s4+?,s8=s8+?'.
             ' WHERE date=?';
      printf "%s\n", Utilities->new->StringifySql($sql, $row->[1], $row->[2], $row->[3], $row->[4], $date);
      $crmsUS->PrepareSubmitSql($sql, $row->[1], $row->[2], $row->[3], $row->[4], $date);
    }
    else
    {
      $sql = 'INSERT INTO predeterminationsbreakdown (date,s2,s3,s4,s8)'.
             ' VALUES (?,?,?,?,?)';
      printf "%s\n", Utilities->new->StringifySql($sql, $date, $row->[1], $row->[2], $row->[3], $row->[4]);
      $crmsUS->PrepareSubmitSql($sql, $date, $row->[1], $row->[2], $row->[3], $row->[4]);
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
  $crmsUS->UpdateUserStats();
}

print "Warning: $_\n" for @{$crmsUS->GetErrors()};
print "Warning: $_\n" for @{$crmsWorld->GetErrors()};
