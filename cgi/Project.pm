package Project;

sub new
{
  my ($class, %args) = @_;
  my $self = bless {}, $class;
  $self->{'crms'} = $args{'crms'};
  $self->{'id'}   = $args{'id'};
  $self->{'name'} = $args{'name'};
  return $self;
}

sub id
{
  my $self = shift;

  return $self->{'id'};
}

sub name
{
  my $self = shift;

  return $self->{'name'};
}

# Return a list of HTIDs that should be claimed by this project.
sub tests
{
  my $self = shift;

  return [];
}

# Run internal self-tests.
sub test
{
  my $self = shift;

  return 1;
}



1;
