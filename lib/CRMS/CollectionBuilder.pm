package CRMS::CollectionBuilder;

use Capture::Tiny qw();
use Data::Dumper;
use File::Spec qw();

# Routines for interfacing with the mb batch_collection.pl script.
# Eventually we'll go through an API,
# This is used for creating yearly collections in advance of public domain day rollover.
use strict;
use warnings;
use utf8;

use lib "$ENV{SDRROOT}/crms/lib";

use CRMS::Database::HT qw();
use CRMS::Utility::Time qw();

use constant BATCH_COLLECTION_PATH => File::Spec->catfile($ENV{SDRROOT}, 'mb', 'scripts', 'batch-collection.pl');

# Not constantized to keep interpolation simpler.
our $BATCH_COLLECTION_OWNER = 'hathitrust@gmail.com';
our $BATCH_COLLECTION_OWNER_NAME = 'HathiTrust';

my $SHARED_VALUES = {
  'draft' => -1,
  'private' => 0,
  'public' => 1
};

sub new {
  my ($class, %args) = @_;
  my $self = bless {}, $class;

  # `whoami` is used to hack around the strange access controls embedded in `batch-collection.pl`
  my $who = `whoami`;
  chomp $who;
  $self->{whoami} = $who;
  # The New Year we are preparing for. Defaults to current year + 1.
  $self->{year} = $args{year} || CRMS::Utility::Time->new->year + 1;
  # Use a non-default value for the `batch-collection.pl` executable as a mock for testing.
  $self->{batch_collection_path} = $args{batch_collection_path} || BATCH_COLLECTION_PATH;
  return $self;
}

# Owner is assumed to be `$BATCH_COLLECTION_OWNER`
# Returns a single hashref on success or undef.
sub find_collection_by_name {
  my $self = shift;
  my $name = shift;

  die 'find_collection_by_name: missing name' unless defined $name;

  my $database = CRMS::Database::HT->new;
  my $sql = "SELECT MColl_ID FROM mb_collection WHERE collname=? AND owner=?";
  my $ref = $database->all($sql, $name, $BATCH_COLLECTION_OWNER);
  if (scalar @$ref > 1) {
    die "found more than one collection for name='$name' and owner='$BATCH_COLLECTION_OWNER'";
  }
  return $ref->[0];
}

sub pdd_collection_description {
  my $self  = shift;
  my $world = shift;

  if ($world) {
    return "Volumes newly opened to the world as of January 1, $self->{year} based on bibliographic data";
  } else {
    my $target_year = $self->pdd_collection_target_year;
    return "Volumes published in $target_year for the purpose of sharing items " .
      "that became public domain in the U.S. in $self->{year}";
  }
}

sub pdd_collection_name {
  my $self  = shift;
  my $world = shift;

  if ($world) {
    return "Newly Opened Worldwide January $self->{year}";
  } else {
    my $target_year = $self->pdd_collection_target_year;
    return "$target_year Publications";
  }
}

# Used by US and World collection crons for database query, and in the US name/description.
# The 95- and 125- year cutoff dates in bib_rights.pm are the earliest dates still eligible for copyright.
# Going one year earlier gives us the newest rights date that is opening in $self->{year}.
sub pdd_collection_target_year {
  my $self  = shift;
  my $world = shift;

  if ($world) {
    return $self->{year} - 126;
  } else {
    return $self->{year} - 96;
  }
}

### === The `submit_*` methods all wrap calls to `batch-collection.pl` === ###

# Call `batch-collection.pl` to create a US or Worldwide collection.
sub submit_create_collection {
  my $self        = shift;
  my $name        = shift;
  my $description = shift;
  my $file        = shift;

  die 'submit_create_collection: missing name' unless $name;
  die 'submit_create_collection: missing description' unless $description;
  die 'submit_create_collection: missing file' unless $file;
  die "submit_create_collection: file $file does not exist" unless -e $file;

  my $res = $self->_batch_collection(
    '-d', $description,
    '-f', $file,
    '-o', $BATCH_COLLECTION_OWNER,
    '-O', $BATCH_COLLECTION_OWNER_NAME,
    '-t', $name,
  );
  my $collection = $self->find_collection_by_name($name);
  $res->{coll_id} = $collection->{MColl_ID};
  return $res;
}

# Call `batch-collection.pl` to set or unset featured status for collection id.
sub submit_set_featured {
  my $self     = shift;
  my $coll_id  = shift;
  my $featured = shift;

  die 'submit_set_featured: missing coll_id' unless defined $coll_id;

  # Translate the Boolean `featured` parameter into terms `batch-collection.pl` understands:
  # If set, generate a YYYY-01-02 date for the *following* year,
  # Otherwise 0000-00-00 (will end up with NULL in the collection's `featured` column).
  my $featured_date = '0000-00-00';
  if ($featured) {
    $featured_date = ($self->{year} + 1) . '-01-02';
  }
  return $self->_batch_collection(
    '-q', $featured_date,
    '-u', $coll_id,
  );
}

# Call `batch-collection.pl` to set shared (draft, private, public) status for collection id.
sub submit_set_shared {
  my $self    = shift;
  my $coll_id = shift;
  my $shared  = shift;

  die 'submit_set_shared: missing coll_id' unless defined $coll_id;
  die 'submit_set_shared: missing shared' unless $shared;
  die "submit_set_shared: unknown shared value '$shared'" unless exists $SHARED_VALUES->{$shared};

  return $self->_batch_collection(
    '-s', $shared,
    '-u', $coll_id,
  );
}

# Internal routine to Capture::Tiny the supplied command with
# HT_DEV set to nothing, and MB_SUPERUSER set to the current user.
# SDRDATAROOT also needs to be set in some cases?
sub _batch_collection {
  my $self = shift;

  my @params = ($self->{batch_collection_path}, @_);
  my ($stdout, $stderr, $status) = Capture::Tiny::capture {
    local $ENV{HT_DEV} = '';
    local $ENV{MB_SUPERUSER} = $self->{whoami};
    ####local $ENV{SDRDATAROOT} = '/sdr1' unless defined $ENV{SDRDATAROOT};
    system(@params);
  };
  chomp $stdout;
  chomp $stderr;
  return {
    stdout => $stdout,
    stderr => $stderr,
    status => $status
  };
}

1;
