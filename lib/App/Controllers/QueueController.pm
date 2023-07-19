package App::Controllers::QueueController;
use parent 'App::Controller';

use strict;
use warnings;
use utf8;

use Data::Dumper;

use App::Presenter;
use CRMS::Queue;

sub __index {
  my $self = shift;
  
  #$self->{vars}->{flash}->add('notice', "QueueController->index trying to render 'queue/index'");
  $self->{vars}->{flash}->add('notice', sprintf("QueueController params '%s", Dumper $self->{params}));
  $self->{vars}->{data} = CRMS::Queue::Search(%{$self->{params}});
  return $self->render('queue/index');
}

# Add to queue page, no actual entries are created here because it's a batch creation UI.
sub __new {
  my $self = shift;

  return $self->render('queue/new');
}

# Submission values from Add to queue page
sub __create {
  my $self = shift;

  my $ids = $self->{params}->{queue}->{ids};
  my @ids = split "\n", $self->{params}->{queue}->{ids};
  foreach my $id (@ids) {
    $self->{vars}->{flash}->add('notice', "QueueController->__create with $ids");
  }
  return $self->render('queue/new');
}

1;
