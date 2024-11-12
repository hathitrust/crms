package CRMS::Controller::CandidatesController;

use strict;
use warnings;
use utf8;

sub new {
  my ($class, %args) = @_;

  my $self = bless {}, $class;
  die "No CRMS object passed to CRMS::Candidates->new" unless $args{crms};
  $self->{$_} = $args{$_} for keys %args;
  return $self;
}

# Called from ?p=candidates_remove
# Returns an arrayref with one hashref per id submitted:
# {
#    id => 'the HTID submitted'
#    status => 'ok', 'error', 'noop'
#    message => explanation of the error
#    tracking => volume tracking info after update
# }
sub remove {
  my $self = shift;

  my $cgi = $self->{crms}->{cgi};
  my $noop = $cgi->param('noop');
  my $user_projects = $self->{crms}->GetUserProjects;
  # Make a project.id => project.name hash for quick lookup
  my $user_project_id_to_name = {};
  $user_project_id_to_name->{$_->{id}} = $_->{name} for @$user_projects;
  my @ids = split(m/\s+/, $cgi->param('ids'));
  my $return = [];
  foreach my $id (@ids) {
    my $status_hash = {
      id => $id,
      status => 'ok',
      message => 'placeholder message'
    };
    my $sql = 'SELECT project FROM candidates WHERE id=?';
    my $candidate_project_id = $self->{crms}->SimpleSqlGet($sql, $id);
    # First check the user's ability to remove the candidate based on their project
    # assignments.
    # If everything checks out then we can try to alter the database (or do a noop).
    if (!defined $candidate_project_id) {
      $status_hash->{status} = 'error';
      $status_hash->{message} = "Not in candidates";
    } elsif (!defined $user_project_id_to_name->{$candidate_project_id}) {
      $status_hash->{status} = 'error';
      $status_hash->{message} = "You are not assigned to project $candidate_project_id";
    } elsif ($noop) {
      $status_hash->{status} = 'noop';
      $status_hash->{message} = 'Test Only: no changes made';
    } elsif ($self->{crms}->RemoveFromCandidates($id) == 1) {
      $status_hash->{status} = 'ok';
      $status_hash->{message} = '';
    } else {
      $status_hash->{status} = 'error';
      $status_hash->{message} = 'Unable to remove from candidates';
    }
    $status_hash->{tracking} = $self->{crms}->GetTrackingInfo($id, 1, 1);
    push @$return, $status_hash;
  }
  return $return;
}

1;