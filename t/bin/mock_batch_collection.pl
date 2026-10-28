#!/usr/bin/env perl

# Simulates a call to `mb/scripts/batch_collection.pl`.
# Use cases covered are collection creation, and shared/featured updates.
# Validates input parameters, updates HT DB, and generates predictable STDERR and STDOUT.
# CollectionBuilder.pm will query the database for the new collection id, it might be possible
# for it to parse the STDOUT of `batch_collection.pl` for the id but it would be brittle. As a
# result, this script has extra work to do.

use Getopt::Long qw(:config no_ignore_case bundling);

use lib "$ENV{SDRROOT}/crms/lib";
use CRMS::Database::HT;

my $SHARED_VALUES = {
  'draft' => -1,
  'private' => 0,
  'public' => 1
};

my ($description, $featured, $file, $owner, $owner_name, $shared, $title, $update);

Getopt::Long::Configure('bundling');
die 'Terminating' unless GetOptions(
  'd:s' => \$description,
  'f:s' => \$file,
  'o:s' => \$owner,
  'O:s' => \$owner_name,
  'q:s' => \$featured,
  's:s' => \$shared,
  't:s' => \$title,
  'u:s' => \$update,
);

my $database = CRMS::Database::HT->new;

if (defined $update) {
  if (defined $shared) {
    update_shared($update, $shared);
  }
  if (defined $featured) {
    update_featured($update, $featured);
  }
} else {
  die "Missing description" unless $description;
  die "Missing file" unless $file;
  die "Missing owner" unless $owner;
  die "Missing owner name" unless $owner_name;
  die "Missing title" unless $title;

  $coll_id = create_collection();
  print "Done. coll_id for \"$title\" collection is: $coll_id\n";
}

# Returns new collection id.
sub create_collection {
  $coll_id = new_collection_id();
  my $sql = 'INSERT INTO mb_collection (MColl_ID,collname,owner,owner_name,description)' .
  'VALUES (?,?,?,?,?)';
  $database->submit($sql, $coll_id, $title, $owner, $owner_name, $description);
  return $coll_id;
}

# Get an unused collection id
sub new_collection_id {
  return 1 + $database->one('SELECT MAX(MColl_ID) FROM mb_collection') || 0;
}

sub update_featured {
  my $coll_id  = shift;
  my $featured = shift;

  # Translate 0000-00-00 into NULL
  if ($featured eq '0000-00-00') {
    $featured = undef;
  }
  my $sql = 'UPDATE mb_collection SET featured=? WHERE MColl_ID=?';
  $database->submit($sql, $featured, $coll_id);
}


sub update_shared {
  my $coll_id = shift;
  my $shared  = shift;

  die "unknown shared value $shared" unless exists $SHARED_VALUES->{$shared};
  my $sql = 'UPDATE mb_collection SET shared=? WHERE MColl_ID=?';
  $database->submit($sql, $SHARED_VALUES->{$shared}, $coll_id);
}
