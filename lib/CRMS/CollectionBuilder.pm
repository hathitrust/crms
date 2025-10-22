package CRMS::CollectionBuilder;

# Routines for interfacing with the mb batch_collection.pl script.
# Eventually we'll go through an API,
# This is used for creating yearly collections in advance of public domain day rollover.
use strict;
use warnings;
use utf8;

my $BATCH_COLLECTION_PATH  = $ENV{'SDRROOT'} . '/mb/scripts/batch-collection.pl';
my $BATCH_COLLECTION_OWNER = 'hathitrust@gmail.com';
my $BATCH_COLLECTION_OWNER_NAME = 'HathiTrust';

my $VISIBILITIES = {
  'public' => 1,
  'private' => 1,
  'draft' => 1
};

sub new {
  my ($class, %args) = @_;
  my $self = bless {}, $class;
  my $who = `whoami`;
  chomp $who;
  $self->{whoami} = $who;
  return $self;
}

# Returns a shell command that will create a public domain day collection.
# It is up to the caller to run the command.
sub create_collection_cmd {
  my $self = shift;
  my %args = @_;

  my $title = $args{title};
  my $description = $args{description};
  my $file = $args{file};
  die 'missing required parameter "title"' unless $title;
  die 'missing required parameter "description"' unless $description;
  die 'missing required parameter "file"' unless $file;

  my $cmd = <<CMD;
HT_DEV= MB_SUPERUSER=$self->{whoami} $BATCH_COLLECTION_PATH
-t "$title"
-d "$description"
-o $BATCH_COLLECTION_OWNER
-O $BATCH_COLLECTION_OWNER_NAME
-f $file
2>&1
CMD
  $cmd =~ s/\n/ /g;
  return $cmd;
}

# Returns a shell command that will set the collections visibility.
# It is up to the caller to run the command.
sub set_visibility_cmd {
  my $self = shift;
  my %args = @_;

  my $coll_id = $args{coll_id};
  my $visibility = $args{visibility} || 'private';
  die 'missing required parameter "coll_id"' unless $coll_id;
  die "unknown visibility parameter '$visibility'" unless $VISIBILITIES->{$visibility};

  my $cmd = <<CMD;
HT_DEV= MB_SUPERUSER=$self->{whoami} $BATCH_COLLECTION_PATH
-u $coll_id
-s $visibility
2>&1
CMD
  $cmd =~ s/\n/ /g;
  return $cmd;
}

