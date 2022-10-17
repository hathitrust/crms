package BibRights;

# A CRMS-oriented wrapper around bib_rights.pm using HathiTrust Bib API
# to retrieve MARC XML.

use strict;
use warnings;
use utf8;

use Capture::Tiny;
use Data::Dumper;
use MARC::File::XML(BinaryEncoding => 'utf8');
use MARC::Record;

use lib $ENV{SDRROOT} . '/crms/post_zephir_processing';
use bib_rights;
use Metadata;

binmode(STDOUT, ':encoding(UTF-8)');

our @BIB_RIGHTS_INFO_FIELDS = qw(attr bib_fmt bib_key date1 date2 date_desc
  date_munged date_type date_used desc gov_pub id orig_date1 orig_date2
  pub_country pub_place reason us_fed_doc vol_date);


sub new {
  my ($class, %args) = @_;
  my $self = bless {}, $class;
  return $self;
}

# Returns a structure {entries => [bib_rights_info+], optional error => errstr}
sub query {
  my $self = shift;
  my $id   = shift;

  my $br;
  # bib_rights.pm likes to emit cutoff year debugging info to STDERR.
  # So suppress it.
  my ($stderr, @result) = Capture::Tiny::capture_stderr sub {
    $br = bib_rights->new();
  };
  my $marc;
  my $data = { entries => [] };
  my $metadata = Metadata->new('id' => $id);
  if ($metadata->is_error) {
    $data->{error} = $metadata->error;
    return $data;
  }
  eval { $marc = MARC::Record->new_from_xml($metadata->xml); };
  # uncoverable branch true
  if ($@) {
    # uncoverable statement
    $data->{error} = "problem creating MARC::Record from XML: $@";
    # uncoverable statement
    return $data;
  }
  my $htids = ($id =~ m/\./) ? [ $id ] : $metadata->allHTIDs();
  my $cid = $marc->field('001')->as_string;
  my $bib_info = $br->get_bib_info($marc, $cid);
  $data->{cid} = $cid;
  $data->{title} = $marc->title();
  $data->{entries} = [];
  foreach my $htid (@{$htids}) {
    my $enumcron = $metadata->enumcron($htid) || '';
    my $bib_rights_info = $br->get_bib_rights_info($htid, $bib_info, $enumcron);
    push @{$data->{entries}}, $bib_rights_info;
  }
  return $data;
}

1;
