package App::Presenters::UserPresenter;
use parent 'App::Presenter';

#use User;
use Institution;
use Utilities;

my $ALL_FIELDS = ['id', 'email', 'name', 'reviewer', 'advanced', 'expert', 'admin',
  'role', 'note', 'institution', 'commitment', 'project', 'active', 'internal'];

sub all_fields {
  my $self = shift;

  return $ALL_FIELDS;
}

sub show_institution {
  my $self = shift;

  return $self->{obj}->institution->{name};
}

sub show_reviewer {
  my $self = shift;

  return ($self->{obj}->is_reviewer)? $self->__check_mark : '';
}

sub show_advanced {
  my $self = shift;

  return ($self->{obj}->is_advanced)? $self->__check_mark : '';
}

sub show_expert {
  my $self = shift;

  return ($self->{obj}->is_expert)? $self->__check_mark : '';
}

sub show_admin {
  my $self = shift;

  return ($self->{obj}->is_admin)? $self->__check_mark : '';
}

sub __check_mark {
  my $self = shift;

  return '<img width="16" height="16" alt="Check" src="/crms/web/CheckIcon.png"/>';
}


sub edit_institution {
  my $self = shift;

  my $html = '<select id="institution" class="select-institution" name="user[institution]">' . "\n";
  foreach my $institution (@{Institution::All()}) {
    $html .= "<option value='$institution->{inst_id}'";
    $html .= ' selected' if $self->{obj}->{institution} eq $institution->{inst_id};
    $html .= '>';
    $html .= Utilities->new->EscapeHTML($institution->{name});
    $html .= "</option>\n";
  }
  $html .= "</select>\n";
  return $html;
}

1;
