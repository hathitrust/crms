package App::Controllers::AppController;
use parent 'App::Controller';

use strict;
use warnings;
use utf8;

#use User;
#use Utilities;

sub __index {
  my $self = shift;

  #$self->{vars}->{flash}->add('notice', "AppController->index trying to render 'home'");
  return $self->render('home');
}

1;
