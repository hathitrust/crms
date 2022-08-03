package App::Controllers::UsersController;
use parent 'App::Controller';

use strict;
use warnings;

use App::Presenters::UserPresenter;
use User;
use Utilities;

sub __edit {
  my $self    = shift;

  my $uid = $self->{params}->{id};
  $self->{vars}->{user} = User::Find($uid);
  $self->__setup_presenter;
  return $self->render('users/edit');
}

sub __index {
  my $self = shift;

  my $tt_vars = $self->{vars};
  my $order = $self->{req}->param('order') || 0;
  my $users = User::All;
  my @sorted;
  if ($order == 1) {
    @sorted = sort { $b->{active} <=> $a->{active} || $a->{institution} cmp $b->{institution} } @$users;
  } elsif ($order == 2) {
    @sorted = sort { $b->{active} <=> $a->{active} || $a->privilege_level <=> $b->privilege_level || $a->{name} cmp $b->{name} } @$users;
  } elsif ($order == 3) {
    @sorted = sort { $b->{active} <=> $a->{active} || ($a->{commitment} || 0) <=> ($b->{commitment} || 0) } @$users;
  } else {
    @sorted = sort { $b->{active} <=> $a->{active} || $a->{name} cmp $b->{name} } @$users;
  }
  $self->{vars}->{users} = \@sorted;
  return $self->render('users/index');
}

sub __new {
  my $self = shift;

  $self->{vars}->{user} = User::new;
  $self->__setup_presenter;
  return $self->render('users/new');
}

sub __show {
  my $self = shift;

  my $uid = $self->{params}->{id};
  $self->{vars}->{user} = User::Find($uid);
  $self->__setup_presenter;
  return $self->render('users/show');
}


sub __update {
  my $self = shift;
use Data::Dumper;
  my $uid = $self->{params}->{id};
  my $user = User::Find($uid);
  $self->{vars}->{user} = $user;
  $self->{vars}->{flash}->add('notice', sprintf("__update dealing with %s", Dumper $self->{params}));
  $self->{vars}->{flash}->add('notice', sprintf("__update applying to %s", Dumper $user));
  Carp::confess "No user found in __update params" unless defined $self->{params}->{user};
  foreach my $key (keys %{$self->{params}->{user}}) {
    $self->{vars}->{flash}->add('notice', sprintf("key %s value %s", Dumper $key, Dumper $self->{params}->{user}->{$key}));
    $user->{$key} = $self->{params}->{user}->{$key};
  }
  $self->__setup_presenter;
  $self->{vars}->{flash}->add('notice', sprintf("__update saving %s", Dumper $user));
  if ($self->{vars}->{user}->save) {
    # FIXME: this needs to be done in the session.
    $self->{vars}->{flash}->add('notice',
      sprintf("$self->{vars}->{user}->{name} updated<br/>\n%s", Dumper $self->{vars}->{user}));
    #return $self->redirect("/crms/users/$uid");
    return $self->render('users/edit');
  } else {
    $self->{vars}->{flash}->add('warning', $self->{vars}->{user}->errors);
    return $self->render('users/edit');
  }
}

sub __setup_presenter {
  my $self = shift;

  $self->{vars}->{presenter} = $self->presenter_for_user($self->{vars}->{user});
}

sub presenter_for_user {
  my $self = shift;
  my $user = shift;

  return App::Presenters::UserPresenter->new(obj => $user, controller => $self);
}

1;
