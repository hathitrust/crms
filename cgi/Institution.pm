package Institution;

use strict;
use warnings;
use utf8;
use 5.010;

use Carp;
use Data::Dumper;

use CRMS::DB;
use Utilities;

sub Default {
  return Find('umich');
}

sub All {
  my $sql = 'SELECT * FROM ht_institutions ORDER BY inst_id';
  my $ref = __dbh()->selectall_hashref($sql, 'inst_id');
  return __institutions_from_hashref($ref);
}

sub Active {
  my $sql = 'SELECT * FROM ht_institutions WHERE enabled=1 ORDER BY inst_id';
  my $ref = __dbh()->selectall_hashref($sql, 'inst_id');
  return __institutions_from_hashref($ref);
}

sub Find {
  my $id = shift;

  Carp::confess "Institution::Find called with undef" unless defined $id;

  my $sql = 'SELECT * FROM ht_institutions WHERE inst_id=?';
  my $ref = __dbh()->selectall_hashref($sql, 'inst_id', undef, $id);
  my $institutions = __institutions_from_hashref($ref);
  return (scalar @$institutions)? $institutions->[0] : undef;
}

sub FindByEmail {
  my $email = shift || '';

  my @parts = split '@', $email;
  if (scalar @parts == 2) {
    my $suff = $parts[1];
    my $sql = 'SELECT inst_id FROM ht_institutions WHERE domain!="" AND LOCATE(domain,?)>0';
    my $ref = __dbh()->selectall_hashref($sql, 'inst_id', undef, $suff);
    my $institutions = __institutions_from_hashref($ref);
  }
  return Default;
}

sub new {
  my $class = shift;

  my $self = { @_ };
  bless($self, $class);
  return $self;
}

sub __dbh {
  return CRMS::DB->new(name => 'ht')->dbh;
}

sub __institutions_from_hashref {
  my $hashref = shift;

  my @institutions;
  foreach my $key (sort keys %$hashref) {
    my $inst = Institution->new(%{$hashref->{$key}});
#   Carp::confess sprintf("%s NOT A REFERENCE FROM %s\n",
#       Dumper $inst,
#       Dumper $hashref->{$key}) if '' eq ref $inst;
    push @institutions, $inst;
  }
  return \@institutions;
}

1;
