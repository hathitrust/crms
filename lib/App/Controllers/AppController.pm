package App::Controllers::AppController;
use parent 'App::Controller';

use strict;
use warnings;
use utf8;

sub __index {
  my $self = shift;

  my $page = $self->{req}->param('p') || 'home';
  #$self->{vars}->{flash}->add('notice', "AppController->index trying to render '$page'");
  return $self->render($page);
}

1;
