package App::Presenter;

use strict;
use warnings;

use Carp;
use Plack::Response;

use Utilities;

# This should be overridden somehow to give us our localization namespace
#my $NAMESPACE = 'crms.something.something';

my $TEXT_FIELD_SIZE = 60;

sub new {
  my ($class, %args) = @_;
  my $self = bless {}, $class;
  $self->{$_} = $args{$_} for keys %args;
  Carp::confess "No controller passed to Presenter" unless $args{'controller'};
  Carp::confess "No object passed to Presenter" unless $args{'obj'};
  return $self;
}

sub all_fields {
  my $self = shift;

  return [];
}

sub field_label {
  my $self  = shift;
  my $field = shift;
  my $form  = shift;

  # FIXME: replace this with a localization call.
  my $text = ucfirst $field;
  $text = Utilities->new->EscapeHTML($text);
  if (defined $form) {
    return "<label for='$field'>" . $text . "</label>\n";
  }
  #use Data::Dumper;
  #$text .= sprintf("(args %s)", Dumper \%args);
  return $text;
}

# Call subclass show_<field> if available.
# Otherwise call object-><field> if available.
sub show_field_value {
  my $self  = shift;
  my $field = shift;

  my $method = 'show_' . $field;
  if (my $ref = eval { $self->can($method); }) {
    return $self->$ref();
  }
  my $value = $self->{obj}->{$field};
  if (my $ref = eval { $self->{obj}->can($field); }) {
    $value = $self->{obj}->$ref();
  }
  #return $value;
  return Utilities->new->EscapeHTML($value);
}

# Call subclass edit_<field> if available.
# Otherwise return <input> with object-><field> if available.
sub edit_field_value {
  my $self  = shift;
  my $field = shift;

  
  my $method = 'edit_' . $field;
  if (my $ref = eval { $self->can($method); }) {
    return $self->$ref();
  }
  my $value = $self->{obj}->{$field} || '';
  if (my $ref = eval { $self->{obj}->can($field); }) {
    $value = $self->{obj}->$ref();
  }
  return "<input id='$field' type='text' value='$value' size='$TEXT_FIELD_SIZE'/>\n";
}

1;
